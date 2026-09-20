-- =============================================================================
-- 36_app_sala_espera.sql
-- La sala de espera y la cola de cupos.
--
-- La agenda ya sabía programar, pero la clínica no funciona sólo con cita
-- previa: entra un perro atropellado sin avisar, y entra antes que los tres
-- controles que esperaban desde temprano. Eso es triaje, y no estaba.
--
-- Dos cosas distintas que la gente confunde:
--   · SALA DE ESPERA → quién está AHORA en la clínica esperando ser atendido,
--     ordenado por gravedad y no por hora de llegada.
--   · LISTA DE ESPERA (core.citas_lista_espera) → quién quiere adelantar su
--     cita si se libera un cupo. La tabla existía desde el inicio y no tenía
--     un solo SP: nadie podía anotarse ni consultarla.
--
-- Idempotente.
-- =============================================================================

SET search_path = app, internal, core, public;

-- -----------------------------------------------------------------------------
-- internal.prioridad_mas_grave — se queda con la peor de las dos.
--
-- El triaje del mostrador puede AGRAVAR lo que venía en la cita, nunca
-- rebajarlo: si el animal llegó peor de lo que se esperaba, sube; si llegó
-- bien, la cita conserva la prioridad con la que se programó.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.prioridad_mas_grave(
  a core.prioridad_cita,
  b core.prioridad_cita
)
RETURNS core.prioridad_cita
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN 'emergencia' IN (a::text, b::text) THEN 'emergencia'
    WHEN 'urgencia'   IN (a::text, b::text) THEN 'urgencia'
    WHEN 'preferente' IN (a::text, b::text) THEN 'preferente'
    ELSE 'normal'
  END::core.prioridad_cita;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_sala_espera
--
-- El tablero del mostrador y del consultorio. El orden NO es por hora de
-- llegada: una emergencia entra antes que una consulta programada que llegó
-- primero. Dentro de la misma prioridad sí manda quién llegó antes.
--
-- `espera_min` se cuenta desde la llegada real, no desde la hora de la cita:
-- lo que reclama el propietario es el tiempo que lleva sentado.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_sala_espera(
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
  v_vet    UUID    := NULLIF(p_filtros->>'veterinario_id','')::uuid;
  v_data   JSONB;
  v_resumen JSONB;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'citas:listar');

  SELECT COALESCE(jsonb_agg(x ORDER BY x.orden_triaje, x.llegada), '[]'::jsonb) INTO v_data
  FROM (
    SELECT c.id, c.codigo, c.estado, c.prioridad, c.motivo, c.origen,
           c.fecha_hora, c.duracion_min,
           COALESCE(c.hora_llegada, c.fecha_hora) AS llegada,
           c.hora_atencion,
           -- Gravedad primero: el orden clínico, no el de la fila.
           CASE c.prioridad
             WHEN 'emergencia' THEN 1
             WHEN 'urgencia'   THEN 2
             WHEN 'preferente' THEN 3
             ELSE 4 END AS orden_triaje,
           round(EXTRACT(EPOCH FROM (
             now() - COALESCE(c.hora_llegada, c.fecha_hora))) / 60.0)::int AS espera_min,
           m.id AS mascota_id, m.nombre AS mascota, m.foto_url AS mascota_foto,
           m.alergias, m.condiciones_cronicas,
           esp.nombre AS especie,
           internal.edad_mascota(m.fecha_nacimiento, m.edad_aproximada_meses) AS edad,
           cl.id AS cliente_id,
           trim(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'')) AS cliente,
           cl.telefono AS cliente_telefono,
           c.veterinario_id,
           trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS veterinario,
           u.color_agenda,
           s.nombre AS servicio,
           cons.id AS consultorio_id, cons.nombre AS consultorio,
           -- Si ya se abrió la consulta, el botón lleva ahí y no a crear otra.
           (SELECT co.id FROM core.consultas co
             WHERE co.cita_id = c.id AND co.deleted_at IS NULL
             ORDER BY co.created_at DESC LIMIT 1) AS consulta_id
      FROM core.citas c
      JOIN core.mascotas m  ON m.id = c.mascota_id
      JOIN core.clientes cl ON cl.id = c.cliente_id
      JOIN core.especies esp ON esp.id = m.especie_id
      LEFT JOIN core.users u ON u.id = c.veterinario_id
      LEFT JOIN core.servicios s ON s.id = c.servicio_id
      LEFT JOIN core.consultorios cons ON cons.id = c.consultorio_id
     WHERE c.deleted_at IS NULL
       AND c.estado IN ('en_espera','en_atencion')
       AND (v_global OR c.empresa_id = v_emp)
       AND (v_vet IS NULL OR c.veterinario_id = v_vet)
  ) x;

  SELECT jsonb_build_object(
    'en_espera',   count(*) FILTER (WHERE x->>'estado' = 'en_espera'),
    'en_atencion', count(*) FILTER (WHERE x->>'estado' = 'en_atencion'),
    'urgentes',    count(*) FILTER (WHERE x->>'prioridad' IN ('urgencia','emergencia')),
    'espera_max_min', COALESCE(max((x->>'espera_min')::int)
                               FILTER (WHERE x->>'estado' = 'en_espera'), 0),
    -- Los que aún no llegaron pero se les espera hoy: lo que viene.
    'agendados_hoy', (
      SELECT count(*) FROM core.citas c2
       WHERE c2.deleted_at IS NULL
         AND c2.estado IN ('programada','confirmada')
         AND (c2.fecha_hora AT TIME ZONE 'America/Lima')::date = CURRENT_DATE
         AND (v_global OR c2.empresa_id = v_emp)))
  INTO v_resumen
  FROM jsonb_array_elements(v_data) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data, 'meta', v_resumen);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_cita_registrar_llegada
--
-- El paciente llegó. Si tenía cita, la pasa a la sala de espera; si no la
-- tenía —que es el caso que no estaba resuelto—, crea la cita del momento y la
-- deja esperando.
--
-- Un walk-in NO valida solapamiento ni horario: el animal ya está en la
-- puerta. Rechazar una emergencia porque el veterinario tiene la agenda llena
-- sería exactamente lo contrario de lo que se necesita.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_cita_registrar_llegada(
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
  v_emp     UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_cita    UUID := NULLIF(p_payload->>'cita_id','')::uuid;
  v_mascota UUID := NULLIF(p_payload->>'mascota_id','')::uuid;
  v_cliente UUID;
  v_prio    core.prioridad_cita := COALESCE((p_payload->>'prioridad')::core.prioridad_cita, 'normal');
  v_c       RECORD;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'citas:crear');

  -- Caso 1: tenía cita. Sólo se marca la llegada.
  IF v_cita IS NOT NULL THEN
    SELECT * INTO v_c FROM core.citas
     WHERE id = v_cita AND deleted_at IS NULL
       AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, empresa_id);
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('NOT_FOUND','Cita no encontrada'));
    END IF;

    IF v_c.estado IN ('completada','cancelada') THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('BUSINESS_RULE',
          format('La cita está %s: registra una llegada sin cita', v_c.estado)));
    END IF;

    UPDATE core.citas SET
      estado       = 'en_espera',
      hora_llegada = COALESCE(hora_llegada, now()),
      -- El triaje del mostrador puede subir la prioridad con la que venía.
      prioridad    = internal.prioridad_mas_grave(prioridad, v_prio),
      updated_by   = p_user_id
    WHERE id = v_cita;

    RETURN jsonb_build_object('ok', true,
      'data', jsonb_build_object('id', v_cita, 'estado', 'en_espera', 'creada', false));
  END IF;

  -- Caso 2: llegó sin cita.
  PERFORM internal.validar_payload(p_payload, ARRAY['mascota_id']);

  SELECT cliente_id INTO v_cliente FROM core.mascotas
   WHERE id = v_mascota AND deleted_at IS NULL
     AND (internal.es_acceso_global(p_user_id, p_is_super_admin) OR empresa_id = v_emp);
  IF v_cliente IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','El paciente indicado no existe','mascota_id'));
  END IF;

  INSERT INTO core.citas (
    empresa_id, codigo, cliente_id, mascota_id, veterinario_id, servicio_id,
    consultorio_id, fecha_hora, duracion_min, motivo, prioridad, origen,
    estado, hora_llegada, observaciones, created_by
  ) VALUES (
    v_emp, internal.siguiente_numero(v_emp, 'CIT', 6), v_cliente, v_mascota,
    NULLIF(p_payload->>'veterinario_id','')::uuid,
    NULLIF(p_payload->>'servicio_id','')::uuid,
    NULLIF(p_payload->>'consultorio_id','')::uuid,
    now(),
    COALESCE((p_payload->>'duracion_min')::int,
             (SELECT e.duracion_cita_min FROM core.empresas e WHERE e.id = v_emp), 30),
    COALESCE(NULLIF(p_payload->>'motivo',''), 'Atención sin cita'),
    v_prio, 'mostrador', 'en_espera', now(),
    p_payload->>'observaciones', p_user_id
  ) RETURNING id INTO v_cita;

  INSERT INTO core.citas_historial (cita_id, accion, fecha_hora_despues, motivo, user_id)
  VALUES (v_cita, 'creada', now(), 'Llegada sin cita previa', p_user_id);

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'registrar_llegada', 'citas', v_cita, NULL, p_payload);

  RETURN jsonb_build_object('ok', true,
    'data', jsonb_build_object('id', v_cita, 'estado', 'en_espera', 'creada', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- LISTA DE ESPERA — quién quiere adelantar su cita si se libera un cupo
-- =============================================================================

CREATE OR REPLACE FUNCTION app.sp_lista_espera_anotar(
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
  v_mascota UUID := (p_payload->>'mascota_id')::uuid;
  v_cliente UUID;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'citas:crear');
  PERFORM internal.validar_payload(p_payload, ARRAY['mascota_id','desde']);

  -- El propietario se deriva del paciente, igual que al agendar: así no se
  -- puede anotar a un paciente de otra empresa pasando su id.
  SELECT cliente_id INTO v_cliente FROM core.mascotas
   WHERE id = v_mascota AND deleted_at IS NULL
     AND (internal.es_acceso_global(p_user_id, p_is_super_admin) OR empresa_id = v_emp);
  IF v_cliente IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','El paciente indicado no existe','mascota_id'));
  END IF;

  INSERT INTO core.citas_lista_espera (
    empresa_id, cliente_id, mascota_id, servicio_id, veterinario_id, desde, hasta, nota)
  VALUES (
    v_emp, v_cliente, v_mascota,
    NULLIF(p_payload->>'servicio_id','')::uuid,
    NULLIF(p_payload->>'veterinario_id','')::uuid,
    (p_payload->>'desde')::date,
    NULLIF(p_payload->>'hasta','')::date,
    p_payload->>'nota')
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_lista_espera_listar
--
-- A quién llamar cuando se cancela una cita. Ordenado por antigüedad de la
-- anotación: el que lleva más tiempo esperando un cupo es el primero.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_lista_espera_listar(
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
  v_fecha  DATE    := NULLIF(p_filtros->>'fecha','')::date;
  v_vet    UUID    := NULLIF(p_filtros->>'veterinario_id','')::uuid;
  v_data   JSONB;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'citas:listar');

  SELECT COALESCE(jsonb_agg(x ORDER BY x.created_at), '[]'::jsonb) INTO v_data
  FROM (
    SELECT le.id, le.desde, le.hasta, le.nota, le.created_at,
           le.mascota_id, m.nombre AS mascota, esp.nombre AS especie,
           le.cliente_id,
           trim(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'')) AS cliente,
           cl.telefono AS cliente_telefono,
           le.servicio_id, s.nombre AS servicio,
           le.veterinario_id,
           trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS veterinario,
           (CURRENT_DATE - le.created_at::date) AS dias_esperando
      FROM core.citas_lista_espera le
      JOIN core.mascotas m  ON m.id = le.mascota_id
      JOIN core.clientes cl ON cl.id = le.cliente_id
      JOIN core.especies esp ON esp.id = m.especie_id
      LEFT JOIN core.servicios s ON s.id = le.servicio_id
      LEFT JOIN core.users u ON u.id = le.veterinario_id
     WHERE le.atendido = false
       AND (v_global OR le.empresa_id = v_emp)
       -- Un cupo que se libera sólo le sirve a quien lo quería en esa fecha.
       AND (v_fecha IS NULL OR (v_fecha >= le.desde AND (le.hasta IS NULL OR v_fecha <= le.hasta)))
       AND (v_vet IS NULL OR le.veterinario_id IS NULL OR le.veterinario_id = v_vet)
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_lista_espera_resolver(
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
  v_emp UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'citas:editar');

  UPDATE core.citas_lista_espera SET atendido = true
   WHERE id = p_id
     AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, empresa_id);

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Anotación no encontrada'));
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'atendido', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app TO vet_app_user;
