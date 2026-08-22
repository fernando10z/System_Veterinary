-- =============================================================================
-- 40_app_dashboard.sql — Panel de control de la sede
-- =============================================================================

SET search_path = app, internal, core, public;

CREATE OR REPLACE FUNCTION app.fn_dashboard_resumen(
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
  v_global BOOLEAN := internal.es_acceso_global(p_user_id, p_is_super_admin);
  v_emp    UUID    := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_desde  DATE    := COALESCE(p_desde, date_trunc('month', CURRENT_DATE)::date);
  v_hasta  DATE    := COALESCE(p_hasta, CURRENT_DATE);
  -- Mismo número de días hacia atrás, para comparar contra el periodo anterior
  v_dias   INT     := GREATEST((v_hasta - v_desde) + 1, 1);
  v_prev_d DATE    := v_desde - v_dias;
  v_prev_h DATE    := v_desde - 1;
BEGIN
  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(

    'periodo', jsonb_build_object('desde', v_desde, 'hasta', v_hasta, 'dias', v_dias),

    -- ---- Agenda de hoy ----
    'hoy', (
      SELECT jsonb_build_object(
        'citas',       count(*),
        'completadas', count(*) FILTER (WHERE c.estado = 'completada'),
        'en_espera',   count(*) FILTER (WHERE c.estado = 'en_espera'),
        'en_atencion', count(*) FILTER (WHERE c.estado = 'en_atencion'),
        'pendientes',  count(*) FILTER (WHERE c.estado IN ('programada','confirmada')),
        'urgencias',   count(*) FILTER (WHERE c.prioridad IN ('urgencia','emergencia')))
      FROM core.citas c
      WHERE (v_global OR c.empresa_id = v_emp) AND c.deleted_at IS NULL
        AND c.fecha_hora::date = CURRENT_DATE),

    -- ---- Ingresos del periodo, con comparativo ----
    'ingresos', (
      SELECT jsonb_build_object(
        'facturado', COALESCE(SUM(cp.total), 0),
        'cobrado',   COALESCE(SUM(cp.total - cp.saldo_pendiente), 0),
        'pendiente', COALESCE(SUM(cp.saldo_pendiente), 0),
        'documentos', count(*),
        'ticket_promedio', CASE WHEN count(*) > 0
                           THEN round(COALESCE(SUM(cp.total),0) / count(*), 2) ELSE 0 END)
      FROM core.comprobantes cp
      WHERE (v_global OR cp.empresa_id = v_emp)
        AND cp.deleted_at IS NULL AND cp.anulado_at IS NULL
        AND cp.fecha_emision::date BETWEEN v_desde AND v_hasta),

    'ingresos_periodo_anterior', (
      SELECT COALESCE(SUM(cp.total), 0)
      FROM core.comprobantes cp
      WHERE (v_global OR cp.empresa_id = v_emp)
        AND cp.deleted_at IS NULL AND cp.anulado_at IS NULL
        AND cp.fecha_emision::date BETWEEN v_prev_d AND v_prev_h),

    -- ---- Actividad clínica ----
    'clinico', (
      SELECT jsonb_build_object(
        'consultas',   (SELECT count(*) FROM core.consultas co
                         WHERE (v_global OR co.empresa_id = v_emp) AND co.deleted_at IS NULL
                           AND co.fecha::date BETWEEN v_desde AND v_hasta),
        'cirugias',    (SELECT count(*) FROM core.cirugias ci
                         WHERE (v_global OR ci.empresa_id = v_emp) AND ci.estado = 'realizada'
                           AND ci.fecha_inicio::date BETWEEN v_desde AND v_hasta),
        'vacunas',     (SELECT count(*) FROM core.vacunas v
                         WHERE (v_global OR v.empresa_id = v_emp)
                           AND v.fecha_aplicacion BETWEEN v_desde AND v_hasta),
        'hospitalizados', (SELECT count(*) FROM core.hospitalizaciones h
                            WHERE (v_global OR h.empresa_id = v_emp)
                              AND h.estado IN ('ingresado','en_observacion')))),

    -- ---- Pacientes y clientes ----
    'pacientes', (
      SELECT jsonb_build_object(
        'total_activos', (SELECT count(*) FROM core.mascotas m
                           WHERE m.deleted_at IS NULL AND m.estado = 'activo'),
        'nuevos',        (SELECT count(*) FROM core.mascotas m
                           WHERE m.deleted_at IS NULL
                             AND m.created_at::date BETWEEN v_desde AND v_hasta),
        'clientes_activos', (SELECT count(*) FROM core.clientes c
                              WHERE c.deleted_at IS NULL AND c.estado = 'activo'),
        'clientes_nuevos',  (SELECT count(*) FROM core.clientes c
                              WHERE c.deleted_at IS NULL
                                AND c.created_at::date BETWEEN v_desde AND v_hasta))),

    -- ---- Alertas que exigen acción ----
    'alertas', jsonb_build_object(
      'stock_critico', (SELECT count(*) FROM core.productos p
                         WHERE p.empresa_id = v_emp AND p.deleted_at IS NULL
                           AND p.estado = 'activo' AND p.stock_actual <= p.stock_minimo),
      'por_vencer',    (SELECT count(*) FROM core.lotes l
                         WHERE l.empresa_id = v_emp AND l.cantidad > 0
                           AND l.fecha_vencimiento BETWEEN CURRENT_DATE AND CURRENT_DATE + 90),
      'refuerzos_pendientes', (SELECT count(*) FROM core.vacunas v
                                WHERE (v_global OR v.empresa_id = v_emp)
                                  AND v.proximo_refuerzo BETWEEN CURRENT_DATE AND CURRENT_DATE + 30),
      'deuda_vencida', (SELECT COALESCE(SUM(cp.saldo_pendiente), 0) FROM core.comprobantes cp
                         WHERE (v_global OR cp.empresa_id = v_emp)
                           AND cp.deleted_at IS NULL AND cp.anulado_at IS NULL
                           AND cp.saldo_pendiente > 0 AND cp.fecha_vencimiento < CURRENT_DATE),
      'permisos_pendientes', (SELECT count(*) FROM core.permisos_laborales pl
                               WHERE pl.empresa_id = v_emp AND pl.estado = 'pendiente')),

    -- ---- Serie diaria para el gráfico ----
    'serie_diaria', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'fecha', d::date,
        'citas', (SELECT count(*) FROM core.citas c
                   WHERE (v_global OR c.empresa_id = v_emp) AND c.deleted_at IS NULL
                     AND c.fecha_hora::date = d::date),
        'ingresos', (SELECT COALESCE(SUM(cp.total), 0) FROM core.comprobantes cp
                      WHERE (v_global OR cp.empresa_id = v_emp)
                        AND cp.deleted_at IS NULL AND cp.anulado_at IS NULL
                        AND cp.fecha_emision::date = d::date)
      ) ORDER BY d), '[]'::jsonb)
      FROM generate_series(v_desde, v_hasta, '1 day'::interval) d),

    -- ---- Top servicios del periodo ----
    'top_servicios', (
      SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) FROM (
        SELECT s.nombre, s.tipo, count(*) AS veces,
               COALESCE(SUM(os.total), 0) AS ingresos
        FROM core.ordenes_servicio os
        JOIN core.servicios s ON s.id = os.servicio_id
        WHERE (v_global OR os.empresa_id = v_emp)
          AND os.fecha::date BETWEEN v_desde AND v_hasta
          AND os.estado <> 'anulado'
        GROUP BY s.nombre, s.tipo
        ORDER BY ingresos DESC
        LIMIT 8) t),

    -- ---- Distribución por especie ----
    'por_especie', (
      SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) FROM (
        SELECT e.nombre AS especie, e.icono, count(*) AS pacientes
        FROM core.mascotas m
        JOIN core.especies e ON e.id = m.especie_id
        WHERE m.deleted_at IS NULL AND m.estado = 'activo'
        GROUP BY e.nombre, e.icono
        ORDER BY pacientes DESC) t)
  ));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_dashboard_recordatorios — la cola de contactos del día
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_recordatorios_listar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_dias           INT DEFAULT 7
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
  SELECT COALESCE(jsonb_agg(x ORDER BY x.fecha_objetivo), '[]'::jsonb) INTO v_data
  FROM (
    SELECT r.id, r.tipo, r.titulo, r.mensaje, r.fecha_objetivo, r.canal,
           r.enviado_at, r.completado,
           (r.fecha_objetivo - CURRENT_DATE) AS dias_restantes,
           r.cliente_id,
           trim(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'')) AS cliente,
           cl.telefono AS cliente_telefono, cl.correo AS cliente_correo,
           r.mascota_id, m.nombre AS mascota, m.foto_url AS mascota_foto
    FROM core.recordatorios r
    JOIN core.clientes cl ON cl.id = r.cliente_id
    LEFT JOIN core.mascotas m ON m.id = r.mascota_id
    WHERE r.empresa_id = v_emp AND r.completado = false
      AND r.fecha_objetivo <= CURRENT_DATE + COALESCE(p_dias, 7)
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_recordatorio_completar(
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
BEGIN
  UPDATE core.recordatorios SET completado = true, enviado_at = COALESCE(enviado_at, now())
   WHERE id = p_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Recordatorio no encontrado'));
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'completado', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;
