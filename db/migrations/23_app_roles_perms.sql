-- =============================================================================
-- 23_app_roles_perms.sql — Roles y permisos
-- =============================================================================

SET search_path = app, internal, core, public;

CREATE OR REPLACE FUNCTION app.fn_roles_listar(
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
  v_data JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(x ORDER BY x.scope, x.nombre), '[]'::jsonb) INTO v_data
  FROM (
    SELECT r.id, r.codigo, r.nombre, r.descripcion, r.scope, r.is_sistema,
           (SELECT count(*) FROM core.users u WHERE u.rol_id = r.id AND u.deleted_at IS NULL) AS usuarios,
           (SELECT COALESCE(jsonb_agg(p.codigo ORDER BY p.codigo), '[]'::jsonb)
              FROM core.rol_permisos rp
              JOIN core.permisos p ON p.id = rp.permiso_id
             WHERE rp.rol_id = r.id) AS permisos
    FROM core.roles r
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.fn_permisos_listar(
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
  v_data JSONB;
BEGIN
  -- Agrupado por módulo: así la UI arma la matriz de permisos directamente.
  SELECT COALESCE(jsonb_agg(x ORDER BY x.modulo), '[]'::jsonb) INTO v_data
  FROM (
    SELECT p.modulo,
           jsonb_agg(jsonb_build_object(
             'id', p.id, 'codigo', p.codigo, 'accion', p.accion, 'descripcion', p.descripcion
           ) ORDER BY p.accion) AS permisos
    FROM core.permisos p
    GROUP BY p.modulo
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_rol_crear(
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
  IF NOT p_is_super_admin THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('FORBIDDEN','Solo un super administrador gestiona roles'));
  END IF;

  PERFORM internal.validar_payload(p_payload, ARRAY['codigo','nombre']);

  INSERT INTO core.roles (codigo, nombre, descripcion, scope)
  VALUES (p_payload->>'codigo', p_payload->>'nombre', p_payload->>'descripcion',
          COALESCE((p_payload->>'scope')::core.scope_rol, 'empresa'))
  RETURNING id INTO v_id;

  PERFORM internal.registrar_auditoria(p_user_id, NULL, 'crear', 'roles', v_id, NULL, p_payload);
  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('CONFLICT','Ya existe un rol con ese código','codigo'));
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_rol_set_permisos — reemplaza el set completo de permisos del rol
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_rol_set_permisos(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_rol_id         UUID,
  p_codigos        JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_is_sistema BOOLEAN;
  v_total      INT;
BEGIN
  IF NOT p_is_super_admin THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('FORBIDDEN','Solo un super administrador gestiona permisos'));
  END IF;

  SELECT is_sistema INTO v_is_sistema FROM core.roles WHERE id = p_rol_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Rol no encontrado'));
  END IF;

  DELETE FROM core.rol_permisos WHERE rol_id = p_rol_id;

  INSERT INTO core.rol_permisos (rol_id, permiso_id)
  SELECT p_rol_id, p.id
  FROM core.permisos p
  WHERE p.codigo IN (SELECT jsonb_array_elements_text(p_codigos));

  GET DIAGNOSTICS v_total = ROW_COUNT;

  PERFORM internal.registrar_auditoria(
    p_user_id, NULL, 'set_permisos', 'roles', p_rol_id, NULL,
    jsonb_build_object('permisos', p_codigos));

  RETURN jsonb_build_object('ok', true,
    'data', jsonb_build_object('rol_id', p_rol_id, 'permisos_asignados', v_total));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_rol_eliminar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_rol_id         UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_usuarios INT;
  v_sistema  BOOLEAN;
BEGIN
  IF NOT p_is_super_admin THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('FORBIDDEN','Solo un super administrador gestiona roles'));
  END IF;

  SELECT is_sistema INTO v_sistema FROM core.roles WHERE id = p_rol_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Rol no encontrado'));
  END IF;

  IF v_sistema THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE','Los roles del sistema no se pueden eliminar'));
  END IF;

  SELECT count(*) INTO v_usuarios FROM core.users WHERE rol_id = p_rol_id AND deleted_at IS NULL;
  IF v_usuarios > 0 THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        format('El rol tiene %s usuario(s) asignado(s). Reasígnalos antes de eliminarlo.', v_usuarios)));
  END IF;

  DELETE FROM core.roles WHERE id = p_rol_id;
  PERFORM internal.registrar_auditoria(p_user_id, NULL, 'eliminar', 'roles', p_rol_id);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('eliminado', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;
