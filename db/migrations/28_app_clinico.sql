-- =============================================================================
-- 28_app_clinico.sql — Historia clínica: consultas, vacunas, desparasitaciones,
-- tratamientos, cirugías, hospitalizaciones, exámenes, notas y documentos.
--
-- Regla transversal: todo acto clínico registra su evento en
-- core.historia_clinica vía internal.registrar_evento_clinico, para que la
-- línea de tiempo del paciente se arme con una sola consulta.
-- =============================================================================

SET search_path = app, internal, core, public;

-- =============================================================================
-- CONSULTAS
-- =============================================================================

CREATE OR REPLACE FUNCTION app.sp_consulta_crear(
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
  v_cliente UUID;
  v_vet     UUID := COALESCE(NULLIF(p_payload->>'veterinario_id','')::uuid, p_user_id);
  v_cita    UUID := NULLIF(p_payload->>'cita_id','')::uuid;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clinico:registrar');
  PERFORM internal.validar_payload(p_payload, ARRAY['mascota_id','motivo']);

  -- El paciente debe ser de la empresa: un id de otra empresa se comporta
  -- como inexistente.
  SELECT cliente_id INTO v_cliente FROM core.mascotas
   WHERE id = (p_payload->>'mascota_id')::uuid AND deleted_at IS NULL
     AND (internal.es_acceso_global(p_user_id, p_is_super_admin) OR empresa_id = v_emp);

  IF v_cliente IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','El paciente indicado no existe','mascota_id'));
  END IF;

  -- Solo un veterinario colegiado firma una consulta.
  IF NOT EXISTS (SELECT 1 FROM core.users
                  WHERE id = v_vet AND es_veterinario = true AND deleted_at IS NULL) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'La consulta debe estar firmada por un veterinario colegiado','veterinario_id'));
  END IF;

  INSERT INTO core.consultas (
    empresa_id, codigo, mascota_id, cliente_id, veterinario_id, cita_id, fecha,
    motivo, anamnesis, peso_kg, temperatura_c, frecuencia_cardiaca,
    frecuencia_respiratoria, mucosas, tllc_seg, condicion_corporal, examen_fisico,
    diagnostico, diagnostico_diferencial, pronostico, plan_terapeutico,
    prescripcion, indicaciones_casa, proxima_visita, estado, created_by
  ) VALUES (
    v_emp,
    internal.siguiente_numero(v_emp, 'CON', 6),
    (p_payload->>'mascota_id')::uuid, v_cliente, v_vet, v_cita,
    COALESCE(NULLIF(p_payload->>'fecha','')::timestamptz, now()),
    p_payload->>'motivo',
    p_payload->>'anamnesis',
    NULLIF(p_payload->>'peso_kg','')::numeric,
    NULLIF(p_payload->>'temperatura_c','')::numeric,
    NULLIF(p_payload->>'frecuencia_cardiaca','')::int,
    NULLIF(p_payload->>'frecuencia_respiratoria','')::int,
    p_payload->>'mucosas',
    NULLIF(p_payload->>'tllc_seg','')::numeric,
    NULLIF(p_payload->>'condicion_corporal','')::int,
    p_payload->>'examen_fisico',
    p_payload->>'diagnostico',
    p_payload->>'diagnostico_diferencial',
    p_payload->>'pronostico',
    p_payload->>'plan_terapeutico',
    p_payload->>'prescripcion',
    p_payload->>'indicaciones_casa',
    NULLIF(p_payload->>'proxima_visita','')::date,
    COALESCE((p_payload->>'estado')::core.estado_consulta, 'borrador'),
    p_user_id
  ) RETURNING id INTO v_id;

  PERFORM internal.registrar_evento_clinico(
    v_emp, (p_payload->>'mascota_id')::uuid, v_cliente, v_vet, 'consulta',
    'Consulta: ' || left(p_payload->>'motivo', 120),
    p_payload->>'diagnostico', v_id, v_cita);

  -- Atender desde la agenda cierra la cita sin un paso manual extra.
  IF v_cita IS NOT NULL THEN
    UPDATE core.citas
       SET estado = 'en_atencion',
           hora_atencion = COALESCE(hora_atencion, now()),
           updated_by = p_user_id
     WHERE id = v_cita AND estado NOT IN ('completada','cancelada');
  END IF;

  -- Recordatorio de control si el veterinario fijó próxima visita
  IF NULLIF(p_payload->>'proxima_visita','') IS NOT NULL THEN
    INSERT INTO core.recordatorios (
      empresa_id, cliente_id, mascota_id, tipo, titulo, mensaje,
      fecha_objetivo, entidad_ref, entidad_id)
    VALUES (
      v_emp, v_cliente, (p_payload->>'mascota_id')::uuid, 'control',
      'Control post-consulta',
      'Recordar al propietario la visita de control indicada en la consulta.',
      (p_payload->>'proxima_visita')::date, 'consultas', v_id);
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_consulta_actualizar(
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
  v_estado core.estado_consulta;
  v_antes  JSONB;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clinico:registrar');

  SELECT estado, to_jsonb(c) INTO v_estado, v_antes
    FROM core.consultas c
   WHERE c.id = p_id AND c.deleted_at IS NULL
     AND internal.es_de_empresa(p_user_id, p_is_super_admin,
           internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin), c.empresa_id);

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Consulta no encontrada'));
  END IF;

  -- Una consulta cerrada es un documento clínico firmado: no se reescribe.
  IF v_estado = 'cerrada' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'La consulta está cerrada. Registra una nota médica o una nueva consulta.'));
  END IF;

  UPDATE core.consultas SET
    motivo                  = COALESCE(p_payload->>'motivo', motivo),
    anamnesis               = COALESCE(p_payload->>'anamnesis', anamnesis),
    peso_kg                 = COALESCE(NULLIF(p_payload->>'peso_kg','')::numeric, peso_kg),
    temperatura_c           = COALESCE(NULLIF(p_payload->>'temperatura_c','')::numeric, temperatura_c),
    frecuencia_cardiaca     = COALESCE(NULLIF(p_payload->>'frecuencia_cardiaca','')::int, frecuencia_cardiaca),
    frecuencia_respiratoria = COALESCE(NULLIF(p_payload->>'frecuencia_respiratoria','')::int, frecuencia_respiratoria),
    mucosas                 = COALESCE(p_payload->>'mucosas', mucosas),
    tllc_seg                = COALESCE(NULLIF(p_payload->>'tllc_seg','')::numeric, tllc_seg),
    condicion_corporal      = COALESCE(NULLIF(p_payload->>'condicion_corporal','')::int, condicion_corporal),
    examen_fisico           = COALESCE(p_payload->>'examen_fisico', examen_fisico),
    diagnostico             = COALESCE(p_payload->>'diagnostico', diagnostico),
    diagnostico_diferencial = COALESCE(p_payload->>'diagnostico_diferencial', diagnostico_diferencial),
    pronostico              = COALESCE(p_payload->>'pronostico', pronostico),
    plan_terapeutico        = COALESCE(p_payload->>'plan_terapeutico', plan_terapeutico),
    prescripcion            = COALESCE(p_payload->>'prescripcion', prescripcion),
    indicaciones_casa       = COALESCE(p_payload->>'indicaciones_casa', indicaciones_casa),
    proxima_visita          = COALESCE(NULLIF(p_payload->>'proxima_visita','')::date, proxima_visita),
    updated_by              = p_user_id
  WHERE id = p_id;

  PERFORM internal.registrar_auditoria(
    p_user_id, p_empresa_id, 'actualizar', 'consultas', p_id, v_antes, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_consulta_cerrar — firma la consulta y completa la cita asociada
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_consulta_cerrar(
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
  v_consulta RECORD;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clinico:registrar');

  SELECT * INTO v_consulta FROM core.consultas
   WHERE id = p_id AND deleted_at IS NULL
     AND internal.es_de_empresa(p_user_id, p_is_super_admin,
           internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin), empresa_id);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Consulta no encontrada'));
  END IF;

  IF COALESCE(trim(v_consulta.diagnostico), '') = '' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'No se puede cerrar una consulta sin diagnóstico','diagnostico'));
  END IF;

  UPDATE core.consultas SET estado = 'cerrada', updated_by = p_user_id WHERE id = p_id;

  IF v_consulta.cita_id IS NOT NULL THEN
    UPDATE core.citas
       SET estado = 'completada',
           hora_salida = COALESCE(hora_salida, now()),
           updated_by = p_user_id
     WHERE id = v_consulta.cita_id;

    INSERT INTO core.citas_historial (cita_id, accion, motivo, user_id)
    VALUES (v_consulta.cita_id, 'atendida', 'Consulta cerrada', p_user_id);
  END IF;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_consulta.empresa_id, 'cerrar', 'consultas', p_id);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'estado', 'cerrada'));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_consulta_obtener — con insumos, exámenes y órdenes de servicio
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_consulta_obtener(
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
           m.condiciones_cronicas,
           esp.nombre AS especie, r.nombre AS raza,
           internal.edad_mascota(m.fecha_nacimiento, m.edad_aproximada_meses) AS edad,
           trim(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'')) AS cliente,
           cl.telefono AS cliente_telefono,
           trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS veterinario,
           u.colegiatura,
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id', iu.id, 'producto_id', iu.producto_id, 'producto', pr.nombre,
                     'cantidad', iu.cantidad, 'precio_unitario', iu.precio_unitario,
                     'facturado', iu.facturado)), '[]'::jsonb)
              FROM core.insumos_utilizados iu
              JOIN core.productos pr ON pr.id = iu.producto_id
             WHERE iu.consulta_id = c.id) AS insumos,
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id', ex.id, 'tipo', ex.tipo, 'nombre', ex.nombre,
                     'fecha_solicitud', ex.fecha_solicitud, 'fecha_resultado', ex.fecha_resultado,
                     'resultado', ex.resultado, 'valores', ex.valores,
                     'archivo_url', ex.archivo_url)), '[]'::jsonb)
              FROM core.examenes ex WHERE ex.consulta_id = c.id) AS examenes,
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id', os.id, 'servicio', s.nombre, 'cantidad', os.cantidad,
                     'precio_unitario', os.precio_unitario, 'total', os.total,
                     'estado', os.estado, 'facturado', os.facturado)), '[]'::jsonb)
              FROM core.ordenes_servicio os
              JOIN core.servicios s ON s.id = os.servicio_id
             WHERE os.consulta_id = c.id) AS servicios,
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id', t.id, 'medicamento', t.medicamento, 'dosis', t.dosis,
                     'via', t.via, 'frecuencia_horas', t.frecuencia_horas,
                     'duracion_dias', t.duracion_dias, 'estado', t.estado)), '[]'::jsonb)
              FROM core.tratamientos t WHERE t.consulta_id = c.id) AS tratamientos
    FROM core.consultas c
    JOIN core.mascotas m  ON m.id = c.mascota_id
    JOIN core.clientes cl ON cl.id = c.cliente_id
    JOIN core.especies esp ON esp.id = m.especie_id
    LEFT JOIN core.razas r ON r.id = m.raza_id
    LEFT JOIN core.users u ON u.id = c.veterinario_id
    WHERE c.id = p_id AND c.deleted_at IS NULL
      AND (v_global OR c.empresa_id = v_emp)
  ) x;

  IF v_data IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Consulta no encontrada'));
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_consultas_listar(
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
  v_size   INT     := LEAST(GREATEST(COALESCE(p_page_size, 20), 1), 100);
  v_page   INT     := GREATEST(COALESCE(p_page, 1), 1);
  v_total  INT;
  v_data   JSONB;
BEGIN
  SELECT count(*) INTO v_total
  FROM core.consultas c
  WHERE c.deleted_at IS NULL AND (v_global OR c.empresa_id = v_emp)
    AND (p_filtros->>'mascota_id'     IS NULL OR c.mascota_id = (p_filtros->>'mascota_id')::uuid)
    AND (p_filtros->>'veterinario_id' IS NULL OR c.veterinario_id = (p_filtros->>'veterinario_id')::uuid)
    AND (p_filtros->>'estado'         IS NULL OR c.estado::text = p_filtros->>'estado')
    AND (p_filtros->>'desde' IS NULL OR c.fecha >= (p_filtros->>'desde')::timestamptz)
    AND (p_filtros->>'hasta' IS NULL OR c.fecha <  (p_filtros->>'hasta')::timestamptz);

  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) INTO v_data
  FROM (
    SELECT c.id, c.codigo, c.fecha, c.motivo, c.diagnostico, c.estado,
           c.peso_kg, c.temperatura_c, c.proxima_visita,
           c.mascota_id, m.nombre AS mascota, m.foto_url AS mascota_foto,
           esp.nombre AS especie,
           c.cliente_id,
           trim(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'')) AS cliente,
           c.veterinario_id,
           trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS veterinario
    FROM core.consultas c
    JOIN core.mascotas m  ON m.id = c.mascota_id
    JOIN core.clientes cl ON cl.id = c.cliente_id
    JOIN core.especies esp ON esp.id = m.especie_id
    LEFT JOIN core.users u ON u.id = c.veterinario_id
    WHERE c.deleted_at IS NULL AND (v_global OR c.empresa_id = v_emp)
      AND (p_filtros->>'mascota_id'     IS NULL OR c.mascota_id = (p_filtros->>'mascota_id')::uuid)
      AND (p_filtros->>'veterinario_id' IS NULL OR c.veterinario_id = (p_filtros->>'veterinario_id')::uuid)
      AND (p_filtros->>'estado'         IS NULL OR c.estado::text = p_filtros->>'estado')
      AND (p_filtros->>'desde' IS NULL OR c.fecha >= (p_filtros->>'desde')::timestamptz)
      AND (p_filtros->>'hasta' IS NULL OR c.fecha <  (p_filtros->>'hasta')::timestamptz)
    ORDER BY c.fecha DESC
    LIMIT v_size OFFSET (v_page - 1) * v_size
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data, 'meta', jsonb_build_object(
    'total', v_total, 'page', v_page, 'pageSize', v_size,
    'pages', GREATEST(CEIL(v_total::numeric / v_size)::int, 1)));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- VACUNAS
-- =============================================================================

CREATE OR REPLACE FUNCTION app.sp_vacuna_aplicar(
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
  v_cliente  UUID;
  v_mascota  UUID := (p_payload->>'mascota_id')::uuid;
  v_producto UUID := NULLIF(p_payload->>'producto_id','')::uuid;
  v_refuerzo DATE := NULLIF(p_payload->>'proximo_refuerzo','')::date;
  v_esquema  UUID := NULLIF(p_payload->>'esquema_id','')::uuid;
  v_fecha    DATE := COALESCE(NULLIF(p_payload->>'fecha_aplicacion','')::date, CURRENT_DATE);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clinico:registrar');
  PERFORM internal.validar_payload(p_payload, ARRAY['mascota_id','nombre_vacuna']);

  SELECT cliente_id INTO v_cliente FROM core.mascotas
   WHERE id = v_mascota AND deleted_at IS NULL
     AND (internal.es_acceso_global(p_user_id, p_is_super_admin) OR empresa_id = v_emp);
  IF v_cliente IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','El paciente indicado no existe','mascota_id'));
  END IF;

  -- Si no llega refuerzo explícito pero hay esquema, se calcula del protocolo.
  IF v_refuerzo IS NULL AND v_esquema IS NOT NULL THEN
    SELECT v_fecha + COALESCE(ev.intervalo_dias, ev.revacunacion_meses * 30, 365)
      INTO v_refuerzo
    FROM core.esquemas_vacunacion ev WHERE ev.id = v_esquema;
  END IF;

  INSERT INTO core.vacunas (
    empresa_id, mascota_id, veterinario_id, consulta_id, esquema_id, producto_id,
    nombre_vacuna, laboratorio, lote, fecha_aplicacion, dosis_numero,
    proximo_refuerzo, via, reaccion_adversa, observaciones, created_by
  ) VALUES (
    v_emp, v_mascota,
    COALESCE(NULLIF(p_payload->>'veterinario_id','')::uuid, p_user_id),
    NULLIF(p_payload->>'consulta_id','')::uuid,
    v_esquema, v_producto,
    p_payload->>'nombre_vacuna',
    p_payload->>'laboratorio',
    p_payload->>'lote',
    v_fecha,
    COALESCE((p_payload->>'dosis_numero')::int, 1),
    v_refuerzo,
    COALESCE((p_payload->>'via')::core.via_administracion, 'subcutanea'),
    p_payload->>'reaccion_adversa',
    p_payload->>'observaciones',
    p_user_id
  ) RETURNING id INTO v_id;

  -- La dosis sale del inventario si se indicó el producto.
  IF v_producto IS NOT NULL THEN
    PERFORM internal.mover_stock(
      v_emp, v_producto, 'salida', 'uso_clinico', 1, p_user_id, NULL,
      jsonb_build_object('mascota_id', v_mascota,
                         'consulta_id', p_payload->>'consulta_id',
                         'observaciones', 'Vacuna aplicada: ' || (p_payload->>'nombre_vacuna')));
  END IF;

  PERFORM internal.registrar_evento_clinico(
    v_emp, v_mascota, v_cliente,
    COALESCE(NULLIF(p_payload->>'veterinario_id','')::uuid, p_user_id),
    'vacuna', 'Vacuna: ' || (p_payload->>'nombre_vacuna'),
    CASE WHEN v_refuerzo IS NOT NULL
         THEN 'Próximo refuerzo: ' || to_char(v_refuerzo, 'DD/MM/YYYY') END,
    v_id, NULLIF(p_payload->>'cita_id','')::uuid, v_fecha::timestamptz);

  -- Recordatorio del refuerzo para que recepción lo contacte a tiempo.
  IF v_refuerzo IS NOT NULL THEN
    INSERT INTO core.recordatorios (
      empresa_id, cliente_id, mascota_id, tipo, titulo, mensaje,
      fecha_objetivo, entidad_ref, entidad_id)
    VALUES (
      v_emp, v_cliente, v_mascota, 'vacuna',
      'Refuerzo de ' || (p_payload->>'nombre_vacuna'),
      'Corresponde el refuerzo de la vacuna aplicada el ' || to_char(v_fecha, 'DD/MM/YYYY') || '.',
      v_refuerzo, 'vacunas', v_id);
  END IF;

  RETURN jsonb_build_object('ok', true,
    'data', jsonb_build_object('id', v_id, 'proximo_refuerzo', v_refuerzo));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- Carné de vacunación: lo que está al día, lo vencido y lo próximo
CREATE OR REPLACE FUNCTION app.fn_vacunas_carne(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_mascota_id     UUID
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
  IF NOT EXISTS (SELECT 1 FROM core.mascotas
                  WHERE id = p_mascota_id AND deleted_at IS NULL
                    AND (v_global OR empresa_id = v_emp)) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Paciente no encontrado'));
  END IF;

  SELECT COALESCE(jsonb_agg(x ORDER BY x.fecha_aplicacion DESC), '[]'::jsonb) INTO v_data
  FROM (
    SELECT v.id, v.nombre_vacuna, v.laboratorio, v.lote, v.fecha_aplicacion,
           v.dosis_numero, v.proximo_refuerzo, v.via, v.reaccion_adversa,
           v.observaciones, emp.nombre_comercial AS empresa,
           trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS veterinario,
           u.colegiatura,
           CASE
             WHEN v.proximo_refuerzo IS NULL THEN 'sin_refuerzo'
             WHEN v.proximo_refuerzo < CURRENT_DATE THEN 'vencida'
             WHEN v.proximo_refuerzo <= CURRENT_DATE + 30 THEN 'por_vencer'
             ELSE 'vigente'
           END AS situacion
    FROM core.vacunas v
    LEFT JOIN core.users u ON u.id = v.veterinario_id
    LEFT JOIN core.empresas emp ON emp.id = v.empresa_id
    WHERE v.mascota_id = p_mascota_id
      AND (v_global OR v.empresa_id = v_emp)
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- DESPARASITACIONES
-- =============================================================================

CREATE OR REPLACE FUNCTION app.sp_desparasitacion_registrar(
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
  v_proxima DATE := NULLIF(p_payload->>'proxima_dosis','')::date;
  v_fecha   DATE := COALESCE(NULLIF(p_payload->>'fecha_aplicacion','')::date, CURRENT_DATE);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clinico:registrar');
  PERFORM internal.validar_payload(p_payload, ARRAY['mascota_id','producto_nombre']);

  SELECT cliente_id INTO v_cliente FROM core.mascotas
   WHERE id = v_mascota AND deleted_at IS NULL
     AND (internal.es_acceso_global(p_user_id, p_is_super_admin) OR empresa_id = v_emp);

  INSERT INTO core.desparasitaciones (
    empresa_id, mascota_id, veterinario_id, consulta_id, producto_id,
    producto_nombre, tipo, dosis, fecha_aplicacion, proxima_dosis, observaciones, created_by
  ) VALUES (
    v_emp, v_mascota,
    COALESCE(NULLIF(p_payload->>'veterinario_id','')::uuid, p_user_id),
    NULLIF(p_payload->>'consulta_id','')::uuid,
    NULLIF(p_payload->>'producto_id','')::uuid,
    p_payload->>'producto_nombre',
    COALESCE(p_payload->>'tipo','interna'),
    p_payload->>'dosis',
    v_fecha, v_proxima,
    p_payload->>'observaciones',
    p_user_id
  ) RETURNING id INTO v_id;

  IF NULLIF(p_payload->>'producto_id','') IS NOT NULL THEN
    PERFORM internal.mover_stock(
      v_emp, (p_payload->>'producto_id')::uuid, 'salida', 'uso_clinico', 1, p_user_id, NULL,
      jsonb_build_object('mascota_id', v_mascota, 'observaciones', 'Desparasitación'));
  END IF;

  PERFORM internal.registrar_evento_clinico(
    v_emp, v_mascota, v_cliente, p_user_id, 'desparasitacion',
    'Desparasitación ' || COALESCE(p_payload->>'tipo','interna'),
    p_payload->>'producto_nombre', v_id, NULL, v_fecha::timestamptz);

  IF v_proxima IS NOT NULL THEN
    INSERT INTO core.recordatorios (
      empresa_id, cliente_id, mascota_id, tipo, titulo, mensaje,
      fecha_objetivo, entidad_ref, entidad_id)
    VALUES (v_emp, v_cliente, v_mascota, 'desparasitacion',
            'Próxima desparasitación',
            'Corresponde la siguiente dosis de desparasitación.',
            v_proxima, 'desparasitaciones', v_id);
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- TRATAMIENTOS
-- =============================================================================

CREATE OR REPLACE FUNCTION app.sp_tratamiento_registrar(
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
  v_inicio  DATE := COALESCE(NULLIF(p_payload->>'fecha_inicio','')::date, CURRENT_DATE);
  v_dias    INT  := NULLIF(p_payload->>'duracion_dias','')::int;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clinico:registrar');
  PERFORM internal.validar_payload(p_payload, ARRAY['mascota_id','medicamento','dosis']);

  SELECT cliente_id INTO v_cliente FROM core.mascotas
   WHERE id = v_mascota AND deleted_at IS NULL
     AND (internal.es_acceso_global(p_user_id, p_is_super_admin) OR empresa_id = v_emp);

  INSERT INTO core.tratamientos (
    empresa_id, mascota_id, consulta_id, veterinario_id, producto_id,
    medicamento, principio_activo, dosis, via, frecuencia_horas, duracion_dias,
    fecha_inicio, fecha_fin, indicaciones, estado, created_by
  ) VALUES (
    v_emp, v_mascota,
    NULLIF(p_payload->>'consulta_id','')::uuid,
    COALESCE(NULLIF(p_payload->>'veterinario_id','')::uuid, p_user_id),
    NULLIF(p_payload->>'producto_id','')::uuid,
    p_payload->>'medicamento',
    p_payload->>'principio_activo',
    p_payload->>'dosis',
    COALESCE((p_payload->>'via')::core.via_administracion, 'oral'),
    NULLIF(p_payload->>'frecuencia_horas','')::int,
    v_dias, v_inicio,
    COALESCE(NULLIF(p_payload->>'fecha_fin','')::date,
             CASE WHEN v_dias IS NOT NULL THEN v_inicio + v_dias END),
    p_payload->>'indicaciones',
    COALESCE((p_payload->>'estado')::core.estado_tratamiento, 'activo'),
    p_user_id
  ) RETURNING id INTO v_id;

  PERFORM internal.registrar_evento_clinico(
    v_emp, v_mascota, v_cliente, p_user_id, 'tratamiento',
    'Tratamiento: ' || (p_payload->>'medicamento'),
    (p_payload->>'dosis') || ' · ' || COALESCE(p_payload->>'via','oral'),
    v_id, NULL, v_inicio::timestamptz);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_tratamiento_cambiar_estado(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_id             UUID,
  p_estado         VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clinico:registrar');

  UPDATE core.tratamientos
     SET estado = p_estado::core.estado_tratamiento,
         fecha_fin = CASE WHEN p_estado <> 'activo' THEN COALESCE(fecha_fin, CURRENT_DATE) ELSE fecha_fin END
   WHERE id = p_id
     AND internal.es_de_empresa(p_user_id, p_is_super_admin,
           internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin), empresa_id);

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Tratamiento no encontrado'));
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'estado', p_estado));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- CIRUGÍAS
-- =============================================================================

CREATE OR REPLACE FUNCTION app.sp_cirugia_programar(
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
  PERFORM internal.assert_permiso(p_user_id, 'clinico:registrar');
  PERFORM internal.validar_payload(p_payload, ARRAY['mascota_id','nombre']);

  SELECT cliente_id INTO v_cliente FROM core.mascotas
   WHERE id = v_mascota AND deleted_at IS NULL
     AND (internal.es_acceso_global(p_user_id, p_is_super_admin) OR empresa_id = v_emp);
  IF v_cliente IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','El paciente indicado no existe','mascota_id'));
  END IF;

  INSERT INTO core.cirugias (
    empresa_id, codigo, mascota_id, cirujano_id, anestesista_id, consultorio_id,
    servicio_id, cita_id, nombre, descripcion, fecha_programada,
    anestesia_tipo, consentimiento_firmado, estado, created_by
  ) VALUES (
    v_emp, internal.siguiente_numero(v_emp, 'CIR', 5), v_mascota,
    COALESCE(NULLIF(p_payload->>'cirujano_id','')::uuid, p_user_id),
    NULLIF(p_payload->>'anestesista_id','')::uuid,
    NULLIF(p_payload->>'consultorio_id','')::uuid,
    NULLIF(p_payload->>'servicio_id','')::uuid,
    NULLIF(p_payload->>'cita_id','')::uuid,
    p_payload->>'nombre', p_payload->>'descripcion',
    NULLIF(p_payload->>'fecha_programada','')::timestamptz,
    p_payload->>'anestesia_tipo',
    COALESCE((p_payload->>'consentimiento_firmado')::boolean, false),
    'programada', p_user_id
  ) RETURNING id INTO v_id;

  PERFORM internal.registrar_evento_clinico(
    v_emp, v_mascota, v_cliente,
    COALESCE(NULLIF(p_payload->>'cirujano_id','')::uuid, p_user_id),
    'cirugia', 'Cirugía programada: ' || (p_payload->>'nombre'),
    p_payload->>'descripcion', v_id, NULLIF(p_payload->>'cita_id','')::uuid);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_cirugia_registrar_resultado(
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
  v_cir RECORD;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clinico:registrar');

  SELECT * INTO v_cir FROM core.cirugias
   WHERE id = p_id
     AND internal.es_de_empresa(p_user_id, p_is_super_admin,
           internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin), empresa_id);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Cirugía no encontrada'));
  END IF;

  IF NOT v_cir.consentimiento_firmado
     AND COALESCE((p_payload->>'consentimiento_firmado')::boolean, false) = false THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'No se puede cerrar la cirugía sin el consentimiento informado firmado',
        'consentimiento_firmado'));
  END IF;

  UPDATE core.cirugias SET
    fecha_inicio    = COALESCE(NULLIF(p_payload->>'fecha_inicio','')::timestamptz, fecha_inicio, now()),
    fecha_fin       = COALESCE(NULLIF(p_payload->>'fecha_fin','')::timestamptz, fecha_fin, now()),
    anestesia_tipo  = COALESCE(p_payload->>'anestesia_tipo', anestesia_tipo),
    anestesia_dosis = COALESCE(p_payload->>'anestesia_dosis', anestesia_dosis),
    hallazgos       = COALESCE(p_payload->>'hallazgos', hallazgos),
    complicaciones  = COALESCE(p_payload->>'complicaciones', complicaciones),
    resultado       = COALESCE(p_payload->>'resultado', resultado),
    cuidados_post   = COALESCE(p_payload->>'cuidados_post', cuidados_post),
    consentimiento_firmado = COALESCE((p_payload->>'consentimiento_firmado')::boolean, consentimiento_firmado),
    estado          = COALESCE((p_payload->>'estado')::core.estado_cirugia, 'realizada'),
    updated_by      = p_user_id
  WHERE id = p_id;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_cir.empresa_id, 'registrar_resultado', 'cirugias', p_id, NULL, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_cirugias_listar(
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
  v_data   JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(x ORDER BY x.fecha DESC NULLS LAST), '[]'::jsonb) INTO v_data
  FROM (
    SELECT c.id, c.codigo, c.nombre, c.descripcion, c.estado,
           COALESCE(c.fecha_inicio, c.fecha_programada) AS fecha,
           c.fecha_programada, c.fecha_inicio, c.fecha_fin,
           c.anestesia_tipo, c.hallazgos, c.complicaciones, c.resultado,
           c.consentimiento_firmado,
           c.mascota_id, m.nombre AS mascota, m.foto_url AS mascota_foto,
           esp.nombre AS especie,
           trim(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'')) AS cliente,
           trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS cirujano,
           co.nombre AS quirofano
    FROM core.cirugias c
    JOIN core.mascotas m ON m.id = c.mascota_id
    JOIN core.clientes cl ON cl.id = m.cliente_id
    JOIN core.especies esp ON esp.id = m.especie_id
    LEFT JOIN core.users u ON u.id = c.cirujano_id
    LEFT JOIN core.consultorios co ON co.id = c.consultorio_id
    WHERE (v_global OR c.empresa_id = v_emp)
      AND (p_filtros->>'estado'     IS NULL OR c.estado::text = p_filtros->>'estado')
      AND (p_filtros->>'mascota_id' IS NULL OR c.mascota_id = (p_filtros->>'mascota_id')::uuid)
      AND (p_filtros->>'desde' IS NULL OR COALESCE(c.fecha_inicio, c.fecha_programada) >= (p_filtros->>'desde')::timestamptz)
      AND (p_filtros->>'hasta' IS NULL OR COALESCE(c.fecha_inicio, c.fecha_programada) <  (p_filtros->>'hasta')::timestamptz)
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- HOSPITALIZACIÓN
-- =============================================================================

CREATE OR REPLACE FUNCTION app.sp_hospitalizacion_ingresar(
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
  PERFORM internal.assert_permiso(p_user_id, 'clinico:registrar');
  PERFORM internal.validar_payload(p_payload, ARRAY['mascota_id','motivo']);

  IF EXISTS (SELECT 1 FROM core.hospitalizaciones
              WHERE mascota_id = v_mascota AND estado IN ('ingresado','en_observacion')) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('CONFLICT','El paciente ya está hospitalizado'));
  END IF;

  SELECT cliente_id INTO v_cliente FROM core.mascotas
   WHERE id = v_mascota AND deleted_at IS NULL
     AND (internal.es_acceso_global(p_user_id, p_is_super_admin) OR empresa_id = v_emp);

  INSERT INTO core.hospitalizaciones (
    empresa_id, codigo, mascota_id, veterinario_id, consultorio_id, jaula,
    motivo, diagnostico, fecha_ingreso, estado, created_by
  ) VALUES (
    v_emp, internal.siguiente_numero(v_emp, 'HOSP', 5), v_mascota,
    COALESCE(NULLIF(p_payload->>'veterinario_id','')::uuid, p_user_id),
    NULLIF(p_payload->>'consultorio_id','')::uuid,
    p_payload->>'jaula', p_payload->>'motivo', p_payload->>'diagnostico',
    COALESCE(NULLIF(p_payload->>'fecha_ingreso','')::timestamptz, now()),
    'ingresado', p_user_id
  ) RETURNING id INTO v_id;

  PERFORM internal.registrar_evento_clinico(
    v_emp, v_mascota, v_cliente, p_user_id, 'hospitalizacion',
    'Ingreso a hospitalización', p_payload->>'motivo', v_id);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_hospitalizacion_evolucion(
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
  v_id UUID;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clinico:registrar');
  PERFORM internal.validar_payload(p_payload, ARRAY['hospitalizacion_id']);

  IF NOT EXISTS (
      SELECT 1 FROM core.hospitalizaciones h
       WHERE h.id = (p_payload->>'hospitalizacion_id')::uuid
         AND internal.es_de_empresa(p_user_id, p_is_super_admin,
               internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin), h.empresa_id)) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Hospitalización no encontrada','hospitalizacion_id'));
  END IF;

  INSERT INTO core.hospitalizacion_evoluciones (
    hospitalizacion_id, user_id, fecha_hora, temperatura_c,
    frecuencia_cardiaca, frecuencia_respiratoria, come, orina, defeca, nota
  ) VALUES (
    (p_payload->>'hospitalizacion_id')::uuid, p_user_id,
    COALESCE(NULLIF(p_payload->>'fecha_hora','')::timestamptz, now()),
    NULLIF(p_payload->>'temperatura_c','')::numeric,
    NULLIF(p_payload->>'frecuencia_cardiaca','')::int,
    NULLIF(p_payload->>'frecuencia_respiratoria','')::int,
    NULLIF(p_payload->>'come','')::boolean,
    NULLIF(p_payload->>'orina','')::boolean,
    NULLIF(p_payload->>'defeca','')::boolean,
    p_payload->>'nota'
  ) RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_hospitalizacion_alta(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_id             UUID,
  p_payload        JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_h RECORD;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clinico:registrar');

  SELECT * INTO v_h FROM core.hospitalizaciones
   WHERE id = p_id
     AND internal.es_de_empresa(p_user_id, p_is_super_admin,
           internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin), empresa_id);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Hospitalización no encontrada'));
  END IF;

  UPDATE core.hospitalizaciones SET
    fecha_alta        = COALESCE(NULLIF(p_payload->>'fecha_alta','')::timestamptz, now()),
    indicaciones_alta = COALESCE(p_payload->>'indicaciones_alta', indicaciones_alta),
    estado            = COALESCE((p_payload->>'estado')::core.estado_hospitalizacion, 'alta')
  WHERE id = p_id;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_hospitalizaciones_listar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_solo_activas   BOOLEAN DEFAULT true
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
  SELECT COALESCE(jsonb_agg(x ORDER BY x.fecha_ingreso DESC), '[]'::jsonb) INTO v_data
  FROM (
    SELECT h.id, h.codigo, h.jaula, h.motivo, h.diagnostico, h.estado,
           h.fecha_ingreso, h.fecha_alta, h.indicaciones_alta,
           EXTRACT(DAY FROM (COALESCE(h.fecha_alta, now()) - h.fecha_ingreso))::int AS dias_internado,
           h.mascota_id, m.nombre AS mascota, m.foto_url AS mascota_foto, m.peso_kg,
           esp.nombre AS especie,
           trim(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'')) AS cliente,
           cl.telefono AS cliente_telefono,
           trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS veterinario,
           (SELECT jsonb_build_object(
                     'fecha_hora', e.fecha_hora, 'temperatura_c', e.temperatura_c,
                     'nota', e.nota)
              FROM core.hospitalizacion_evoluciones e
             WHERE e.hospitalizacion_id = h.id
             ORDER BY e.fecha_hora DESC LIMIT 1) AS ultima_evolucion
    FROM core.hospitalizaciones h
    JOIN core.mascotas m ON m.id = h.mascota_id
    JOIN core.clientes cl ON cl.id = m.cliente_id
    JOIN core.especies esp ON esp.id = m.especie_id
    LEFT JOIN core.users u ON u.id = h.veterinario_id
    WHERE (v_global OR h.empresa_id = v_emp)
      AND (p_solo_activas = false OR h.estado IN ('ingresado','en_observacion'))
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- EXÁMENES, NOTAS Y DOCUMENTOS
-- =============================================================================

CREATE OR REPLACE FUNCTION app.sp_examen_registrar(
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
  PERFORM internal.assert_permiso(p_user_id, 'clinico:registrar');
  PERFORM internal.validar_payload(p_payload, ARRAY['mascota_id','tipo','nombre']);

  SELECT cliente_id INTO v_cliente FROM core.mascotas
   WHERE id = v_mascota AND deleted_at IS NULL
     AND (internal.es_acceso_global(p_user_id, p_is_super_admin) OR empresa_id = v_emp);

  INSERT INTO core.examenes (
    empresa_id, mascota_id, consulta_id, servicio_id, veterinario_id,
    tipo, nombre, fecha_solicitud, fecha_resultado, resultado, valores,
    interpretacion, archivo_url, created_by
  ) VALUES (
    v_emp, v_mascota,
    NULLIF(p_payload->>'consulta_id','')::uuid,
    NULLIF(p_payload->>'servicio_id','')::uuid,
    COALESCE(NULLIF(p_payload->>'veterinario_id','')::uuid, p_user_id),
    p_payload->>'tipo', p_payload->>'nombre',
    COALESCE(NULLIF(p_payload->>'fecha_solicitud','')::timestamptz, now()),
    NULLIF(p_payload->>'fecha_resultado','')::timestamptz,
    p_payload->>'resultado',
    CASE WHEN p_payload ? 'valores' THEN p_payload->'valores' END,
    p_payload->>'interpretacion',
    p_payload->>'archivo_url',
    p_user_id
  ) RETURNING id INTO v_id;

  PERFORM internal.registrar_evento_clinico(
    v_emp, v_mascota, v_cliente, p_user_id, 'examen',
    (p_payload->>'tipo') || ': ' || (p_payload->>'nombre'),
    p_payload->>'interpretacion', v_id);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_nota_medica_crear(
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
  PERFORM internal.validar_payload(p_payload, ARRAY['mascota_id','nota']);

  SELECT cliente_id INTO v_cliente FROM core.mascotas
   WHERE id = v_mascota AND deleted_at IS NULL
     AND (internal.es_acceso_global(p_user_id, p_is_super_admin) OR empresa_id = v_emp);

  INSERT INTO core.notas_medicas (empresa_id, mascota_id, user_id, nota, destacada)
  VALUES (v_emp, v_mascota, p_user_id, p_payload->>'nota',
          COALESCE((p_payload->>'destacada')::boolean, false))
  RETURNING id INTO v_id;

  PERFORM internal.registrar_evento_clinico(
    v_emp, v_mascota, v_cliente, p_user_id, 'nota',
    'Nota médica', left(p_payload->>'nota', 200), v_id);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_documento_medico_registrar(
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
  PERFORM internal.validar_payload(p_payload, ARRAY['mascota_id','titulo','storage_key']);

  SELECT cliente_id INTO v_cliente FROM core.mascotas
   WHERE id = v_mascota AND deleted_at IS NULL
     AND (internal.es_acceso_global(p_user_id, p_is_super_admin) OR empresa_id = v_emp);

  INSERT INTO core.documentos_medicos (
    empresa_id, mascota_id, consulta_id, tipo, titulo, descripcion,
    storage_key, mime_type, tamanio_bytes, created_by
  ) VALUES (
    v_emp, v_mascota,
    NULLIF(p_payload->>'consulta_id','')::uuid,
    COALESCE(p_payload->>'tipo','otro'),
    p_payload->>'titulo', p_payload->>'descripcion',
    p_payload->>'storage_key', p_payload->>'mime_type',
    NULLIF(p_payload->>'tamanio_bytes','')::bigint,
    p_user_id
  ) RETURNING id INTO v_id;

  PERFORM internal.registrar_evento_clinico(
    v_emp, v_mascota, v_cliente, p_user_id, 'documento',
    'Documento: ' || (p_payload->>'titulo'), p_payload->>'descripcion', v_id);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_documentos_medicos_listar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_mascota_id     UUID
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
  IF NOT EXISTS (SELECT 1 FROM core.mascotas
                  WHERE id = p_mascota_id AND deleted_at IS NULL
                    AND (v_global OR empresa_id = v_emp)) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Paciente no encontrado'));
  END IF;

  SELECT COALESCE(jsonb_agg(x ORDER BY x.created_at DESC), '[]'::jsonb) INTO v_data
  FROM (
    SELECT d.id, d.tipo, d.titulo, d.descripcion, d.storage_key, d.mime_type,
           d.tamanio_bytes, d.created_at,
           trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS subido_por
    FROM core.documentos_medicos d
    LEFT JOIN core.users u ON u.id = d.created_by
    WHERE d.mascota_id = p_mascota_id
      AND (v_global OR d.empresa_id = v_emp)
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- ÓRDENES DE SERVICIO E INSUMOS (lo facturable de la atención)
-- =============================================================================

CREATE OR REPLACE FUNCTION app.sp_orden_servicio_crear(
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
  v_mascota  UUID := (p_payload->>'mascota_id')::uuid;
  v_cliente  UUID;
  v_precio   NUMERIC(12,2);
  v_cant     NUMERIC(10,2) := COALESCE((p_payload->>'cantidad')::numeric, 1);
  v_desc     NUMERIC(12,2) := COALESCE((p_payload->>'descuento')::numeric, 0);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clinico:registrar');
  PERFORM internal.validar_payload(p_payload, ARRAY['mascota_id','servicio_id']);

  SELECT cliente_id INTO v_cliente FROM core.mascotas
   WHERE id = v_mascota AND deleted_at IS NULL
     AND (internal.es_acceso_global(p_user_id, p_is_super_admin) OR empresa_id = v_emp);

  SELECT COALESCE(NULLIF(p_payload->>'precio_unitario','')::numeric, s.precio) INTO v_precio
    FROM core.servicios s
   WHERE s.id = (p_payload->>'servicio_id')::uuid AND s.deleted_at IS NULL
     AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, s.empresa_id);

  IF v_precio IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Servicio no encontrado','servicio_id'));
  END IF;

  INSERT INTO core.ordenes_servicio (
    empresa_id, codigo, mascota_id, cliente_id, servicio_id, veterinario_id,
    cita_id, consulta_id, cantidad, precio_unitario, descuento, total,
    descripcion, estado, created_by
  ) VALUES (
    v_emp, internal.siguiente_numero(v_emp, 'OS', 6), v_mascota, v_cliente,
    (p_payload->>'servicio_id')::uuid,
    COALESCE(NULLIF(p_payload->>'veterinario_id','')::uuid, p_user_id),
    NULLIF(p_payload->>'cita_id','')::uuid,
    NULLIF(p_payload->>'consulta_id','')::uuid,
    v_cant, v_precio, v_desc, round(v_cant * v_precio - v_desc, 2),
    p_payload->>'descripcion',
    COALESCE((p_payload->>'estado')::core.estado_orden_servicio, 'completado'),
    p_user_id
  ) RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- Consumir insumo del inventario dentro de un acto clínico
CREATE OR REPLACE FUNCTION app.sp_insumo_consumir(
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
  v_prod    UUID := (p_payload->>'producto_id')::uuid;
  v_cant    NUMERIC := (p_payload->>'cantidad')::numeric;
  v_precio  NUMERIC(12,2);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clinico:registrar');
  PERFORM internal.validar_payload(p_payload, ARRAY['producto_id','cantidad']);

  SELECT COALESCE(NULLIF(p_payload->>'precio_unitario','')::numeric, precio_venta)
    INTO v_precio FROM core.productos
   WHERE id = v_prod AND deleted_at IS NULL
     AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, empresa_id);

  IF v_precio IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Producto no encontrado','producto_id'));
  END IF;

  -- mover_stock valida que haya existencias antes de descontar
  PERFORM internal.mover_stock(
    v_emp, v_prod, 'salida', 'uso_clinico', v_cant, p_user_id,
    NULLIF(p_payload->>'almacen_id','')::uuid,
    jsonb_build_object('mascota_id', p_payload->>'mascota_id',
                       'consulta_id', p_payload->>'consulta_id',
                       'observaciones', 'Insumo usado en atención clínica'));

  INSERT INTO core.insumos_utilizados (
    empresa_id, producto_id, mascota_id, consulta_id, cirugia_id,
    hospitalizacion_id, orden_servicio_id, cantidad, precio_unitario, created_by
  ) VALUES (
    v_emp, v_prod,
    NULLIF(p_payload->>'mascota_id','')::uuid,
    NULLIF(p_payload->>'consulta_id','')::uuid,
    NULLIF(p_payload->>'cirugia_id','')::uuid,
    NULLIF(p_payload->>'hospitalizacion_id','')::uuid,
    NULLIF(p_payload->>'orden_servicio_id','')::uuid,
    v_cant, v_precio, p_user_id
  ) RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- Lo pendiente de facturar de un cliente: servicios + insumos aún no cobrados
CREATE OR REPLACE FUNCTION app.fn_pendiente_facturar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_cliente_id     UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp   UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_serv  JSONB;
  v_ins   JSONB;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM core.clientes c
                  WHERE c.id = p_cliente_id AND c.deleted_at IS NULL
                    AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, c.empresa_id)) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Cliente no encontrado'));
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'orden_servicio_id', os.id, 'tipo', 'servicio',
           'servicio_id', os.servicio_id, 'codigo', s.codigo,
           'descripcion', s.nombre || ' — ' || m.nombre,
           'cantidad', os.cantidad, 'precio_unitario', os.precio_unitario,
           'descuento', os.descuento, 'total', os.total,
           'afecto_igv', s.afecto_igv, 'fecha', os.fecha,
           'mascota', m.nombre) ORDER BY os.fecha), '[]'::jsonb) INTO v_serv
  FROM core.ordenes_servicio os
  JOIN core.servicios s ON s.id = os.servicio_id
  JOIN core.mascotas m ON m.id = os.mascota_id
  WHERE os.empresa_id = v_emp AND os.cliente_id = p_cliente_id
    AND os.facturado = false AND os.estado = 'completado';
  -- Nota: el filtro por os.empresa_id ya acota el resultado a la empresa; un
  -- cliente de otra empresa simplemente no tiene órdenes aquí.

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'insumo_id', iu.id, 'tipo', 'producto',
           'producto_id', iu.producto_id, 'codigo', pr.codigo,
           'descripcion', pr.nombre,
           'cantidad', iu.cantidad, 'precio_unitario', iu.precio_unitario,
           'total', round(iu.cantidad * iu.precio_unitario, 2),
           'afecto_igv', pr.afecto_igv, 'fecha', iu.fecha,
           'mascota', m.nombre) ORDER BY iu.fecha), '[]'::jsonb) INTO v_ins
  FROM core.insumos_utilizados iu
  JOIN core.productos pr ON pr.id = iu.producto_id
  LEFT JOIN core.mascotas m ON m.id = iu.mascota_id
  WHERE iu.empresa_id = v_emp AND iu.facturado = false
    AND m.cliente_id = p_cliente_id;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'servicios', v_serv, 'insumos', v_ins));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;
