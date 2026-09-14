-- =============================================================================
-- 26_app_catalogos.sql — Especies, razas, servicios, categorías, consultorios,
-- horarios de atención, especializaciones, esquemas de vacunación y cláusulas.
-- =============================================================================

SET search_path = app, internal, core, public;

-- =============================================================================
-- ESPECIES Y RAZAS (maestros globales)
-- =============================================================================

CREATE OR REPLACE FUNCTION app.fn_especies_listar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_incluir_inactivos BOOLEAN DEFAULT false
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
  SELECT COALESCE(jsonb_agg(x ORDER BY x.nombre), '[]'::jsonb) INTO v_data
  FROM (
    SELECT e.id, e.codigo, e.nombre, e.nombre_cria, e.icono, e.estado,
           -- El conteo es de la empresa que consulta, no de toda la instalación.
           (SELECT count(*) FROM core.mascotas m
             WHERE m.especie_id = e.id AND m.deleted_at IS NULL
               AND (v_global OR m.empresa_id = v_emp)) AS total_pacientes,
           -- Razas globales (empresa_id NULL) más las que agregó esta empresa.
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id', r.id, 'nombre', r.nombre, 'tamanio_referencia', r.tamanio_referencia,
                     'peso_min_kg', r.peso_min_kg, 'peso_max_kg', r.peso_max_kg,
                     'esperanza_vida', r.esperanza_vida, 'estado', r.estado,
                     'propia', r.empresa_id IS NOT NULL)
                   ORDER BY r.nombre), '[]'::jsonb)
              FROM core.razas r
             WHERE r.especie_id = e.id
               AND (r.empresa_id IS NULL OR v_global OR r.empresa_id = v_emp)
               AND (p_incluir_inactivos OR r.estado = 'activo')) AS razas
    FROM core.especies e
    WHERE (p_incluir_inactivos OR e.estado = 'activo')
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_especie_guardar(
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
  v_id UUID := NULLIF(p_payload->>'id','')::uuid;
BEGIN
  IF NOT p_is_super_admin THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('FORBIDDEN',
        'La taxonomía (especies, razas y especialidades) la mantiene el operador del ERP: '
        'es compartida por todas las empresas'));
  END IF;
  PERFORM internal.assert_permiso(p_user_id, 'catalogos:gestionar');
  PERFORM internal.validar_payload(p_payload, ARRAY['nombre']);

  IF v_id IS NULL THEN
    INSERT INTO core.especies (codigo, nombre, nombre_cria, icono, estado)
    VALUES (
      COALESCE(NULLIF(p_payload->>'codigo',''),
               upper(regexp_replace(internal.normalizar(p_payload->>'nombre'), '[^a-z0-9]+', '_', 'g'))),
      p_payload->>'nombre', p_payload->>'nombre_cria',
      COALESCE(NULLIF(p_payload->>'icono',''), 'PawPrint'),
      COALESCE((p_payload->>'estado')::core.estado_generico, 'activo'))
    RETURNING id INTO v_id;
  ELSE
    UPDATE core.especies SET
      nombre      = COALESCE(p_payload->>'nombre', nombre),
      nombre_cria = COALESCE(p_payload->>'nombre_cria', nombre_cria),
      icono       = COALESCE(NULLIF(p_payload->>'icono',''), icono),
      estado      = COALESCE((p_payload->>'estado')::core.estado_generico, estado)
    WHERE id = v_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('CONFLICT','Ya existe una especie con ese código','codigo'));
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_raza_guardar(
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
  v_id  UUID := NULLIF(p_payload->>'id','')::uuid;
  v_emp UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'catalogos:gestionar');

  -- Una raza sin empresa es taxonomía global y solo la toca el operador del ERP.
  -- Cualquier empresa puede crear las SUYAS, que solo ella ve: así no necesita un
  -- campo de texto libre en la ficha del paciente para las razas fuera de catálogo.
  IF v_id IS NULL THEN
    PERFORM internal.validar_payload(p_payload, ARRAY['especie_id','nombre']);
    INSERT INTO core.razas (
      especie_id, empresa_id, nombre, tamanio_referencia, peso_min_kg, peso_max_kg,
      esperanza_vida, estado
    ) VALUES (
      (p_payload->>'especie_id')::uuid,
      CASE WHEN p_is_super_admin AND COALESCE((p_payload->>'global')::boolean, false)
           THEN NULL ELSE v_emp END,
      p_payload->>'nombre',
      NULLIF(p_payload->>'tamanio_referencia','')::core.tamanio_mascota,
      NULLIF(p_payload->>'peso_min_kg','')::numeric,
      NULLIF(p_payload->>'peso_max_kg','')::numeric,
      NULLIF(p_payload->>'esperanza_vida','')::int,
      COALESCE((p_payload->>'estado')::core.estado_generico, 'activo'))
    RETURNING id INTO v_id;
  ELSE
    -- Editar: la global solo el super admin; la propia, su empresa.
    IF NOT EXISTS (SELECT 1 FROM core.razas
                    WHERE id = v_id
                      AND ((empresa_id IS NULL AND p_is_super_admin)
                           OR internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, empresa_id))) THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('FORBIDDEN',
          'Las razas del catálogo global las mantiene el operador del ERP'));
    END IF;

    UPDATE core.razas SET
      nombre             = COALESCE(p_payload->>'nombre', nombre),
      tamanio_referencia = COALESCE(NULLIF(p_payload->>'tamanio_referencia','')::core.tamanio_mascota, tamanio_referencia),
      peso_min_kg        = COALESCE(NULLIF(p_payload->>'peso_min_kg','')::numeric, peso_min_kg),
      peso_max_kg        = COALESCE(NULLIF(p_payload->>'peso_max_kg','')::numeric, peso_max_kg),
      esperanza_vida     = COALESCE(NULLIF(p_payload->>'esperanza_vida','')::int, esperanza_vida),
      estado             = COALESCE((p_payload->>'estado')::core.estado_generico, estado)
    WHERE id = v_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('CONFLICT','Esa raza ya existe para la especie','nombre'));
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- SERVICIOS
-- =============================================================================

CREATE OR REPLACE FUNCTION app.fn_servicios_listar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_filtros        JSONB DEFAULT '{}'::jsonb
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
  v_data   JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(x ORDER BY x.tipo, x.nombre), '[]'::jsonb) INTO v_data
  FROM (
    SELECT s.id, s.codigo, s.nombre, s.descripcion, s.tipo, s.precio, s.costo_estimado,
           s.duracion_min, s.requiere_ayuno, s.requiere_cita, s.afecto_igv,
           s.categoria_id, s.estado, s.empresa_id,
           cat.nombre AS categoria,
           (SELECT count(*) FROM core.ordenes_servicio os
             WHERE os.servicio_id = s.id
               AND os.fecha >= date_trunc('month', CURRENT_DATE)) AS usos_mes
    FROM core.servicios s
    LEFT JOIN core.categorias cat ON cat.id = s.categoria_id
    WHERE s.deleted_at IS NULL
      AND (v_global OR s.empresa_id = v_emp)
      AND (p_filtros->>'tipo'   IS NULL OR s.tipo::text = p_filtros->>'tipo')
      AND (p_filtros->>'estado' IS NULL OR s.estado::text = p_filtros->>'estado')
      AND (p_filtros->>'categoria_id' IS NULL OR s.categoria_id = (p_filtros->>'categoria_id')::uuid)
      AND (v_buscar IS NULL OR v_buscar = '' OR
           internal.normalizar(s.nombre) LIKE '%' || v_buscar || '%' OR
           internal.normalizar(s.codigo) LIKE '%' || v_buscar || '%')
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_servicio_guardar(
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
  v_id  UUID := NULLIF(p_payload->>'id','')::uuid;
  v_emp UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'servicios:gestionar');

  IF v_id IS NULL THEN
    PERFORM internal.validar_payload(p_payload, ARRAY['nombre','precio']);
    INSERT INTO core.servicios (
      empresa_id, codigo, nombre, descripcion, tipo, categoria_id, precio,
      costo_estimado, duracion_min, requiere_ayuno, requiere_cita, afecto_igv,
      producto_id, estado, created_by
    ) VALUES (
      v_emp,
      COALESCE(NULLIF(p_payload->>'codigo',''), internal.siguiente_numero(v_emp, 'SRV', 4)),
      p_payload->>'nombre', p_payload->>'descripcion',
      COALESCE((p_payload->>'tipo')::core.tipo_servicio, 'consulta'),
      NULLIF(p_payload->>'categoria_id','')::uuid,
      (p_payload->>'precio')::numeric,
      COALESCE((p_payload->>'costo_estimado')::numeric, 0),
      COALESCE((p_payload->>'duracion_min')::int, 30),
      COALESCE((p_payload->>'requiere_ayuno')::boolean, false),
      COALESCE((p_payload->>'requiere_cita')::boolean, true),
      COALESCE((p_payload->>'afecto_igv')::boolean, true),
      NULLIF(p_payload->>'producto_id','')::uuid,
      COALESCE((p_payload->>'estado')::core.estado_generico, 'activo'),
      p_user_id
    ) RETURNING id INTO v_id;
  ELSE
    -- Editar exige que el servicio sea de la empresa: con solo el UUID, otra
    -- empresa podría reescribir el catálogo ajeno.
    IF NOT EXISTS (SELECT 1 FROM core.servicios
                    WHERE id = v_id AND deleted_at IS NULL
                      AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, empresa_id)) THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('NOT_FOUND','Servicio no encontrado'));
    END IF;

    UPDATE core.servicios SET
      nombre         = COALESCE(p_payload->>'nombre', nombre),
      descripcion    = COALESCE(p_payload->>'descripcion', descripcion),
      tipo           = COALESCE((p_payload->>'tipo')::core.tipo_servicio, tipo),
      categoria_id   = COALESCE(NULLIF(p_payload->>'categoria_id','')::uuid, categoria_id),
      precio         = COALESCE((p_payload->>'precio')::numeric, precio),
      costo_estimado = COALESCE((p_payload->>'costo_estimado')::numeric, costo_estimado),
      duracion_min   = COALESCE((p_payload->>'duracion_min')::int, duracion_min),
      requiere_ayuno = COALESCE((p_payload->>'requiere_ayuno')::boolean, requiere_ayuno),
      requiere_cita  = COALESCE((p_payload->>'requiere_cita')::boolean, requiere_cita),
      afecto_igv     = COALESCE((p_payload->>'afecto_igv')::boolean, afecto_igv),
      producto_id    = COALESCE(NULLIF(p_payload->>'producto_id','')::uuid, producto_id),
      estado         = COALESCE((p_payload->>'estado')::core.estado_generico, estado),
      updated_by     = p_user_id
    WHERE id = v_id AND deleted_at IS NULL;
  END IF;

  PERFORM internal.registrar_auditoria(p_user_id, v_emp, 'guardar', 'servicios', v_id, NULL, p_payload);
  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('CONFLICT','Ya existe un servicio con ese código','codigo'));
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_servicio_eliminar(
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
  v_usos INT;
  v_emp  UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'servicios:gestionar');

  IF NOT EXISTS (SELECT 1 FROM core.servicios
                  WHERE id = p_id AND deleted_at IS NULL
                    AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, empresa_id)) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Servicio no encontrado'));
  END IF;

  SELECT count(*) INTO v_usos FROM core.ordenes_servicio WHERE servicio_id = p_id;
  IF v_usos > 0 THEN
    UPDATE core.servicios SET estado = 'inactivo', updated_by = p_user_id WHERE id = p_id;
    RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
      'id', p_id, 'desactivado', true,
      'mensaje', 'El servicio ya fue prestado a pacientes: se desactivó para no romper el histórico.'));
  END IF;

  UPDATE core.servicios SET deleted_at = now(), estado = 'inactivo', updated_by = p_user_id
   WHERE id = p_id AND deleted_at IS NULL;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'eliminado', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- CATEGORÍAS (servicio / producto / proveedor)
-- =============================================================================

CREATE OR REPLACE FUNCTION app.fn_categorias_listar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_ambito         VARCHAR DEFAULT NULL
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
  SELECT COALESCE(jsonb_agg(x ORDER BY x.ambito, x.orden, x.nombre), '[]'::jsonb) INTO v_data
  FROM (
    SELECT c.id, c.ambito, c.codigo, c.nombre, c.descripcion, c.padre_id, c.orden, c.estado
    FROM core.categorias c
    WHERE (v_global OR c.empresa_id = v_emp)
      AND (p_ambito IS NULL OR c.ambito = p_ambito)
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_categoria_guardar(
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
  v_id  UUID := NULLIF(p_payload->>'id','')::uuid;
  v_emp UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'catalogos:gestionar');

  IF v_id IS NULL THEN
    PERFORM internal.validar_payload(p_payload, ARRAY['ambito','nombre']);
    INSERT INTO core.categorias (empresa_id, ambito, codigo, nombre, descripcion, padre_id, orden, estado)
    VALUES (
      v_emp, p_payload->>'ambito',
      COALESCE(NULLIF(p_payload->>'codigo',''),
               upper(substr(regexp_replace(internal.normalizar(p_payload->>'nombre'), '[^a-z0-9]+', '', 'g'), 1, 12))
               || '-' || substr(gen_random_uuid()::text, 1, 4)),
      p_payload->>'nombre', p_payload->>'descripcion',
      NULLIF(p_payload->>'padre_id','')::uuid,
      COALESCE((p_payload->>'orden')::int, 0),
      COALESCE((p_payload->>'estado')::core.estado_generico, 'activo'))
    RETURNING id INTO v_id;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM core.categorias
                    WHERE id = v_id
                      AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, empresa_id)) THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('NOT_FOUND','Categoría no encontrada'));
    END IF;

    UPDATE core.categorias SET
      nombre      = COALESCE(p_payload->>'nombre', nombre),
      descripcion = COALESCE(p_payload->>'descripcion', descripcion),
      padre_id    = COALESCE(NULLIF(p_payload->>'padre_id','')::uuid, padre_id),
      orden       = COALESCE((p_payload->>'orden')::int, orden),
      estado      = COALESCE((p_payload->>'estado')::core.estado_generico, estado)
    WHERE id = v_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- CONSULTORIOS, HORARIOS, ESPECIALIZACIONES, ESQUEMAS DE VACUNACIÓN, CLÁUSULAS
-- =============================================================================

CREATE OR REPLACE FUNCTION app.fn_consultorios_listar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN
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
  SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.nombre), '[]'::jsonb) INTO v_data
  FROM core.consultorios c
  WHERE (v_global OR c.empresa_id = v_emp);

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_consultorio_guardar(
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
  v_id  UUID := NULLIF(p_payload->>'id','')::uuid;
  v_emp UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'catalogos:gestionar');

  IF v_id IS NULL THEN
    PERFORM internal.validar_payload(p_payload, ARRAY['nombre']);
    INSERT INTO core.consultorios (empresa_id, nombre, tipo, capacidad, estado)
    VALUES (v_emp, p_payload->>'nombre', COALESCE(p_payload->>'tipo','consulta'),
            COALESCE((p_payload->>'capacidad')::int, 1),
            COALESCE((p_payload->>'estado')::core.estado_generico, 'activo'))
    RETURNING id INTO v_id;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM core.consultorios
                    WHERE id = v_id
                      AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, empresa_id)) THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('NOT_FOUND','Consultorio no encontrado'));
    END IF;

    UPDATE core.consultorios SET
      nombre    = COALESCE(p_payload->>'nombre', nombre),
      tipo      = COALESCE(p_payload->>'tipo', tipo),
      capacidad = COALESCE((p_payload->>'capacidad')::int, capacidad),
      estado    = COALESCE((p_payload->>'estado')::core.estado_generico, estado)
    WHERE id = v_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_horarios_atencion_listar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp  UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_data JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(to_jsonb(h) ORDER BY h.dia_semana, h.hora_inicio), '[]'::jsonb) INTO v_data
  FROM core.horarios_atencion h WHERE h.empresa_id = v_emp;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- Reemplaza el horario semanal completo: es más simple y evita estados a medias.
CREATE OR REPLACE FUNCTION app.sp_horarios_atencion_guardar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_horarios       JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp  UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_item JSONB;
  v_n    INT := 0;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'catalogos:gestionar');

  DELETE FROM core.horarios_atencion WHERE empresa_id = v_emp;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_horarios) LOOP
    INSERT INTO core.horarios_atencion (empresa_id, dia_semana, hora_inicio, hora_fin, activo, es_guardia)
    VALUES (
      v_emp,
      (v_item->>'dia_semana')::int,
      (v_item->>'hora_inicio')::time,
      (v_item->>'hora_fin')::time,
      COALESCE((v_item->>'activo')::boolean, true),
      COALESCE((v_item->>'es_guardia')::boolean, false));
    v_n := v_n + 1;
  END LOOP;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'guardar', 'horarios_atencion', NULL, NULL, p_horarios);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('guardados', v_n));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_especializaciones_listar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN
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
  SELECT COALESCE(jsonb_agg(x ORDER BY x.nombre), '[]'::jsonb) INTO v_data
  FROM (
    SELECT e.id, e.codigo, e.nombre, e.descripcion, e.estado,
           (SELECT count(*) FROM core.users u
             WHERE u.especializacion_id = e.id AND u.deleted_at IS NULL
               AND (v_global OR u.empresa_id = v_emp)) AS veterinarios
    FROM core.especializaciones e
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_especializacion_guardar(
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
  v_id UUID := NULLIF(p_payload->>'id','')::uuid;
BEGIN
  IF NOT p_is_super_admin THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('FORBIDDEN',
        'La taxonomía (especies, razas y especialidades) la mantiene el operador del ERP: '
        'es compartida por todas las empresas'));
  END IF;
  PERFORM internal.assert_permiso(p_user_id, 'catalogos:gestionar');

  IF v_id IS NULL THEN
    PERFORM internal.validar_payload(p_payload, ARRAY['nombre']);
    INSERT INTO core.especializaciones (codigo, nombre, descripcion, estado)
    VALUES (
      COALESCE(NULLIF(p_payload->>'codigo',''),
               upper(regexp_replace(internal.normalizar(p_payload->>'nombre'), '[^a-z0-9]+', '_', 'g'))),
      p_payload->>'nombre', p_payload->>'descripcion',
      COALESCE((p_payload->>'estado')::core.estado_generico, 'activo'))
    RETURNING id INTO v_id;
  ELSE
    UPDATE core.especializaciones SET
      nombre      = COALESCE(p_payload->>'nombre', nombre),
      descripcion = COALESCE(p_payload->>'descripcion', descripcion),
      estado      = COALESCE((p_payload->>'estado')::core.estado_generico, estado)
    WHERE id = v_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('CONFLICT','Ya existe una especialidad con ese código','codigo'));
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_esquemas_vacunacion_listar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_especie_id     UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp  UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_data JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(x ORDER BY x.especie, x.nombre), '[]'::jsonb) INTO v_data
  FROM (
    SELECT ev.id, ev.nombre, ev.descripcion, ev.obligatoria, ev.edad_inicio_semanas,
           ev.intervalo_dias, ev.dosis_totales, ev.revacunacion_meses, ev.estado,
           ev.especie_id, e.nombre AS especie
    FROM core.esquemas_vacunacion ev
    JOIN core.especies e ON e.id = ev.especie_id
    WHERE ev.empresa_id = v_emp
      AND (p_especie_id IS NULL OR ev.especie_id = p_especie_id)
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_esquema_vacunacion_guardar(
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
  v_id  UUID := NULLIF(p_payload->>'id','')::uuid;
  v_emp UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'catalogos:gestionar');

  IF v_id IS NULL THEN
    PERFORM internal.validar_payload(p_payload, ARRAY['especie_id','nombre']);
    INSERT INTO core.esquemas_vacunacion (
      empresa_id, especie_id, nombre, descripcion, obligatoria,
      edad_inicio_semanas, intervalo_dias, dosis_totales, revacunacion_meses, estado
    ) VALUES (
      v_emp, (p_payload->>'especie_id')::uuid, p_payload->>'nombre', p_payload->>'descripcion',
      COALESCE((p_payload->>'obligatoria')::boolean, false),
      NULLIF(p_payload->>'edad_inicio_semanas','')::int,
      NULLIF(p_payload->>'intervalo_dias','')::int,
      COALESCE((p_payload->>'dosis_totales')::int, 1),
      NULLIF(p_payload->>'revacunacion_meses','')::int,
      COALESCE((p_payload->>'estado')::core.estado_generico, 'activo'))
    RETURNING id INTO v_id;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM core.esquemas_vacunacion
                    WHERE id = v_id
                      AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, empresa_id)) THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('NOT_FOUND','Protocolo no encontrado'));
    END IF;

    UPDATE core.esquemas_vacunacion SET
      nombre              = COALESCE(p_payload->>'nombre', nombre),
      descripcion         = COALESCE(p_payload->>'descripcion', descripcion),
      obligatoria         = COALESCE((p_payload->>'obligatoria')::boolean, obligatoria),
      edad_inicio_semanas = COALESCE(NULLIF(p_payload->>'edad_inicio_semanas','')::int, edad_inicio_semanas),
      intervalo_dias      = COALESCE(NULLIF(p_payload->>'intervalo_dias','')::int, intervalo_dias),
      dosis_totales       = COALESCE((p_payload->>'dosis_totales')::int, dosis_totales),
      revacunacion_meses  = COALESCE(NULLIF(p_payload->>'revacunacion_meses','')::int, revacunacion_meses),
      estado              = COALESCE((p_payload->>'estado')::core.estado_generico, estado)
    WHERE id = v_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_clausulas_listar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_tipo           VARCHAR DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp  UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_data JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(to_jsonb(c) ORDER BY c.orden, c.titulo), '[]'::jsonb) INTO v_data
  FROM core.clausulas c
  WHERE c.empresa_id = v_emp AND (p_tipo IS NULL OR c.tipo = p_tipo);

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_clausula_guardar(
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
  v_id  UUID := NULLIF(p_payload->>'id','')::uuid;
  v_emp UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'catalogos:gestionar');

  IF v_id IS NULL THEN
    PERFORM internal.validar_payload(p_payload, ARRAY['titulo','contenido']);
    INSERT INTO core.clausulas (empresa_id, tipo, titulo, contenido, orden, estado)
    VALUES (v_emp, COALESCE(p_payload->>'tipo','consentimiento'),
            p_payload->>'titulo', p_payload->>'contenido',
            COALESCE((p_payload->>'orden')::int, 0),
            COALESCE((p_payload->>'estado')::core.estado_generico, 'activo'))
    RETURNING id INTO v_id;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM core.clausulas
                    WHERE id = v_id
                      AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, empresa_id)) THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('NOT_FOUND','Cláusula no encontrada'));
    END IF;

    UPDATE core.clausulas SET
      tipo      = COALESCE(p_payload->>'tipo', tipo),
      titulo    = COALESCE(p_payload->>'titulo', titulo),
      contenido = COALESCE(p_payload->>'contenido', contenido),
      orden     = COALESCE((p_payload->>'orden')::int, orden),
      estado    = COALESCE((p_payload->>'estado')::core.estado_generico, estado)
    WHERE id = v_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;
