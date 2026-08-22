-- =============================================================================
-- 41_app_reportes.sql — Reportes ejecutivos y operativos
-- =============================================================================

SET search_path = app, internal, core, public;

-- -----------------------------------------------------------------------------
-- app.fn_reporte_ventas — ventas por periodo, servicio y forma de pago
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_reporte_ventas(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_desde          DATE,
  p_hasta          DATE
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
BEGIN
  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'periodo', jsonb_build_object('desde', p_desde, 'hasta', p_hasta),

    'resumen', (
      SELECT jsonb_build_object(
        'facturado',  COALESCE(SUM(c.total), 0),
        'subtotal',   COALESCE(SUM(c.subtotal), 0),
        'igv',        COALESCE(SUM(c.igv), 0),
        'cobrado',    COALESCE(SUM(c.total - c.saldo_pendiente), 0),
        'pendiente',  COALESCE(SUM(c.saldo_pendiente), 0),
        'documentos', count(*),
        'ticket_promedio', CASE WHEN count(*) > 0
                           THEN round(COALESCE(SUM(c.total),0) / count(*), 2) ELSE 0 END)
      FROM core.comprobantes c
      WHERE (v_global OR c.empresa_id = v_emp)
        AND c.deleted_at IS NULL AND c.anulado_at IS NULL
        AND c.fecha_emision::date BETWEEN p_desde AND p_hasta),

    'por_tipo', (
      SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) FROM (
        SELECT c.tipo, count(*) AS documentos, COALESCE(SUM(c.total), 0) AS total
        FROM core.comprobantes c
        WHERE (v_global OR c.empresa_id = v_emp)
          AND c.deleted_at IS NULL AND c.anulado_at IS NULL
          AND c.fecha_emision::date BETWEEN p_desde AND p_hasta
        GROUP BY c.tipo ORDER BY total DESC) t),

    'por_metodo_pago', (
      SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) FROM (
        SELECT pg.metodo, count(*) AS operaciones, COALESCE(SUM(pg.monto), 0) AS total
        FROM core.pagos pg
        WHERE (v_global OR pg.empresa_id = v_emp) AND pg.anulado_at IS NULL
          AND pg.fecha_pago::date BETWEEN p_desde AND p_hasta
        GROUP BY pg.metodo ORDER BY total DESC) t),

    'por_servicio', (
      SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) FROM (
        SELECT s.nombre AS servicio, s.tipo, count(*) AS veces,
               COALESCE(SUM(os.total), 0) AS ingresos
        FROM core.ordenes_servicio os
        JOIN core.servicios s ON s.id = os.servicio_id
        WHERE (v_global OR os.empresa_id = v_emp) AND os.estado <> 'anulado'
          AND os.fecha::date BETWEEN p_desde AND p_hasta
        GROUP BY s.nombre, s.tipo ORDER BY ingresos DESC) t),

    'por_veterinario', (
      SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) FROM (
        SELECT trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS veterinario,
               count(*) AS atenciones, COALESCE(SUM(os.total), 0) AS ingresos
        FROM core.ordenes_servicio os
        JOIN core.users u ON u.id = os.veterinario_id
        WHERE (v_global OR os.empresa_id = v_emp) AND os.estado <> 'anulado'
          AND os.fecha::date BETWEEN p_desde AND p_hasta
        GROUP BY u.id, u.nombres, u.apellido_paterno
        ORDER BY ingresos DESC) t),

    'serie_diaria', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'fecha', d::date,
        'facturado', (SELECT COALESCE(SUM(c.total), 0) FROM core.comprobantes c
                       WHERE (v_global OR c.empresa_id = v_emp)
                         AND c.deleted_at IS NULL AND c.anulado_at IS NULL
                         AND c.fecha_emision::date = d::date),
        'cobrado', (SELECT COALESCE(SUM(pg.monto), 0) FROM core.pagos pg
                     WHERE (v_global OR pg.empresa_id = v_emp) AND pg.anulado_at IS NULL
                       AND pg.fecha_pago::date = d::date)
      ) ORDER BY d), '[]'::jsonb)
      FROM generate_series(p_desde, p_hasta, '1 day'::interval) d)
  ));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_reporte_clinico — producción clínica del periodo
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_reporte_clinico(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_desde          DATE,
  p_hasta          DATE
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
BEGIN
  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'periodo', jsonb_build_object('desde', p_desde, 'hasta', p_hasta),

    'resumen', jsonb_build_object(
      'consultas', (SELECT count(*) FROM core.consultas c
                     WHERE (v_global OR c.empresa_id = v_emp) AND c.deleted_at IS NULL
                       AND c.fecha::date BETWEEN p_desde AND p_hasta),
      'cirugias',  (SELECT count(*) FROM core.cirugias ci
                     WHERE (v_global OR ci.empresa_id = v_emp) AND ci.estado = 'realizada'
                       AND ci.fecha_inicio::date BETWEEN p_desde AND p_hasta),
      'vacunas',   (SELECT count(*) FROM core.vacunas v
                     WHERE (v_global OR v.empresa_id = v_emp)
                       AND v.fecha_aplicacion BETWEEN p_desde AND p_hasta),
      'desparasitaciones', (SELECT count(*) FROM core.desparasitaciones d
                             WHERE (v_global OR d.empresa_id = v_emp)
                               AND d.fecha_aplicacion BETWEEN p_desde AND p_hasta),
      'hospitalizaciones', (SELECT count(*) FROM core.hospitalizaciones h
                             WHERE (v_global OR h.empresa_id = v_emp)
                               AND h.fecha_ingreso::date BETWEEN p_desde AND p_hasta),
      'examenes',  (SELECT count(*) FROM core.examenes e
                     WHERE (v_global OR e.empresa_id = v_emp)
                       AND e.fecha_solicitud::date BETWEEN p_desde AND p_hasta)),

    -- Motivos de consulta más frecuentes: dice qué está entrando por la puerta
    'diagnosticos_frecuentes', (
      SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) FROM (
        SELECT left(c.diagnostico, 80) AS diagnostico, count(*) AS casos
        FROM core.consultas c
        WHERE (v_global OR c.empresa_id = v_emp) AND c.deleted_at IS NULL
          AND c.fecha::date BETWEEN p_desde AND p_hasta
          AND COALESCE(trim(c.diagnostico), '') <> ''
        GROUP BY left(c.diagnostico, 80)
        ORDER BY casos DESC LIMIT 15) t),

    'por_especie', (
      SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) FROM (
        SELECT e.nombre AS especie, count(*) AS atenciones
        FROM core.consultas c
        JOIN core.mascotas m ON m.id = c.mascota_id
        JOIN core.especies e ON e.id = m.especie_id
        WHERE (v_global OR c.empresa_id = v_emp) AND c.deleted_at IS NULL
          AND c.fecha::date BETWEEN p_desde AND p_hasta
        GROUP BY e.nombre ORDER BY atenciones DESC) t),

    'citas', (
      SELECT jsonb_build_object(
        'total',       count(*),
        'completadas', count(*) FILTER (WHERE c.estado = 'completada'),
        'canceladas',  count(*) FILTER (WHERE c.estado = 'cancelada'),
        'no_asistio',  count(*) FILTER (WHERE c.estado = 'no_asistio'),
        'tasa_asistencia', CASE WHEN count(*) > 0
          THEN round(100.0 * count(*) FILTER (WHERE c.estado = 'completada') / count(*), 1)
          ELSE 0 END)
      FROM core.citas c
      WHERE (v_global OR c.empresa_id = v_emp) AND c.deleted_at IS NULL
        AND c.fecha_hora::date BETWEEN p_desde AND p_hasta)
  ));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_reporte_inventario — valorización y rotación
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_reporte_inventario(
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
BEGIN
  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'periodo', jsonb_build_object('desde', v_desde, 'hasta', v_hasta),

    'valorizacion', (
      SELECT jsonb_build_object(
        'productos',      count(*),
        'unidades',       COALESCE(SUM(p.stock_actual), 0),
        'valor_compra',   COALESCE(SUM(p.stock_actual * p.precio_compra), 0),
        'valor_venta',    COALESCE(SUM(p.stock_actual * p.precio_venta), 0),
        'criticos',       count(*) FILTER (WHERE p.stock_actual <= p.stock_minimo),
        'agotados',       count(*) FILTER (WHERE p.stock_actual <= 0))
      FROM core.productos p
      WHERE p.empresa_id = v_emp AND p.deleted_at IS NULL AND p.estado = 'activo'),

    'por_tipo', (
      SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) FROM (
        SELECT p.tipo, count(*) AS productos,
               COALESCE(SUM(p.stock_actual), 0) AS unidades,
               COALESCE(SUM(p.stock_actual * p.precio_compra), 0) AS valor
        FROM core.productos p
        WHERE p.empresa_id = v_emp AND p.deleted_at IS NULL AND p.estado = 'activo'
        GROUP BY p.tipo ORDER BY valor DESC) t),

    -- Más consumidos: lo que hay que tener siempre en stock
    'mas_consumidos', (
      SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) FROM (
        SELECT p.nombre AS producto, p.codigo, p.unidad_medida,
               COALESCE(SUM(mv.cantidad), 0) AS salidas,
               p.stock_actual, p.stock_minimo
        FROM core.movimientos_inventario mv
        JOIN core.productos p ON p.id = mv.producto_id
        WHERE mv.empresa_id = v_emp
          AND mv.tipo = 'salida'
          AND mv.fecha::date BETWEEN v_desde AND v_hasta
        GROUP BY p.id, p.nombre, p.codigo, p.unidad_medida, p.stock_actual, p.stock_minimo
        ORDER BY salidas DESC LIMIT 20) t),

    'movimientos', (
      SELECT jsonb_build_object(
        'entradas', COALESCE(SUM(mv.cantidad) FILTER (WHERE mv.tipo = 'entrada'), 0),
        'salidas',  COALESCE(SUM(mv.cantidad) FILTER (WHERE mv.tipo = 'salida'), 0),
        'mermas',   COALESCE(SUM(mv.cantidad) FILTER (WHERE mv.tipo IN ('merma','vencimiento')), 0),
        'ajustes',  COALESCE(SUM(mv.cantidad) FILTER (
                      WHERE mv.tipo IN ('ajuste_positivo','ajuste_negativo')), 0))
      FROM core.movimientos_inventario mv
      WHERE mv.empresa_id = v_emp AND mv.fecha::date BETWEEN v_desde AND v_hasta)
  ));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_reporte_ejecutivo — la foto que mira gerencia
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_reporte_ejecutivo(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_desde          DATE,
  p_hasta          DATE
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
BEGIN
  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'periodo', jsonb_build_object('desde', p_desde, 'hasta', p_hasta),

    -- Comparativo entre sedes (solo aporta con acceso global)
    'por_sede', (
      SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) FROM (
        SELECT e.id, e.nombre_comercial AS sede, e.razon_social,
               (SELECT count(*) FROM core.citas c
                 WHERE c.empresa_id = e.id AND c.deleted_at IS NULL
                   AND c.fecha_hora::date BETWEEN p_desde AND p_hasta) AS citas,
               (SELECT COALESCE(SUM(cp.total), 0) FROM core.comprobantes cp
                 WHERE cp.empresa_id = e.id AND cp.deleted_at IS NULL
                   AND cp.anulado_at IS NULL
                   AND cp.fecha_emision::date BETWEEN p_desde AND p_hasta) AS facturado,
               (SELECT COALESCE(SUM(cp.saldo_pendiente), 0) FROM core.comprobantes cp
                 WHERE cp.empresa_id = e.id AND cp.deleted_at IS NULL
                   AND cp.anulado_at IS NULL AND cp.saldo_pendiente > 0) AS por_cobrar,
               (SELECT count(*) FROM core.users u
                 WHERE u.empresa_id = e.id AND u.deleted_at IS NULL
                   AND u.estado = 'activo') AS personal
        FROM core.empresas e
        WHERE e.deleted_at IS NULL AND (v_global OR e.id = v_emp)
        ORDER BY facturado DESC) t),

    -- Clientes que más facturan
    'top_clientes', (
      SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) FROM (
        SELECT trim(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'')) AS cliente,
               cl.numero_documento, count(*) AS documentos,
               COALESCE(SUM(c.total), 0) AS facturado,
               (SELECT count(*) FROM core.mascotas m
                 WHERE m.cliente_id = cl.id AND m.deleted_at IS NULL) AS mascotas
        FROM core.comprobantes c
        JOIN core.clientes cl ON cl.id = c.cliente_id
        WHERE (v_global OR c.empresa_id = v_emp)
          AND c.deleted_at IS NULL AND c.anulado_at IS NULL
          AND c.fecha_emision::date BETWEEN p_desde AND p_hasta
        GROUP BY cl.id, cl.nombres, cl.apellido_paterno, cl.numero_documento
        ORDER BY facturado DESC LIMIT 15) t),

    -- Rentabilidad aproximada: ingreso vs. costo de lo consumido
    'margen', (
      SELECT jsonb_build_object(
        'ingresos', COALESCE((SELECT SUM(c.total) FROM core.comprobantes c
                               WHERE (v_global OR c.empresa_id = v_emp)
                                 AND c.deleted_at IS NULL AND c.anulado_at IS NULL
                                 AND c.fecha_emision::date BETWEEN p_desde AND p_hasta), 0),
        'costo_insumos', COALESCE((SELECT SUM(mv.cantidad * mv.costo_unitario)
                                     FROM core.movimientos_inventario mv
                                    WHERE mv.empresa_id = v_emp AND mv.tipo = 'salida'
                                      AND mv.fecha::date BETWEEN p_desde AND p_hasta), 0),
        'compras', COALESCE((SELECT SUM(oc.total) FROM core.ordenes_compra oc
                              WHERE oc.empresa_id = v_emp AND oc.deleted_at IS NULL
                                AND oc.estado NOT IN ('borrador','cancelada')
                                AND oc.fecha_emision BETWEEN p_desde AND p_hasta), 0)))
  ));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;
