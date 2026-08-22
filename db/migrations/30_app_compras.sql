-- =============================================================================
-- 30_app_compras.sql — Proveedores, órdenes de compra y pagos a proveedores
-- =============================================================================

SET search_path = app, internal, core, public;

-- =============================================================================
-- PROVEEDORES
-- =============================================================================

CREATE OR REPLACE FUNCTION app.fn_proveedores_listar(
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
BEGIN
  SELECT count(*) INTO v_total
  FROM core.proveedores p
  WHERE p.deleted_at IS NULL AND (v_global OR p.empresa_id = v_emp)
    AND (p_filtros->>'estado'       IS NULL OR p.estado::text = p_filtros->>'estado')
    AND (p_filtros->>'categoria_id' IS NULL OR p.categoria_id = (p_filtros->>'categoria_id')::uuid)
    AND (v_buscar IS NULL OR v_buscar = '' OR
         internal.normalizar(p.razon_social) LIKE '%' || v_buscar || '%' OR
         p.numero_documento LIKE '%' || v_raw || '%');

  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) INTO v_data
  FROM (
    SELECT p.id, p.codigo, p.tipo_documento, p.numero_documento, p.razon_social,
           p.nombre_comercial, p.direccion, p.telefono, p.correo, p.web,
           p.dias_credito, p.cuenta_bancaria, p.banco, p.estado, p.observaciones,
           p.categoria_id, cat.nombre AS categoria, p.empresa_id,
           (SELECT count(*) FROM core.ordenes_compra oc
             WHERE oc.proveedor_id = p.id AND oc.deleted_at IS NULL) AS total_ordenes,
           (SELECT COALESCE(SUM(oc.saldo_pendiente), 0) FROM core.ordenes_compra oc
             WHERE oc.proveedor_id = p.id AND oc.deleted_at IS NULL
               AND oc.estado_pago <> 'pagado') AS deuda_pendiente,
           (SELECT max(oc.fecha_emision) FROM core.ordenes_compra oc
             WHERE oc.proveedor_id = p.id AND oc.deleted_at IS NULL) AS ultima_compra,
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id', c.id, 'nombres', c.nombres, 'cargo', c.cargo,
                     'telefono', c.telefono, 'correo', c.correo,
                     'es_principal', c.es_principal) ORDER BY c.es_principal DESC), '[]'::jsonb)
              FROM core.proveedor_contactos c WHERE c.proveedor_id = p.id) AS contactos
    FROM core.proveedores p
    LEFT JOIN core.categorias cat ON cat.id = p.categoria_id
    WHERE p.deleted_at IS NULL AND (v_global OR p.empresa_id = v_emp)
      AND (p_filtros->>'estado'       IS NULL OR p.estado::text = p_filtros->>'estado')
      AND (p_filtros->>'categoria_id' IS NULL OR p.categoria_id = (p_filtros->>'categoria_id')::uuid)
      AND (v_buscar IS NULL OR v_buscar = '' OR
           internal.normalizar(p.razon_social) LIKE '%' || v_buscar || '%' OR
           p.numero_documento LIKE '%' || v_raw || '%')
    ORDER BY p.razon_social
    LIMIT v_size OFFSET (v_page - 1) * v_size
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data, 'meta', jsonb_build_object(
    'total', v_total, 'page', v_page, 'pageSize', v_size,
    'pages', GREATEST(CEIL(v_total::numeric / v_size)::int, 1)));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_proveedor_guardar(
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
  v_doc TEXT := p_payload->>'numero_documento';
  v_tipo core.tipo_documento_identidad :=
    COALESCE((p_payload->>'tipo_documento')::core.tipo_documento_identidad, 'RUC');
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'compras:gestionar');

  IF v_id IS NULL THEN
    PERFORM internal.validar_payload(p_payload, ARRAY['numero_documento','razon_social']);

    IF v_tipo = 'RUC' AND NOT internal.validar_ruc(v_doc) THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('VALIDATION_ERROR','El RUC no es válido','numero_documento'));
    END IF;

    INSERT INTO core.proveedores (
      empresa_id, codigo, tipo_documento, numero_documento, razon_social,
      nombre_comercial, categoria_id, direccion, telefono, correo, web,
      dias_credito, cuenta_bancaria, banco, estado, observaciones, created_by
    ) VALUES (
      v_emp,
      COALESCE(NULLIF(p_payload->>'codigo',''), internal.siguiente_numero(v_emp, 'PRV', 4)),
      v_tipo, v_doc, p_payload->>'razon_social', p_payload->>'nombre_comercial',
      NULLIF(p_payload->>'categoria_id','')::uuid,
      p_payload->>'direccion', p_payload->>'telefono',
      lower(NULLIF(p_payload->>'correo','')), p_payload->>'web',
      COALESCE((p_payload->>'dias_credito')::int, 0),
      p_payload->>'cuenta_bancaria', p_payload->>'banco',
      COALESCE((p_payload->>'estado')::core.estado_proveedor, 'activo'),
      p_payload->>'observaciones', p_user_id
    ) RETURNING id INTO v_id;
  ELSE
    UPDATE core.proveedores SET
      razon_social     = COALESCE(p_payload->>'razon_social', razon_social),
      nombre_comercial = COALESCE(p_payload->>'nombre_comercial', nombre_comercial),
      categoria_id     = COALESCE(NULLIF(p_payload->>'categoria_id','')::uuid, categoria_id),
      direccion        = COALESCE(p_payload->>'direccion', direccion),
      telefono         = COALESCE(p_payload->>'telefono', telefono),
      correo           = COALESCE(lower(NULLIF(p_payload->>'correo','')), correo),
      web              = COALESCE(p_payload->>'web', web),
      dias_credito     = COALESCE((p_payload->>'dias_credito')::int, dias_credito),
      cuenta_bancaria  = COALESCE(p_payload->>'cuenta_bancaria', cuenta_bancaria),
      banco            = COALESCE(p_payload->>'banco', banco),
      estado           = COALESCE((p_payload->>'estado')::core.estado_proveedor, estado),
      observaciones    = COALESCE(p_payload->>'observaciones', observaciones),
      updated_by       = p_user_id
    WHERE id = v_id AND deleted_at IS NULL;
  END IF;

  PERFORM internal.registrar_auditoria(p_user_id, v_emp, 'guardar', 'proveedores', v_id, NULL, p_payload);
  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('CONFLICT','Ya existe un proveedor con ese documento','numero_documento'));
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_proveedor_contacto_guardar(
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
  PERFORM internal.assert_permiso(p_user_id, 'compras:gestionar');

  IF v_id IS NULL THEN
    PERFORM internal.validar_payload(p_payload, ARRAY['proveedor_id','nombres']);
    INSERT INTO core.proveedor_contactos (proveedor_id, nombres, cargo, telefono, correo, es_principal)
    VALUES ((p_payload->>'proveedor_id')::uuid, p_payload->>'nombres', p_payload->>'cargo',
            p_payload->>'telefono', lower(NULLIF(p_payload->>'correo','')),
            COALESCE((p_payload->>'es_principal')::boolean, false))
    RETURNING id INTO v_id;
  ELSE
    UPDATE core.proveedor_contactos SET
      nombres      = COALESCE(p_payload->>'nombres', nombres),
      cargo        = COALESCE(p_payload->>'cargo', cargo),
      telefono     = COALESCE(p_payload->>'telefono', telefono),
      correo       = COALESCE(lower(NULLIF(p_payload->>'correo','')), correo),
      es_principal = COALESCE((p_payload->>'es_principal')::boolean, es_principal)
    WHERE id = v_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_proveedor_eliminar(
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
  v_ordenes INT;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'compras:gestionar');

  SELECT count(*) INTO v_ordenes FROM core.ordenes_compra
   WHERE proveedor_id = p_id AND deleted_at IS NULL;

  IF v_ordenes > 0 THEN
    UPDATE core.proveedores SET estado = 'inactivo', updated_by = p_user_id WHERE id = p_id;
    RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
      'id', p_id, 'desactivado', true,
      'mensaje', 'El proveedor tiene órdenes de compra: se desactivó en lugar de eliminarse.'));
  END IF;

  UPDATE core.proveedores SET deleted_at = now(), estado = 'inactivo', updated_by = p_user_id
   WHERE id = p_id AND deleted_at IS NULL;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'eliminado', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- ÓRDENES DE COMPRA
-- =============================================================================

CREATE OR REPLACE FUNCTION app.sp_orden_compra_crear(
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
  v_item     JSONB;
  v_subtotal NUMERIC(14,2) := 0;
  v_igv      NUMERIC(14,2) := 0;
  v_tasa     NUMERIC(5,4);
  v_sub_item NUMERIC(14,2);
  v_orden    INT := 0;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'compras:gestionar');
  PERFORM internal.validar_payload(p_payload, ARRAY['proveedor_id','items']);

  IF jsonb_array_length(p_payload->'items') = 0 THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR','La orden necesita al menos un ítem','items'));
  END IF;

  SELECT igv_tasa INTO v_tasa FROM core.empresas WHERE id = v_emp;
  v_tasa := COALESCE(v_tasa, 0.18);

  INSERT INTO core.ordenes_compra (
    empresa_id, numero, proveedor_id, almacen_id, fecha_emision, fecha_estimada,
    moneda, estado, observaciones, created_by
  ) VALUES (
    v_emp, internal.siguiente_numero(v_emp, 'OC', 6),
    (p_payload->>'proveedor_id')::uuid,
    COALESCE(NULLIF(p_payload->>'almacen_id','')::uuid,
             (SELECT id FROM core.almacenes WHERE empresa_id = v_emp AND es_principal LIMIT 1)),
    COALESCE(NULLIF(p_payload->>'fecha_emision','')::date, CURRENT_DATE),
    NULLIF(p_payload->>'fecha_estimada','')::date,
    COALESCE((p_payload->>'moneda')::core.moneda_codigo, 'PEN'),
    COALESCE((p_payload->>'estado')::core.estado_orden_compra, 'borrador'),
    p_payload->>'observaciones', p_user_id
  ) RETURNING id INTO v_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_payload->'items') LOOP
    v_orden := v_orden + 1;
    v_sub_item := round(
      (v_item->>'cantidad')::numeric * (v_item->>'precio_unitario')::numeric
      - COALESCE((v_item->>'descuento')::numeric, 0), 2);

    INSERT INTO core.orden_compra_items (
      orden_compra_id, producto_id, descripcion, cantidad, precio_unitario,
      descuento, subtotal, numero_lote, fecha_vencimiento, orden
    ) VALUES (
      v_id, (v_item->>'producto_id')::uuid, v_item->>'descripcion',
      (v_item->>'cantidad')::numeric, (v_item->>'precio_unitario')::numeric,
      COALESCE((v_item->>'descuento')::numeric, 0), v_sub_item,
      NULLIF(v_item->>'numero_lote',''),
      NULLIF(v_item->>'fecha_vencimiento','')::date, v_orden);

    v_subtotal := v_subtotal + v_sub_item;
  END LOOP;

  v_igv := internal.calcular_igv(v_subtotal, v_tasa);

  UPDATE core.ordenes_compra
     SET subtotal = v_subtotal, igv = v_igv,
         total = v_subtotal + v_igv, saldo_pendiente = v_subtotal + v_igv
   WHERE id = v_id;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'crear', 'ordenes_compra', v_id, NULL, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'id', v_id, 'subtotal', v_subtotal, 'igv', v_igv, 'total', v_subtotal + v_igv));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_orden_compra_recibir
-- Recibir la mercadería es lo que mueve el inventario: crea/actualiza lotes y
-- registra una entrada por cada ítem.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_orden_compra_recibir(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_id             UUID,
  p_recepcion      JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_oc      RECORD;
  v_item    RECORD;
  v_recibir NUMERIC;
  v_lote    UUID;
  v_pend    INT;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'compras:recibir');

  SELECT * INTO v_oc FROM core.ordenes_compra WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Orden de compra no encontrada'));
  END IF;

  IF v_oc.estado IN ('recibida','cancelada') THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        format('La orden ya está %s', v_oc.estado)));
  END IF;

  FOR v_item IN SELECT * FROM core.orden_compra_items WHERE orden_compra_id = p_id LOOP
    -- Recepción parcial: si viene detalle, se usa; si no, se recibe todo.
    v_recibir := COALESCE(
      (SELECT (e->>'cantidad')::numeric
         FROM jsonb_array_elements(COALESCE(p_recepcion, '[]'::jsonb)) e
        WHERE (e->>'item_id')::uuid = v_item.id),
      v_item.cantidad - v_item.cantidad_recibida);

    CONTINUE WHEN v_recibir IS NULL OR v_recibir <= 0;

    v_lote := NULL;
    IF v_item.numero_lote IS NOT NULL THEN
      INSERT INTO core.lotes (empresa_id, producto_id, numero_lote, fecha_vencimiento, cantidad, costo_unitario)
      VALUES (v_oc.empresa_id, v_item.producto_id, v_item.numero_lote,
              v_item.fecha_vencimiento, 0, v_item.precio_unitario)
      ON CONFLICT (producto_id, numero_lote) DO UPDATE
        SET fecha_vencimiento = COALESCE(EXCLUDED.fecha_vencimiento, core.lotes.fecha_vencimiento),
            updated_at = now()
      RETURNING id INTO v_lote;
    END IF;

    PERFORM internal.mover_stock(
      v_oc.empresa_id, v_item.producto_id, 'entrada', 'compra', v_recibir, p_user_id,
      v_oc.almacen_id,
      jsonb_build_object('lote_id', v_lote,
                         'costo_unitario', v_item.precio_unitario,
                         'proveedor_id', v_oc.proveedor_id,
                         'orden_compra_id', p_id,
                         'observaciones', 'Recepción de ' || v_oc.numero));

    UPDATE core.orden_compra_items
       SET cantidad_recibida = cantidad_recibida + v_recibir
     WHERE id = v_item.id;

    -- El precio de compra del producto se refresca con la última compra real.
    UPDATE core.productos
       SET precio_compra = v_item.precio_unitario,
           margen_pct = CASE WHEN v_item.precio_unitario > 0
                        THEN round((precio_venta - v_item.precio_unitario) / v_item.precio_unitario * 100, 2) END,
           updated_at = now()
     WHERE id = v_item.producto_id;
  END LOOP;

  SELECT count(*) INTO v_pend FROM core.orden_compra_items
   WHERE orden_compra_id = p_id AND cantidad_recibida < cantidad;

  UPDATE core.ordenes_compra
     SET estado = CASE WHEN v_pend = 0 THEN 'recibida' ELSE 'recibida_parcial' END::core.estado_orden_compra,
         fecha_recepcion = CASE WHEN v_pend = 0 THEN CURRENT_DATE ELSE fecha_recepcion END,
         updated_by = p_user_id
   WHERE id = p_id;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_oc.empresa_id, 'recibir', 'ordenes_compra', p_id);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'id', p_id, 'items_pendientes', v_pend,
    'estado', CASE WHEN v_pend = 0 THEN 'recibida' ELSE 'recibida_parcial' END));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_ordenes_compra_listar(
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
  FROM core.ordenes_compra oc
  WHERE oc.deleted_at IS NULL AND (v_global OR oc.empresa_id = v_emp)
    AND (p_filtros->>'estado'       IS NULL OR oc.estado::text = p_filtros->>'estado')
    AND (p_filtros->>'estado_pago'  IS NULL OR oc.estado_pago::text = p_filtros->>'estado_pago')
    AND (p_filtros->>'proveedor_id' IS NULL OR oc.proveedor_id = (p_filtros->>'proveedor_id')::uuid)
    AND (p_filtros->>'desde' IS NULL OR oc.fecha_emision >= (p_filtros->>'desde')::date)
    AND (p_filtros->>'hasta' IS NULL OR oc.fecha_emision <= (p_filtros->>'hasta')::date);

  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) INTO v_data
  FROM (
    SELECT oc.id, oc.numero, oc.fecha_emision, oc.fecha_estimada, oc.fecha_recepcion,
           oc.moneda, oc.subtotal, oc.igv, oc.total, oc.saldo_pendiente,
           oc.estado, oc.estado_pago, oc.observaciones,
           oc.proveedor_id, pv.razon_social AS proveedor, pv.numero_documento AS proveedor_doc,
           al.nombre AS almacen,
           (SELECT count(*) FROM core.orden_compra_items i WHERE i.orden_compra_id = oc.id) AS items,
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id', i.id, 'producto_id', i.producto_id, 'producto', pr.nombre,
                     'codigo', pr.codigo, 'cantidad', i.cantidad,
                     'cantidad_recibida', i.cantidad_recibida,
                     'precio_unitario', i.precio_unitario, 'descuento', i.descuento,
                     'subtotal', i.subtotal, 'numero_lote', i.numero_lote,
                     'fecha_vencimiento', i.fecha_vencimiento) ORDER BY i.orden), '[]'::jsonb)
              FROM core.orden_compra_items i
              JOIN core.productos pr ON pr.id = i.producto_id
             WHERE i.orden_compra_id = oc.id) AS detalle
    FROM core.ordenes_compra oc
    JOIN core.proveedores pv ON pv.id = oc.proveedor_id
    LEFT JOIN core.almacenes al ON al.id = oc.almacen_id
    WHERE oc.deleted_at IS NULL AND (v_global OR oc.empresa_id = v_emp)
      AND (p_filtros->>'estado'       IS NULL OR oc.estado::text = p_filtros->>'estado')
      AND (p_filtros->>'estado_pago'  IS NULL OR oc.estado_pago::text = p_filtros->>'estado_pago')
      AND (p_filtros->>'proveedor_id' IS NULL OR oc.proveedor_id = (p_filtros->>'proveedor_id')::uuid)
      AND (p_filtros->>'desde' IS NULL OR oc.fecha_emision >= (p_filtros->>'desde')::date)
      AND (p_filtros->>'hasta' IS NULL OR oc.fecha_emision <= (p_filtros->>'hasta')::date)
    ORDER BY oc.fecha_emision DESC, oc.numero DESC
    LIMIT v_size OFFSET (v_page - 1) * v_size
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data, 'meta', jsonb_build_object(
    'total', v_total, 'page', v_page, 'pageSize', v_size,
    'pages', GREATEST(CEIL(v_total::numeric / v_size)::int, 1)));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_orden_compra_cambiar_estado(
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
DECLARE
  v_actual core.estado_orden_compra;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'compras:gestionar');

  SELECT estado INTO v_actual FROM core.ordenes_compra WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Orden de compra no encontrada'));
  END IF;

  IF v_actual IN ('recibida','recibida_parcial') AND p_estado = 'cancelada' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'No se cancela una orden con mercadería ya recibida: registra la devolución en inventario'));
  END IF;

  UPDATE core.ordenes_compra
     SET estado = p_estado::core.estado_orden_compra, updated_by = p_user_id
   WHERE id = p_id;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'estado', p_estado));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- PAGOS A PROVEEDORES
-- =============================================================================

CREATE OR REPLACE FUNCTION app.sp_pago_proveedor_registrar(
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
  v_id     UUID;
  v_emp    UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_oc     UUID := NULLIF(p_payload->>'orden_compra_id','')::uuid;
  v_monto  NUMERIC(14,2) := (p_payload->>'monto')::numeric;
  v_saldo  NUMERIC(14,2);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'compras:pagar');
  PERFORM internal.validar_payload(p_payload, ARRAY['proveedor_id','monto']);

  IF v_monto <= 0 THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR','El monto debe ser mayor a cero','monto'));
  END IF;

  IF v_oc IS NOT NULL THEN
    SELECT saldo_pendiente INTO v_saldo FROM core.ordenes_compra WHERE id = v_oc;
    IF v_monto > v_saldo THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('BUSINESS_RULE',
          format('El pago (%s) excede el saldo pendiente de la orden (%s)', v_monto, v_saldo), 'monto'));
    END IF;
  END IF;

  INSERT INTO core.pagos_proveedor (
    empresa_id, proveedor_id, orden_compra_id, numero, metodo, monto, moneda,
    referencia, comprobante_url, fecha_pago, observaciones, created_by
  ) VALUES (
    v_emp, (p_payload->>'proveedor_id')::uuid, v_oc,
    internal.siguiente_numero(v_emp, 'PGP', 6),
    COALESCE((p_payload->>'metodo')::core.metodo_pago, 'transferencia'),
    v_monto,
    COALESCE((p_payload->>'moneda')::core.moneda_codigo, 'PEN'),
    p_payload->>'referencia', p_payload->>'comprobante_url',
    COALESCE(NULLIF(p_payload->>'fecha_pago','')::timestamptz, now()),
    p_payload->>'observaciones', p_user_id
  ) RETURNING id INTO v_id;

  IF v_oc IS NOT NULL THEN
    UPDATE core.ordenes_compra
       SET saldo_pendiente = saldo_pendiente - v_monto,
           estado_pago = CASE
             WHEN saldo_pendiente - v_monto <= 0 THEN 'pagado'::core.estado_pago
             ELSE 'parcial'::core.estado_pago END,
           updated_at = now()
     WHERE id = v_oc;
  END IF;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'registrar_pago', 'pagos_proveedor', v_id, NULL, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_pagos_proveedor_listar(
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
  SELECT COALESCE(jsonb_agg(x ORDER BY x.fecha_pago DESC), '[]'::jsonb) INTO v_data
  FROM (
    SELECT pp.id, pp.numero, pp.metodo, pp.monto, pp.moneda, pp.referencia,
           pp.comprobante_url, pp.fecha_pago, pp.anulado_at, pp.observaciones,
           pv.razon_social AS proveedor, oc.numero AS orden_compra,
           trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS registrado_por
    FROM core.pagos_proveedor pp
    JOIN core.proveedores pv ON pv.id = pp.proveedor_id
    LEFT JOIN core.ordenes_compra oc ON oc.id = pp.orden_compra_id
    LEFT JOIN core.users u ON u.id = pp.created_by
    WHERE (v_global OR pp.empresa_id = v_emp)
      AND (p_filtros->>'proveedor_id' IS NULL OR pp.proveedor_id = (p_filtros->>'proveedor_id')::uuid)
      AND (p_filtros->>'desde' IS NULL OR pp.fecha_pago >= (p_filtros->>'desde')::timestamptz)
      AND (p_filtros->>'hasta' IS NULL OR pp.fecha_pago <  (p_filtros->>'hasta')::timestamptz)
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;
