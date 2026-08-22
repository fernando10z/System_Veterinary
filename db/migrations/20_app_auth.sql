-- =============================================================================
-- 20_app_auth.sql — Autenticación e identidad
--
-- Convención de TODOS los SPs de app.*:
--   · Devuelven JSONB {ok, data?, error?, meta?}
--   · Nunca lanzan al backend: capturan con EXCEPTION WHEN OTHERS
--   · Los de contexto reciben (p_user_id, p_empresa_id, p_is_super_admin, …)
-- =============================================================================

SET search_path = app, internal, core, public;

-- -----------------------------------------------------------------------------
-- app.sp_auth_login
-- El hash bcrypt se compara EN LA BASE con pgcrypto crypt(): el backend nunca ve
-- el hash almacenado. Bloquea la cuenta 15 min tras 5 intentos fallidos.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_auth_login(
  p_email    VARCHAR,
  p_password TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_user     RECORD;
  v_rol      JSONB;
  v_permisos JSONB;
  v_empresa  JSONB;
BEGIN
  SELECT u.* INTO v_user
  FROM core.users u
  WHERE lower(u.email) = lower(p_email) AND u.deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('UNAUTHORIZED','Credenciales inválidas'));
  END IF;

  IF v_user.estado <> 'activo' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('FORBIDDEN','La cuenta no está activa'));
  END IF;

  IF v_user.bloqueado_hasta IS NOT NULL AND v_user.bloqueado_hasta > now() THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('FORBIDDEN',
        'Cuenta bloqueada temporalmente por intentos fallidos. Intenta en unos minutos.'));
  END IF;

  IF v_user.password_hash IS DISTINCT FROM crypt(p_password, v_user.password_hash) THEN
    UPDATE core.users
       SET intentos_fallidos = intentos_fallidos + 1,
           bloqueado_hasta = CASE
             WHEN intentos_fallidos + 1 >= 5 THEN now() + INTERVAL '15 minutes'
             ELSE bloqueado_hasta END,
           updated_at = now()
     WHERE id = v_user.id;
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('UNAUTHORIZED','Credenciales inválidas'));
  END IF;

  UPDATE core.users
     SET intentos_fallidos = 0, bloqueado_hasta = NULL,
         ultimo_login_at = now(), updated_at = now()
   WHERE id = v_user.id;

  SELECT to_jsonb(r) INTO v_rol FROM core.roles r WHERE r.id = v_user.rol_id;

  SELECT COALESCE(jsonb_agg(p.codigo ORDER BY p.codigo), '[]'::jsonb) INTO v_permisos
  FROM core.rol_permisos rp
  JOIN core.permisos p ON p.id = rp.permiso_id
  WHERE rp.rol_id = v_user.rol_id;

  IF v_user.empresa_id IS NOT NULL THEN
    SELECT to_jsonb(e) - 'pse_password_enc' INTO v_empresa
    FROM core.empresas e WHERE e.id = v_user.empresa_id;
  END IF;

  PERFORM internal.registrar_auditoria(
    v_user.id, v_user.empresa_id, 'login', 'users', v_user.id);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'user', jsonb_build_object(
      'id',                   v_user.id,
      'codigo',               v_user.codigo,
      'email',                v_user.email,
      'nombres',              v_user.nombres,
      'apellido_paterno',     v_user.apellido_paterno,
      'apellido_materno',     v_user.apellido_materno,
      'telefono',             v_user.telefono,
      'foto_url',             v_user.foto_url,
      'is_super_admin',       v_user.is_super_admin,
      'empresa_id',           v_user.empresa_id,
      'es_veterinario',       v_user.es_veterinario,
      'colegiatura',          v_user.colegiatura,
      'must_change_password', v_user.must_change_password
    ),
    'rol',      v_rol,
    'permisos', v_permisos,
    'empresa',  v_empresa
  ));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_auth_perfil — datos frescos del usuario autenticado (refresh de sesión)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_auth_perfil(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_user     RECORD;
  v_rol      JSONB;
  v_permisos JSONB;
  v_empresa  JSONB;
BEGIN
  SELECT u.* INTO v_user FROM core.users u
   WHERE u.id = p_user_id AND u.deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Usuario no encontrado'));
  END IF;

  SELECT to_jsonb(r) INTO v_rol FROM core.roles r WHERE r.id = v_user.rol_id;

  SELECT COALESCE(jsonb_agg(p.codigo ORDER BY p.codigo), '[]'::jsonb) INTO v_permisos
  FROM core.rol_permisos rp
  JOIN core.permisos p ON p.id = rp.permiso_id
  WHERE rp.rol_id = v_user.rol_id;

  IF v_user.empresa_id IS NOT NULL THEN
    SELECT to_jsonb(e) - 'pse_password_enc' INTO v_empresa
    FROM core.empresas e WHERE e.id = v_user.empresa_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'user', to_jsonb(v_user) - 'password_hash' - 'password_reset_token',
    'rol', v_rol, 'permisos', v_permisos, 'empresa', v_empresa
  ));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_auth_cambiar_password
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_auth_cambiar_password(
  p_user_id         UUID,
  p_empresa_id      UUID,
  p_is_super_admin  BOOLEAN,
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
  SELECT password_hash INTO v_hash FROM core.users WHERE id = p_user_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Usuario no encontrado'));
  END IF;

  IF v_hash IS DISTINCT FROM crypt(p_password_actual, v_hash) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('FORBIDDEN','La contraseña actual es incorrecta','password_actual'));
  END IF;

  IF length(p_password_nuevo) < 8 THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'La contraseña nueva debe tener al menos 8 caracteres','password_nuevo'));
  END IF;

  UPDATE core.users
     SET password_hash = crypt(p_password_nuevo, gen_salt('bf', 10)),
         must_change_password = false,
         password_reset_token = NULL, password_reset_expires = NULL,
         updated_at = now(), updated_by = p_user_id
   WHERE id = p_user_id;

  PERFORM internal.registrar_auditoria(
    p_user_id, p_empresa_id, 'cambio_password', 'users', p_user_id);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('updated', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_auth_solicitar_reset
-- No revela si el correo existe: responde siempre ok.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_auth_solicitar_reset(p_email VARCHAR)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_user_id UUID;
  v_token   VARCHAR(64);
BEGIN
  SELECT id INTO v_user_id FROM core.users
   WHERE lower(email) = lower(p_email) AND deleted_at IS NULL AND estado = 'activo';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true,
      'data', jsonb_build_object('enviado', true, 'token', NULL));
  END IF;

  v_token := encode(gen_random_bytes(24), 'hex');

  UPDATE core.users
     SET password_reset_token = v_token,
         password_reset_expires = now() + INTERVAL '1 hour',
         updated_at = now()
   WHERE id = v_user_id;

  -- El backend usa el token para armar el enlace y enviar el correo.
  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'enviado', true, 'token', v_token, 'user_id', v_user_id, 'email', p_email));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_auth_reset_password — consume el token del correo
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_auth_reset_password(
  p_token          VARCHAR,
  p_password_nuevo TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  IF length(p_password_nuevo) < 8 THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'La contraseña debe tener al menos 8 caracteres','password'));
  END IF;

  SELECT id INTO v_user_id FROM core.users
   WHERE password_reset_token = p_token
     AND password_reset_expires > now()
     AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('FORBIDDEN','El enlace es inválido o ya expiró'));
  END IF;

  UPDATE core.users
     SET password_hash = crypt(p_password_nuevo, gen_salt('bf', 10)),
         password_reset_token = NULL, password_reset_expires = NULL,
         must_change_password = false,
         intentos_fallidos = 0, bloqueado_hasta = NULL,
         updated_at = now()
   WHERE id = v_user_id;

  PERFORM internal.registrar_auditoria(v_user_id, NULL, 'reset_password', 'users', v_user_id);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('updated', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_portal_login — acceso del PROPIETARIO al portal (no es staff)
-- Emite un contexto separado: el backend firma un JWT con type=portal.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_portal_login(
  p_documento VARCHAR,
  p_password  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_cli RECORD;
BEGIN
  -- El documento es único por empresa, así que la misma persona puede existir
  -- en varias. Se toma la primera cuyo password coincida más abajo; en la
  -- práctica solo una empresa le habilita el portal.
  SELECT c.* INTO v_cli FROM core.clientes c
   WHERE (c.numero_documento = p_documento OR lower(c.correo) = lower(p_documento))
     AND c.portal_acceso = true
     AND c.deleted_at IS NULL
   ORDER BY c.portal_ultimo_login_at DESC NULLS LAST, c.created_at
   LIMIT 1;

  IF NOT FOUND OR v_cli.portal_acceso = false OR v_cli.portal_password_hash IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('UNAUTHORIZED','Credenciales inválidas'));
  END IF;

  IF v_cli.estado <> 'activo' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('FORBIDDEN','El acceso al portal está deshabilitado'));
  END IF;

  IF v_cli.portal_password_hash IS DISTINCT FROM crypt(p_password, v_cli.portal_password_hash) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('UNAUTHORIZED','Credenciales inválidas'));
  END IF;

  UPDATE core.clientes SET portal_ultimo_login_at = now() WHERE id = v_cli.id;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'cliente', jsonb_build_object(
      'id', v_cli.id, 'codigo', v_cli.codigo,
      'nombres', v_cli.nombres, 'apellido_paterno', v_cli.apellido_paterno,
      'correo', v_cli.correo, 'telefono', v_cli.telefono,
      -- El propietario pertenece a UNA empresa: el portal solo le muestra
      -- lo de esa empresa y solo puede pedir cita ahí.
      'empresa_id', v_cli.empresa_id
    )
  ));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;
