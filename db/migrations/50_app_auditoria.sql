-- =============================================================================
-- 50_app_auditoria.sql — Bitácora y notificaciones internas
-- =============================================================================

SET search_path = app, internal, core, public;

CREATE OR REPLACE FUNCTION app.fn_auditoria_listar(
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
  PERFORM internal.assert_permiso(p_user_id, 'auditoria:ver');

  SELECT count(*) INTO v_total
  FROM core.audit_log a
  WHERE (v_global OR a.empresa_id = v_emp)
    AND (p_filtros->>'entidad' IS NULL OR a.entidad = p_filtros->>'entidad')
    AND (p_filtros->>'accion'  IS NULL OR a.accion = p_filtros->>'accion')
    AND (p_filtros->>'user_id' IS NULL OR a.user_id = (p_filtros->>'user_id')::uuid)
    AND (p_filtros->>'desde' IS NULL OR a.created_at >= (p_filtros->>'desde')::timestamptz)
    AND (p_filtros->>'hasta' IS NULL OR a.created_at <  (p_filtros->>'hasta')::timestamptz);

  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) INTO v_data
  FROM (
    SELECT a.id, a.accion, a.entidad, a.entidad_id, a.diff, a.ip, a.created_at,
           a.user_id,
           trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')) AS usuario,
           u.email AS usuario_email,
           e.nombre_comercial AS empresa
    FROM core.audit_log a
    LEFT JOIN core.users u ON u.id = a.user_id
    LEFT JOIN core.empresas e ON e.id = a.empresa_id
    WHERE (v_global OR a.empresa_id = v_emp)
      AND (p_filtros->>'entidad' IS NULL OR a.entidad = p_filtros->>'entidad')
      AND (p_filtros->>'accion'  IS NULL OR a.accion = p_filtros->>'accion')
      AND (p_filtros->>'user_id' IS NULL OR a.user_id = (p_filtros->>'user_id')::uuid)
      AND (p_filtros->>'desde' IS NULL OR a.created_at >= (p_filtros->>'desde')::timestamptz)
      AND (p_filtros->>'hasta' IS NULL OR a.created_at <  (p_filtros->>'hasta')::timestamptz)
    ORDER BY a.created_at DESC
    LIMIT v_size OFFSET (v_page - 1) * v_size
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data, 'meta', jsonb_build_object(
    'total', v_total, 'page', v_page, 'pageSize', v_size,
    'pages', GREATEST(CEIL(v_total::numeric / v_size)::int, 1)));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_notificaciones_listar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_solo_no_leidas BOOLEAN DEFAULT false,
  p_limit          INT DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_data JSONB;
  v_no_leidas INT;
BEGIN
  SELECT COALESCE(jsonb_agg(x ORDER BY x.created_at DESC), '[]'::jsonb) INTO v_data
  FROM (
    SELECT n.id, n.canal, n.titulo, n.cuerpo, n.url, n.entidad, n.entidad_id,
           n.leida_at, n.created_at
    FROM core.notificaciones n
    WHERE n.user_id = p_user_id
      AND (NOT p_solo_no_leidas OR n.leida_at IS NULL)
    ORDER BY n.created_at DESC
    LIMIT LEAST(COALESCE(p_limit, 30), 100)
  ) x;

  SELECT count(*) INTO v_no_leidas FROM core.notificaciones
   WHERE user_id = p_user_id AND leida_at IS NULL;

  RETURN jsonb_build_object('ok', true, 'data', v_data,
    'meta', jsonb_build_object('no_leidas', v_no_leidas));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_notificacion_marcar_leida(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_id             UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_n INT;
BEGIN
  -- Sin id: marca todas las del usuario (botón "marcar todo como leído")
  UPDATE core.notificaciones SET leida_at = now()
   WHERE user_id = p_user_id AND leida_at IS NULL
     AND (p_id IS NULL OR id = p_id);

  GET DIAGNOSTICS v_n = ROW_COUNT;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('marcadas', v_n));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;
