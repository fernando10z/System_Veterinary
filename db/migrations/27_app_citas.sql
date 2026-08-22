-- =============================================================================
-- 27_app_citas.sql — Agenda clínica
--
-- El flujo de una cita: programada → confirmada → en_espera (llegó) →
-- en_atencion → completada. Ramas: cancelada / no_asistio.
-- =============================================================================

SET search_path = app, internal, core, public;

-- -----------------------------------------------------------------------------
-- app.fn_citas_listar — agenda por rango, filtrable por veterinario y estado
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_citas_listar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_filtros        JSONB DEFAULT '{}'::jsonb,
  p_page           INT DEFAULT 1,
  p_page_size      INT DEFAULT 50
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
  v_desde  TIMESTAMPTZ := COALESCE(NULLIF(p_filtros->>'desde','')::timestamptz, date_trunc('day', now()));
  v_hasta  TIMESTAMPTZ := COALESCE(NULLIF(p_filtros->>'hasta','')::timestamptz, date_trunc('day', now()) + INTERVAL '1 day');
  v_buscar TEXT    := internal.normalizar(p_filtros->>'buscar');
  v_size   INT     := LEAST(GREATEST(COALESCE(p_page_size, 50), 1), 200);
  v_page   INT     := GREATEST(COALESCE(p_page, 1), 1);
  v_total  INT;
  v_data   JSONB;
BEGIN
  SELECT count(*) INTO v_total
  FROM core.citas c
  JOIN core.mascotas m ON m.id = c.mascota_id
  JOIN core.clientes cl ON cl.id = c.cliente_id
  WHERE c.deleted_at IS NULL
    AND (v_global OR c.empresa_id = v_emp)
    AND c.fecha_hora >= v_desde AND c.fecha_hora < v_hasta
    AND (p_filtros->>'estado'         IS NULL OR c.estado::text = p_filtros->>'estado')
    AND (p_filtros->>'veterinario_id' IS NULL OR c.veterinario_id = (p_filtros->>'veterinario_id')::uuid)
    AND (p_filtros->>'mascota_id'     IS NULL OR c.mascota_id = (p_filtros->>'mascota_id')::uuid)
    AND (p_filtros->>'cliente_id'     IS NULL OR c.cliente_id = (p_filtros->>'cliente_id')::uuid)
    AND (v_buscar IS NULL OR v_buscar = '' OR
         internal.normalizar(m.nombre) LIKE '%' || v_buscar || '%' OR
         internal.normalizar(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'')) LIKE '%' || v_buscar || '%');

  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) INTO v_data
  FROM (
    SELECT c.id, c.codigo, c.fecha_hora, c.duracion_min, c.motivo, c.estado,
           c.prioridad, c.origen, c.observaciones, c.empresa_id,
           c.hora_llegada, c.hora_atencion, c.hora_salida,
           c.motivo_cancelacion, c.created_at,
           -- Paciente
           c.mascota_id, m.nombre AS mascota, m.foto_url AS mascota_foto,
           m.alergias, m.sexo AS mascota_sexo, m.peso_kg,
           esp.nombre AS especie, COALESCE(r.nombre, m.raza_libre) AS raza,
           internal.edad_mascota(m.fecha_nacimiento, m.edad_aproximada_meses) AS edad,
           -- Propietario
           c.cliente_id,
           trim(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'') || ' ' ||
                COALESCE(cl.apellido_materno,'')) AS cliente,
           cl.telefono AS cliente_telefono,
           -- Profesional y recurso
           c.veterinario_id,
           trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS veterinario,
           u.color_agenda,
           c.servicio_id, s.nombre AS servicio, s.precio AS servicio_precio,
           c.consultorio_id, co.nombre AS consultorio,
           -- ¿Ya se atendió? (hay consulta ligada)
           EXISTS (SELECT 1 FROM core.consultas cs
                    WHERE cs.cita_id = c.id AND cs.deleted_at IS NULL) AS tiene_consulta
    FROM core.citas c
    JOIN core.mascotas m  ON m.id = c.mascota_id
    JOIN core.clientes cl ON cl.id = c.cliente_id
    JOIN core.especies esp ON esp.id = m.especie_id
    LEFT JOIN core.razas r ON r.id = m.raza_id
    LEFT JOIN core.users u ON u.id = c.veterinario_id
    LEFT JOIN core.servicios s ON s.id = c.servicio_id
    LEFT JOIN core.consultorios co ON co.id = c.consultorio_id
    WHERE c.deleted_at IS NULL
      AND (v_global OR c.empresa_id = v_emp)
      AND c.fecha_hora >= v_desde AND c.fecha_hora < v_hasta
      AND (p_filtros->>'estado'         IS NULL OR c.estado::text = p_filtros->>'estado')
      AND (p_filtros->>'veterinario_id' IS NULL OR c.veterinario_id = (p_filtros->>'veterinario_id')::uuid)
      AND (p_filtros->>'mascota_id'     IS NULL OR c.mascota_id = (p_filtros->>'mascota_id')::uuid)
      AND (p_filtros->>'cliente_id'     IS NULL OR c.cliente_id = (p_filtros->>'cliente_id')::uuid)
      AND (v_buscar IS NULL OR v_buscar = '' OR
           internal.normalizar(m.nombre) LIKE '%' || v_buscar || '%' OR
           internal.normalizar(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'')) LIKE '%' || v_buscar || '%')
    ORDER BY c.fecha_hora
    LIMIT v_size OFFSET (v_page - 1) * v_size
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data, 'meta', jsonb_build_object(
    'total', v_total, 'page', v_page, 'pageSize', v_size,
    'pages', GREATEST(CEIL(v_total::numeric / v_size)::int, 1),
    'desde', v_desde, 'hasta', v_hasta));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_citas_agenda_dia — sala de espera: lo que pasa HOY, agrupado por estado
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_citas_agenda_dia(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_fecha          DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp   UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_fecha DATE := COALESCE(p_fecha, CURRENT_DATE);
  v_data  JSONB;
BEGIN
  SELECT jsonb_build_object(
    'fecha', v_fecha,
    'resumen', jsonb_build_object(
      'total',       count(*),
      'programadas', count(*) FILTER (WHERE c.estado = 'programada'),
      'confirmadas', count(*) FILTER (WHERE c.estado = 'confirmada'),
      'en_espera',   count(*) FILTER (WHERE c.estado = 'en_espera'),
      'en_atencion', count(*) FILTER (WHERE c.estado = 'en_atencion'),
      'completadas', count(*) FILTER (WHERE c.estado = 'completada'),
      'canceladas',  count(*) FILTER (WHERE c.estado = 'cancelada'),
      'no_asistio',  count(*) FILTER (WHERE c.estado = 'no_asistio'),
      'urgencias',   count(*) FILTER (WHERE c.prioridad IN ('urgencia','emergencia'))
    )
  ) INTO v_data
  FROM core.citas c
  WHERE c.empresa_id = v_emp AND c.deleted_at IS NULL
    AND c.fecha_hora::date = v_fecha;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_citas_disponibilidad
-- Devuelve los huecos libres de un veterinario en una fecha, cruzando el horario
-- de atención de la empresa, su disponibilidad declarada y las citas ya tomadas.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_citas_disponibilidad(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_veterinario_id UUID,
  p_fecha          DATE,
  p_duracion_min   INT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp      UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_dur      INT;
  v_slots    JSONB := '[]'::jsonb;
  v_rango    RECORD;
  v_cursor   TIMESTAMPTZ;
  v_fin      TIMESTAMPTZ;
  v_ocupado  BOOLEAN;
BEGIN
  SELECT COALESCE(p_duracion_min, duracion_cita_min) INTO v_dur
    FROM core.empresas WHERE id = v_emp;
  v_dur := COALESCE(v_dur, 30);

  -- Franjas candidatas: la disponibilidad declarada del profesional para esa
  -- fecha; si no declaró nada, el horario de atención de la empresa.
  FOR v_rango IN
    SELECT d.hora_inicio, d.hora_fin
      FROM core.disponibilidad d
     WHERE d.empresa_id = v_emp AND d.user_id = p_veterinario_id
       AND d.fecha = p_fecha AND d.tipo IN ('laboral','guardia')
    UNION ALL
    SELECT h.hora_inicio, h.hora_fin
      FROM core.horarios_atencion h
     WHERE h.empresa_id = v_emp AND h.activo = true
       AND h.dia_semana = EXTRACT(DOW FROM p_fecha)::int
       AND NOT EXISTS (SELECT 1 FROM core.disponibilidad d2
                        WHERE d2.empresa_id = v_emp AND d2.user_id = p_veterinario_id
                          AND d2.fecha = p_fecha AND d2.tipo IN ('laboral','guardia'))
    ORDER BY 1
  LOOP
    v_cursor := (p_fecha + v_rango.hora_inicio)::timestamptz;
    v_fin    := (p_fecha + v_rango.hora_fin)::timestamptz;

    WHILE v_cursor + (v_dur || ' minutes')::interval <= v_fin LOOP
      v_ocupado := internal.hay_solapamiento_cita(v_emp, p_veterinario_id, v_cursor, v_dur);

      -- Un permiso aprobado bloquea la franja aunque haya horario
      IF NOT v_ocupado THEN
        v_ocupado := EXISTS (
          SELECT 1 FROM core.permisos_laborales pl
           WHERE pl.user_id = p_veterinario_id AND pl.estado = 'aprobado'
             AND p_fecha BETWEEN pl.fecha_inicio AND pl.fecha_fin);
      END IF;

      v_slots := v_slots || jsonb_build_object(
        'inicio', v_cursor,
        'fin', v_cursor + (v_dur || ' minutes')::interval,
        'disponible', NOT v_ocupado);

      v_cursor := v_cursor + (v_dur || ' minutes')::interval;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'fecha', p_fecha, 'veterinario_id', p_veterinario_id,
    'duracion_min', v_dur, 'slots', v_slots));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_cita_crear
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_cita_crear(
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
  v_id      UUID;
  v_emp     UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_vet     UUID := NULLIF(p_payload->>'veterinario_id','')::uuid;
  v_fecha   TIMESTAMPTZ := (p_payload->>'fecha_hora')::timestamptz;
  v_dur     INT;
  v_cliente UUID;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'citas:crear');
  PERFORM internal.validar_payload(p_payload, ARRAY['mascota_id','fecha_hora']);

  -- El propietario se deriva de la mascota, y la mascota debe pertenecer a la
  -- empresa: así no se puede agendar un paciente de otra empresa pasando su id.
  SELECT cliente_id INTO v_cliente FROM core.mascotas
   WHERE id = (p_payload->>'mascota_id')::uuid AND deleted_at IS NULL
     AND (internal.es_acceso_global(p_user_id, p_is_super_admin) OR empresa_id = v_emp);

  IF v_cliente IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','El paciente indicado no existe','mascota_id'));
  END IF;

  -- Duración: la del servicio, o la configurada por la empresa
  SELECT COALESCE(
    NULLIF(p_payload->>'duracion_min','')::int,
    (SELECT s.duracion_min FROM core.servicios s
      WHERE s.id = NULLIF(p_payload->>'servicio_id','')::uuid),
    (SELECT e.duracion_cita_min FROM core.empresas e WHERE e.id = v_emp),
    30) INTO v_dur;

  IF v_fecha < now() - INTERVAL '1 day' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'No se pueden agendar citas en el pasado','fecha_hora'));
  END IF;

  IF v_vet IS NOT NULL AND internal.hay_solapamiento_cita(v_emp, v_vet, v_fecha, v_dur) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('CONFLICT',
        'El veterinario ya tiene una cita en ese horario','fecha_hora'));
  END IF;

  INSERT INTO core.citas (
    empresa_id, codigo, cliente_id, mascota_id, veterinario_id, servicio_id,
    consultorio_id, fecha_hora, duracion_min, motivo, prioridad, origen,
    estado, observaciones, created_by
  ) VALUES (
    v_emp,
    internal.siguiente_numero(v_emp, 'CIT', 6),
    v_cliente,
    (p_payload->>'mascota_id')::uuid,
    v_vet,
    NULLIF(p_payload->>'servicio_id','')::uuid,
    NULLIF(p_payload->>'consultorio_id','')::uuid,
    v_fecha, v_dur,
    p_payload->>'motivo',
    COALESCE((p_payload->>'prioridad')::core.prioridad_cita, 'normal'),
    COALESCE((p_payload->>'origen')::core.origen_cita, 'mostrador'),
    COALESCE((p_payload->>'estado')::core.estado_cita, 'programada'),
    p_payload->>'observaciones',
    p_user_id
  ) RETURNING id INTO v_id;

  INSERT INTO core.citas_historial (cita_id, accion, fecha_hora_despues, motivo, user_id)
  VALUES (v_id, 'creada', v_fecha, p_payload->>'motivo', p_user_id);

  PERFORM internal.registrar_auditoria(p_user_id, v_emp, 'crear', 'citas', v_id, NULL, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_cita_reprogramar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_cita_reprogramar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_id             UUID,
  p_fecha_hora     TIMESTAMPTZ,
  p_motivo         TEXT DEFAULT NULL,
  p_veterinario_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_cita RECORD;
  v_vet  UUID;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'citas:editar');

  SELECT * INTO v_cita FROM core.citas
   WHERE id = p_id AND deleted_at IS NULL AND internal.es_de_empresa(p_user_id, p_is_super_admin,
           internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin), empresa_id);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Cita no encontrada'));
  END IF;

  IF v_cita.estado IN ('completada','cancelada') THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        format('Una cita %s no se puede reprogramar', v_cita.estado)));
  END IF;

  v_vet := COALESCE(p_veterinario_id, v_cita.veterinario_id);

  IF v_vet IS NOT NULL AND
     internal.hay_solapamiento_cita(v_cita.empresa_id, v_vet, p_fecha_hora, v_cita.duracion_min, p_id) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('CONFLICT',
        'El veterinario ya tiene una cita en ese horario','fecha_hora'));
  END IF;

  UPDATE core.citas
     SET fecha_hora = p_fecha_hora,
         veterinario_id = v_vet,
         estado = 'programada',
         updated_by = p_user_id
   WHERE id = p_id;

  INSERT INTO core.citas_historial (
    cita_id, accion, fecha_hora_antes, fecha_hora_despues, motivo, user_id)
  VALUES (p_id, 'reprogramada', v_cita.fecha_hora, p_fecha_hora, p_motivo, p_user_id);

  PERFORM internal.registrar_auditoria(
    p_user_id, v_cita.empresa_id, 'reprogramar', 'citas', p_id,
    jsonb_build_object('fecha_hora', v_cita.fecha_hora),
    jsonb_build_object('fecha_hora', p_fecha_hora));

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_cita_cambiar_estado
-- Puerta única para avanzar la cita. Sella las horas del recorrido y valida
-- que la transición tenga sentido.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_cita_cambiar_estado(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_id             UUID,
  p_estado         VARCHAR,
  p_motivo         TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_cita   RECORD;
  v_nuevo  core.estado_cita := p_estado::core.estado_cita;
  v_accion core.accion_cita;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'citas:editar');

  SELECT * INTO v_cita FROM core.citas
   WHERE id = p_id AND deleted_at IS NULL AND internal.es_de_empresa(p_user_id, p_is_super_admin,
           internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin), empresa_id);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Cita no encontrada'));
  END IF;

  IF v_cita.estado = 'completada' AND v_nuevo <> 'completada' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'Una cita completada ya no cambia de estado'));
  END IF;

  IF v_nuevo = 'cancelada' AND COALESCE(trim(p_motivo),'') = '' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'Indica el motivo de la cancelación','motivo'));
  END IF;

  UPDATE core.citas SET
    estado        = v_nuevo,
    hora_llegada  = CASE WHEN v_nuevo = 'en_espera'   AND hora_llegada  IS NULL THEN now() ELSE hora_llegada END,
    hora_atencion = CASE WHEN v_nuevo = 'en_atencion' AND hora_atencion IS NULL THEN now() ELSE hora_atencion END,
    hora_salida   = CASE WHEN v_nuevo = 'completada'  AND hora_salida   IS NULL THEN now() ELSE hora_salida END,
    motivo_cancelacion = CASE WHEN v_nuevo = 'cancelada' THEN p_motivo ELSE motivo_cancelacion END,
    updated_by    = p_user_id
  WHERE id = p_id;

  v_accion := CASE v_nuevo
    WHEN 'confirmada' THEN 'confirmada'::core.accion_cita
    WHEN 'cancelada'  THEN 'cancelada'::core.accion_cita
    WHEN 'completada' THEN 'atendida'::core.accion_cita
    WHEN 'no_asistio' THEN 'no_asistio'::core.accion_cita
    ELSE NULL END;

  IF v_accion IS NOT NULL THEN
    INSERT INTO core.citas_historial (cita_id, accion, fecha_hora_antes, motivo, user_id)
    VALUES (p_id, v_accion, v_cita.fecha_hora, p_motivo, p_user_id);
  END IF;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_cita.empresa_id, 'cambiar_estado', 'citas', p_id,
    jsonb_build_object('estado', v_cita.estado),
    jsonb_build_object('estado', v_nuevo, 'motivo', p_motivo));

  RETURN jsonb_build_object('ok', true,
    'data', jsonb_build_object('id', p_id, 'estado', v_nuevo));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_cita_obtener — detalle con historial de cambios
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_cita_obtener(
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
    SELECT c.*,
           m.nombre AS mascota, m.foto_url AS mascota_foto, m.alergias,
           m.condiciones_cronicas, m.peso_kg,
           esp.nombre AS especie, COALESCE(r.nombre, m.raza_libre) AS raza,
           internal.edad_mascota(m.fecha_nacimiento, m.edad_aproximada_meses) AS edad,
           trim(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'')) AS cliente,
           cl.telefono AS cliente_telefono, cl.correo AS cliente_correo,
           trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS veterinario,
           s.nombre AS servicio, s.precio AS servicio_precio,
           co.nombre AS consultorio,
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'accion', ch.accion, 'fecha_hora_antes', ch.fecha_hora_antes,
                     'fecha_hora_despues', ch.fecha_hora_despues, 'motivo', ch.motivo,
                     'created_at', ch.created_at,
                     'usuario', trim(uh.nombres || ' ' || COALESCE(uh.apellido_paterno,'')))
                   ORDER BY ch.created_at DESC), '[]'::jsonb)
              FROM core.citas_historial ch
              LEFT JOIN core.users uh ON uh.id = ch.user_id
             WHERE ch.cita_id = c.id) AS historial,
           (SELECT cs.id FROM core.consultas cs
             WHERE cs.cita_id = c.id AND cs.deleted_at IS NULL LIMIT 1) AS consulta_id
    FROM core.citas c
    JOIN core.mascotas m  ON m.id = c.mascota_id
    JOIN core.clientes cl ON cl.id = c.cliente_id
    JOIN core.especies esp ON esp.id = m.especie_id
    LEFT JOIN core.razas r ON r.id = m.raza_id
    LEFT JOIN core.users u ON u.id = c.veterinario_id
    LEFT JOIN core.servicios s ON s.id = c.servicio_id
    LEFT JOIN core.consultorios co ON co.id = c.consultorio_id
    WHERE c.id = p_id AND c.deleted_at IS NULL
      AND (v_global OR c.empresa_id = v_emp)
  ) x;

  IF v_data IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Cita no encontrada'));
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_cita_eliminar — borrado lógico (solo si no llegó a atenderse)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_cita_eliminar(
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
  v_estado core.estado_cita;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'citas:eliminar');

  SELECT estado INTO v_estado FROM core.citas
   WHERE id = p_id AND deleted_at IS NULL AND internal.es_de_empresa(p_user_id, p_is_super_admin,
           internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin), empresa_id);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Cita no encontrada'));
  END IF;

  IF v_estado = 'completada' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'Una cita completada no se elimina: forma parte del historial clínico'));
  END IF;

  UPDATE core.citas SET deleted_at = now(), updated_by = p_user_id WHERE id = p_id;
  PERFORM internal.registrar_auditoria(p_user_id, p_empresa_id, 'eliminar', 'citas', p_id);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'eliminado', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;
