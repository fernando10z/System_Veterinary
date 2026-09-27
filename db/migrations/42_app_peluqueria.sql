-- =============================================================================
-- 42_app_peluqueria.sql — La peluquería como flujo propio
--
-- Se estaba tratando como "un servicio más del catálogo", y no lo es. Una
-- consulta dura veinte minutos con el propietario delante; un baño con corte
-- son cuatro horas con el animal solo, en las que la clínica responde por él.
-- Eso son dos cosas distintas y necesitan flujos distintos.
--
-- El recorrido: recibir → iniciar → (hallazgos) → terminar → entregar.
--
-- Lo que este módulo sostiene y ningún otro sostenía:
--
--   · El estado en que llegó, con foto. La discusión "mi perro no tenía esa
--     herida" la pierde siempre quien no dejó constancia.
--   · Lo que el peluquero encuentra. Es quien más toca al animal —piel entera,
--     orejas, uñas, dientes— y encuentra pulgas, bultos y otitis antes que
--     nadie. Ese hallazgo entra en la historia clínica y, si urge, le salta al
--     veterinario.
--   · El cobro. Cada servicio hecho genera su cargo por el mismo camino que
--     todo lo demás, así que no se escapa de la cuenta del día.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- app.sp_peluqueria_recibir — el animal entra
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_peluqueria_recibir(
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
  v_id      UUID;
  v_mascota UUID := NULLIF(p_payload->>'mascota_id','')::uuid;
  v_cliente UUID;
  v_estado  core.estado_mascota;
  v_item    JSONB;
  v_precio  NUMERIC(12,2);
  v_total   NUMERIC(12,2) := 0;
  v_n       INT := 0;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'peluqueria:operar');
  PERFORM internal.validar_payload(p_payload, ARRAY['mascota_id','servicios']);

  SELECT m.cliente_id, m.estado INTO v_cliente, v_estado
    FROM core.mascotas m
   WHERE m.id = v_mascota AND m.deleted_at IS NULL
     AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, m.empresa_id);
  IF v_cliente IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Paciente no encontrado'));
  END IF;
  IF v_estado = 'fallecido' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE','El paciente figura como fallecido'));
  END IF;

  -- Un animal no puede estar dos veces en la peluquería a la vez.
  IF EXISTS (SELECT 1 FROM core.peluqueria_ordenes
              WHERE mascota_id = v_mascota AND deleted_at IS NULL
                AND estado IN ('recibido','en_proceso','terminado')) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('CONFLICT',
        'Ese paciente ya está en peluquería y todavía no se ha entregado'));
  END IF;

  INSERT INTO core.peluqueria_ordenes (
    empresa_id, sede_id, codigo, mascota_id, cliente_id, cita_id, peluquero_id,
    entrega_estimada, peso_kg, condicion_pelaje, temperamento,
    observaciones_ingreso, foto_ingreso, autoriza_rapado, created_by)
  VALUES (
    v_emp,
    internal.sede_efectiva(p_user_id, v_emp, NULLIF(p_payload->>'sede_id','')::uuid),
    internal.siguiente_numero(v_emp, 'PEL', 6),
    v_mascota, v_cliente,
    NULLIF(p_payload->>'cita_id','')::uuid,
    COALESCE(NULLIF(p_payload->>'peluquero_id','')::uuid, p_user_id),
    NULLIF(p_payload->>'entrega_estimada','')::timestamptz,
    NULLIF(p_payload->>'peso_kg','')::numeric,
    p_payload->>'condicion_pelaje',
    p_payload->>'temperamento',
    p_payload->>'observaciones_ingreso',
    NULLIF(p_payload->>'foto_ingreso',''),
    COALESCE((p_payload->>'autoriza_rapado')::boolean, false),
    p_user_id)
  RETURNING id INTO v_id;

  -- Servicios pedidos. El precio se congela al recibir: si la tarifa cambia a
  -- media mañana, al propietario se le cobra lo que se le dijo en el mostrador.
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_payload->'servicios') LOOP
    SELECT COALESCE(NULLIF(v_item->>'precio_unitario','')::numeric, s.precio)
      INTO v_precio
      FROM core.servicios s
     WHERE s.id = (v_item->>'servicio_id')::uuid
       AND s.empresa_id = v_emp AND s.deleted_at IS NULL;

    IF v_precio IS NULL THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('VALIDATION_ERROR',
          'Uno de los servicios no existe en el catálogo','servicios'));
    END IF;

    INSERT INTO core.peluqueria_items (orden_id, servicio_id, cantidad, precio_unitario, total, nota)
    VALUES (v_id, (v_item->>'servicio_id')::uuid,
            COALESCE(NULLIF(v_item->>'cantidad','')::numeric, 1), v_precio,
            round(COALESCE(NULLIF(v_item->>'cantidad','')::numeric, 1) * v_precio, 2),
            v_item->>'nota')
    ON CONFLICT (orden_id, servicio_id) DO NOTHING;

    v_total := v_total + round(COALESCE(NULLIF(v_item->>'cantidad','')::numeric, 1) * v_precio, 2);
    v_n := v_n + 1;
  END LOOP;

  IF v_n = 0 THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'Indica al menos un servicio de peluquería','servicios'));
  END IF;

  UPDATE core.peluqueria_ordenes SET total = v_total WHERE id = v_id;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'recibir', 'peluqueria_ordenes', v_id, NULL, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'id', v_id, 'servicios', v_n, 'total', v_total));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_peluqueria_iniciar — empieza el trabajo
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_peluqueria_iniciar(
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
  v_o   RECORD;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'peluqueria:operar');

  SELECT * INTO v_o FROM core.peluqueria_ordenes
   WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND
     OR NOT internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, v_o.empresa_id) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Orden de peluquería no encontrada'));
  END IF;
  IF v_o.estado <> 'recibido' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        format('La orden está en estado "%s": solo se puede iniciar una recibida', v_o.estado)));
  END IF;

  UPDATE core.peluqueria_ordenes
     SET estado = 'en_proceso', hora_inicio = now(),
         peluquero_id = COALESCE(peluquero_id, p_user_id), updated_by = p_user_id
   WHERE id = p_id;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'estado', 'en_proceso'));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_peluqueria_hallazgo — lo que vio quien lo bañó
--
-- Esto es lo que hace que la peluquería valga la pena como módulo y no como
-- línea de factura: el peluquero es el primero que ve la pulga, el bulto o la
-- oreja infectada, y hasta ahora eso se quedaba en un comentario de pasillo.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_peluqueria_hallazgo(
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
  v_emp   UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_o     RECORD;
  v_hid   UUID;
  v_urge  BOOLEAN := COALESCE((p_payload->>'requiere_veterinario')::boolean, false);
  v_nom   TEXT;
  v_vet   RECORD;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'peluqueria:operar');
  PERFORM internal.validar_payload(p_payload, ARRAY['hallazgo']);

  SELECT * INTO v_o FROM core.peluqueria_ordenes
   WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND
     OR NOT internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, v_o.empresa_id) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Orden de peluquería no encontrada'));
  END IF;
  IF v_o.estado IN ('entregado','cancelado') THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'La orden ya se cerró. Un hallazgo posterior va como nota médica.'));
  END IF;

  INSERT INTO core.peluqueria_hallazgos (
    orden_id, hallazgo, zona, detalle, requiere_veterinario, created_by)
  VALUES (p_id, (p_payload->>'hallazgo')::core.hallazgo_peluqueria,
          p_payload->>'zona', p_payload->>'detalle', v_urge, p_user_id)
  RETURNING id INTO v_hid;

  SELECT m.nombre INTO v_nom FROM core.mascotas m WHERE m.id = v_o.mascota_id;

  -- Lo urgente no espera a que alguien abra la pantalla de peluquería: se le
  -- pone delante a los veterinarios de la sede.
  IF v_urge THEN
    FOR v_vet IN
      SELECT u.id FROM core.users u
       WHERE u.empresa_id = v_emp AND u.es_veterinario AND u.estado = 'activo'
         AND u.deleted_at IS NULL
         AND (u.sede_id IS NULL OR v_o.sede_id IS NULL OR u.sede_id = v_o.sede_id)
    LOOP
      INSERT INTO core.notificaciones (user_id, empresa_id, titulo, cuerpo, entidad, entidad_id)
      VALUES (v_vet.id, v_emp,
              format('Peluquería: %s en %s', p_payload->>'hallazgo', COALESCE(v_nom,'un paciente')),
              COALESCE(p_payload->>'detalle', 'Requiere que lo vea un veterinario antes de la entrega.'),
              'peluqueria_ordenes', p_id);
    END LOOP;
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'id', v_hid, 'aviso_enviado', v_urge));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_peluqueria_terminar — trabajo hecho: se cobra y se deja constancia
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_peluqueria_terminar(
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
  v_emp    UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_o      RECORD;
  v_it     RECORD;
  v_cargos INT := 0;
  v_total  NUMERIC(12,2) := 0;
  v_os     UUID;
  v_serv   TEXT;
  v_hall   TEXT;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'peluqueria:operar');

  SELECT * INTO v_o FROM core.peluqueria_ordenes
   WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND
     OR NOT internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, v_o.empresa_id) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Orden de peluquería no encontrada'));
  END IF;
  IF v_o.estado NOT IN ('recibido','en_proceso') THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        format('La orden está en estado "%s"', v_o.estado)));
  END IF;

  -- Un cargo por servicio. La clave de idempotencia es el item, no la orden:
  -- así terminar dos veces no duplica el baño ni pierde el corte de uñas.
  FOR v_it IN
    SELECT i.*, s.nombre AS servicio
      FROM core.peluqueria_items i
      JOIN core.servicios s ON s.id = i.servicio_id
     WHERE i.orden_id = p_id
  LOOP
    v_os := internal.registrar_cargo_servicio(
      v_emp, v_it.servicio_id, v_o.mascota_id, p_user_id, v_it.cantidad,
      jsonb_build_object(
        'cita_id',        v_o.cita_id,
        'veterinario_id', v_o.peluquero_id,
        'precio_unitario', v_it.precio_unitario,
        'descripcion',    v_it.servicio,
        'origen_tabla',   'peluqueria_items',
        'origen_id',      v_it.id));
    IF v_os IS NOT NULL THEN
      v_cargos := v_cargos + 1;
      SELECT total INTO v_total FROM core.ordenes_servicio WHERE id = v_os;
    END IF;
  END LOOP;

  SELECT COALESCE(SUM(os.total), 0) INTO v_total
    FROM core.ordenes_servicio os
   WHERE os.origen_tabla = 'peluqueria_items'
     AND os.origen_id IN (SELECT id FROM core.peluqueria_items WHERE orden_id = p_id)
     AND os.estado <> 'anulado';

  UPDATE core.peluqueria_ordenes
     SET estado = 'terminado', hora_fin = now(), total = v_total,
         foto_salida = COALESCE(NULLIF(p_payload->>'foto_salida',''), foto_salida),
         observaciones_salida = COALESCE(p_payload->>'observaciones_salida', observaciones_salida),
         updated_by = p_user_id
   WHERE id = p_id;

  -- La historia clínica del paciente recoge la sesión y, sobre todo, lo que se
  -- vio: dentro de un año, "en marzo ya tenía ese bulto" puede importar.
  SELECT string_agg(s.nombre, ', ' ORDER BY s.nombre) INTO v_serv
    FROM core.peluqueria_items i JOIN core.servicios s ON s.id = i.servicio_id
   WHERE i.orden_id = p_id;

  SELECT string_agg(
           h.hallazgo::text || COALESCE(' ('||h.zona||')','') ||
           COALESCE(': '||h.detalle,''), ' · ' ORDER BY h.created_at)
    INTO v_hall
    FROM core.peluqueria_hallazgos h WHERE h.orden_id = p_id;

  PERFORM internal.registrar_evento_clinico(
    v_emp, v_o.mascota_id, v_o.cliente_id, v_o.peluquero_id, 'peluqueria',
    'Sesión de peluquería: ' || COALESCE(v_serv, 'sin detalle'),
    CASE WHEN v_hall IS NULL THEN NULLIF(p_payload->>'observaciones_salida','')
         ELSE 'Hallazgos: ' || v_hall ||
              COALESCE(E'\n' || NULLIF(p_payload->>'observaciones_salida',''), '') END,
    p_id, v_o.cita_id);

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'terminar', 'peluqueria_ordenes', p_id, NULL, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'id', p_id, 'cargos', v_cargos, 'total', v_total, 'hallazgos', v_hall));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_peluqueria_entregar — se lo llevan
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_peluqueria_entregar(
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
  v_emp  UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_o    RECORD;
  v_pend INT;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'peluqueria:operar');

  SELECT * INTO v_o FROM core.peluqueria_ordenes
   WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND
     OR NOT internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, v_o.empresa_id) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Orden de peluquería no encontrada'));
  END IF;
  IF v_o.estado = 'entregado' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE','Ese paciente ya fue entregado'));
  END IF;
  IF v_o.estado <> 'terminado' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'El trabajo todavía no está terminado. Ciérralo antes de entregar.'));
  END IF;

  -- Entregar al animal con un hallazgo urgente sin que nadie lo haya mirado es
  -- perder la única oportunidad de tratarlo: el propietario ya está en la
  -- puerta. Se puede forzar, pero queda dicho.
  SELECT count(*) INTO v_pend FROM core.peluqueria_hallazgos
   WHERE orden_id = p_id AND requiere_veterinario AND atendido_at IS NULL;
  IF v_pend > 0 AND NOT COALESCE((p_payload->>'omitir_aviso')::boolean, false) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        format('Hay %s hallazgo(s) marcados para que los vea un veterinario y nadie los ha revisado. '
               'Avisa al propietario antes de entregar, o confirma la entrega igualmente.', v_pend)));
  END IF;

  UPDATE core.peluqueria_ordenes
     SET estado = 'entregado', fecha_entrega = now(),
         entregado_a = NULLIF(p_payload->>'entregado_a',''),
         documento_receptor = NULLIF(p_payload->>'documento_receptor',''),
         observaciones_salida = COALESCE(p_payload->>'observaciones_salida', observaciones_salida),
         updated_by = p_user_id
   WHERE id = p_id;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'entregar', 'peluqueria_ordenes', p_id, NULL, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'id', p_id, 'estado', 'entregado', 'hallazgos_sin_revisar', v_pend));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_peluqueria_cancelar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_peluqueria_cancelar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_id             UUID,
  p_motivo         TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_o   RECORD;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'peluqueria:operar');

  SELECT * INTO v_o FROM core.peluqueria_ordenes WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND
     OR NOT internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, v_o.empresa_id) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Orden de peluquería no encontrada'));
  END IF;
  IF v_o.estado = 'entregado' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'El paciente ya se entregó. Si hay que devolver dinero, va por nota de crédito.'));
  END IF;

  -- Si ya se había cerrado el trabajo, los cargos existen: se anulan.
  UPDATE core.ordenes_servicio SET estado = 'anulado'
   WHERE origen_tabla = 'peluqueria_items'
     AND origen_id IN (SELECT id FROM core.peluqueria_items WHERE orden_id = p_id)
     AND facturado = false AND estado <> 'anulado';

  UPDATE core.peluqueria_ordenes
     SET estado = 'cancelado', motivo_cancelacion = p_motivo, updated_by = p_user_id
   WHERE id = p_id;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'cancelar', 'peluqueria_ordenes', p_id, NULL,
    jsonb_build_object('motivo', p_motivo));

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'estado', 'cancelado'));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_peluqueria_listar — el tablero del día
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_peluqueria_listar(
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
  v_desde  DATE    := COALESCE(NULLIF(p_filtros->>'desde','')::date, CURRENT_DATE);
  v_hasta  DATE    := COALESCE(NULLIF(p_filtros->>'hasta','')::date, CURRENT_DATE);
  v_data   JSONB;
  v_resumen JSONB;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'peluqueria:ver');

  SELECT COALESCE(jsonb_agg(x ORDER BY x.fecha_ingreso), '[]'::jsonb) INTO v_data
  FROM (
    SELECT o.id, o.codigo, o.estado, o.fecha_ingreso, o.hora_inicio, o.hora_fin,
           o.entrega_estimada, o.fecha_entrega, o.total, o.autoriza_rapado,
           o.condicion_pelaje, o.temperamento, o.observaciones_ingreso,
           o.foto_ingreso, o.foto_salida, o.sede_id,
           (SELECT se.nombre FROM core.sedes se WHERE se.id = o.sede_id) AS sede,
           jsonb_build_object(
             'id', m.id, 'nombre', m.nombre, 'especie', esp.nombre,
             'raza', r.nombre, 'tamanio', m.tamanio, 'foto_url', m.foto_url) AS mascota,
           jsonb_build_object(
             'id', c.id, 'nombre', trim(c.nombres || ' ' || COALESCE(c.apellido_paterno,'')),
             'telefono', c.telefono) AS propietario,
           trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS peluquero,
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'servicio', s.nombre, 'cantidad', i.cantidad, 'total', i.total)
                   ORDER BY s.nombre), '[]'::jsonb)
              FROM core.peluqueria_items i JOIN core.servicios s ON s.id = i.servicio_id
             WHERE i.orden_id = o.id) AS servicios,
           (SELECT count(*) FROM core.peluqueria_hallazgos h
             WHERE h.orden_id = o.id) AS hallazgos,
           (SELECT count(*) FROM core.peluqueria_hallazgos h
             WHERE h.orden_id = o.id AND h.requiere_veterinario AND h.atendido_at IS NULL)
             AS hallazgos_urgentes,
           -- Se pasó de la hora prometida y todavía está dentro.
           (o.entrega_estimada IS NOT NULL AND o.entrega_estimada < now()
            AND o.estado IN ('recibido','en_proceso')) AS retrasado
    FROM core.peluqueria_ordenes o
    JOIN core.mascotas m  ON m.id = o.mascota_id
    JOIN core.clientes c  ON c.id = o.cliente_id
    LEFT JOIN core.especies esp ON esp.id = m.especie_id
    LEFT JOIN core.razas r      ON r.id = m.raza_id
    LEFT JOIN core.users u      ON u.id = o.peluquero_id
    WHERE o.deleted_at IS NULL
      AND (v_global OR o.empresa_id = v_emp)
      AND o.fecha_ingreso::date BETWEEN v_desde AND v_hasta
      AND (p_filtros->>'estado'  IS NULL OR o.estado::text = p_filtros->>'estado')
      AND (p_filtros->>'sede_id' IS NULL OR o.sede_id = (p_filtros->>'sede_id')::uuid)
      AND (p_filtros->>'mascota_id' IS NULL OR o.mascota_id = (p_filtros->>'mascota_id')::uuid)
  ) x;

  SELECT jsonb_build_object(
    'recibidos',  count(*) FILTER (WHERE o.estado = 'recibido'),
    'en_proceso', count(*) FILTER (WHERE o.estado = 'en_proceso'),
    'terminados', count(*) FILTER (WHERE o.estado = 'terminado'),
    'entregados', count(*) FILTER (WHERE o.estado = 'entregado'),
    'facturable', COALESCE(SUM(o.total) FILTER (WHERE o.estado IN ('terminado','entregado')), 0))
  INTO v_resumen
  FROM core.peluqueria_ordenes o
  WHERE o.deleted_at IS NULL AND (v_global OR o.empresa_id = v_emp)
    AND o.fecha_ingreso::date BETWEEN v_desde AND v_hasta
    AND (p_filtros->>'sede_id' IS NULL OR o.sede_id = (p_filtros->>'sede_id')::uuid);

  RETURN jsonb_build_object('ok', true, 'data', v_data, 'meta', v_resumen);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_peluqueria_obtener — la ficha completa
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_peluqueria_obtener(
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
  v_emp  UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_data JSONB;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'peluqueria:ver');

  SELECT to_jsonb(x) INTO v_data FROM (
    SELECT o.*,
           (SELECT se.nombre FROM core.sedes se WHERE se.id = o.sede_id) AS sede,
           jsonb_build_object(
             'id', m.id, 'nombre', m.nombre, 'especie', esp.nombre, 'raza', r.nombre,
             'sexo', m.sexo, 'tamanio', m.tamanio, 'foto_url', m.foto_url,
             'alergias', m.alergias) AS mascota,
           jsonb_build_object(
             'id', c.id, 'nombre', trim(c.nombres || ' ' || COALESCE(c.apellido_paterno,'')),
             'telefono', c.telefono, 'correo', c.correo) AS propietario,
           trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS peluquero,
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id', i.id, 'servicio_id', i.servicio_id, 'servicio', s.nombre,
                     'cantidad', i.cantidad, 'precio_unitario', i.precio_unitario,
                     'total', i.total, 'nota', i.nota) ORDER BY s.nombre), '[]'::jsonb)
              FROM core.peluqueria_items i JOIN core.servicios s ON s.id = i.servicio_id
             WHERE i.orden_id = o.id) AS servicios,
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id', h.id, 'hallazgo', h.hallazgo, 'zona', h.zona,
                     'detalle', h.detalle, 'requiere_veterinario', h.requiere_veterinario,
                     'atendido_at', h.atendido_at, 'fecha', h.created_at)
                   ORDER BY h.created_at), '[]'::jsonb)
              FROM core.peluqueria_hallazgos h WHERE h.orden_id = o.id) AS hallazgos
    FROM core.peluqueria_ordenes o
    JOIN core.mascotas m ON m.id = o.mascota_id
    JOIN core.clientes c ON c.id = o.cliente_id
    LEFT JOIN core.especies esp ON esp.id = m.especie_id
    LEFT JOIN core.razas r      ON r.id = m.raza_id
    LEFT JOIN core.users u      ON u.id = o.peluquero_id
    WHERE o.id = p_id AND o.deleted_at IS NULL
      AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, o.empresa_id)
  ) x;

  IF v_data IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Orden de peluquería no encontrada'));
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_peluqueria_hallazgo_atender — el veterinario lo dio por visto
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_peluqueria_hallazgo_atender(
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
  v_ok  BOOLEAN;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clinico:registrar');

  SELECT true INTO v_ok
    FROM core.peluqueria_hallazgos h
    JOIN core.peluqueria_ordenes o ON o.id = h.orden_id
   WHERE h.id = p_id
     AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, o.empresa_id);
  IF v_ok IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Hallazgo no encontrado'));
  END IF;

  UPDATE core.peluqueria_hallazgos
     SET atendido_at = now(), atendido_por = p_user_id
   WHERE id = p_id AND atendido_at IS NULL;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

COMMENT ON FUNCTION app.fn_peluqueria_listar IS
  'Tablero de peluquería: quién está dentro, en qué estado y qué se le encontró.';
