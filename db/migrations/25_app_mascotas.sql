-- =============================================================================
-- 25_app_mascotas.sql — Pacientes: ficha, historia clínica y extravíos
--
-- Los pacientes son de la empresa: heredan empresa_id de su propietario y toda
-- lectura filtra por él. La historia clínica de un paciente no sale de su empresa.
-- =============================================================================

SET search_path = app, internal, core, public;

-- -----------------------------------------------------------------------------
-- app.fn_mascota_listar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_mascota_listar(
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
  v_global  BOOLEAN := internal.es_acceso_global(p_user_id, p_is_super_admin);
  v_emp     UUID    := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_buscar  TEXT    := internal.normalizar(p_filtros->>'buscar');
  v_size    INT     := LEAST(GREATEST(COALESCE(p_page_size, 20), 1), 100);
  v_page    INT     := GREATEST(COALESCE(p_page, 1), 1);
  v_total   INT;
  v_data    JSONB;
BEGIN
  SELECT count(*) INTO v_total
  FROM core.mascotas m
  JOIN core.clientes c ON c.id = m.cliente_id
  WHERE m.deleted_at IS NULL
    AND (v_global OR m.empresa_id = v_emp)
    AND (p_filtros->>'estado'     IS NULL OR m.estado::text = p_filtros->>'estado')
    AND (p_filtros->>'especie_id' IS NULL OR m.especie_id = (p_filtros->>'especie_id')::uuid)
    AND (p_filtros->>'cliente_id' IS NULL OR m.cliente_id = (p_filtros->>'cliente_id')::uuid)
    AND (p_filtros->>'sexo'       IS NULL OR m.sexo::text = p_filtros->>'sexo')
    AND (v_buscar IS NULL OR v_buscar = '' OR
         internal.normalizar(m.nombre) LIKE '%' || v_buscar || '%' OR
         COALESCE(m.microchip,'') LIKE '%' || COALESCE(p_filtros->>'buscar','') || '%' OR
         COALESCE(m.codigo,'') LIKE '%' || upper(COALESCE(p_filtros->>'buscar','')) || '%' OR
         internal.normalizar(c.nombres || ' ' || COALESCE(c.apellido_paterno,''))
           LIKE '%' || v_buscar || '%');

  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) INTO v_data
  FROM (
    SELECT m.id, m.codigo, m.nombre, m.sexo, m.color, m.peso_kg, m.tamanio,
           m.fecha_nacimiento, m.esterilizado, m.microchip, m.foto_url,
           m.alergias, m.condiciones_cronicas, m.estado, m.created_at,
           internal.edad_mascota(m.fecha_nacimiento, m.edad_aproximada_meses) AS edad,
           m.especie_id, e.nombre AS especie, e.icono AS especie_icono,
           m.raza_id, r.nombre AS raza,
           m.cliente_id,
           trim(c.nombres || ' ' || COALESCE(c.apellido_paterno,'') || ' ' ||
                COALESCE(c.apellido_materno,'')) AS propietario,
           c.telefono AS propietario_telefono,
           (SELECT max(ci.fecha_hora) FROM core.citas ci
             WHERE ci.mascota_id = m.id AND ci.estado = 'completada'
               AND ci.deleted_at IS NULL
               AND (v_global OR ci.empresa_id = v_emp)) AS ultima_visita,
           (SELECT min(v.proximo_refuerzo) FROM core.vacunas v
             WHERE v.mascota_id = m.id AND v.proximo_refuerzo >= CURRENT_DATE) AS proxima_vacuna,
           (SELECT count(*) FROM core.consultas co
             WHERE co.mascota_id = m.id AND co.deleted_at IS NULL) AS total_consultas
    FROM core.mascotas m
    JOIN core.clientes c ON c.id = m.cliente_id
    JOIN core.especies e ON e.id = m.especie_id
    LEFT JOIN core.razas r ON r.id = m.raza_id
    WHERE m.deleted_at IS NULL
      AND (v_global OR m.empresa_id = v_emp)
      AND (p_filtros->>'estado'     IS NULL OR m.estado::text = p_filtros->>'estado')
      AND (p_filtros->>'especie_id' IS NULL OR m.especie_id = (p_filtros->>'especie_id')::uuid)
      AND (p_filtros->>'cliente_id' IS NULL OR m.cliente_id = (p_filtros->>'cliente_id')::uuid)
      AND (p_filtros->>'sexo'       IS NULL OR m.sexo::text = p_filtros->>'sexo')
      AND (v_buscar IS NULL OR v_buscar = '' OR
           internal.normalizar(m.nombre) LIKE '%' || v_buscar || '%' OR
           COALESCE(m.microchip,'') LIKE '%' || COALESCE(p_filtros->>'buscar','') || '%' OR
           COALESCE(m.codigo,'') LIKE '%' || upper(COALESCE(p_filtros->>'buscar','')) || '%' OR
           internal.normalizar(c.nombres || ' ' || COALESCE(c.apellido_paterno,''))
             LIKE '%' || v_buscar || '%')
    ORDER BY m.nombre
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
-- app.fn_mascota_obtener — ficha clínica completa del paciente
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_mascota_obtener(
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
    SELECT m.id, m.codigo, m.nombre, m.sexo, m.color, m.senias_particulares,
           m.fecha_nacimiento, m.edad_aproximada_meses, m.peso_kg, m.tamanio,
           m.esterilizado, m.fecha_esterilizacion, m.microchip, m.num_placa,
           m.foto_url, m.alergias, m.condiciones_cronicas, m.observaciones,
           m.estado, m.fecha_fallecimiento, m.created_at,
           internal.edad_mascota(m.fecha_nacimiento, m.edad_aproximada_meses) AS edad,
           m.especie_id, e.nombre AS especie, e.icono AS especie_icono,
           m.raza_id, r.nombre AS raza,
           r.esperanza_vida,
           -- Propietario
           jsonb_build_object(
             'id', c.id, 'codigo', c.codigo,
             'nombre_completo', trim(c.nombres || ' ' || COALESCE(c.apellido_paterno,'') || ' ' ||
                                     COALESCE(c.apellido_materno,'')),
             'telefono', c.telefono, 'correo', c.correo,
             'numero_documento', c.numero_documento, 'direccion', c.direccion
           ) AS propietario,
           -- Vacunas
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id', v.id, 'nombre_vacuna', v.nombre_vacuna, 'laboratorio', v.laboratorio,
                     'lote', v.lote, 'fecha_aplicacion', v.fecha_aplicacion,
                     'proximo_refuerzo', v.proximo_refuerzo, 'dosis_numero', v.dosis_numero,
                     'vencida', (v.proximo_refuerzo IS NOT NULL AND v.proximo_refuerzo < CURRENT_DATE))
                   ORDER BY v.fecha_aplicacion DESC), '[]'::jsonb)
              FROM core.vacunas v WHERE v.mascota_id = m.id) AS vacunas,
           -- Tratamientos activos
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id', t.id, 'medicamento', t.medicamento, 'dosis', t.dosis,
                     'via', t.via, 'frecuencia_horas', t.frecuencia_horas,
                     'fecha_inicio', t.fecha_inicio, 'fecha_fin', t.fecha_fin,
                     'estado', t.estado)
                   ORDER BY t.fecha_inicio DESC), '[]'::jsonb)
              FROM core.tratamientos t
             WHERE t.mascota_id = m.id AND t.estado = 'activo') AS tratamientos_activos,
           -- Cirugías
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id', ci.id, 'nombre', ci.nombre, 'fecha_programada', ci.fecha_programada,
                     'fecha_inicio', ci.fecha_inicio, 'estado', ci.estado, 'resultado', ci.resultado)
                   ORDER BY COALESCE(ci.fecha_inicio, ci.fecha_programada) DESC), '[]'::jsonb)
              FROM core.cirugias ci WHERE ci.mascota_id = m.id) AS cirugias,
           -- Curva de peso: alimenta el gráfico de la ficha
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'fecha', co.fecha, 'peso_kg', co.peso_kg) ORDER BY co.fecha), '[]'::jsonb)
              FROM core.consultas co
             WHERE co.mascota_id = m.id AND co.peso_kg IS NOT NULL
               AND co.deleted_at IS NULL) AS curva_peso,
           -- Próxima cita
           (SELECT jsonb_build_object('id', ci.id, 'fecha_hora', ci.fecha_hora,
                                      'motivo', ci.motivo, 'estado', ci.estado)
              FROM core.citas ci
             WHERE ci.mascota_id = m.id AND ci.deleted_at IS NULL
               AND ci.fecha_hora >= now()
               AND ci.estado IN ('programada','confirmada')
             ORDER BY ci.fecha_hora LIMIT 1) AS proxima_cita,
           -- Hospitalización en curso
           (SELECT jsonb_build_object('id', h.id, 'fecha_ingreso', h.fecha_ingreso,
                                      'motivo', h.motivo, 'jaula', h.jaula, 'estado', h.estado)
              FROM core.hospitalizaciones h
             WHERE h.mascota_id = m.id AND h.estado IN ('ingresado','en_observacion')
             ORDER BY h.fecha_ingreso DESC LIMIT 1) AS hospitalizacion_actual,
           (SELECT count(*) FROM core.consultas co
             WHERE co.mascota_id = m.id AND co.deleted_at IS NULL) AS total_consultas
    FROM core.mascotas m
    JOIN core.clientes c ON c.id = m.cliente_id
    JOIN core.especies e ON e.id = m.especie_id
    LEFT JOIN core.razas r ON r.id = m.raza_id
    WHERE m.id = p_id AND m.deleted_at IS NULL
      AND (v_global OR m.empresa_id = v_emp)
  ) x;

  IF v_data IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Paciente no encontrado'));
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_mascota_historia — línea de tiempo clínica del paciente
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_mascota_historia(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_mascota_id     UUID,
  p_tipo           VARCHAR DEFAULT NULL,
  p_limit          INT DEFAULT 100
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
  -- Si el paciente no es de la empresa, se responde NOT_FOUND igual que en el
  -- resto del módulo. Devolver una lista vacía sugeriría que existe pero no
  -- tiene historia, que es otra cosa.
  IF NOT EXISTS (SELECT 1 FROM core.mascotas
                  WHERE id = p_mascota_id AND deleted_at IS NULL
                    AND (v_global OR empresa_id = v_emp)) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Paciente no encontrado'));
  END IF;

  SELECT COALESCE(jsonb_agg(x ORDER BY x.fecha DESC), '[]'::jsonb) INTO v_data
  FROM (
    SELECT h.id, h.tipo_evento, h.fecha, h.titulo, h.resumen, h.entidad_id, h.cita_id,
           h.empresa_id, emp.nombre_comercial AS empresa,
           h.veterinario_id,
           trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS veterinario,
           u.colegiatura
    FROM core.historia_clinica h
    LEFT JOIN core.users u ON u.id = h.veterinario_id
    LEFT JOIN core.empresas emp ON emp.id = h.empresa_id
    WHERE h.mascota_id = p_mascota_id
      -- Cada empresa ve solo los eventos que registró: son negocios distintos.
      AND (v_global OR h.empresa_id = v_emp)
      AND (p_tipo IS NULL OR h.tipo_evento::text = p_tipo)
    ORDER BY h.fecha DESC
    LIMIT LEAST(COALESCE(p_limit, 100), 500)
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_mascota_crear
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_mascota_crear(
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
  v_id   UUID;
  v_emp  UUID;   -- se hereda del propietario, ver abajo
  v_chip TEXT := NULLIF(p_payload->>'microchip','');
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'mascotas:crear');
  PERFORM internal.validar_payload(p_payload, ARRAY['cliente_id','nombre','especie_id']);

  -- La empresa la manda el propietario, no el payload: así una mascota nunca
  -- queda en una empresa distinta a la de su dueño.
  SELECT empresa_id INTO v_emp FROM core.clientes
   WHERE id = (p_payload->>'cliente_id')::uuid AND deleted_at IS NULL
     AND (internal.es_acceso_global(p_user_id, p_is_super_admin)
          OR empresa_id = internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin));

  IF v_emp IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','El propietario indicado no existe','cliente_id'));
  END IF;

  IF v_chip IS NOT NULL AND EXISTS (
      SELECT 1 FROM core.mascotas
       WHERE empresa_id = v_emp AND microchip = v_chip AND deleted_at IS NULL) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('CONFLICT','Ese microchip ya está registrado en otro paciente','microchip'));
  END IF;

  INSERT INTO core.mascotas (
    empresa_id, codigo, cliente_id, nombre, especie_id, raza_id, sexo, color,
    senias_particulares, fecha_nacimiento, edad_aproximada_meses, peso_kg, tamanio,
    esterilizado, fecha_esterilizacion, microchip, num_placa, foto_url,
    alergias, condiciones_cronicas, observaciones, created_by
  ) VALUES (
    v_emp,
    COALESCE(NULLIF(p_payload->>'codigo',''), internal.siguiente_numero(v_emp, 'HC', 6)),
    (p_payload->>'cliente_id')::uuid,
    p_payload->>'nombre',
    (p_payload->>'especie_id')::uuid,
    NULLIF(p_payload->>'raza_id','')::uuid,
    COALESCE((p_payload->>'sexo')::core.sexo_mascota, 'desconocido'),
    p_payload->>'color',
    p_payload->>'senias_particulares',
    NULLIF(p_payload->>'fecha_nacimiento','')::date,
    NULLIF(p_payload->>'edad_aproximada_meses','')::int,
    NULLIF(p_payload->>'peso_kg','')::numeric,
    NULLIF(p_payload->>'tamanio','')::core.tamanio_mascota,
    COALESCE((p_payload->>'esterilizado')::boolean, false),
    NULLIF(p_payload->>'fecha_esterilizacion','')::date,
    v_chip,
    NULLIF(p_payload->>'num_placa',''),
    p_payload->>'foto_url',
    p_payload->>'alergias',
    p_payload->>'condiciones_cronicas',
    p_payload->>'observaciones',
    p_user_id
  ) RETURNING id INTO v_id;

  PERFORM internal.registrar_auditoria(p_user_id, v_emp, 'crear', 'mascotas', v_id, NULL, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_mascota_actualizar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_mascota_actualizar(
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
  v_chip  TEXT := NULLIF(p_payload->>'microchip','');
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'mascotas:editar');

  SELECT to_jsonb(m) INTO v_antes FROM core.mascotas m
   WHERE m.id = p_id AND m.deleted_at IS NULL
     AND (internal.es_acceso_global(p_user_id, p_is_super_admin) OR m.empresa_id = v_emp);

  IF v_antes IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Paciente no encontrado'));
  END IF;

  IF v_chip IS NOT NULL AND EXISTS (
      SELECT 1 FROM core.mascotas
       WHERE empresa_id = (v_antes->>'empresa_id')::uuid
         AND microchip = v_chip AND id <> p_id AND deleted_at IS NULL) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('CONFLICT','Ese microchip ya está registrado en otro paciente','microchip'));
  END IF;

  UPDATE core.mascotas SET
    nombre               = COALESCE(p_payload->>'nombre', nombre),
    especie_id           = COALESCE(NULLIF(p_payload->>'especie_id','')::uuid, especie_id),
    raza_id              = COALESCE(NULLIF(p_payload->>'raza_id','')::uuid, raza_id),
    sexo                 = COALESCE((p_payload->>'sexo')::core.sexo_mascota, sexo),
    color                = COALESCE(p_payload->>'color', color),
    senias_particulares  = COALESCE(p_payload->>'senias_particulares', senias_particulares),
    fecha_nacimiento     = COALESCE(NULLIF(p_payload->>'fecha_nacimiento','')::date, fecha_nacimiento),
    edad_aproximada_meses = COALESCE(NULLIF(p_payload->>'edad_aproximada_meses','')::int, edad_aproximada_meses),
    peso_kg              = COALESCE(NULLIF(p_payload->>'peso_kg','')::numeric, peso_kg),
    tamanio              = COALESCE(NULLIF(p_payload->>'tamanio','')::core.tamanio_mascota, tamanio),
    esterilizado         = COALESCE((p_payload->>'esterilizado')::boolean, esterilizado),
    fecha_esterilizacion = COALESCE(NULLIF(p_payload->>'fecha_esterilizacion','')::date, fecha_esterilizacion),
    microchip            = COALESCE(v_chip, microchip),
    num_placa            = COALESCE(NULLIF(p_payload->>'num_placa',''), num_placa),
    foto_url             = COALESCE(p_payload->>'foto_url', foto_url),
    alergias             = COALESCE(p_payload->>'alergias', alergias),
    condiciones_cronicas = COALESCE(p_payload->>'condiciones_cronicas', condiciones_cronicas),
    observaciones        = COALESCE(p_payload->>'observaciones', observaciones),
    estado               = COALESCE((p_payload->>'estado')::core.estado_mascota, estado),
    fecha_fallecimiento  = COALESCE(NULLIF(p_payload->>'fecha_fallecimiento','')::date, fecha_fallecimiento),
    updated_by           = p_user_id
  WHERE id = p_id;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'actualizar', 'mascotas', p_id, v_antes, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_mascota_eliminar — lógico; nunca borra si hay historia clínica
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_mascota_eliminar(
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
  v_eventos INT;
  v_emp     UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'mascotas:eliminar');

  IF NOT EXISTS (SELECT 1 FROM core.mascotas
                  WHERE id = p_id AND deleted_at IS NULL
                    AND (internal.es_acceso_global(p_user_id, p_is_super_admin)
                         OR empresa_id = v_emp)) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Paciente no encontrado'));
  END IF;

  SELECT count(*) INTO v_eventos FROM core.historia_clinica WHERE mascota_id = p_id;

  IF v_eventos > 0 THEN
    UPDATE core.mascotas SET estado = 'inactivo', updated_by = p_user_id
     WHERE id = p_id AND deleted_at IS NULL;
    RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
      'id', p_id, 'desactivado', true,
      'mensaje', 'El paciente tiene historia clínica: se marcó como inactivo. La historia se conserva.'));
  END IF;

  UPDATE core.mascotas SET deleted_at = now(), estado = 'inactivo', updated_by = p_user_id
   WHERE id = p_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Paciente no encontrado'));
  END IF;

  PERFORM internal.registrar_auditoria(p_user_id, p_empresa_id, 'eliminar', 'mascotas', p_id);
  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'eliminado', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_mascota_reportar_extravio / resolver
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_mascota_reportar_extravio(
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
  PERFORM internal.validar_payload(p_payload, ARRAY['mascota_id','fecha_extravio']);

  IF NOT EXISTS (SELECT 1 FROM core.mascotas
                  WHERE id = (p_payload->>'mascota_id')::uuid AND deleted_at IS NULL
                    AND (internal.es_acceso_global(p_user_id, p_is_super_admin)
                         OR empresa_id = v_emp)) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Paciente no encontrado','mascota_id'));
  END IF;

  INSERT INTO core.mascotas_extraviadas (
    empresa_id, mascota_id, fecha_extravio, zona, descripcion, contacto, recompensa, created_by
  ) VALUES (
    v_emp,
    (p_payload->>'mascota_id')::uuid,
    (p_payload->>'fecha_extravio')::date,
    p_payload->>'zona',
    p_payload->>'descripcion',
    p_payload->>'contacto',
    NULLIF(p_payload->>'recompensa','')::numeric,
    p_user_id
  ) RETURNING id INTO v_id;

  UPDATE core.mascotas SET estado = 'extraviado', updated_by = p_user_id
   WHERE id = (p_payload->>'mascota_id')::uuid;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_mascota_marcar_encontrada(
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
  v_mascota UUID;
BEGIN
  UPDATE core.mascotas_extraviadas
     SET encontrado = true, fecha_hallazgo = CURRENT_DATE
   WHERE id = p_id
     AND (internal.es_acceso_global(p_user_id, p_is_super_admin)
          OR empresa_id = internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin))
   RETURNING mascota_id INTO v_mascota;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Reporte no encontrado'));
  END IF;

  UPDATE core.mascotas SET estado = 'activo', updated_by = p_user_id WHERE id = v_mascota;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'encontrado', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_mascotas_extraviadas_listar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_solo_activos   BOOLEAN DEFAULT true
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
  SELECT COALESCE(jsonb_agg(x ORDER BY x.fecha_extravio DESC), '[]'::jsonb) INTO v_data
  FROM (
    SELECT me.id, me.fecha_extravio, me.zona, me.descripcion, me.contacto,
           me.recompensa, me.encontrado, me.fecha_hallazgo,
           m.id AS mascota_id, m.nombre AS mascota, m.foto_url, m.microchip,
           e.nombre AS especie, r.nombre AS raza,
           trim(c.nombres || ' ' || COALESCE(c.apellido_paterno,'')) AS propietario,
           c.telefono AS propietario_telefono
    FROM core.mascotas_extraviadas me
    JOIN core.mascotas m ON m.id = me.mascota_id
    JOIN core.clientes c ON c.id = m.cliente_id
    JOIN core.especies e ON e.id = m.especie_id
    LEFT JOIN core.razas r ON r.id = m.raza_id
    WHERE (v_global OR me.empresa_id = v_emp)
      AND (p_solo_activos = false OR me.encontrado = false)
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;
