-- =============================================================================
-- 24_app_clientes.sql — Propietarios de mascotas + comunicaciones
--
-- La cartera es PRIVADA de cada empresa: toda lectura filtra por empresa_id y
-- toda escritura la fija desde el contexto, nunca desde el payload.
-- =============================================================================

SET search_path = app, internal, core, public;

-- -----------------------------------------------------------------------------
-- app.fn_cliente_listar
-- Solo los propietarios de la empresa del usuario, enriquecidos con su
-- actividad (nº de mascotas, última visita, deuda pendiente).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_cliente_listar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_filtros        JSONB DEFAULT '{}'::jsonb,
  p_page           INT DEFAULT 1,
  p_page_size      INT DEFAULT 20
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_global BOOLEAN := internal.es_acceso_global(p_user_id, p_is_super_admin);
  v_emp    UUID    := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_buscar TEXT    := internal.normalizar(p_filtros->>'buscar');
  v_raw    TEXT    := COALESCE(p_filtros->>'buscar','');
  v_size   INT     := LEAST(GREATEST(COALESCE(p_page_size, 20), 1), 100);
  v_page   INT     := GREATEST(COALESCE(p_page, 1), 1);
  v_total  INT;
  v_data   JSONB;
BEGIN
  SELECT count(*) INTO v_total
  FROM core.clientes c
  WHERE c.deleted_at IS NULL
    AND (v_global OR c.empresa_id = v_emp)
    AND (p_filtros->>'estado' IS NULL OR c.estado::text = p_filtros->>'estado')
    AND (p_filtros->>'con_portal' IS NULL
         OR c.portal_acceso = (p_filtros->>'con_portal')::boolean)
    AND (v_buscar IS NULL OR v_buscar = '' OR
         internal.normalizar(c.nombres || ' ' || COALESCE(c.apellido_paterno,'') || ' ' ||
                             COALESCE(c.apellido_materno,'') || ' ' || COALESCE(c.razon_social,''))
           LIKE '%' || v_buscar || '%'
         OR c.numero_documento LIKE '%' || v_raw || '%'
         OR COALESCE(c.telefono,'') LIKE '%' || v_raw || '%'
         -- buscar también por el nombre de alguna de sus mascotas
         OR EXISTS (SELECT 1 FROM core.mascotas m
                     WHERE m.cliente_id = c.id AND m.deleted_at IS NULL
                       AND internal.normalizar(m.nombre) LIKE '%' || v_buscar || '%'));

  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) INTO v_data
  FROM (
    SELECT c.id, c.codigo, c.tipo_documento, c.numero_documento,
           c.nombres, c.apellido_paterno, c.apellido_materno, c.razon_social,
           trim(c.nombres || ' ' || COALESCE(c.apellido_paterno,'') || ' ' ||
                COALESCE(c.apellido_materno,'')) AS nombre_completo,
           c.telefono, c.telefono_alterno, c.correo, c.direccion,
           c.portal_acceso, c.estado, c.acepta_marketing, c.created_at,
           (SELECT count(*) FROM core.mascotas m
             WHERE m.cliente_id = c.id AND m.deleted_at IS NULL
               AND m.estado = 'activo') AS total_mascotas,
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id', m.id, 'nombre', m.nombre, 'especie', e.nombre, 'foto_url', m.foto_url)
                   ORDER BY m.nombre), '[]'::jsonb)
              FROM core.mascotas m
              JOIN core.especies e ON e.id = m.especie_id
             WHERE m.cliente_id = c.id AND m.deleted_at IS NULL AND m.estado = 'activo') AS mascotas,
           (SELECT max(ci.fecha_hora) FROM core.citas ci
             WHERE ci.cliente_id = c.id AND ci.deleted_at IS NULL
               AND ci.estado = 'completada'
               AND (v_global OR ci.empresa_id = v_emp)) AS ultima_visita,
           (SELECT COALESCE(SUM(cp.saldo_pendiente), 0) FROM core.comprobantes cp
             WHERE cp.cliente_id = c.id AND cp.deleted_at IS NULL
               AND cp.estado_pago <> 'pagado' AND cp.anulado_at IS NULL
               AND (v_global OR cp.empresa_id = v_emp)) AS deuda_pendiente
    FROM core.clientes c
    WHERE c.deleted_at IS NULL
      AND (v_global OR c.empresa_id = v_emp)
      AND (p_filtros->>'estado' IS NULL OR c.estado::text = p_filtros->>'estado')
      AND (p_filtros->>'con_portal' IS NULL
           OR c.portal_acceso = (p_filtros->>'con_portal')::boolean)
      AND (v_buscar IS NULL OR v_buscar = '' OR
           internal.normalizar(c.nombres || ' ' || COALESCE(c.apellido_paterno,'') || ' ' ||
                               COALESCE(c.apellido_materno,'') || ' ' || COALESCE(c.razon_social,''))
             LIKE '%' || v_buscar || '%'
           OR c.numero_documento LIKE '%' || v_raw || '%'
           OR COALESCE(c.telefono,'') LIKE '%' || v_raw || '%'
           OR EXISTS (SELECT 1 FROM core.mascotas m
                       WHERE m.cliente_id = c.id AND m.deleted_at IS NULL
                         AND internal.normalizar(m.nombre) LIKE '%' || v_buscar || '%'))
    ORDER BY c.apellido_paterno NULLS LAST, c.nombres
    LIMIT v_size OFFSET (v_page - 1) * v_size
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data, 'meta', jsonb_build_object(
    'total', v_total, 'page', v_page, 'pageSize', v_size,
    'pages', GREATEST(CEIL(v_total::numeric / v_size)::int, 1)));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_cliente_obtener — ficha 360°: mascotas, últimas citas, deuda, contacto
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_cliente_obtener(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_id             UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_global BOOLEAN := internal.es_acceso_global(p_user_id, p_is_super_admin);
  v_emp    UUID    := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_data   JSONB;
BEGIN
  SELECT to_jsonb(x) INTO v_data FROM (
    SELECT c.id, c.codigo, c.tipo_documento, c.numero_documento,
           c.nombres, c.apellido_paterno, c.apellido_materno, c.razon_social,
           trim(c.nombres || ' ' || COALESCE(c.apellido_paterno,'') || ' ' ||
                COALESCE(c.apellido_materno,'')) AS nombre_completo,
           c.telefono, c.telefono_alterno, c.correo, c.direccion, c.ubigeo,
           c.fecha_nacimiento, c.linea_credito, c.dias_credito, c.acepta_marketing,
           c.portal_acceso, c.portal_ultimo_login_at, c.estado, c.observaciones,
           c.created_at,
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id', m.id, 'codigo', m.codigo, 'nombre', m.nombre,
                     'especie', e.nombre, 'especie_id', m.especie_id,
                     'raza', r.nombre,
                     'sexo', m.sexo, 'peso_kg', m.peso_kg, 'foto_url', m.foto_url,
                     'estado', m.estado,
                     'edad', internal.edad_mascota(m.fecha_nacimiento, m.edad_aproximada_meses),
                     'alergias', m.alergias)
                   ORDER BY m.nombre), '[]'::jsonb)
              FROM core.mascotas m
              JOIN core.especies e ON e.id = m.especie_id
              LEFT JOIN core.razas r ON r.id = m.raza_id
             WHERE m.cliente_id = c.id AND m.deleted_at IS NULL) AS mascotas,
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id', ci.id, 'fecha_hora', ci.fecha_hora, 'estado', ci.estado,
                     'motivo', ci.motivo, 'mascota', m2.nombre,
                     'servicio', s.nombre)
                   ORDER BY ci.fecha_hora DESC), '[]'::jsonb)
              FROM (SELECT * FROM core.citas ci2
                     WHERE ci2.cliente_id = c.id AND ci2.deleted_at IS NULL
                       AND (v_global OR ci2.empresa_id = v_emp)
                     ORDER BY ci2.fecha_hora DESC LIMIT 10) ci
              JOIN core.mascotas m2 ON m2.id = ci.mascota_id
              LEFT JOIN core.servicios s ON s.id = ci.servicio_id) AS ultimas_citas,
           (SELECT COALESCE(SUM(cp.saldo_pendiente), 0) FROM core.comprobantes cp
             WHERE cp.cliente_id = c.id AND cp.deleted_at IS NULL
               AND cp.estado_pago <> 'pagado' AND cp.anulado_at IS NULL
               AND (v_global OR cp.empresa_id = v_emp)) AS deuda_pendiente,
           (SELECT COALESCE(SUM(cp.total), 0) FROM core.comprobantes cp
             WHERE cp.cliente_id = c.id AND cp.deleted_at IS NULL
               AND cp.anulado_at IS NULL
               AND (v_global OR cp.empresa_id = v_emp)) AS facturado_historico
    FROM core.clientes c
    WHERE c.id = p_id AND c.deleted_at IS NULL
      AND (v_global OR c.empresa_id = v_emp)
  ) x;

  IF v_data IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Cliente no encontrado'));
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_cliente_buscar — autocompletar (recepción escribe y elige)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_cliente_buscar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_query          TEXT,
  p_limit          INT DEFAULT 20
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_global BOOLEAN := internal.es_acceso_global(p_user_id, p_is_super_admin);
  v_emp    UUID    := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_q      TEXT    := internal.normalizar(p_query);
  v_data   JSONB;
BEGIN
  IF v_q IS NULL OR length(v_q) < 2 THEN
    RETURN jsonb_build_object('ok', true, 'data', '[]'::jsonb);
  END IF;

  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) INTO v_data
  FROM (
    SELECT c.id, c.codigo, c.numero_documento, c.telefono, c.correo,
           trim(c.nombres || ' ' || COALESCE(c.apellido_paterno,'') || ' ' ||
                COALESCE(c.apellido_materno,'')) AS nombre_completo,
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id', m.id, 'nombre', m.nombre, 'especie', e.nombre) ORDER BY m.nombre), '[]'::jsonb)
              FROM core.mascotas m JOIN core.especies e ON e.id = m.especie_id
             WHERE m.cliente_id = c.id AND m.deleted_at IS NULL AND m.estado = 'activo') AS mascotas
    FROM core.clientes c
    WHERE c.deleted_at IS NULL AND c.estado = 'activo'
      AND (v_global OR c.empresa_id = v_emp)
      AND (internal.normalizar(c.nombres || ' ' || COALESCE(c.apellido_paterno,'') || ' ' ||
                               COALESCE(c.apellido_materno,'')) LIKE '%' || v_q || '%'
           OR c.numero_documento LIKE p_query || '%'
           OR COALESCE(c.telefono,'') LIKE '%' || p_query || '%'
           OR EXISTS (SELECT 1 FROM core.mascotas m
                       WHERE m.cliente_id = c.id AND m.deleted_at IS NULL
                         AND internal.normalizar(m.nombre) LIKE v_q || '%'))
    ORDER BY c.apellido_paterno NULLS LAST, c.nombres
    LIMIT LEAST(COALESCE(p_limit, 20), 50)
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_cliente_crear
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_cliente_crear(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_payload        JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_id       UUID;
  v_emp      UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_tipo_doc core.tipo_documento_identidad :=
    COALESCE((p_payload->>'tipo_documento')::core.tipo_documento_identidad, 'DNI');
  -- Se normaliza ANTES de validar y de buscar duplicados: si no, '12.345.678'
  -- se rechazaría por 'no son 8 dígitos' y esquivaría el chequeo de duplicado
  -- (los valores guardados sí están normalizados por trigger).
  v_doc      TEXT := internal.normalizar_documento(p_payload->>'numero_documento');
  v_existente UUID;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clientes:crear');
  PERFORM internal.validar_payload(p_payload, ARRAY['numero_documento','nombres']);

  IF v_tipo_doc = 'DNI' AND NOT internal.validar_dni(v_doc) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR','El DNI debe tener 8 dígitos','numero_documento'));
  END IF;

  IF v_tipo_doc = 'RUC' AND NOT internal.validar_ruc(v_doc) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR','El RUC no es válido','numero_documento'));
  END IF;

  IF v_emp IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'No se pudo determinar la empresa del usuario','empresa_id'));
  END IF;

  -- El documento es único DENTRO de la empresa. Otra empresa puede tener a la
  -- misma persona en su cartera: son negocios independientes.
  SELECT id INTO v_existente FROM core.clientes
   WHERE empresa_id = v_emp
     AND tipo_documento = v_tipo_doc AND numero_documento = v_doc
     AND deleted_at IS NULL;

  IF v_existente IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(
      'CONFLICT', 'Ya existe un cliente con ese documento', 'numero_documento')
      || jsonb_build_object('cliente_id', v_existente));
  END IF;

  INSERT INTO core.clientes (
    empresa_id, codigo, tipo_documento, numero_documento,
    nombres, apellido_paterno, apellido_materno,
    razon_social, telefono, telefono_alterno, correo, direccion, ubigeo,
    fecha_nacimiento, linea_credito, dias_credito,
    acepta_marketing, observaciones, created_by
  ) VALUES (
    v_emp,
    COALESCE(NULLIF(p_payload->>'codigo',''), internal.siguiente_numero(v_emp, 'CLI', 5)),
    v_tipo_doc, v_doc,
    p_payload->>'nombres',
    p_payload->>'apellido_paterno',
    p_payload->>'apellido_materno',
    p_payload->>'razon_social',
    p_payload->>'telefono',
    p_payload->>'telefono_alterno',
    lower(NULLIF(p_payload->>'correo','')),
    p_payload->>'direccion',
    p_payload->>'ubigeo',
    NULLIF(p_payload->>'fecha_nacimiento','')::date,
    COALESCE((p_payload->>'linea_credito')::numeric, 0),
    COALESCE((p_payload->>'dias_credito')::int, 0),
    COALESCE((p_payload->>'acepta_marketing')::boolean, true),
    p_payload->>'observaciones',
    p_user_id
  ) RETURNING id INTO v_id;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'crear', 'clientes', v_id, NULL, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_cliente_actualizar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_cliente_actualizar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_id             UUID,
  p_payload        JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_antes JSONB;
  v_emp   UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clientes:editar');

  -- El filtro por empresa va en el SELECT: un cliente de otra empresa se
  -- comporta como inexistente, sin revelar que existe.
  SELECT to_jsonb(c) - 'portal_password_hash' INTO v_antes
  FROM core.clientes c
  WHERE c.id = p_id AND c.deleted_at IS NULL
    AND (internal.es_acceso_global(p_user_id, p_is_super_admin) OR c.empresa_id = v_emp);

  IF v_antes IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Cliente no encontrado'));
  END IF;

  UPDATE core.clientes SET
    nombres          = COALESCE(p_payload->>'nombres', nombres),
    apellido_paterno = COALESCE(p_payload->>'apellido_paterno', apellido_paterno),
    apellido_materno = COALESCE(p_payload->>'apellido_materno', apellido_materno),
    razon_social     = COALESCE(p_payload->>'razon_social', razon_social),
    telefono         = COALESCE(p_payload->>'telefono', telefono),
    telefono_alterno = COALESCE(p_payload->>'telefono_alterno', telefono_alterno),
    correo           = COALESCE(lower(NULLIF(p_payload->>'correo','')), correo),
    direccion        = COALESCE(p_payload->>'direccion', direccion),
    ubigeo           = COALESCE(p_payload->>'ubigeo', ubigeo),
    fecha_nacimiento = COALESCE(NULLIF(p_payload->>'fecha_nacimiento','')::date, fecha_nacimiento),
    linea_credito    = COALESCE((p_payload->>'linea_credito')::numeric, linea_credito),
    dias_credito     = COALESCE((p_payload->>'dias_credito')::int, dias_credito),
    acepta_marketing = COALESCE((p_payload->>'acepta_marketing')::boolean, acepta_marketing),
    observaciones    = COALESCE(p_payload->>'observaciones', observaciones),
    estado           = COALESCE((p_payload->>'estado')::core.estado_cliente, estado),
    updated_by       = p_user_id
  WHERE id = p_id;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'actualizar', 'clientes', p_id, v_antes, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_cliente_activar_portal
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_cliente_activar_portal(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_id             UUID,
  p_password       TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clientes:editar');

  IF length(COALESCE(p_password,'')) < 8 THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'La contraseña del portal debe tener al menos 8 caracteres','password'));
  END IF;

  UPDATE core.clientes
     SET portal_acceso = true,
         portal_password_hash = crypt(p_password, gen_salt('bf', 10)),
         updated_by = p_user_id
   WHERE id = p_id AND deleted_at IS NULL
     AND (internal.es_acceso_global(p_user_id, p_is_super_admin) OR empresa_id = v_emp);

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Cliente no encontrado'));
  END IF;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'activar_portal', 'clientes', p_id);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'portal_acceso', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_cliente_eliminar — lógico, y solo si no tiene historia
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_cliente_eliminar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_id             UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_citas INT;
  v_emp   UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clientes:eliminar');

  IF NOT EXISTS (SELECT 1 FROM core.clientes
                  WHERE id = p_id AND deleted_at IS NULL
                    AND (internal.es_acceso_global(p_user_id, p_is_super_admin)
                         OR empresa_id = v_emp)) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Cliente no encontrado'));
  END IF;

  SELECT count(*) INTO v_citas FROM core.citas WHERE cliente_id = p_id AND deleted_at IS NULL;

  IF v_citas > 0 THEN
    UPDATE core.clientes SET estado = 'inactivo', updated_by = p_user_id WHERE id = p_id;
    RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
      'id', p_id, 'desactivado', true,
      'mensaje', 'El cliente tiene historial de atenciones: se desactivó en lugar de eliminarse.'));
  END IF;

  UPDATE core.clientes SET deleted_at = now(), estado = 'inactivo', updated_by = p_user_id
   WHERE id = p_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Cliente no encontrado'));
  END IF;

  PERFORM internal.registrar_auditoria(p_user_id, p_empresa_id, 'eliminar', 'clientes', p_id);
  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'eliminado', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- COMUNICACIONES (seguimiento al propietario)
-- =============================================================================

CREATE OR REPLACE FUNCTION app.fn_comunicaciones_listar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_cliente_id     UUID DEFAULT NULL,
  p_limit          INT DEFAULT 50
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_global BOOLEAN := internal.es_acceso_global(p_user_id, p_is_super_admin);
  v_emp    UUID    := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_data   JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(x ORDER BY x.fecha DESC), '[]'::jsonb) INTO v_data
  FROM (
    SELECT co.id, co.tipo, co.asunto, co.mensaje, co.fecha,
           co.requiere_seguimiento, co.fecha_seguimiento,
           co.cliente_id, co.mascota_id,
           trim(c.nombres || ' ' || COALESCE(c.apellido_paterno,'')) AS cliente,
           m.nombre AS mascota,
           trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS registrado_por
    FROM core.comunicaciones co
    JOIN core.clientes c ON c.id = co.cliente_id
    LEFT JOIN core.mascotas m ON m.id = co.mascota_id
    LEFT JOIN core.users u ON u.id = co.user_id
    WHERE (v_global OR co.empresa_id = v_emp)
      AND (p_cliente_id IS NULL OR co.cliente_id = p_cliente_id)
    ORDER BY co.fecha DESC
    LIMIT LEAST(COALESCE(p_limit, 50), 200)
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_comunicacion_registrar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_payload        JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_id  UUID;
  v_emp UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
BEGIN
  PERFORM internal.validar_payload(p_payload, ARRAY['cliente_id','mensaje']);

  INSERT INTO core.comunicaciones (
    empresa_id, cliente_id, mascota_id, user_id, tipo, asunto, mensaje,
    requiere_seguimiento, fecha_seguimiento, created_by
  ) VALUES (
    v_emp,
    (p_payload->>'cliente_id')::uuid,
    NULLIF(p_payload->>'mascota_id','')::uuid,
    p_user_id,
    COALESCE((p_payload->>'tipo')::core.tipo_comunicacion, 'llamada'),
    p_payload->>'asunto',
    p_payload->>'mensaje',
    COALESCE((p_payload->>'requiere_seguimiento')::boolean, false),
    NULLIF(p_payload->>'fecha_seguimiento','')::date,
    p_user_id
  ) RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;
