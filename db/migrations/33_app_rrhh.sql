-- =============================================================================
-- 33_app_rrhh.sql — Personal clínico: contratos, disponibilidad, asistencia,
-- permisos y evaluaciones.
-- =============================================================================

SET search_path = app, internal, core, public;

-- =============================================================================
-- DISPONIBILIDAD (turnos del profesional)
-- =============================================================================

CREATE OR REPLACE FUNCTION app.fn_disponibilidad_listar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_desde          DATE,
  p_hasta          DATE,
  p_target_user_id UUID DEFAULT NULL
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
  SELECT COALESCE(jsonb_agg(x ORDER BY x.fecha, x.hora_inicio), '[]'::jsonb) INTO v_data
  FROM (
    SELECT d.id, d.fecha, d.hora_inicio, d.hora_fin, d.tipo, d.nota,
           d.user_id, trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS profesional,
           u.color_agenda, u.es_veterinario,
           co.nombre AS consultorio
    FROM core.disponibilidad d
    JOIN core.users u ON u.id = d.user_id
    LEFT JOIN core.consultorios co ON co.id = d.consultorio_id
    WHERE d.empresa_id = v_emp
      AND d.fecha BETWEEN p_desde AND p_hasta
      AND (p_target_user_id IS NULL OR d.user_id = p_target_user_id)
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_disponibilidad_guardar(
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
  PERFORM internal.assert_permiso(p_user_id, 'rrhh:gestionar');

  IF v_id IS NULL THEN
    PERFORM internal.validar_payload(p_payload, ARRAY['user_id','fecha','hora_inicio','hora_fin']);
    INSERT INTO core.disponibilidad (
      empresa_id, user_id, fecha, hora_inicio, hora_fin, tipo, consultorio_id, nota)
    VALUES (
      v_emp, (p_payload->>'user_id')::uuid, (p_payload->>'fecha')::date,
      (p_payload->>'hora_inicio')::time, (p_payload->>'hora_fin')::time,
      COALESCE((p_payload->>'tipo')::core.tipo_disponibilidad, 'laboral'),
      NULLIF(p_payload->>'consultorio_id','')::uuid, p_payload->>'nota')
    RETURNING id INTO v_id;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM core.disponibilidad
                    WHERE id = v_id
                      AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, empresa_id)) THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('NOT_FOUND','Turno no encontrado'));
    END IF;

    UPDATE core.disponibilidad SET
      fecha       = COALESCE(NULLIF(p_payload->>'fecha','')::date, fecha),
      hora_inicio = COALESCE(NULLIF(p_payload->>'hora_inicio','')::time, hora_inicio),
      hora_fin    = COALESCE(NULLIF(p_payload->>'hora_fin','')::time, hora_fin),
      tipo        = COALESCE((p_payload->>'tipo')::core.tipo_disponibilidad, tipo),
      consultorio_id = COALESCE(NULLIF(p_payload->>'consultorio_id','')::uuid, consultorio_id),
      nota        = COALESCE(p_payload->>'nota', nota)
    WHERE id = v_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_disponibilidad_eliminar(
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
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'rrhh:gestionar');
  DELETE FROM core.disponibilidad
   WHERE id = p_id
     AND internal.es_de_empresa(p_user_id, p_is_super_admin,
           internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin), empresa_id);
  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('eliminado', true));
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- ASISTENCIA
-- =============================================================================

-- Marca entrada o salida según el estado del día: un solo botón en la UI.
CREATE OR REPLACE FUNCTION app.sp_asistencia_marcar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_target_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp    UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_target UUID := COALESCE(p_target_user_id, p_user_id);
  v_reg    RECORD;
  v_estado core.estado_asistencia := 'puntual';
  v_limite TIME;
BEGIN
  SELECT * INTO v_reg FROM core.asistencia
   WHERE user_id = v_target AND fecha = CURRENT_DATE;

  IF NOT FOUND THEN
    -- Tardanza: entra más de 10 min después del inicio del horario de la empresa
    SELECT min(hora_inicio) INTO v_limite FROM core.horarios_atencion
     WHERE empresa_id = v_emp AND activo = true
       AND dia_semana = EXTRACT(DOW FROM CURRENT_DATE)::int;

    IF v_limite IS NOT NULL AND CURRENT_TIME > v_limite + INTERVAL '10 minutes' THEN
      v_estado := 'tardanza';
    END IF;

    INSERT INTO core.asistencia (empresa_id, user_id, fecha, hora_entrada, estado)
    VALUES (v_emp, v_target, CURRENT_DATE, CURRENT_TIME, v_estado);

    RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
      'accion', 'entrada', 'hora', CURRENT_TIME, 'estado', v_estado));
  END IF;

  IF v_reg.hora_salida IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE','Ya se registró la salida de hoy'));
  END IF;

  UPDATE core.asistencia SET hora_salida = CURRENT_TIME
   WHERE id = v_reg.id;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'accion', 'salida', 'hora', CURRENT_TIME));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_asistencia_listar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_desde          DATE,
  p_hasta          DATE,
  p_target_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp     UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_data    JSONB;
  v_resumen JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(x ORDER BY x.fecha DESC, x.profesional), '[]'::jsonb) INTO v_data
  FROM (
    SELECT a.id, a.fecha, a.hora_entrada, a.hora_salida, a.horas_trabajadas,
           a.estado, a.observaciones, a.user_id,
           trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS profesional,
           u.foto_url, r.nombre AS rol
    FROM core.asistencia a
    JOIN core.users u ON u.id = a.user_id
    LEFT JOIN core.roles r ON r.id = u.rol_id
    WHERE a.empresa_id = v_emp
      AND a.fecha BETWEEN p_desde AND p_hasta
      AND (p_target_user_id IS NULL OR a.user_id = p_target_user_id)
  ) x;

  SELECT jsonb_build_object(
    'dias',      count(*),
    'puntuales', count(*) FILTER (WHERE a.estado = 'puntual'),
    'tardanzas', count(*) FILTER (WHERE a.estado = 'tardanza'),
    'faltas',    count(*) FILTER (WHERE a.estado = 'falta'),
    'horas_totales', COALESCE(SUM(a.horas_trabajadas), 0)
  ) INTO v_resumen
  FROM core.asistencia a
  WHERE a.empresa_id = v_emp AND a.fecha BETWEEN p_desde AND p_hasta
    AND (p_target_user_id IS NULL OR a.user_id = p_target_user_id);

  RETURN jsonb_build_object('ok', true, 'data', v_data, 'meta', v_resumen);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- PERMISOS LABORALES
-- =============================================================================

CREATE OR REPLACE FUNCTION app.sp_permiso_solicitar(
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
  PERFORM internal.validar_payload(p_payload, ARRAY['fecha_inicio','fecha_fin']);

  INSERT INTO core.permisos_laborales (
    empresa_id, user_id, tipo, fecha_inicio, fecha_fin, hora_inicio, hora_fin, motivo)
  VALUES (
    v_emp,
    COALESCE(NULLIF(p_payload->>'user_id','')::uuid, p_user_id),
    COALESCE((p_payload->>'tipo')::core.tipo_permiso_laboral, 'personal'),
    (p_payload->>'fecha_inicio')::date, (p_payload->>'fecha_fin')::date,
    NULLIF(p_payload->>'hora_inicio','')::time,
    NULLIF(p_payload->>'hora_fin','')::time,
    p_payload->>'motivo')
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_permiso_resolver(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_id             UUID,
  p_estado         VARCHAR,
  p_comentario     TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_p RECORD;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'rrhh:aprobar');

  SELECT * INTO v_p FROM core.permisos_laborales
   WHERE id = p_id
     AND internal.es_de_empresa(p_user_id, p_is_super_admin,
           internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin), empresa_id);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Solicitud no encontrada'));
  END IF;

  IF v_p.user_id = p_user_id THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE','No puedes aprobar tu propia solicitud'));
  END IF;

  UPDATE core.permisos_laborales SET
    estado = p_estado::core.estado_solicitud,
    aprobado_por = p_user_id, aprobado_at = now(),
    comentario_aprobacion = p_comentario
  WHERE id = p_id;

  -- Un permiso aprobado bloquea la agenda de esos días
  IF p_estado = 'aprobado' THEN
    INSERT INTO core.disponibilidad (empresa_id, user_id, fecha, hora_inicio, hora_fin, tipo, nota)
    SELECT v_p.empresa_id, v_p.user_id, d::date,
           COALESCE(v_p.hora_inicio, '00:00'::time),
           COALESCE(v_p.hora_fin, '23:59'::time),
           CASE v_p.tipo WHEN 'vacaciones' THEN 'vacaciones' ELSE 'permiso' END::core.tipo_disponibilidad,
           'Permiso aprobado: ' || COALESCE(v_p.motivo, v_p.tipo::text)
      FROM generate_series(v_p.fecha_inicio, v_p.fecha_fin, '1 day'::interval) d;
  END IF;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_p.empresa_id, 'resolver', 'permisos_laborales', p_id, NULL,
    jsonb_build_object('estado', p_estado, 'comentario', p_comentario));

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'estado', p_estado));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_permisos_laborales_listar(
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
  v_emp  UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_data JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(x ORDER BY x.fecha_inicio DESC), '[]'::jsonb) INTO v_data
  FROM (
    SELECT pl.id, pl.tipo, pl.fecha_inicio, pl.fecha_fin, pl.hora_inicio, pl.hora_fin,
           pl.motivo, pl.estado, pl.aprobado_at, pl.comentario_aprobacion,
           (pl.fecha_fin - pl.fecha_inicio + 1) AS dias,
           pl.user_id, trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS solicitante,
           trim(ua.nombres || ' ' || COALESCE(ua.apellido_paterno,'')) AS aprobador
    FROM core.permisos_laborales pl
    JOIN core.users u ON u.id = pl.user_id
    LEFT JOIN core.users ua ON ua.id = pl.aprobado_por
    WHERE pl.empresa_id = v_emp
      AND (p_filtros->>'estado'  IS NULL OR pl.estado::text = p_filtros->>'estado')
      AND (p_filtros->>'user_id' IS NULL OR pl.user_id = (p_filtros->>'user_id')::uuid)
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- CONTRATOS Y EVALUACIONES
-- =============================================================================

CREATE OR REPLACE FUNCTION app.sp_contrato_personal_guardar(
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
  PERFORM internal.assert_permiso(p_user_id, 'rrhh:gestionar');

  IF v_id IS NULL THEN
    PERFORM internal.validar_payload(p_payload, ARRAY['user_id','fecha_inicio']);

    -- Un solo contrato vigente por persona: el nuevo cierra el anterior.
    UPDATE core.contratos_personal SET vigente = false
     WHERE user_id = (p_payload->>'user_id')::uuid AND vigente = true;

    INSERT INTO core.contratos_personal (
      empresa_id, user_id, tipo, cargo, fecha_inicio, fecha_fin,
      salario, moneda, documento_url, vigente)
    VALUES (
      v_emp, (p_payload->>'user_id')::uuid,
      COALESCE((p_payload->>'tipo')::core.tipo_contrato_empleado, 'plazo_fijo'),
      p_payload->>'cargo',
      (p_payload->>'fecha_inicio')::date,
      NULLIF(p_payload->>'fecha_fin','')::date,
      NULLIF(p_payload->>'salario','')::numeric,
      COALESCE((p_payload->>'moneda')::core.moneda_codigo, 'PEN'),
      p_payload->>'documento_url', true)
    RETURNING id INTO v_id;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM core.contratos_personal
                    WHERE id = v_id
                      AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, empresa_id)) THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('NOT_FOUND','Contrato no encontrado'));
    END IF;

    UPDATE core.contratos_personal SET
      tipo          = COALESCE((p_payload->>'tipo')::core.tipo_contrato_empleado, tipo),
      cargo         = COALESCE(p_payload->>'cargo', cargo),
      fecha_inicio  = COALESCE(NULLIF(p_payload->>'fecha_inicio','')::date, fecha_inicio),
      fecha_fin     = COALESCE(NULLIF(p_payload->>'fecha_fin','')::date, fecha_fin),
      salario       = COALESCE(NULLIF(p_payload->>'salario','')::numeric, salario),
      documento_url = COALESCE(p_payload->>'documento_url', documento_url),
      vigente       = COALESCE((p_payload->>'vigente')::boolean, vigente)
    WHERE id = v_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_evaluacion_registrar(
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
  PERFORM internal.assert_permiso(p_user_id, 'rrhh:gestionar');
  PERFORM internal.validar_payload(p_payload, ARRAY['user_id','periodo']);

  INSERT INTO core.evaluaciones_personal (
    empresa_id, user_id, evaluador_id, periodo, fecha,
    puntualidad, eficiencia, calidad_atencion, trabajo_equipo, observaciones)
  VALUES (
    v_emp, (p_payload->>'user_id')::uuid, p_user_id, p_payload->>'periodo',
    COALESCE(NULLIF(p_payload->>'fecha','')::date, CURRENT_DATE),
    NULLIF(p_payload->>'puntualidad','')::int,
    NULLIF(p_payload->>'eficiencia','')::int,
    NULLIF(p_payload->>'calidad_atencion','')::int,
    NULLIF(p_payload->>'trabajo_equipo','')::int,
    p_payload->>'observaciones')
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_equipo_resumen — ficha del equipo: carga, asistencia y evaluación
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_equipo_resumen(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_desde          DATE DEFAULT NULL,
  p_hasta          DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp   UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_desde DATE := COALESCE(p_desde, date_trunc('month', CURRENT_DATE)::date);
  v_hasta DATE := COALESCE(p_hasta, CURRENT_DATE);
  v_data  JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(x ORDER BY x.profesional), '[]'::jsonb) INTO v_data
  FROM (
    SELECT u.id AS user_id,
           trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS profesional,
           u.foto_url, u.es_veterinario, u.colegiatura, u.color_agenda, u.estado,
           r.nombre AS rol, esp.nombre AS especializacion,
           (SELECT jsonb_build_object('tipo', cp.tipo, 'cargo', cp.cargo,
                                      'fecha_inicio', cp.fecha_inicio, 'fecha_fin', cp.fecha_fin)
              FROM core.contratos_personal cp
             WHERE cp.user_id = u.id AND cp.vigente = true LIMIT 1) AS contrato,
           (SELECT count(*) FROM core.citas c
             WHERE c.veterinario_id = u.id AND c.deleted_at IS NULL
               AND c.fecha_hora::date BETWEEN v_desde AND v_hasta
               AND c.estado = 'completada') AS citas_atendidas,
           (SELECT count(*) FROM core.consultas co
             WHERE co.veterinario_id = u.id AND co.deleted_at IS NULL
               AND co.fecha::date BETWEEN v_desde AND v_hasta) AS consultas,
           (SELECT count(*) FROM core.cirugias ci
             WHERE ci.cirujano_id = u.id AND ci.estado = 'realizada'
               AND ci.fecha_inicio::date BETWEEN v_desde AND v_hasta) AS cirugias,
           (SELECT COALESCE(SUM(a.horas_trabajadas), 0) FROM core.asistencia a
             WHERE a.user_id = u.id AND a.fecha BETWEEN v_desde AND v_hasta) AS horas_trabajadas,
           (SELECT count(*) FROM core.asistencia a
             WHERE a.user_id = u.id AND a.fecha BETWEEN v_desde AND v_hasta
               AND a.estado = 'tardanza') AS tardanzas,
           (SELECT round(avg(ev.promedio), 2) FROM core.evaluaciones_personal ev
             WHERE ev.user_id = u.id) AS evaluacion_promedio
    FROM core.users u
    LEFT JOIN core.roles r ON r.id = u.rol_id
    LEFT JOIN core.especializaciones esp ON esp.id = u.especializacion_id
    WHERE u.empresa_id = v_emp AND u.deleted_at IS NULL
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data,
    'meta', jsonb_build_object('desde', v_desde, 'hasta', v_hasta));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;
