-- =============================================================================
-- 31_app_facturacion.sql — Comprobantes de venta (factura, boleta, nota de venta)
--
-- El comprobante se arma desde lo pendiente de facturar del cliente: órdenes de
-- servicio e insumos consumidos. Emitir marca esos ítems como facturados, para
-- que no se cobren dos veces.
-- =============================================================================

SET search_path = app, internal, core, public;

CREATE OR REPLACE FUNCTION app.fn_comprobantes_listar(
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
  v_totales JSONB;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'facturacion:ver');

  SELECT count(*) INTO v_total
  FROM core.comprobantes c
  JOIN core.clientes cl ON cl.id = c.cliente_id
  WHERE c.deleted_at IS NULL AND (v_global OR c.empresa_id = v_emp)
    AND (p_filtros->>'tipo'        IS NULL OR c.tipo::text = p_filtros->>'tipo')
    AND (p_filtros->>'estado'      IS NULL OR c.estado::text = p_filtros->>'estado')
    AND (p_filtros->>'estado_pago' IS NULL OR c.estado_pago::text = p_filtros->>'estado_pago')
    AND (p_filtros->>'cliente_id'  IS NULL OR c.cliente_id = (p_filtros->>'cliente_id')::uuid)
    AND (p_filtros->>'desde' IS NULL OR c.fecha_emision >= (p_filtros->>'desde')::timestamptz)
    AND (p_filtros->>'hasta' IS NULL OR c.fecha_emision <  (p_filtros->>'hasta')::timestamptz)
    AND (v_buscar IS NULL OR v_buscar = '' OR
         c.numero_completo LIKE '%' || upper(v_raw) || '%' OR
         internal.normalizar(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'')) LIKE '%' || v_buscar || '%' OR
         cl.numero_documento LIKE '%' || v_raw || '%');

  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) INTO v_data
  FROM (
    SELECT c.id, c.tipo, c.serie, c.numero, c.numero_completo,
           c.fecha_emision, c.fecha_vencimiento, c.moneda,
           c.subtotal, c.descuento_global, c.igv, c.total, c.saldo_pendiente,
           c.estado, c.estado_pago, c.sunat_codigo, c.sunat_mensaje,
           c.pdf_url, c.xml_url, c.anulado_at, c.observaciones,
           c.cliente_id,
           trim(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'') || ' ' ||
                COALESCE(cl.apellido_materno,'')) AS cliente,
           COALESCE(cl.razon_social, trim(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,''))) AS cliente_facturacion,
           cl.numero_documento AS cliente_documento, cl.tipo_documento AS cliente_tipo_doc,
           m.nombre AS mascota,
           (SELECT count(*) FROM core.comprobante_items i WHERE i.comprobante_id = c.id) AS items
    FROM core.comprobantes c
    JOIN core.clientes cl ON cl.id = c.cliente_id
    LEFT JOIN core.mascotas m ON m.id = c.mascota_id
    WHERE c.deleted_at IS NULL AND (v_global OR c.empresa_id = v_emp)
      AND (p_filtros->>'tipo'        IS NULL OR c.tipo::text = p_filtros->>'tipo')
      AND (p_filtros->>'estado'      IS NULL OR c.estado::text = p_filtros->>'estado')
      AND (p_filtros->>'estado_pago' IS NULL OR c.estado_pago::text = p_filtros->>'estado_pago')
      AND (p_filtros->>'cliente_id'  IS NULL OR c.cliente_id = (p_filtros->>'cliente_id')::uuid)
      AND (p_filtros->>'desde' IS NULL OR c.fecha_emision >= (p_filtros->>'desde')::timestamptz)
      AND (p_filtros->>'hasta' IS NULL OR c.fecha_emision <  (p_filtros->>'hasta')::timestamptz)
      AND (v_buscar IS NULL OR v_buscar = '' OR
           c.numero_completo LIKE '%' || upper(v_raw) || '%' OR
           internal.normalizar(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'')) LIKE '%' || v_buscar || '%' OR
           cl.numero_documento LIKE '%' || v_raw || '%')
    ORDER BY c.fecha_emision DESC
    LIMIT v_size OFFSET (v_page - 1) * v_size
  ) x;

  -- Totales del filtro completo (no solo de la página) para las tarjetas KPI
  SELECT jsonb_build_object(
    'facturado', COALESCE(SUM(c.total) FILTER (WHERE c.anulado_at IS NULL), 0),
    'cobrado',   COALESCE(SUM(c.total - c.saldo_pendiente) FILTER (WHERE c.anulado_at IS NULL), 0),
    'pendiente', COALESCE(SUM(c.saldo_pendiente) FILTER (WHERE c.anulado_at IS NULL), 0)
  ) INTO v_totales
  FROM core.comprobantes c
  WHERE c.deleted_at IS NULL AND (v_global OR c.empresa_id = v_emp)
    AND (p_filtros->>'desde' IS NULL OR c.fecha_emision >= (p_filtros->>'desde')::timestamptz)
    AND (p_filtros->>'hasta' IS NULL OR c.fecha_emision <  (p_filtros->>'hasta')::timestamptz);

  RETURN jsonb_build_object('ok', true, 'data', v_data, 'meta', jsonb_build_object(
    'total', v_total, 'page', v_page, 'pageSize', v_size,
    'pages', GREATEST(CEIL(v_total::numeric / v_size)::int, 1),
    'totales', v_totales));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_comprobante_obtener(
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
  PERFORM internal.assert_permiso(p_user_id, 'facturacion:ver');

  SELECT to_jsonb(x) INTO v_data FROM (
    SELECT c.*,
           jsonb_build_object(
             'id', cl.id, 'nombre_completo', trim(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'') || ' ' ||
                                                  COALESCE(cl.apellido_materno,'')),
             'razon_social', cl.razon_social,
             'tipo_documento', cl.tipo_documento, 'numero_documento', cl.numero_documento,
             'direccion', cl.direccion, 'telefono', cl.telefono, 'correo', cl.correo
           ) AS cliente,
           jsonb_build_object(
             'ruc', e.ruc, 'razon_social', e.razon_social,
             'nombre_comercial', e.nombre_comercial, 'direccion', e.direccion_fiscal,
             'telefono', e.telefono, 'correo', e.correo, 'logo_url', e.logo_url
           ) AS emisor,
           m.nombre AS mascota,
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id', i.id, 'tipo_item', i.tipo_item, 'codigo', i.codigo,
                     'descripcion', i.descripcion, 'cantidad', i.cantidad,
                     'precio_unitario', i.precio_unitario, 'descuento', i.descuento,
                     'afecto_igv', i.afecto_igv, 'tipo_afectacion_igv', i.tipo_afectacion_igv,
                     'unidad_medida', i.unidad_medida, 'subtotal', i.subtotal,
                     'igv', i.igv, 'total', i.total) ORDER BY i.orden), '[]'::jsonb)
              FROM core.comprobante_items i WHERE i.comprobante_id = c.id) AS items,
           -- Últimos intentos contra el PSE: cuando SUNAT rechaza, el mensaje
           -- del proveedor es lo único que dice por qué.
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'intento', l.intento, 'operacion', l.operacion, 'exito', l.exito,
                     'mensaje', l.mensaje, 'fecha', l.created_at)
                     ORDER BY l.created_at DESC), '[]'::jsonb)
              FROM (SELECT * FROM core.comprobante_pse_log
                     WHERE comprobante_id = c.id ORDER BY created_at DESC LIMIT 5) l) AS pse_log,
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id', pg.id, 'numero', pg.numero, 'metodo', pg.metodo,
                     'monto_aplicado', pa.monto_aplicado, 'fecha_pago', pg.fecha_pago,
                     'referencia', pg.referencia) ORDER BY pg.fecha_pago), '[]'::jsonb)
              FROM core.pago_aplicaciones pa
              JOIN core.pagos pg ON pg.id = pa.pago_id
             WHERE pa.comprobante_id = c.id AND pg.anulado_at IS NULL) AS pagos,
           -- El documento que esta nota corrige, y las notas que corrigen a este.
           (SELECT jsonb_build_object('id', r.id, 'numero_completo', r.numero_completo,
                                      'tipo', r.tipo, 'total', r.total)
              FROM core.comprobantes r WHERE r.id = c.documento_ref_id) AS documento_ref,
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id', nc.id, 'numero_completo', nc.numero_completo,
                     'total', nc.total, 'motivo', nc.motivo_nota,
                     'fecha_emision', nc.fecha_emision) ORDER BY nc.fecha_emision), '[]'::jsonb)
              FROM core.comprobantes nc
             WHERE nc.documento_ref_id = c.id AND nc.deleted_at IS NULL) AS notas_credito
    FROM core.comprobantes c
    JOIN core.clientes cl ON cl.id = c.cliente_id
    JOIN core.empresas e  ON e.id = c.empresa_id
    LEFT JOIN core.mascotas m ON m.id = c.mascota_id
    WHERE c.id = p_id AND c.deleted_at IS NULL
      AND (v_global OR c.empresa_id = v_emp)
  ) x;

  IF v_data IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Comprobante no encontrado'));
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_comprobante_emitir
-- Ítems explícitos o, si no vienen, todo lo pendiente de facturar del cliente.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_comprobante_emitir(
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
  v_tipo     core.tipo_comprobante := COALESCE((p_payload->>'tipo')::core.tipo_comprobante, 'boleta');
  v_cliente  UUID := (p_payload->>'cliente_id')::uuid;
  v_idem     UUID := NULLIF(p_payload->>'idempotency_key','')::uuid;
  v_sede     UUID;
  v_serie    TEXT;
  v_numero   INT;
  v_tasa     NUMERIC(5,4);
  v_items    JSONB := COALESCE(p_payload->'items', '[]'::jsonb);
  v_prorrateados JSONB := '[]'::jsonb;
  v_item     JSONB;
  v_orden    INT := 0;
  v_n        INT;
  v_base     NUMERIC(14,2);
  v_bruto    NUMERIC(14,2) := 0;
  v_dto_glob NUMERIC(14,2) := COALESCE(NULLIF(p_payload->>'descuento_global','')::numeric, 0);
  v_dto_item NUMERIC(14,2);
  v_asignado NUMERIC(14,2) := 0;
  v_igv_item NUMERIC(14,2);
  v_fecha    TIMESTAMPTZ := COALESCE(NULLIF(p_payload->>'fecha_emision','')::timestamptz, now());
  v_filas    INT;
  v_total    NUMERIC(14,2);
  v_cli      RECORD;
  v_electronico BOOLEAN;
  v_estado   core.estado_comprobante;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'facturacion:emitir');
  PERFORM internal.validar_payload(p_payload, ARRAY['cliente_id']);

  -- Idempotencia: el mismo intento (doble clic, reintento tras un timeout)
  -- devuelve el comprobante que ya se emitió en vez de numerar otro. El candado
  -- cubre el caso de las dos peticiones llegando a la vez.
  IF v_idem IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('emitir:' || v_idem::text, 0));
    SELECT id INTO v_id FROM core.comprobantes
     WHERE empresa_id = v_emp AND idempotency_key = v_idem;
    IF v_id IS NOT NULL THEN
      RETURN jsonb_build_object('ok', true, 'meta', jsonb_build_object('repetido', true),
        'data', (SELECT jsonb_build_object(
          'id', c.id, 'numero_completo', c.numero_completo, 'tipo', c.tipo,
          'subtotal', c.subtotal, 'igv', c.igv, 'total', c.total,
          'saldo_pendiente', c.saldo_pendiente)
        FROM core.comprobantes c WHERE c.id = v_id));
    END IF;
  END IF;

  -- El cliente se bloquea durante la emisión. Es lo que hace que dos cajeros
  -- que pulsan "Emitir" a la vez para el mismo propietario lo hagan en fila: el
  -- segundo ya encuentra lo pendiente marcado como facturado y no vuelve a
  -- cobrar la misma consulta en otra boleta.
  SELECT * INTO v_cli FROM core.clientes
   WHERE id = v_cliente AND deleted_at IS NULL
     AND (internal.es_acceso_global(p_user_id, p_is_super_admin) OR empresa_id = v_emp)
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Cliente no encontrado','cliente_id'));
  END IF;

  -- Una factura exige RUC: si el cliente no lo tiene, corresponde boleta.
  IF v_tipo = 'factura' AND v_cli.tipo_documento <> 'RUC' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'Para emitir factura el cliente debe tener RUC. Usa boleta o actualiza sus datos.','tipo'));
  END IF;

  IF v_tipo NOT IN ('factura','boleta','nota_venta') THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'Las notas de crédito se emiten desde el comprobante que corrigen','tipo'));
  END IF;

  -- Serie: la que pide el mostrador → la del local donde se emite → la de la
  -- empresa. Cada local es un establecimiento ante SUNAT y numera por su cuenta.
  v_sede := internal.sede_efectiva(p_user_id, v_emp, NULLIF(p_payload->>'sede_id','')::uuid);

  SELECT e.igv_tasa,
         CASE v_tipo
           WHEN 'factura' THEN COALESCE(NULLIF(s.serie_factura,''), e.serie_factura_default, 'F001')
           WHEN 'boleta'  THEN COALESCE(NULLIF(s.serie_boleta,''),  e.serie_boleta_default,  'B001')
           ELSE COALESCE(e.serie_nota_venta_default, 'NV01')
         END,
         e.emite_electronico
    INTO v_tasa, v_serie, v_electronico
    FROM core.empresas e
    LEFT JOIN core.sedes s ON s.id = v_sede
   WHERE e.id = v_emp;

  v_tasa  := COALESCE(v_tasa, 0.18);
  v_serie := upper(COALESCE(NULLIF(trim(p_payload->>'serie'),''), v_serie));

  -- SUNAT valida la serie contra el tipo: F para factura, B para boleta, cuatro
  -- caracteres. Una boleta con serie F sale numerada y vuelve rechazada.
  IF (v_tipo = 'factura' AND v_serie !~ '^F[A-Z0-9]{3}$')
     OR (v_tipo = 'boleta' AND v_serie !~ '^B[A-Z0-9]{3}$') THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        format('La serie %s no es válida para %s (debe empezar con %s y tener 4 caracteres)',
               v_serie, v_tipo, CASE v_tipo WHEN 'factura' THEN 'F' ELSE 'B' END), 'serie'));
  END IF;

  -- La fecha de emisión no se inventa: ni futura, ni más antigua de lo que
  -- SUNAT acepta para un comprobante electrónico (3 días calendario).
  IF v_fecha > now() + INTERVAL '5 minutes' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'La fecha de emisión no puede ser futura','fecha_emision'));
  END IF;
  IF COALESCE(v_electronico, false) AND v_tipo IN ('factura','boleta')
     AND (v_fecha AT TIME ZONE 'America/Lima')::date
         < (now() AT TIME ZONE 'America/Lima')::date - 3 THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'SUNAT solo acepta comprobantes electrónicos con hasta 3 días de antigüedad','fecha_emision'));
  END IF;

  -- Si no vienen ítems, se toma todo lo pendiente del cliente en esta empresa,
  -- con el mismo criterio que muestra fn_pendiente_facturar.
  IF jsonb_array_length(v_items) = 0 THEN
    SELECT COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
         'tipo_item', 'servicio', 'orden_servicio_id', os.id, 'servicio_id', os.servicio_id,
         'codigo', s.codigo, 'descripcion', s.nombre || ' — ' || m.nombre,
         'cantidad', os.cantidad, 'precio_unitario', os.precio_unitario,
         'descuento', os.descuento, 'afecto_igv', s.afecto_igv) ORDER BY os.fecha)
         FROM core.ordenes_servicio os
         JOIN core.servicios s ON s.id = os.servicio_id
         JOIN core.mascotas m ON m.id = os.mascota_id
        WHERE os.empresa_id = v_emp AND os.cliente_id = v_cliente
          AND os.facturado = false AND os.estado = 'completado'), '[]'::jsonb)
      ||
      COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
         'tipo_item', 'producto', 'insumo_id', iu.id, 'producto_id', iu.producto_id,
         'codigo', pr.codigo, 'descripcion', pr.nombre,
         'cantidad', iu.cantidad, 'precio_unitario', iu.precio_unitario,
         'descuento', 0, 'afecto_igv', pr.afecto_igv) ORDER BY iu.fecha)
         FROM core.insumos_utilizados iu
         JOIN core.productos pr ON pr.id = iu.producto_id
         JOIN core.mascotas m
           ON m.id = COALESCE(iu.mascota_id,
                (SELECT c.mascota_id  FROM core.consultas c          WHERE c.id  = iu.consulta_id),
                (SELECT ci.mascota_id FROM core.cirugias ci          WHERE ci.id = iu.cirugia_id),
                (SELECT h.mascota_id  FROM core.hospitalizaciones h  WHERE h.id  = iu.hospitalizacion_id))
        WHERE iu.empresa_id = v_emp AND iu.facturado = false
          AND m.cliente_id = v_cliente), '[]'::jsonb)
    INTO v_items;
  END IF;

  v_n := jsonb_array_length(v_items);
  IF v_n = 0 THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'No hay servicios ni productos pendientes de facturar para este cliente','items'));
  END IF;

  -- Validación de cada línea y base bruta para prorratear el descuento global.
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_items) LOOP
    IF COALESCE((v_item->>'cantidad')::numeric, 0) <= 0 THEN
      RAISE EXCEPTION 'La cantidad de "%" debe ser mayor a cero', v_item->>'descripcion'
        USING ERRCODE = '22023';
    END IF;
    IF COALESCE((v_item->>'precio_unitario')::numeric, -1) < 0 THEN
      RAISE EXCEPTION 'El precio de "%" no puede ser negativo', v_item->>'descripcion'
        USING ERRCODE = '22023';
    END IF;
    v_base := round((v_item->>'cantidad')::numeric * (v_item->>'precio_unitario')::numeric, 2);
    IF COALESCE((v_item->>'descuento')::numeric, 0) < 0
       OR COALESCE((v_item->>'descuento')::numeric, 0) > v_base THEN
      RAISE EXCEPTION 'El descuento de "%" no puede superar su importe', v_item->>'descripcion'
        USING ERRCODE = '22023';
    END IF;
    v_bruto := v_bruto + v_base - COALESCE((v_item->>'descuento')::numeric, 0);
  END LOOP;

  IF v_dto_glob < 0 OR v_dto_glob > v_bruto THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'El descuento global no puede superar el total','descuento_global'));
  END IF;

  -- El descuento global se reparte entre las líneas en proporción a su importe
  -- (la última absorbe el redondeo). Así cada línea lleva su base e IGV ya
  -- descontados y la cabecera, que es su suma, cuadra: total = base + IGV. Un
  -- descuento restado solo al total dejaba el XML descuadrado ante SUNAT.
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_items) LOOP
    v_orden := v_orden + 1;
    v_base := round((v_item->>'cantidad')::numeric * (v_item->>'precio_unitario')::numeric, 2)
              - COALESCE((v_item->>'descuento')::numeric, 0);
    IF v_dto_glob = 0 OR v_bruto = 0 THEN
      v_dto_item := 0;
    ELSIF v_orden = v_n THEN
      v_dto_item := v_dto_glob - v_asignado;
    ELSE
      v_dto_item := LEAST(round(v_dto_glob * v_base / v_bruto, 2), v_base);
    END IF;
    v_asignado := v_asignado + v_dto_item;
    v_prorrateados := v_prorrateados || jsonb_build_array(
      v_item || jsonb_build_object(
        'descuento', COALESCE((v_item->>'descuento')::numeric, 0) + v_dto_item));
  END LOOP;
  v_items := v_prorrateados;

  -- Un comprobante electrónico en cero no tiene nada que declarar: lo que el
  -- plan cubre entero se documenta con una nota de venta.
  IF v_tipo IN ('factura','boleta') AND v_bruto - v_dto_glob <= 0 THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'El total es cero (lo cubre el plan o el descuento). Emite una nota de venta para dejar constancia.',
        'tipo'));
  END IF;

  -- Una factura o boleta de una empresa que emite electrónicamente nace
  -- pendiente de envío: está numerada y es cobrable, pero SUNAT todavía no la
  -- vio. La nota de venta es interna y no sale nunca.
  v_estado := CASE
    WHEN COALESCE(v_electronico, false) AND v_tipo IN ('factura','boleta')
    THEN 'pendiente_envio'::core.estado_comprobante
    ELSE 'emitido'::core.estado_comprobante END;

  v_numero := internal.siguiente_numero_documento(v_emp, v_tipo::text, v_serie);

  INSERT INTO core.comprobantes (
    empresa_id, sede_id, tipo, serie, numero, cliente_id, mascota_id, cita_id, consulta_id,
    caja_id, fecha_emision, fecha_vencimiento, moneda, descuento_global,
    estado, observaciones, idempotency_key, created_by
  ) VALUES (
    v_emp, v_sede, v_tipo, v_serie, v_numero, v_cliente,
    (SELECT id FROM core.mascotas
      WHERE id = NULLIF(p_payload->>'mascota_id','')::uuid AND cliente_id = v_cliente),
    (SELECT id FROM core.citas
      WHERE id = NULLIF(p_payload->>'cita_id','')::uuid AND empresa_id = v_emp),
    (SELECT id FROM core.consultas
      WHERE id = NULLIF(p_payload->>'consulta_id','')::uuid AND empresa_id = v_emp),
    (SELECT id FROM core.cajas
      WHERE id = NULLIF(p_payload->>'caja_id','')::uuid AND empresa_id = v_emp),
    v_fecha,
    COALESCE(NULLIF(p_payload->>'fecha_vencimiento','')::date,
             CURRENT_DATE + COALESCE(v_cli.dias_credito, 0)),
    COALESCE((p_payload->>'moneda')::core.moneda_codigo, 'PEN'),
    v_dto_glob,
    v_estado, p_payload->>'observaciones', v_idem, p_user_id
  ) RETURNING id INTO v_id;

  v_orden := 0;
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_items) LOOP
    v_orden := v_orden + 1;
    v_base := round(
      (v_item->>'cantidad')::numeric * (v_item->>'precio_unitario')::numeric
      - COALESCE((v_item->>'descuento')::numeric, 0), 2);

    -- El precio de lista ya incluye IGV: se desagrega para el comprobante.
    IF COALESCE((v_item->>'afecto_igv')::boolean, true) THEN
      v_igv_item := round(v_base - (v_base / (1 + v_tasa)), 2);
    ELSE
      v_igv_item := 0;
    END IF;

    IF NULLIF(v_item->>'servicio_id','') IS NOT NULL AND NOT EXISTS (
         SELECT 1 FROM core.servicios
          WHERE id = (v_item->>'servicio_id')::uuid AND empresa_id = v_emp) THEN
      RAISE EXCEPTION 'Servicio no encontrado' USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO core.comprobante_items (
      comprobante_id, tipo_item, servicio_id, producto_id, orden_servicio_id,
      insumo_id, codigo, descripcion, cantidad, precio_unitario, descuento,
      afecto_igv, tipo_afectacion_igv, unidad_medida, subtotal, igv, total, orden
    ) VALUES (
      v_id,
      -- El tipo se deduce del origen antes que de lo que mande el cliente: un
      -- ítem con producto es producto aunque el payload diga otra cosa.
      COALESCE(
        NULLIF(v_item->>'tipo_item','')::core.tipo_item_comprobante,
        CASE WHEN NULLIF(v_item->>'producto_id','') IS NOT NULL
                  OR NULLIF(v_item->>'insumo_id','') IS NOT NULL THEN 'producto'
             WHEN NULLIF(v_item->>'servicio_id','') IS NOT NULL THEN 'servicio'
             ELSE 'otro' END::core.tipo_item_comprobante),
      NULLIF(v_item->>'servicio_id','')::uuid,
      NULLIF(v_item->>'producto_id','')::uuid,
      NULLIF(v_item->>'orden_servicio_id','')::uuid,
      NULLIF(v_item->>'insumo_id','')::uuid,
      v_item->>'codigo', v_item->>'descripcion',
      (v_item->>'cantidad')::numeric, (v_item->>'precio_unitario')::numeric,
      COALESCE((v_item->>'descuento')::numeric, 0),
      COALESCE((v_item->>'afecto_igv')::boolean, true),
      -- Catálogo SUNAT 07: 10 gravado, 20 exonerado. Un servicio veterinario
      -- exonerado (casos de campañas) no puede declarar base gravada.
      CASE WHEN COALESCE((v_item->>'afecto_igv')::boolean, true) THEN '10' ELSE '20' END,
      -- Catálogo SUNAT 03: un producto se mide en unidades (NIU); un servicio
      -- no tiene unidad física y va como ZZ.
      COALESCE(NULLIF(v_item->>'unidad_medida',''),
               CASE WHEN NULLIF(v_item->>'producto_id','') IS NOT NULL
                         OR NULLIF(v_item->>'insumo_id','') IS NOT NULL
                    THEN 'NIU' ELSE 'ZZ' END),
      v_base - v_igv_item, v_igv_item, v_base, v_orden);

    -- Marcar el origen como facturado para que no reaparezca en pendientes.
    --
    -- La condición `facturado = false` y el conteo de filas son la segunda
    -- línea de defensa: si el origen ya se facturó (otra ventana, otro cajero)
    -- o es de otra empresa, la emisión entera se deshace en vez de cobrar lo
    -- mismo dos veces.
    IF NULLIF(v_item->>'orden_servicio_id','') IS NOT NULL THEN
      UPDATE core.ordenes_servicio
         SET facturado = true, comprobante_id = v_id, updated_at = now()
       WHERE id = (v_item->>'orden_servicio_id')::uuid
         AND empresa_id = v_emp AND cliente_id = v_cliente
         AND facturado = false AND estado = 'completado';
      GET DIAGNOSTICS v_filas = ROW_COUNT;
      IF v_filas = 0 THEN
        RAISE EXCEPTION '"%" ya fue facturado o no corresponde a este cliente',
          v_item->>'descripcion' USING ERRCODE = 'P0001';
      END IF;
    END IF;

    IF NULLIF(v_item->>'insumo_id','') IS NOT NULL THEN
      UPDATE core.insumos_utilizados SET facturado = true
       WHERE id = (v_item->>'insumo_id')::uuid
         AND empresa_id = v_emp AND facturado = false;
      GET DIAGNOSTICS v_filas = ROW_COUNT;
      IF v_filas = 0 THEN
        RAISE EXCEPTION '"%" ya fue facturado o no corresponde a esta clínica',
          v_item->>'descripcion' USING ERRCODE = 'P0001';
      END IF;
    END IF;

    -- Venta de mostrador: el producto sale del almacén aquí. Si viene de un
    -- insumo, el stock ya se descontó en la atención y volver a moverlo dejaría
    -- el kardex con el doble de salidas.
    IF NULLIF(v_item->>'insumo_id','') IS NULL
       AND NULLIF(v_item->>'producto_id','') IS NOT NULL THEN
      PERFORM internal.mover_stock(
        v_emp, (v_item->>'producto_id')::uuid, 'salida', 'venta',
        (v_item->>'cantidad')::numeric, p_user_id, NULL,
        jsonb_build_object('cliente_id', v_cliente, 'comprobante_id', v_id,
                           'observaciones', 'Venta ' || v_serie || '-' || v_numero));
    END IF;
  END LOOP;

  -- El trigger de ítems ya recalculó la cabecera y el saldo.
  SELECT total INTO v_total FROM core.comprobantes WHERE id = v_id;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'emitir', 'comprobantes', v_id, NULL,
    jsonb_build_object('tipo', v_tipo, 'serie', v_serie, 'numero', v_numero, 'total', v_total));

  RETURN jsonb_build_object('ok', true, 'data', (
    SELECT jsonb_build_object(
      'id', c.id, 'numero_completo', c.numero_completo, 'tipo', c.tipo,
      'subtotal', c.subtotal, 'igv', c.igv, 'total', c.total,
      'saldo_pendiente', c.saldo_pendiente)
    FROM core.comprobantes c WHERE c.id = v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- internal.revertir_comprobante
--
-- Lo que pasa cuando un comprobante deja de valer, por anulación interna o por
-- comunicación de baja aceptada: se marca anulado, lo que cobraba vuelve a
-- estar pendiente y la venta de mostrador regresa al almacén. Una sola función
-- para que las dos puertas hagan exactamente lo mismo.
--
-- Quien llama ya bloqueó el comprobante y validó que se puede revertir.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.revertir_comprobante(
  p_id      UUID,
  p_user_id UUID,
  p_motivo  TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
DECLARE
  v_c    RECORD;
  v_item RECORD;
BEGIN
  SELECT * INTO v_c FROM core.comprobantes WHERE id = p_id;

  UPDATE core.comprobantes
     SET estado = 'anulado', anulado_at = now(), envio_en_curso_at = NULL,
         motivo_nota = p_motivo, updated_by = p_user_id
   WHERE id = p_id;
  PERFORM internal.recalcular_saldo_comprobante(p_id);

  -- Devolver los ítems al pool de pendientes: lo que se anuló sigue prestado y
  -- sigue debiéndose.
  UPDATE core.ordenes_servicio SET facturado = false, comprobante_id = NULL
   WHERE comprobante_id = p_id;

  UPDATE core.insumos_utilizados SET facturado = false
   WHERE id IN (SELECT i.insumo_id FROM core.comprobante_items i
                 WHERE i.comprobante_id = p_id AND i.insumo_id IS NOT NULL);

  -- La venta de mostrador salió del almacén al emitir: al anular, vuelve. Los
  -- insumos no se reponen porque el producto ya se usó en el paciente.
  FOR v_item IN
    SELECT ci.producto_id, ci.cantidad
      FROM core.comprobante_items ci
     WHERE ci.comprobante_id = p_id
       AND ci.producto_id IS NOT NULL AND ci.insumo_id IS NULL
  LOOP
    PERFORM internal.mover_stock(
      v_c.empresa_id, v_item.producto_id, 'entrada', 'devolucion',
      v_item.cantidad, p_user_id, NULL,
      jsonb_build_object('cliente_id', v_c.cliente_id, 'comprobante_id', p_id,
                         'observaciones', 'Anulación de ' || v_c.numero_completo));
  END LOOP;
END;
$$;

-- -----------------------------------------------------------------------------
-- internal.bloqueo_reversion — por qué un comprobante no se puede revertir
--
-- NULL si se puede. Las reglas comunes a anular y a dar de baja: que no esté
-- ya anulado, que no tenga una nota que lo corrija, que no tenga cobros vivos
-- y que no se esté enviando en este momento.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.bloqueo_reversion(p_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
DECLARE
  v_c RECORD;
BEGIN
  SELECT * INTO v_c FROM core.comprobantes WHERE id = p_id;

  IF v_c.anulado_at IS NOT NULL THEN
    RETURN 'El comprobante ya está anulado';
  END IF;

  IF v_c.envio_en_curso_at IS NOT NULL AND v_c.envio_en_curso_at > now() - INTERVAL '2 minutes' THEN
    RETURN 'El comprobante se está enviando a SUNAT en este momento. Espera la respuesta.';
  END IF;

  -- Si ya se corrigió con una nota de crédito, anular encima devolvería el
  -- stock y el saldo por segunda vez. El documento ya tiene su corrección.
  IF EXISTS (SELECT 1 FROM core.comprobantes nc
              WHERE nc.documento_ref_id = p_id AND nc.anulado_at IS NULL
                AND nc.deleted_at IS NULL) THEN
    RETURN 'El comprobante ya tiene una nota de crédito: esa es su corrección';
  END IF;

  IF EXISTS (SELECT 1 FROM core.pago_aplicaciones pa
              JOIN core.pagos pg ON pg.id = pa.pago_id AND pg.anulado_at IS NULL
             WHERE pa.comprobante_id = p_id) THEN
    RETURN 'El comprobante tiene cobros aplicados: anula primero los pagos o emite una nota de crédito';
  END IF;

  RETURN NULL;
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_comprobante_anular
--
-- Anulación interna: para lo que SUNAT no llegó a ver (nota de venta, un
-- comprobante que aún no se envió o que SUNAT rechazó). Lo que SUNAT ya recibió
-- se corrige con nota de crédito o se da de baja: ver sp_comprobante_registrar_baja.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_comprobante_anular(
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
  v_c       RECORD;
  v_bloqueo TEXT;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'facturacion:anular');

  IF COALESCE(trim(p_motivo), '') = '' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR','Indica el motivo de la anulación','motivo'));
  END IF;

  -- Bloqueado hasta el final: un cobro o una nota de crédito que llegan a la
  -- vez esperan a que esto termine y encuentran el documento ya anulado.
  SELECT * INTO v_c FROM core.comprobantes
   WHERE id = p_id AND deleted_at IS NULL
     AND internal.es_de_empresa(p_user_id, p_is_super_admin,
           internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin), empresa_id)
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Comprobante no encontrado'));
  END IF;

  -- Una vez que el documento salió hacia SUNAT deja de ser nuestro: existe para
  -- la administración tributaria. Lo que corresponde es la nota de crédito (o
  -- la comunicación de baja, dentro del plazo), no borrarlo del sistema.
  IF v_c.estado IN ('enviado_sunat','aceptado_sunat','observado_sunat') THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'El comprobante ya fue enviado a SUNAT: corresponde emitir una nota de crédito o comunicar la baja'));
  END IF;

  IF v_c.tipo = 'nota_credito' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'Una nota de crédito no se anula desde aquí: si SUNAT no la recibió, reenvíala'));
  END IF;

  v_bloqueo := internal.bloqueo_reversion(p_id);
  IF v_bloqueo IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE', v_bloqueo));
  END IF;

  PERFORM internal.revertir_comprobante(p_id, p_user_id, p_motivo);

  PERFORM internal.registrar_auditoria(
    p_user_id, v_c.empresa_id, 'anular', 'comprobantes', p_id, NULL,
    jsonb_build_object('motivo', p_motivo));

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'anulado', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_comprobante_registrar_baja
--
-- Comunicación de baja ante SUNAT: el camino para dar por no emitido un
-- comprobante que SUNAT ya recibió, dentro de los 7 días calendario.
--
-- Dos llamadas del backend, alrededor de la del PSE:
--   p_solo_validar = true  → ¿se puede dar de baja? (antes de hablar con SUNAT)
--   p_solo_validar = false → SUNAT la aceptó: se revierte el comprobante.
--
-- Antes la baja aceptada llamaba a sp_comprobante_anular, que rechaza todo lo
-- enviado a SUNAT: la baja quedaba aceptada allá y el comprobante vivo aquí.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_comprobante_registrar_baja(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_id             UUID,
  p_motivo         TEXT,
  p_solo_validar   BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_c       RECORD;
  v_bloqueo TEXT;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'facturacion:anular');

  IF COALESCE(trim(p_motivo), '') = '' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR','Indica el motivo de la baja','motivo'));
  END IF;

  SELECT * INTO v_c FROM core.comprobantes
   WHERE id = p_id AND deleted_at IS NULL
     AND internal.es_de_empresa(p_user_id, p_is_super_admin,
           internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin), empresa_id)
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Comprobante no encontrado'));
  END IF;

  IF v_c.estado NOT IN ('enviado_sunat','aceptado_sunat','observado_sunat') THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'Solo se comunica la baja de un comprobante que SUNAT recibió. Si no se envió, anúlalo.'));
  END IF;

  IF (now() AT TIME ZONE 'America/Lima')::date
     - (v_c.fecha_emision AT TIME ZONE 'America/Lima')::date > 7 THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'Pasaron más de 7 días desde la emisión: SUNAT ya no acepta la baja. Emite una nota de crédito.'));
  END IF;

  v_bloqueo := internal.bloqueo_reversion(p_id);
  IF v_bloqueo IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE', v_bloqueo));
  END IF;

  IF p_solo_validar THEN
    RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'procede', true));
  END IF;

  PERFORM internal.revertir_comprobante(p_id, p_user_id, 'Baja SUNAT: ' || p_motivo);

  PERFORM internal.registrar_auditoria(
    p_user_id, v_c.empresa_id, 'baja_sunat', 'comprobantes', p_id, NULL,
    jsonb_build_object('motivo', p_motivo));

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'anulado', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_comprobante_actualizar_sunat
-- El backend deja aquí la respuesta del PSE/OSE tras enviar el comprobante.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_comprobante_actualizar_sunat(
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
  v_estado core.estado_comprobante := NULLIF(p_payload->>'estado','')::core.estado_comprobante;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'facturacion:sunat');

  -- Marcar a mano solo sirve para reflejar lo que SUNAT dijo: no para anular
  -- (eso tiene su puerta) ni para devolver un documento a borrador.
  IF v_estado IS NOT NULL
     AND v_estado NOT IN ('enviado_sunat','aceptado_sunat','observado_sunat','rechazado_sunat') THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'Estado no permitido: usa enviado, aceptado, observado o rechazado','estado'));
  END IF;

  UPDATE core.comprobantes SET
    estado        = COALESCE(v_estado, estado),
    aceptado_sunat_at = CASE WHEN v_estado = 'aceptado_sunat'
                             THEN COALESCE(aceptado_sunat_at, now()) ELSE aceptado_sunat_at END,
    hash_cpe      = COALESCE(p_payload->>'hash_cpe', hash_cpe),
    xml_url       = COALESCE(p_payload->>'xml_url', xml_url),
    pdf_url       = COALESCE(p_payload->>'pdf_url', pdf_url),
    cdr_url       = COALESCE(p_payload->>'cdr_url', cdr_url),
    sunat_codigo  = COALESCE(p_payload->>'sunat_codigo', sunat_codigo),
    sunat_mensaje = COALESCE(p_payload->>'sunat_mensaje', sunat_mensaje),
    updated_by    = p_user_id
  WHERE id = p_id AND deleted_at IS NULL AND anulado_at IS NULL
    AND tipo <> 'nota_venta'
    AND internal.es_de_empresa(p_user_id, p_is_super_admin,
          internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin), empresa_id);

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Comprobante no encontrado o anulado'));
  END IF;

  PERFORM internal.registrar_auditoria(
    p_user_id, internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin),
    'actualizar_sunat_manual', 'comprobantes', p_id, NULL, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_nota_credito_emitir
--
-- El camino correcto cuando el comprobante ya llegó a SUNAT. Anularlo no es una
-- opción: el documento existe para la administración tributaria, y lo que
-- corrige el error es otro documento que lo referencia.
--
-- Soporta la nota total (todos los ítems) y la parcial (los ítems indicados,
-- típicamente una devolución de producto o un servicio cobrado de más).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_nota_credito_emitir(
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
  v_ref     RECORD;
  v_serie   TEXT;
  v_numero  INT;
  v_motivo  TEXT := NULLIF(trim(p_payload->>'motivo'), '');
  v_items   JSONB := COALESCE(p_payload->'items', '[]'::jsonb);
  v_item    JSONB;
  v_orden   INT := 0;
  v_ci      RECORD;
  v_cant    NUMERIC(12,2);
  v_total   NUMERIC(14,2) := 0;
  v_acred   NUMERIC(12,2);
  v_repone  BOOLEAN := COALESCE((p_payload->>'repone_stock')::boolean, true);
  v_electronico BOOLEAN;
  -- Catálogo SUNAT 09. El motivo es dato del documento, no un default oculto:
  -- SUNAT valida que el código corresponda a lo que dice la nota.
  v_cod_nota TEXT := COALESCE(NULLIF(p_payload->>'codigo_tipo_nota',''), '01');
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'facturacion:emitir');
  PERFORM internal.validar_payload(p_payload, ARRAY['comprobante_id']);

  IF v_motivo IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'Indica el motivo de la nota de crédito','motivo'));
  END IF;

  -- El comprobante de origen queda bloqueado mientras se emite la nota: dos
  -- notas parciales simultáneas se hacen en fila, y la segunda ve lo que la
  -- primera ya acreditó en vez de acreditar lo mismo otra vez.
  SELECT * INTO v_ref FROM core.comprobantes
   WHERE id = (p_payload->>'comprobante_id')::uuid AND deleted_at IS NULL
     AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, empresa_id)
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Comprobante no encontrado','comprobante_id'));
  END IF;

  IF v_ref.tipo IN ('nota_credito','nota_debito') THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'Una nota de crédito no se emite sobre otra nota'));
  END IF;

  IF v_ref.tipo = 'nota_venta' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'Una nota de venta no existe para SUNAT: se corrige anulándola, no con nota de crédito'));
  END IF;

  IF v_ref.anulado_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'El comprobante está anulado: no hay nada que acreditar'));
  END IF;

  SELECT emite_electronico, serie_nota_credito_default
    INTO v_electronico, v_serie
    FROM core.empresas WHERE id = v_emp;

  -- SUNAT rechaza una nota que referencia un documento que no conoce.
  IF COALESCE(v_electronico, false) THEN
    IF v_ref.estado IN ('pendiente_envio','emitido') THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('BUSINESS_RULE',
          'El comprobante aún no se envió a SUNAT: envíalo primero, o anúlalo si fue un error'));
    ELSIF v_ref.estado = 'rechazado_sunat' THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('BUSINESS_RULE',
          'SUNAT rechazó el comprobante: no hay nada que acreditar. Anúlalo y emite uno nuevo.'));
    END IF;
  END IF;

  -- La serie de la nota sigue a la del documento que corrige: FC.. para una
  -- factura, BC.. para una boleta. Con una sola serie para las dos, la nota de
  -- una boleta salía con F y SUNAT la rechazaba.
  v_serie := upper(COALESCE(NULLIF(trim(p_payload->>'serie'),''),
    CASE WHEN v_ref.tipo = 'factura'
         THEN 'F' || substr(COALESCE(NULLIF(v_serie,''), 'FC01'), 2)
         ELSE 'B' || substr(COALESCE(NULLIF(v_serie,''), 'BC01'), 2) END));

  IF left(v_serie, 1) <> left(v_ref.serie, 1) OR v_serie !~ '^[A-Z][A-Z0-9]{3}$' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        format('La serie de la nota (%s) debe empezar con la misma letra que %s',
               v_serie, v_ref.numero_completo), 'serie'));
  END IF;

  v_numero := internal.siguiente_numero_documento(v_emp, 'nota_credito', v_serie);

  INSERT INTO core.comprobantes (
    empresa_id, tipo, serie, numero, cliente_id, mascota_id, consulta_id,
    fecha_emision, moneda, tipo_cambio, estado, estado_pago,
    documento_ref_id, motivo_nota, codigo_tipo_nota, observaciones, created_by
  ) VALUES (
    v_emp, 'nota_credito', v_serie, v_numero, v_ref.cliente_id, v_ref.mascota_id,
    v_ref.consulta_id, now(), v_ref.moneda, v_ref.tipo_cambio,
    CASE WHEN COALESCE(v_electronico, false) THEN 'pendiente_envio'::core.estado_comprobante
         ELSE 'emitido'::core.estado_comprobante END,
    'pagado', v_ref.id, v_motivo, v_cod_nota, p_payload->>'observaciones', p_user_id
  ) RETURNING id INTO v_id;

  -- Sin detalle: la nota cubre lo que aún no se ha acreditado del comprobante.
  IF jsonb_array_length(v_items) = 0 THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object('comprobante_item_id', ci.id)), '[]'::jsonb)
      INTO v_items
      FROM core.comprobante_items ci WHERE ci.comprobante_id = v_ref.id;
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(v_items) LOOP
    SELECT * INTO v_ci FROM core.comprobante_items
     WHERE id = (v_item->>'comprobante_item_id')::uuid AND comprobante_id = v_ref.id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'El ítem indicado no pertenece al comprobante' USING ERRCODE = 'P0001';
    END IF;

    -- Lo ya acreditado de este ítem en notas anteriores. No se puede devolver
    -- más de lo que se cobró, ni sumando varias notas parciales.
    SELECT COALESCE(SUM(nci.cantidad), 0) INTO v_acred
      FROM core.comprobante_items nci
      JOIN core.comprobantes nc ON nc.id = nci.comprobante_id
     WHERE nci.item_ref_id = v_ci.id
       AND nc.tipo = 'nota_credito' AND nc.anulado_at IS NULL AND nc.deleted_at IS NULL;

    v_cant := COALESCE((v_item->>'cantidad')::numeric, v_ci.cantidad - v_acred);

    IF (v_item->>'cantidad') IS NOT NULL AND v_cant <= 0 THEN
      RAISE EXCEPTION 'La cantidad a acreditar de "%" debe ser mayor a cero', v_ci.descripcion
        USING ERRCODE = 'P0001';
    END IF;

    IF v_cant > v_ci.cantidad - v_acred THEN
      RAISE EXCEPTION
        'Del ítem "%" ya se acreditaron % de %: no se puede acreditar % más',
        v_ci.descripcion, v_acred, v_ci.cantidad, v_cant USING ERRCODE = 'P0001';
    END IF;

    IF v_cant <= 0 THEN CONTINUE; END IF;

    v_orden := v_orden + 1;
    INSERT INTO core.comprobante_items (
      comprobante_id, tipo_item, servicio_id, producto_id, orden_servicio_id,
      insumo_id, item_ref_id, codigo, descripcion, cantidad, precio_unitario, descuento,
      afecto_igv, tipo_afectacion_igv, unidad_medida, subtotal, igv, total, orden
    ) VALUES (
      v_id, v_ci.tipo_item, v_ci.servicio_id, v_ci.producto_id, v_ci.orden_servicio_id,
      v_ci.insumo_id, v_ci.id, v_ci.codigo, v_ci.descripcion, v_cant, v_ci.precio_unitario,
      -- El descuento de la línea original se acredita en la misma proporción:
      -- así cantidad × precio − descuento sigue siendo el total de la línea.
      round(v_ci.descuento * v_cant / v_ci.cantidad, 2),
      v_ci.afecto_igv, v_ci.tipo_afectacion_igv, v_ci.unidad_medida,
      round(v_ci.subtotal * v_cant / v_ci.cantidad, 2),
      round(v_ci.igv      * v_cant / v_ci.cantidad, 2),
      round(v_ci.total    * v_cant / v_ci.cantidad, 2),
      v_orden);

    v_total := v_total + round(v_ci.total * v_cant / v_ci.cantidad, 2);

    -- Devolución de producto vendido en mostrador: vuelve al almacén.
    IF v_repone AND v_ci.producto_id IS NOT NULL AND v_ci.insumo_id IS NULL THEN
      PERFORM internal.mover_stock(
        v_emp, v_ci.producto_id, 'entrada', 'devolucion', v_cant, p_user_id, NULL,
        jsonb_build_object('cliente_id', v_ref.cliente_id, 'comprobante_id', v_id,
                           'observaciones', 'Nota de crédito ' || v_serie || '-' || v_numero));
    END IF;
  END LOOP;

  IF v_orden = 0 THEN
    RAISE EXCEPTION 'La nota de crédito no tiene ítems' USING ERRCODE = 'P0001';
  END IF;

  -- La nota baja la deuda del comprobante que corrige. Si lo cubre entero, ese
  -- comprobante queda sin saldo y deja de aparecer en cobranzas. El cálculo es
  -- el de siempre (internal.recalcular_saldo_comprobante): el trigger de ítems
  -- ya lo hizo, esto solo lo deja explícito.
  PERFORM internal.recalcular_saldo_comprobante(v_ref.id);

  -- Lo acreditado deja de estar cobrado: si fue un error de facturación, vuelve
  -- a pendiente; si fue una devolución, ya no se le debe cobrar a nadie.
  IF COALESCE((p_payload->>'devolver_a_pendientes')::boolean, false) THEN
    UPDATE core.ordenes_servicio SET facturado = false, comprobante_id = NULL
     WHERE id IN (SELECT ci.orden_servicio_id FROM core.comprobante_items ci
                   WHERE ci.comprobante_id = v_id AND ci.orden_servicio_id IS NOT NULL);
    UPDATE core.insumos_utilizados SET facturado = false
     WHERE id IN (SELECT ci.insumo_id FROM core.comprobante_items ci
                   WHERE ci.comprobante_id = v_id AND ci.insumo_id IS NOT NULL);
  END IF;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'emitir_nota_credito', 'comprobantes', v_id, NULL,
    jsonb_build_object('ref', v_ref.numero_completo, 'motivo', v_motivo, 'total', v_total));

  RETURN jsonb_build_object('ok', true, 'data', (
    SELECT jsonb_build_object(
      'id', c.id, 'numero_completo', c.numero_completo, 'tipo', c.tipo,
      'subtotal', c.subtotal, 'igv', c.igv, 'total', c.total,
      'documento_ref', v_ref.numero_completo)
    FROM core.comprobantes c WHERE c.id = v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_cuentas_por_cobrar — aging de la deuda
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_cuentas_por_cobrar(
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
  v_resumen JSONB;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'facturacion:ver');

  SELECT COALESCE(jsonb_agg(x ORDER BY x.dias_vencido DESC NULLS LAST), '[]'::jsonb) INTO v_data
  FROM (
    SELECT c.id, c.numero_completo, c.tipo, c.fecha_emision, c.fecha_vencimiento,
           c.total, c.saldo_pendiente, c.estado_pago, c.moneda,
           c.cliente_id,
           trim(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'')) AS cliente,
           cl.telefono AS cliente_telefono, cl.numero_documento,
           GREATEST((CURRENT_DATE - c.fecha_vencimiento), 0) AS dias_vencido,
           CASE
             WHEN c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= CURRENT_DATE THEN 'por_vencer'
             WHEN CURRENT_DATE - c.fecha_vencimiento <= 30 THEN '1_30'
             WHEN CURRENT_DATE - c.fecha_vencimiento <= 60 THEN '31_60'
             WHEN CURRENT_DATE - c.fecha_vencimiento <= 90 THEN '61_90'
             ELSE 'mas_90'
           END AS tramo
    FROM core.comprobantes c
    JOIN core.clientes cl ON cl.id = c.cliente_id
    WHERE c.deleted_at IS NULL AND c.anulado_at IS NULL
      AND c.tipo IN ('factura','boleta','nota_venta')
      AND (v_global OR c.empresa_id = v_emp)
      AND c.saldo_pendiente > 0
      AND (p_filtros->>'cliente_id' IS NULL OR c.cliente_id = (p_filtros->>'cliente_id')::uuid)
  ) x;

  SELECT jsonb_build_object(
    'total_deuda', COALESCE(SUM(c.saldo_pendiente), 0),
    'por_vencer',  COALESCE(SUM(c.saldo_pendiente) FILTER (
                     WHERE c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= CURRENT_DATE), 0),
    'vencido',     COALESCE(SUM(c.saldo_pendiente) FILTER (
                     WHERE c.fecha_vencimiento < CURRENT_DATE), 0),
    'documentos',  count(*),
    'clientes',    count(DISTINCT c.cliente_id)
  ) INTO v_resumen
  FROM core.comprobantes c
  WHERE c.deleted_at IS NULL AND c.anulado_at IS NULL
    AND c.tipo IN ('factura','boleta','nota_venta')
    AND (v_global OR c.empresa_id = v_emp)
    AND c.saldo_pendiente > 0
    AND (p_filtros->>'cliente_id' IS NULL OR c.cliente_id = (p_filtros->>'cliente_id')::uuid);

  RETURN jsonb_build_object('ok', true, 'data', v_data, 'meta', v_resumen);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;
