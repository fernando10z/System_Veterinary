-- =============================================================================
-- 45_app_portal.sql — Portal del propietario
--
-- Aislamiento total del backoffice: estos SPs reciben p_cliente_id (extraído
-- del JWT type=portal) y NUNCA un user_id de staff. Todo lo que devuelven está
-- acotado a las mascotas de ese cliente.
-- =============================================================================

SET search_path = app, internal, core, public;

CREATE OR REPLACE FUNCTION app.fn_portal_mis_mascotas(p_cliente_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_data JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(x ORDER BY x.nombre), '[]'::jsonb) INTO v_data
  FROM (
    SELECT m.id, m.codigo, m.nombre, m.sexo, m.color, m.peso_kg, m.foto_url,
           m.esterilizado, m.microchip, m.estado, m.alergias,
           internal.edad_mascota(m.fecha_nacimiento, m.edad_aproximada_meses) AS edad,
           e.nombre AS especie, e.icono AS especie_icono,
           r.nombre AS raza,
           (SELECT jsonb_build_object('fecha_hora', c.fecha_hora, 'motivo', c.motivo,
                                      'estado', c.estado)
              FROM core.citas c
             WHERE c.mascota_id = m.id AND c.deleted_at IS NULL
               AND c.fecha_hora >= now() AND c.estado IN ('programada','confirmada')
             ORDER BY c.fecha_hora LIMIT 1) AS proxima_cita,
           (SELECT min(v.proximo_refuerzo) FROM core.vacunas v
             WHERE v.mascota_id = m.id AND v.proximo_refuerzo >= CURRENT_DATE) AS proxima_vacuna,
           (SELECT count(*) FROM core.vacunas v
             WHERE v.mascota_id = m.id AND v.proximo_refuerzo < CURRENT_DATE) AS vacunas_vencidas
    FROM core.mascotas m
    JOIN core.especies e ON e.id = m.especie_id
    LEFT JOIN core.razas r ON r.id = m.raza_id
    WHERE m.cliente_id = p_cliente_id AND m.deleted_at IS NULL
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_portal_mis_citas(
  p_cliente_id UUID,
  p_incluir_pasadas BOOLEAN DEFAULT true
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_data JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(x ORDER BY x.fecha_hora DESC), '[]'::jsonb) INTO v_data
  FROM (
    SELECT c.id, c.codigo, c.fecha_hora, c.duracion_min, c.motivo, c.estado,
           m.nombre AS mascota, m.foto_url AS mascota_foto,
           s.nombre AS servicio,
           trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS veterinario,
           e.nombre_comercial AS empresa, e.direccion_fiscal AS empresa_direccion,
           e.telefono AS empresa_telefono
    FROM core.citas c
    JOIN core.mascotas m ON m.id = c.mascota_id
    JOIN core.empresas e ON e.id = c.empresa_id
    LEFT JOIN core.servicios s ON s.id = c.servicio_id
    LEFT JOIN core.users u ON u.id = c.veterinario_id
    WHERE c.cliente_id = p_cliente_id AND c.deleted_at IS NULL
      AND (p_incluir_pasadas OR c.fecha_hora >= now())
    LIMIT 100
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- Historia clínica en versión propietario: sin notas internas del equipo.
CREATE OR REPLACE FUNCTION app.fn_portal_historial(
  p_cliente_id UUID,
  p_mascota_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_data JSONB;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM core.mascotas
                  WHERE id = p_mascota_id AND cliente_id = p_cliente_id AND deleted_at IS NULL) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('FORBIDDEN','Esa mascota no está asociada a tu cuenta'));
  END IF;

  SELECT jsonb_build_object(
    'eventos', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'tipo_evento', h.tipo_evento, 'fecha', h.fecha,
        'titulo', h.titulo, 'resumen', h.resumen,
        'veterinario', trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')),
        'empresa', e.nombre_comercial) ORDER BY h.fecha DESC), '[]'::jsonb)
      FROM core.historia_clinica h
      LEFT JOIN core.users u ON u.id = h.veterinario_id
      LEFT JOIN core.empresas e ON e.id = h.empresa_id
      WHERE h.mascota_id = p_mascota_id
        AND h.tipo_evento <> 'nota'),   -- las notas internas no se exponen
    'vacunas', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'nombre_vacuna', v.nombre_vacuna, 'fecha_aplicacion', v.fecha_aplicacion,
        'proximo_refuerzo', v.proximo_refuerzo, 'lote', v.lote,
        'vencida', (v.proximo_refuerzo IS NOT NULL AND v.proximo_refuerzo < CURRENT_DATE))
        ORDER BY v.fecha_aplicacion DESC), '[]'::jsonb)
      FROM core.vacunas v WHERE v.mascota_id = p_mascota_id),
    'tratamientos_activos', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'medicamento', t.medicamento, 'dosis', t.dosis, 'via', t.via,
        'frecuencia_horas', t.frecuencia_horas, 'indicaciones', t.indicaciones,
        'fecha_inicio', t.fecha_inicio, 'fecha_fin', t.fecha_fin)), '[]'::jsonb)
      FROM core.tratamientos t
      WHERE t.mascota_id = p_mascota_id AND t.estado = 'activo'),
    'curva_peso', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'fecha', c.fecha, 'peso_kg', c.peso_kg) ORDER BY c.fecha), '[]'::jsonb)
      FROM core.consultas c
      WHERE c.mascota_id = p_mascota_id AND c.peso_kg IS NOT NULL
        AND c.deleted_at IS NULL)
  ) INTO v_data;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_portal_mis_comprobantes(p_cliente_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_data JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(x ORDER BY x.fecha_emision DESC), '[]'::jsonb) INTO v_data
  FROM (
    SELECT c.id, c.tipo, c.numero_completo, c.fecha_emision, c.fecha_vencimiento,
           c.total, c.saldo_pendiente, c.estado_pago, c.moneda, c.pdf_url,
           m.nombre AS mascota, e.nombre_comercial AS empresa
    FROM core.comprobantes c
    JOIN core.empresas e ON e.id = c.empresa_id
    LEFT JOIN core.mascotas m ON m.id = c.mascota_id
    WHERE c.cliente_id = p_cliente_id AND c.deleted_at IS NULL AND c.anulado_at IS NULL
    LIMIT 100
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_portal_solicitar_cita
-- El propietario pide hora; entra como 'programada' con origen 'portal' para
-- que recepción la confirme. No se le deja elegir veterinario ni saltarse la
-- validación de solapamiento.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_portal_solicitar_cita(
  p_cliente_id UUID,
  p_payload    JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_id      UUID;
  v_mascota UUID := (p_payload->>'mascota_id')::uuid;
  v_emp     UUID;
  v_fecha   TIMESTAMPTZ := (p_payload->>'fecha_hora')::timestamptz;
  v_dur     INT;
BEGIN
  PERFORM internal.validar_payload(p_payload, ARRAY['mascota_id','fecha_hora']);

  IF NOT EXISTS (SELECT 1 FROM core.mascotas
                  WHERE id = v_mascota AND cliente_id = p_cliente_id AND deleted_at IS NULL) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('FORBIDDEN','Esa mascota no está asociada a tu cuenta'));
  END IF;

  -- La empresa NO viene del payload: es la del propietario. Así no puede pedir
  -- cita en una empresa que no es la suya aunque manipule la petición.
  SELECT empresa_id INTO v_emp FROM core.clientes WHERE id = p_cliente_id;

  IF v_emp IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Cuenta sin empresa asociada'));
  END IF;

  IF v_fecha < now() THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR','La fecha solicitada ya pasó','fecha_hora'));
  END IF;

  SELECT COALESCE(
    (SELECT s.duracion_min FROM core.servicios s WHERE s.id = NULLIF(p_payload->>'servicio_id','')::uuid),
    (SELECT e.duracion_cita_min FROM core.empresas e WHERE e.id = v_emp),
    30) INTO v_dur;

  INSERT INTO core.citas (
    empresa_id, codigo, cliente_id, mascota_id, servicio_id, fecha_hora,
    duracion_min, motivo, origen, estado)
  VALUES (
    v_emp, internal.siguiente_numero(v_emp, 'CIT', 6), p_cliente_id, v_mascota,
    NULLIF(p_payload->>'servicio_id','')::uuid, v_fecha, v_dur,
    p_payload->>'motivo', 'portal', 'programada')
  RETURNING id INTO v_id;

  INSERT INTO core.citas_historial (cita_id, accion, fecha_hora_despues, motivo)
  VALUES (v_id, 'creada', v_fecha, 'Solicitada desde el portal del propietario');

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'id', v_id, 'estado', 'programada',
    'mensaje', 'Tu solicitud fue registrada. La clínica confirmará el horario.'));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_portal_cambiar_password(
  p_cliente_id      UUID,
  p_password_actual TEXT,
  p_password_nuevo  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_hash TEXT;
BEGIN
  SELECT portal_password_hash INTO v_hash FROM core.clientes WHERE id = p_cliente_id;

  IF v_hash IS NULL OR v_hash IS DISTINCT FROM crypt(p_password_actual, v_hash) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('FORBIDDEN','La contraseña actual es incorrecta','password_actual'));
  END IF;

  IF length(p_password_nuevo) < 8 THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'La contraseña nueva debe tener al menos 8 caracteres','password_nuevo'));
  END IF;

  UPDATE core.clientes
     SET portal_password_hash = crypt(p_password_nuevo, gen_salt('bf', 10)), updated_at = now()
   WHERE id = p_cliente_id;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('updated', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;
