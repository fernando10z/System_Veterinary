-- =============================================================================
-- 29_app_inventario.sql — Productos, almacenes, stock, lotes y movimientos
--
-- Todo el movimiento de stock pasa por internal.mover_stock: valida existencias,
-- inserta el movimiento y el trigger ajusta stock/lotes/denormalizado.
-- =============================================================================

SET search_path = app, internal, core, public;

CREATE OR REPLACE FUNCTION app.fn_productos_listar(
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
  v_solo_criticos BOOLEAN := COALESCE((p_filtros->>'solo_criticos')::boolean, false);
  v_total  INT;
  v_data   JSONB;
BEGIN
  SELECT count(*) INTO v_total
  FROM core.productos p
  WHERE p.deleted_at IS NULL AND (v_global OR p.empresa_id = v_emp)
    AND (p_filtros->>'tipo'         IS NULL OR p.tipo::text = p_filtros->>'tipo')
    AND (p_filtros->>'estado'       IS NULL OR p.estado::text = p_filtros->>'estado')
    AND (p_filtros->>'categoria_id' IS NULL OR p.categoria_id = (p_filtros->>'categoria_id')::uuid)
    AND (NOT v_solo_criticos OR p.stock_actual <= p.stock_minimo)
    AND (v_buscar IS NULL OR v_buscar = '' OR
         internal.normalizar(p.nombre) LIKE '%' || v_buscar || '%' OR
         internal.normalizar(COALESCE(p.principio_activo,'')) LIKE '%' || v_buscar || '%' OR
         p.codigo LIKE '%' || v_raw || '%' OR
         COALESCE(p.codigo_barras,'') LIKE '%' || v_raw || '%');

  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) INTO v_data
  FROM (
    SELECT p.id, p.codigo, p.codigo_barras, p.nombre, p.descripcion, p.tipo,
           p.principio_activo, p.laboratorio, p.presentacion, p.unidad_medida,
           p.requiere_receta, p.controlado, p.refrigerado,
           p.precio_compra, p.precio_venta, p.margen_pct, p.afecto_igv,
           p.stock_actual, p.stock_minimo, p.stock_maximo, p.maneja_lotes,
           p.estado, p.categoria_id, p.empresa_id, cat.nombre AS categoria,
           CASE
             WHEN p.stock_actual <= 0 THEN 'agotado'
             WHEN p.stock_actual <= p.stock_minimo THEN 'critico'
             WHEN p.stock_maximo IS NOT NULL AND p.stock_actual >= p.stock_maximo THEN 'exceso'
             ELSE 'normal'
           END AS situacion_stock,
           (SELECT min(l.fecha_vencimiento) FROM core.lotes l
             WHERE l.producto_id = p.id AND l.cantidad > 0
               AND l.fecha_vencimiento IS NOT NULL) AS proximo_vencimiento,
           (SELECT COALESCE(SUM(l.cantidad), 0) FROM core.lotes l
             WHERE l.producto_id = p.id AND l.cantidad > 0
               AND l.fecha_vencimiento IS NOT NULL
               AND l.fecha_vencimiento <= CURRENT_DATE + 90) AS unidades_por_vencer
    FROM core.productos p
    LEFT JOIN core.categorias cat ON cat.id = p.categoria_id
    WHERE p.deleted_at IS NULL AND (v_global OR p.empresa_id = v_emp)
      AND (p_filtros->>'tipo'         IS NULL OR p.tipo::text = p_filtros->>'tipo')
      AND (p_filtros->>'estado'       IS NULL OR p.estado::text = p_filtros->>'estado')
      AND (p_filtros->>'categoria_id' IS NULL OR p.categoria_id = (p_filtros->>'categoria_id')::uuid)
      AND (NOT v_solo_criticos OR p.stock_actual <= p.stock_minimo)
      AND (v_buscar IS NULL OR v_buscar = '' OR
           internal.normalizar(p.nombre) LIKE '%' || v_buscar || '%' OR
           internal.normalizar(COALESCE(p.principio_activo,'')) LIKE '%' || v_buscar || '%' OR
           p.codigo LIKE '%' || v_raw || '%' OR
           COALESCE(p.codigo_barras,'') LIKE '%' || v_raw || '%')
    ORDER BY p.nombre
    LIMIT v_size OFFSET (v_page - 1) * v_size
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data, 'meta', jsonb_build_object(
    'total', v_total, 'page', v_page, 'pageSize', v_size,
    'pages', GREATEST(CEIL(v_total::numeric / v_size)::int, 1)));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_producto_guardar(
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
  v_compra NUMERIC := NULLIF(p_payload->>'precio_compra','')::numeric;
  v_venta  NUMERIC := NULLIF(p_payload->>'precio_venta','')::numeric;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'inventario:gestionar');

  IF v_id IS NULL THEN
    PERFORM internal.validar_payload(p_payload, ARRAY['nombre','precio_venta']);
    INSERT INTO core.productos (
      empresa_id, codigo, codigo_barras, nombre, descripcion, tipo, categoria_id,
      principio_activo, laboratorio, presentacion, unidad_medida,
      requiere_receta, controlado, refrigerado,
      precio_compra, precio_venta, margen_pct, afecto_igv,
      stock_minimo, stock_maximo, maneja_lotes, estado, created_by
    ) VALUES (
      v_emp,
      COALESCE(NULLIF(p_payload->>'codigo',''), internal.siguiente_numero(v_emp, 'PRD', 5)),
      NULLIF(p_payload->>'codigo_barras',''),
      p_payload->>'nombre', p_payload->>'descripcion',
      COALESCE((p_payload->>'tipo')::core.tipo_producto, 'insumo'),
      NULLIF(p_payload->>'categoria_id','')::uuid,
      p_payload->>'principio_activo', p_payload->>'laboratorio',
      p_payload->>'presentacion',
      COALESCE(NULLIF(p_payload->>'unidad_medida',''), 'UND'),
      COALESCE((p_payload->>'requiere_receta')::boolean, false),
      COALESCE((p_payload->>'controlado')::boolean, false),
      COALESCE((p_payload->>'refrigerado')::boolean, false),
      COALESCE(v_compra, 0), v_venta,
      CASE WHEN COALESCE(v_compra,0) > 0
           THEN round((v_venta - v_compra) / v_compra * 100, 2) END,
      COALESCE((p_payload->>'afecto_igv')::boolean, true),
      COALESCE((p_payload->>'stock_minimo')::numeric, 0),
      NULLIF(p_payload->>'stock_maximo','')::numeric,
      COALESCE((p_payload->>'maneja_lotes')::boolean, false),
      COALESCE((p_payload->>'estado')::core.estado_generico, 'activo'),
      p_user_id
    ) RETURNING id INTO v_id;

    -- Stock inicial opcional: entra como movimiento para dejar rastro
    IF COALESCE((p_payload->>'stock_inicial')::numeric, 0) > 0 THEN
      PERFORM internal.mover_stock(
        v_emp, v_id, 'entrada', 'ajuste_inventario',
        (p_payload->>'stock_inicial')::numeric, p_user_id, NULL,
        jsonb_build_object('costo_unitario', COALESCE(v_compra, 0),
                           'observaciones', 'Stock inicial al crear el producto'));
    END IF;
  ELSE
    UPDATE core.productos SET
      codigo_barras    = COALESCE(NULLIF(p_payload->>'codigo_barras',''), codigo_barras),
      nombre           = COALESCE(p_payload->>'nombre', nombre),
      descripcion      = COALESCE(p_payload->>'descripcion', descripcion),
      tipo             = COALESCE((p_payload->>'tipo')::core.tipo_producto, tipo),
      categoria_id     = COALESCE(NULLIF(p_payload->>'categoria_id','')::uuid, categoria_id),
      principio_activo = COALESCE(p_payload->>'principio_activo', principio_activo),
      laboratorio      = COALESCE(p_payload->>'laboratorio', laboratorio),
      presentacion     = COALESCE(p_payload->>'presentacion', presentacion),
      unidad_medida    = COALESCE(NULLIF(p_payload->>'unidad_medida',''), unidad_medida),
      requiere_receta  = COALESCE((p_payload->>'requiere_receta')::boolean, requiere_receta),
      controlado       = COALESCE((p_payload->>'controlado')::boolean, controlado),
      refrigerado      = COALESCE((p_payload->>'refrigerado')::boolean, refrigerado),
      precio_compra    = COALESCE(v_compra, precio_compra),
      precio_venta     = COALESCE(v_venta, precio_venta),
      margen_pct       = CASE WHEN COALESCE(v_compra, precio_compra) > 0
                         THEN round((COALESCE(v_venta, precio_venta) - COALESCE(v_compra, precio_compra))
                                    / COALESCE(v_compra, precio_compra) * 100, 2)
                         ELSE margen_pct END,
      afecto_igv       = COALESCE((p_payload->>'afecto_igv')::boolean, afecto_igv),
      stock_minimo     = COALESCE((p_payload->>'stock_minimo')::numeric, stock_minimo),
      stock_maximo     = COALESCE(NULLIF(p_payload->>'stock_maximo','')::numeric, stock_maximo),
      maneja_lotes     = COALESCE((p_payload->>'maneja_lotes')::boolean, maneja_lotes),
      estado           = COALESCE((p_payload->>'estado')::core.estado_generico, estado),
      updated_by       = p_user_id
    WHERE id = v_id AND deleted_at IS NULL;
  END IF;

  PERFORM internal.registrar_auditoria(p_user_id, v_emp, 'guardar', 'productos', v_id, NULL, p_payload);
  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('CONFLICT','Ya existe un producto con ese código','codigo'));
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_inventario_movimiento — entrada/salida/ajuste manual
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_inventario_movimiento(
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
  PERFORM internal.assert_permiso(p_user_id, 'inventario:mover');
  PERFORM internal.validar_payload(p_payload, ARRAY['producto_id','tipo','motivo','cantidad']);

  v_id := internal.mover_stock(
    v_emp,
    (p_payload->>'producto_id')::uuid,
    (p_payload->>'tipo')::core.tipo_movimiento_inventario,
    (p_payload->>'motivo')::core.motivo_movimiento,
    (p_payload->>'cantidad')::numeric,
    p_user_id,
    NULLIF(p_payload->>'almacen_id','')::uuid,
    jsonb_build_object(
      'costo_unitario',      p_payload->>'costo_unitario',
      'almacen_destino_id',  p_payload->>'almacen_destino_id',
      'lote_id',             p_payload->>'lote_id',
      'proveedor_id',        p_payload->>'proveedor_id',
      'cliente_id',          p_payload->>'cliente_id',
      'mascota_id',          p_payload->>'mascota_id',
      'observaciones',       p_payload->>'observaciones'));

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_movimientos_listar(
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
  v_size   INT     := LEAST(GREATEST(COALESCE(p_page_size, 50), 1), 200);
  v_page   INT     := GREATEST(COALESCE(p_page, 1), 1);
  v_total  INT;
  v_data   JSONB;
BEGIN
  SELECT count(*) INTO v_total
  FROM core.movimientos_inventario mv
  WHERE (v_global OR mv.empresa_id = v_emp)
    AND (p_filtros->>'producto_id' IS NULL OR mv.producto_id = (p_filtros->>'producto_id')::uuid)
    AND (p_filtros->>'tipo'   IS NULL OR mv.tipo::text = p_filtros->>'tipo')
    AND (p_filtros->>'motivo' IS NULL OR mv.motivo::text = p_filtros->>'motivo')
    AND (p_filtros->>'desde'  IS NULL OR mv.fecha >= (p_filtros->>'desde')::timestamptz)
    AND (p_filtros->>'hasta'  IS NULL OR mv.fecha <  (p_filtros->>'hasta')::timestamptz);

  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) INTO v_data
  FROM (
    SELECT mv.id, mv.tipo, mv.motivo, mv.cantidad, mv.costo_unitario,
           mv.saldo_despues, mv.fecha, mv.observaciones,
           mv.producto_id, pr.nombre AS producto, pr.codigo AS producto_codigo,
           pr.unidad_medida,
           al.nombre AS almacen,
           trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS usuario,
           m.nombre AS mascota,
           pv.razon_social AS proveedor
    FROM core.movimientos_inventario mv
    JOIN core.productos pr ON pr.id = mv.producto_id
    LEFT JOIN core.almacenes al ON al.id = mv.almacen_id
    LEFT JOIN core.users u ON u.id = mv.created_by
    LEFT JOIN core.mascotas m ON m.id = mv.mascota_id
    LEFT JOIN core.proveedores pv ON pv.id = mv.proveedor_id
    WHERE (v_global OR mv.empresa_id = v_emp)
      AND (p_filtros->>'producto_id' IS NULL OR mv.producto_id = (p_filtros->>'producto_id')::uuid)
      AND (p_filtros->>'tipo'   IS NULL OR mv.tipo::text = p_filtros->>'tipo')
      AND (p_filtros->>'motivo' IS NULL OR mv.motivo::text = p_filtros->>'motivo')
      AND (p_filtros->>'desde'  IS NULL OR mv.fecha >= (p_filtros->>'desde')::timestamptz)
      AND (p_filtros->>'hasta'  IS NULL OR mv.fecha <  (p_filtros->>'hasta')::timestamptz)
    ORDER BY mv.fecha DESC
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
-- app.fn_inventario_alertas — lo que exige acción hoy
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_inventario_alertas(
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
  v_emp UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
BEGIN
  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'stock_critico', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', p.id, 'codigo', p.codigo, 'nombre', p.nombre,
        'stock_actual', p.stock_actual, 'stock_minimo', p.stock_minimo,
        'unidad_medida', p.unidad_medida, 'tipo', p.tipo
      ) ORDER BY p.stock_actual), '[]'::jsonb)
      FROM core.productos p
      WHERE p.empresa_id = v_emp AND p.deleted_at IS NULL AND p.estado = 'activo'
        AND p.stock_actual <= p.stock_minimo),
    'por_vencer', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'lote_id', l.id, 'producto_id', p.id, 'producto', p.nombre,
        'numero_lote', l.numero_lote, 'fecha_vencimiento', l.fecha_vencimiento,
        'cantidad', l.cantidad,
        'dias_restantes', (l.fecha_vencimiento - CURRENT_DATE)
      ) ORDER BY l.fecha_vencimiento), '[]'::jsonb)
      FROM core.lotes l
      JOIN core.productos p ON p.id = l.producto_id
      WHERE l.empresa_id = v_emp AND l.cantidad > 0
        AND l.fecha_vencimiento IS NOT NULL
        AND l.fecha_vencimiento <= CURRENT_DATE + 90),
    'vencidos', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'lote_id', l.id, 'producto', p.nombre, 'numero_lote', l.numero_lote,
        'fecha_vencimiento', l.fecha_vencimiento, 'cantidad', l.cantidad
      ) ORDER BY l.fecha_vencimiento), '[]'::jsonb)
      FROM core.lotes l
      JOIN core.productos p ON p.id = l.producto_id
      WHERE l.empresa_id = v_emp AND l.cantidad > 0
        AND l.fecha_vencimiento < CURRENT_DATE)
  ));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_almacenes_listar(
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
  SELECT COALESCE(jsonb_agg(x ORDER BY x.es_principal DESC, x.nombre), '[]'::jsonb) INTO v_data
  FROM (
    SELECT a.id, a.codigo, a.nombre, a.ubicacion, a.es_principal, a.estado,
           (SELECT COALESCE(SUM(s.cantidad), 0) FROM core.stock s WHERE s.almacen_id = a.id) AS unidades,
           (SELECT count(DISTINCT s.producto_id) FROM core.stock s
             WHERE s.almacen_id = a.id AND s.cantidad > 0) AS productos
    FROM core.almacenes a WHERE a.empresa_id = v_emp
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_lote_registrar(
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
  PERFORM internal.assert_permiso(p_user_id, 'inventario:gestionar');
  PERFORM internal.validar_payload(p_payload, ARRAY['producto_id','numero_lote','cantidad']);

  INSERT INTO core.lotes (empresa_id, producto_id, numero_lote, fecha_vencimiento, cantidad, costo_unitario)
  VALUES (v_emp, (p_payload->>'producto_id')::uuid, p_payload->>'numero_lote',
          NULLIF(p_payload->>'fecha_vencimiento','')::date,
          0,  -- el movimiento de entrada es el que suma; así no se duplica
          COALESCE((p_payload->>'costo_unitario')::numeric, 0))
  ON CONFLICT (producto_id, numero_lote) DO UPDATE
    SET fecha_vencimiento = COALESCE(EXCLUDED.fecha_vencimiento, core.lotes.fecha_vencimiento),
        costo_unitario    = COALESCE(NULLIF(EXCLUDED.costo_unitario, 0), core.lotes.costo_unitario),
        updated_at = now()
  RETURNING id INTO v_id;

  PERFORM internal.mover_stock(
    v_emp, (p_payload->>'producto_id')::uuid, 'entrada', 'compra',
    (p_payload->>'cantidad')::numeric, p_user_id,
    NULLIF(p_payload->>'almacen_id','')::uuid,
    jsonb_build_object('lote_id', v_id,
                       'costo_unitario', p_payload->>'costo_unitario',
                       'proveedor_id', p_payload->>'proveedor_id',
                       'observaciones', 'Ingreso de lote ' || (p_payload->>'numero_lote')));

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_producto_eliminar(
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
  v_movs INT;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'inventario:gestionar');

  SELECT count(*) INTO v_movs FROM core.movimientos_inventario WHERE producto_id = p_id;
  IF v_movs > 0 THEN
    UPDATE core.productos SET estado = 'inactivo', updated_by = p_user_id WHERE id = p_id;
    RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
      'id', p_id, 'desactivado', true,
      'mensaje', 'El producto tiene movimientos de inventario: se desactivó para preservar el kardex.'));
  END IF;

  UPDATE core.productos SET deleted_at = now(), estado = 'inactivo', updated_by = p_user_id
   WHERE id = p_id AND deleted_at IS NULL;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'eliminado', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;
