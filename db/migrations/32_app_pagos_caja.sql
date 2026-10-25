-- =============================================================================
-- 32_app_pagos_caja.sql — Cobros de clientes y arqueo de caja
--
-- Un cobro se registra una vez y se aplica a uno o varios comprobantes. Si hay
-- caja abierta, además queda como movimiento de caja para el arqueo del turno.
-- =============================================================================

SET search_path = app, internal, core, public;

-- =============================================================================
-- COBROS
-- =============================================================================

CREATE OR REPLACE FUNCTION app.sp_pago_registrar(
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
  v_id        UUID;
  v_emp       UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_cliente   UUID := (p_payload->>'cliente_id')::uuid;
  v_monto     NUMERIC(14,2) := (p_payload->>'monto')::numeric;
  v_metodo    core.metodo_pago := COALESCE(NULLIF(p_payload->>'metodo','')::core.metodo_pago, 'efectivo');
  v_ref       TEXT := NULLIF(trim(p_payload->>'referencia'), '');
  v_idem      UUID := NULLIF(p_payload->>'idempotency_key','')::uuid;
  v_caja      UUID;
  v_caja_pedida UUID := NULLIF(p_payload->>'caja_id','')::uuid;
  v_aplic     JSONB := COALESCE(p_payload->'aplicaciones', '[]'::jsonb);
  v_item      JSONB;
  v_suma      NUMERIC(14,2) := 0;
  v_aplicar   NUMERIC(14,2);
  v_restante  NUMERIC(14,2);
  v_comp      RECORD;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'pagos:registrar');
  PERFORM internal.validar_payload(p_payload, ARRAY['cliente_id','monto']);

  -- Idempotencia: el mismo intento no cobra dos veces (ver sp_comprobante_emitir).
  IF v_idem IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('pago:' || v_idem::text, 0));
    SELECT id INTO v_id FROM core.pagos WHERE empresa_id = v_emp AND idempotency_key = v_idem;
    IF v_id IS NOT NULL THEN
      RETURN jsonb_build_object('ok', true, 'meta', jsonb_build_object('repetido', true),
        'data', (SELECT jsonb_build_object('id', p.id, 'monto', p.monto, 'caja_id', p.caja_id)
                   FROM core.pagos p WHERE p.id = v_id));
    END IF;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM core.clientes
                  WHERE id = v_cliente AND deleted_at IS NULL
                    AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, empresa_id)) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Cliente no encontrado','cliente_id'));
  END IF;

  IF v_monto IS NULL OR v_monto <= 0 THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR','El monto debe ser mayor a cero','monto'));
  END IF;

  -- Lo que entra al banco se concilia por el número de operación. Sin él, un
  -- Yape "registrado" no se puede cruzar con el extracto, y el mismo voucher
  -- puede cargarse dos veces sin que nadie lo note.
  IF v_metodo IN ('yape','plin','transferencia','deposito') AND v_ref IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'Indica el número de operación del ' || v_metodo::text, 'referencia'));
  END IF;

  IF v_ref IS NOT NULL AND v_metodo IN ('yape','plin','transferencia','deposito')
     AND EXISTS (SELECT 1 FROM core.pagos
                  WHERE empresa_id = v_emp AND metodo = v_metodo AND referencia = v_ref
                    AND anulado_at IS NULL) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('CONFLICT',
        format('La operación %s de %s ya está registrada en otro cobro', v_ref, v_metodo), 'referencia'));
  END IF;

  -- Caja: la indicada (de la empresa y abierta) o la abierta del cajero. Se
  -- toma con FOR SHARE: muchos cobros pueden entrar a la vez, pero el cierre
  -- (FOR UPDATE) espera a que terminen y no se le escapa ninguno del arqueo.
  IF v_caja_pedida IS NOT NULL THEN
    SELECT id INTO v_caja FROM core.cajas
     WHERE id = v_caja_pedida AND empresa_id = v_emp AND estado = 'abierta'
     FOR SHARE;
    IF v_caja IS NULL THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('BUSINESS_RULE',
          'La caja indicada no existe o ya está cerrada','caja_id'));
    END IF;
  ELSE
    SELECT id INTO v_caja FROM core.cajas
     WHERE empresa_id = v_emp AND user_apertura_id = p_user_id AND estado = 'abierta'
     LIMIT 1
     FOR SHARE;
  END IF;

  -- El efectivo SÍ exige caja abierta. Un cobro en efectivo sin caja no genera
  -- movimiento y por tanto no aparece en ningún arqueo: el billete entra al
  -- cajón y no hay nada contra qué cuadrarlo. Los medios que van al banco
  -- (tarjeta, transferencia, yape…) no la necesitan.
  IF v_metodo = 'efectivo' AND v_caja IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(
      'BUSINESS_RULE',
      'Para cobrar en efectivo necesitas una caja abierta', 'caja_id'));
  END IF;

  INSERT INTO core.pagos (
    empresa_id, cliente_id, caja_id, numero, metodo, monto, moneda,
    referencia, fecha_pago, observaciones, idempotency_key, created_by
  ) VALUES (
    v_emp, v_cliente, v_caja,
    internal.siguiente_numero(v_emp, 'PAG', 6),
    v_metodo, v_monto,
    COALESCE((p_payload->>'moneda')::core.moneda_codigo, 'PEN'),
    v_ref,
    COALESCE(NULLIF(p_payload->>'fecha_pago','')::timestamptz, now()),
    p_payload->>'observaciones', v_idem, p_user_id
  ) RETURNING id INTO v_id;

  IF jsonb_array_length(v_aplic) > 0 THEN
    -- Aplicaciones explícitas. Cada comprobante se bloquea antes de leer su
    -- saldo: dos cobros simultáneos a la misma boleta se hacen en fila, y el
    -- segundo ve el saldo que dejó el primero.
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_aplic) LOOP
      v_aplicar := (v_item->>'monto')::numeric;
      IF v_aplicar IS NULL OR v_aplicar <= 0 THEN
        RAISE EXCEPTION 'El monto aplicado debe ser mayor a cero' USING ERRCODE = 'P0001';
      END IF;

      SELECT id, saldo_pendiente, numero_completo INTO v_comp FROM core.comprobantes
       WHERE id = (v_item->>'comprobante_id')::uuid AND deleted_at IS NULL
         AND empresa_id = v_emp AND cliente_id = v_cliente
         AND anulado_at IS NULL AND tipo IN ('factura','boleta','nota_venta')
       FOR UPDATE;

      IF v_comp.id IS NULL THEN
        RAISE EXCEPTION 'Comprobante no encontrado para este cliente' USING ERRCODE = 'P0002';
      END IF;

      IF v_aplicar > v_comp.saldo_pendiente THEN
        RAISE EXCEPTION 'El monto aplicado (%) supera el saldo de % (%)',
          v_aplicar, v_comp.numero_completo, v_comp.saldo_pendiente USING ERRCODE = 'P0001';
      END IF;

      INSERT INTO core.pago_aplicaciones (pago_id, comprobante_id, monto_aplicado)
      VALUES (v_id, v_comp.id, v_aplicar);

      PERFORM internal.recalcular_saldo_comprobante(v_comp.id);
      v_suma := v_suma + v_aplicar;
    END LOOP;

    IF v_suma > v_monto THEN
      RAISE EXCEPTION 'Las aplicaciones (%) superan el monto del pago (%)', v_suma, v_monto
        USING ERRCODE = 'P0001';
    END IF;
  ELSE
    -- Sin detalle: se imputa a los comprobantes más antiguos hasta agotarlo.
    -- Solo documentos que son deuda: una nota de crédito nunca lo es.
    v_restante := v_monto;
    FOR v_comp IN
      SELECT id, saldo_pendiente FROM core.comprobantes
       WHERE empresa_id = v_emp AND cliente_id = v_cliente
         AND deleted_at IS NULL AND anulado_at IS NULL AND saldo_pendiente > 0
         AND tipo IN ('factura','boleta','nota_venta')
       ORDER BY fecha_emision, numero
       FOR UPDATE
    LOOP
      EXIT WHEN v_restante <= 0;
      v_aplicar := LEAST(v_restante, v_comp.saldo_pendiente);
      INSERT INTO core.pago_aplicaciones (pago_id, comprobante_id, monto_aplicado)
      VALUES (v_id, v_comp.id, v_aplicar);

      PERFORM internal.recalcular_saldo_comprobante(v_comp.id);
      v_restante := v_restante - v_aplicar;
    END LOOP;
  END IF;

  IF v_caja IS NOT NULL THEN
    INSERT INTO core.movimientos_caja (
      empresa_id, caja_id, tipo, metodo, concepto, monto, pago_id, created_by)
    VALUES (
      v_emp, v_caja, 'ingreso', v_metodo,
      'Cobro a cliente' || COALESCE(' · op. ' || v_ref, ''), v_monto, v_id, p_user_id);
  END IF;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'registrar_pago', 'pagos', v_id, NULL, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'id', v_id, 'monto', v_monto, 'caja_id', v_caja));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_pago_anular
--
-- El cobro se anula una sola vez (el pago queda bloqueado mientras tanto: dos
-- anulaciones simultáneas ya no generan dos egresos). El dinero sale de la
-- caja donde entró si sigue abierta; si ya se cerró, de la caja abierta de
-- quien anula, porque es ahí donde está el billete que se devuelve.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_pago_anular(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_id             UUID,
  p_motivo         TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_pago RECORD;
  v_comp UUID;
  v_caja UUID;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'pagos:anular');

  SELECT * INTO v_pago FROM core.pagos
   WHERE id = p_id
     AND internal.es_de_empresa(p_user_id, p_is_super_admin,
           internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin), empresa_id)
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Pago no encontrado'));
  END IF;

  IF v_pago.anulado_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE','El pago ya está anulado'));
  END IF;

  IF COALESCE(trim(p_motivo), '') = '' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR','Indica el motivo de la anulación','motivo'));
  END IF;

  -- ¿De qué caja sale la devolución?
  IF v_pago.caja_id IS NOT NULL THEN
    SELECT id INTO v_caja FROM core.cajas
     WHERE id = v_pago.caja_id AND estado = 'abierta' FOR SHARE;
    IF v_caja IS NULL THEN
      SELECT id INTO v_caja FROM core.cajas
       WHERE empresa_id = v_pago.empresa_id AND user_apertura_id = p_user_id
         AND estado = 'abierta'
       LIMIT 1 FOR SHARE;
    END IF;
    IF v_caja IS NULL AND v_pago.metodo = 'efectivo' THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('BUSINESS_RULE',
          'La caja de ese cobro ya se cerró. Abre tu caja para registrar la devolución del efectivo.'));
    END IF;
  END IF;

  UPDATE core.pagos
     SET anulado_at = now(),
         observaciones = COALESCE(observaciones || ' | ', '') || 'ANULADO: ' || p_motivo
   WHERE id = p_id;

  -- Los saldos de los comprobantes vuelven a subir.
  FOR v_comp IN
    SELECT c.id FROM core.comprobantes c
     WHERE c.id IN (SELECT comprobante_id FROM core.pago_aplicaciones WHERE pago_id = p_id)
     ORDER BY c.id FOR UPDATE
  LOOP
    PERFORM internal.recalcular_saldo_comprobante(v_comp);
  END LOOP;

  IF v_caja IS NOT NULL THEN
    INSERT INTO core.movimientos_caja (
      empresa_id, caja_id, tipo, metodo, concepto, monto, pago_id, created_by)
    VALUES (v_pago.empresa_id, v_caja, 'egreso', v_pago.metodo,
            'Anulación de cobro ' || COALESCE(v_pago.numero,''), v_pago.monto, p_id, p_user_id);
  END IF;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_pago.empresa_id, 'anular', 'pagos', p_id, NULL,
    jsonb_build_object('motivo', p_motivo, 'caja_devolucion', v_caja));

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'anulado', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_pagos_listar(
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
  PERFORM internal.assert_permiso(p_user_id, 'pagos:ver');

  SELECT count(*) INTO v_total
  FROM core.pagos p
  WHERE (v_global OR p.empresa_id = v_emp)
    AND (p_filtros->>'cliente_id' IS NULL OR p.cliente_id = (p_filtros->>'cliente_id')::uuid)
    AND (p_filtros->>'metodo'     IS NULL OR p.metodo::text = p_filtros->>'metodo')
    AND (p_filtros->>'desde' IS NULL OR p.fecha_pago >= (p_filtros->>'desde')::timestamptz)
    AND (p_filtros->>'hasta' IS NULL OR p.fecha_pago <  (p_filtros->>'hasta')::timestamptz);

  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) INTO v_data
  FROM (
    SELECT p.id, p.numero, p.metodo, p.monto, p.moneda, p.referencia,
           p.fecha_pago, p.anulado_at, p.observaciones,
           p.cliente_id,
           trim(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'')) AS cliente,
           trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS cajero,
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'comprobante_id', pa.comprobante_id,
                     'numero', c.numero_completo,
                     'monto_aplicado', pa.monto_aplicado)), '[]'::jsonb)
              FROM core.pago_aplicaciones pa
              JOIN core.comprobantes c ON c.id = pa.comprobante_id
             WHERE pa.pago_id = p.id) AS aplicaciones
    FROM core.pagos p
    JOIN core.clientes cl ON cl.id = p.cliente_id
    LEFT JOIN core.users u ON u.id = p.created_by
    WHERE (v_global OR p.empresa_id = v_emp)
      AND (p_filtros->>'cliente_id' IS NULL OR p.cliente_id = (p_filtros->>'cliente_id')::uuid)
      AND (p_filtros->>'metodo'     IS NULL OR p.metodo::text = p_filtros->>'metodo')
      AND (p_filtros->>'desde' IS NULL OR p.fecha_pago >= (p_filtros->>'desde')::timestamptz)
      AND (p_filtros->>'hasta' IS NULL OR p.fecha_pago <  (p_filtros->>'hasta')::timestamptz)
    ORDER BY p.fecha_pago DESC
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
-- CAJA
-- =============================================================================

CREATE OR REPLACE FUNCTION app.sp_caja_abrir(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_monto_apertura NUMERIC DEFAULT 0,
  p_observaciones  TEXT DEFAULT NULL
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
  PERFORM internal.assert_permiso(p_user_id, 'caja:operar');

  IF EXISTS (SELECT 1 FROM core.cajas
              WHERE empresa_id = v_emp AND user_apertura_id = p_user_id AND estado = 'abierta') THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('CONFLICT','Ya tienes una caja abierta. Ciérrala antes de abrir otra.'));
  END IF;

  -- La caja es del mostrador donde está el cajero. Sin esto, el arqueo de
  -- Miraflores acabaría sumado al de la sede principal.
  INSERT INTO core.cajas (
    empresa_id, sede_id, numero, user_apertura_id, monto_apertura, observaciones)
  VALUES (
    v_emp, internal.sede_efectiva(p_user_id, v_emp), 
    internal.siguiente_numero(v_emp, 'CAJA', 5), p_user_id,
    COALESCE(p_monto_apertura, 0), p_observaciones)
  RETURNING id INTO v_id;

  PERFORM internal.registrar_auditoria(p_user_id, v_emp, 'abrir', 'cajas', v_id);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_caja_movimiento(
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
  v_emp  UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_caja UUID := NULLIF(p_payload->>'caja_id','')::uuid;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'caja:operar');
  PERFORM internal.validar_payload(p_payload, ARRAY['tipo','concepto','monto']);

  IF COALESCE(trim(p_payload->>'concepto'), '') = '' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR','Indica el concepto del movimiento','concepto'));
  END IF;

  IF COALESCE((p_payload->>'monto')::numeric, 0) <= 0 THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR','El monto debe ser mayor a cero','monto'));
  END IF;

  -- Solo a una caja abierta: un movimiento en una caja cerrada cambiaría un
  -- arqueo que ya se firmó. FOR SHARE, igual que el cobro, para que el cierre
  -- espere a este movimiento en vez de dejarlo fuera.
  IF v_caja IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM core.cajas
                    WHERE id = v_caja
                      AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, empresa_id)) THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('NOT_FOUND','Caja no encontrada','caja_id'));
    END IF;
    SELECT id INTO v_caja FROM core.cajas
     WHERE id = v_caja AND estado = 'abierta' FOR SHARE;
  ELSE
    SELECT id INTO v_caja FROM core.cajas
     WHERE empresa_id = v_emp AND user_apertura_id = p_user_id AND estado = 'abierta'
     LIMIT 1 FOR SHARE;
  END IF;

  IF v_caja IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE','No hay una caja abierta para registrar el movimiento'));
  END IF;

  INSERT INTO core.movimientos_caja (
    empresa_id, caja_id, tipo, metodo, concepto, monto, created_by)
  VALUES (
    v_emp, v_caja,
    (p_payload->>'tipo')::core.tipo_movimiento_caja,
    COALESCE((p_payload->>'metodo')::core.metodo_pago, 'efectivo'),
    p_payload->>'concepto', (p_payload->>'monto')::numeric, p_user_id)
  RETURNING id INTO v_id;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'movimiento', 'cajas', v_caja, NULL, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_caja_cerrar — arqueo: calcula lo esperado y lo compara con lo contado
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_caja_cerrar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_id             UUID,
  p_monto_contado  NUMERIC,
  p_observaciones  TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_caja      RECORD;
  v_ingresos  NUMERIC(14,2);
  v_egresos   NUMERIC(14,2);
  v_efectivo  NUMERIC(14,2);
  v_tarjeta   NUMERIC(14,2);
  v_digital   NUMERIC(14,2);
  v_esperado  NUMERIC(14,2);
  v_dif       NUMERIC(14,2);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'caja:operar');

  -- FOR UPDATE: espera a que terminen los cobros que están entrando ahora
  -- (tienen la caja con FOR SHARE) y bloquea los que lleguen después, que
  -- encontrarán la caja cerrada. Así ningún cobro queda fuera del arqueo.
  SELECT * INTO v_caja FROM core.cajas
   WHERE id = p_id
     AND internal.es_de_empresa(p_user_id, p_is_super_admin,
           internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin), empresa_id)
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Caja no encontrada'));
  END IF;

  IF v_caja.estado <> 'abierta' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE','La caja ya fue cerrada'));
  END IF;

  IF p_monto_contado IS NULL OR p_monto_contado < 0 THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'Indica el efectivo contado en la caja','monto_contado'));
  END IF;

  SELECT
    COALESCE(SUM(monto) FILTER (WHERE tipo = 'ingreso'), 0),
    COALESCE(SUM(monto) FILTER (WHERE tipo = 'egreso'), 0),
    COALESCE(SUM(CASE WHEN tipo = 'ingreso' THEN monto ELSE -monto END)
             FILTER (WHERE metodo = 'efectivo'), 0),
    COALESCE(SUM(CASE WHEN tipo = 'ingreso' THEN monto ELSE -monto END)
             FILTER (WHERE metodo = 'tarjeta'), 0),
    COALESCE(SUM(CASE WHEN tipo = 'ingreso' THEN monto ELSE -monto END)
             FILTER (WHERE metodo IN ('yape','plin','transferencia','deposito')), 0)
  INTO v_ingresos, v_egresos, v_efectivo, v_tarjeta, v_digital
  FROM core.movimientos_caja WHERE caja_id = p_id;

  -- Solo el efectivo debe estar físicamente en la caja al cerrar.
  v_esperado := v_caja.monto_apertura + v_efectivo;
  v_dif      := COALESCE(p_monto_contado, 0) - v_esperado;

  -- Un descuadre sin explicación es lo que después nadie sabe reconstruir.
  IF v_dif <> 0 AND COALESCE(trim(p_observaciones), '') = '' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'El contado no coincide con lo esperado: explica la diferencia en las observaciones',
        'observaciones'));
  END IF;

  UPDATE core.cajas SET
    user_cierre_id = p_user_id,
    fecha_cierre   = now(),
    total_ingresos = v_ingresos,
    total_egresos  = v_egresos,
    total_efectivo = v_efectivo,
    total_tarjeta  = v_tarjeta,
    total_digital  = v_digital,
    monto_esperado = v_esperado,
    monto_contado  = p_monto_contado,
    diferencia     = v_dif,
    estado         = CASE WHEN v_dif = 0 THEN 'cuadrada' ELSE 'cerrada' END::core.estado_caja,
    observaciones  = COALESCE(observaciones || ' | ', '') || COALESCE(p_observaciones, '')
  WHERE id = p_id;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_caja.empresa_id, 'cerrar', 'cajas', p_id, NULL,
    jsonb_build_object('esperado', v_esperado, 'contado', p_monto_contado, 'diferencia', v_dif));

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'id', p_id, 'monto_esperado', v_esperado, 'monto_contado', p_monto_contado,
    'diferencia', v_dif, 'total_ingresos', v_ingresos, 'total_egresos', v_egresos,
    'total_efectivo', v_efectivo, 'total_tarjeta', v_tarjeta, 'total_digital', v_digital,
    'cuadrada', v_dif = 0));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_caja_actual — estado en vivo de la caja del usuario
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_caja_actual(
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
  PERFORM internal.assert_permiso(p_user_id, 'caja:ver');

  SELECT to_jsonb(x) INTO v_data FROM (
    SELECT c.id, c.numero, c.fecha_apertura, c.monto_apertura, c.estado,
           c.sede_id, (SELECT se.nombre FROM core.sedes se WHERE se.id = c.sede_id) AS sede,
           COALESCE((SELECT SUM(monto) FROM core.movimientos_caja mc
                      WHERE mc.caja_id = c.id AND mc.tipo = 'ingreso'), 0) AS ingresos,
           COALESCE((SELECT SUM(monto) FROM core.movimientos_caja mc
                      WHERE mc.caja_id = c.id AND mc.tipo = 'egreso'), 0) AS egresos,
           COALESCE((SELECT SUM(CASE WHEN tipo='ingreso' THEN monto ELSE -monto END)
                       FROM core.movimientos_caja mc
                      WHERE mc.caja_id = c.id AND mc.metodo = 'efectivo'), 0) AS efectivo,
           (SELECT count(*) FROM core.movimientos_caja mc WHERE mc.caja_id = c.id) AS movimientos,
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id', mc.id, 'tipo', mc.tipo, 'metodo', mc.metodo,
                     'concepto', mc.concepto, 'monto', mc.monto, 'fecha', mc.fecha)
                   ORDER BY mc.fecha DESC), '[]'::jsonb)
              FROM core.movimientos_caja mc WHERE mc.caja_id = c.id) AS detalle
    FROM core.cajas c
    WHERE c.empresa_id = v_emp AND c.user_apertura_id = p_user_id AND c.estado = 'abierta'
    LIMIT 1
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_cajas_listar(
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
  PERFORM internal.assert_permiso(p_user_id, 'caja:ver');

  SELECT COALESCE(jsonb_agg(x ORDER BY x.fecha_apertura DESC), '[]'::jsonb) INTO v_data
  FROM (
    SELECT c.id, c.numero, c.fecha_apertura, c.fecha_cierre, c.monto_apertura,
           c.total_ingresos, c.total_egresos, c.total_efectivo, c.total_tarjeta,
           c.total_digital, c.monto_esperado, c.monto_contado, c.diferencia,
           c.estado, c.observaciones,
           trim(ua.nombres || ' ' || COALESCE(ua.apellido_paterno,'')) AS abierta_por,
           trim(uc.nombres || ' ' || COALESCE(uc.apellido_paterno,'')) AS cerrada_por
    FROM core.cajas c
    JOIN core.users ua ON ua.id = c.user_apertura_id
    LEFT JOIN core.users uc ON uc.id = c.user_cierre_id
    WHERE (v_global OR c.empresa_id = v_emp)
      AND (p_filtros->>'estado' IS NULL OR c.estado::text = p_filtros->>'estado')
      AND (p_filtros->>'desde' IS NULL OR c.fecha_apertura >= (p_filtros->>'desde')::timestamptz)
      AND (p_filtros->>'hasta' IS NULL OR c.fecha_apertura <  (p_filtros->>'hasta')::timestamptz)
    LIMIT 200
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;
