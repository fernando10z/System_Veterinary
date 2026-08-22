-- =============================================================================
-- 22_app_users.sql — Personal del sistema (staff clínico y administrativo)
-- =============================================================================

SET search_path = app, internal, core, public;

-- -----------------------------------------------------------------------------
-- app.fn_users_listar — paginado, con meta {total, page, pages}
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_users_listar(
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
  v_global   BOOLEAN := internal.es_acceso_global(p_user_id, p_is_super_admin);
  v_emp      UUID    := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_buscar   TEXT    := internal.normalizar(p_filtros->>'buscar');
  v_size     INT     := LEAST(GREATEST(COALESCE(p_page_size, 20), 1), 100);
  v_page     INT     := GREATEST(COALESCE(p_page, 1), 1);
  v_total    INT;
  v_data     JSONB;
BEGIN
  SELECT count(*) INTO v_total
  FROM core.users u
  LEFT JOIN core.roles r ON r.id = u.rol_id
  WHERE u.deleted_at IS NULL
    AND (v_global OR u.empresa_id = v_emp)
    AND (p_filtros->>'estado' IS NULL OR u.estado::text = p_filtros->>'estado')
    AND (p_filtros->>'rol_id' IS NULL OR u.rol_id = (p_filtros->>'rol_id')::uuid)
    AND (p_filtros->>'solo_veterinarios' IS NULL
         OR (p_filtros->>'solo_veterinarios')::boolean = false
         OR u.es_veterinario = true)
    AND (v_buscar IS NULL OR v_buscar = '' OR
         internal.normalizar(u.nombres || ' ' || COALESCE(u.apellido_paterno,'') || ' ' ||
                             COALESCE(u.apellido_materno,'')) LIKE '%' || v_buscar || '%' OR
         internal.normalizar(u.email) LIKE '%' || v_buscar || '%' OR
         u.numero_documento LIKE '%' || COALESCE(p_filtros->>'buscar','') || '%');

  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) INTO v_data
  FROM (
    SELECT u.id, u.codigo, u.email, u.nombres, u.apellido_paterno, u.apellido_materno,
           u.tipo_documento, u.numero_documento, u.telefono, u.foto_url,
           u.empresa_id, u.is_super_admin, u.rol_id, u.estado, u.ultimo_login_at,
           u.es_veterinario, u.colegiatura, u.especializacion_id, u.color_agenda,
           u.created_at,
           r.nombre  AS rol_nombre,
           r.codigo  AS rol_codigo,
           r.scope   AS rol_scope,
           e.razon_social AS empresa_nombre,
           esp.nombre AS especializacion_nombre
    FROM core.users u
    LEFT JOIN core.roles r ON r.id = u.rol_id
    LEFT JOIN core.empresas e ON e.id = u.empresa_id
    LEFT JOIN core.especializaciones esp ON esp.id = u.especializacion_id
    WHERE u.deleted_at IS NULL
      AND (v_global OR u.empresa_id = v_emp)
      AND (p_filtros->>'estado' IS NULL OR u.estado::text = p_filtros->>'estado')
      AND (p_filtros->>'rol_id' IS NULL OR u.rol_id = (p_filtros->>'rol_id')::uuid)
      AND (p_filtros->>'solo_veterinarios' IS NULL
           OR (p_filtros->>'solo_veterinarios')::boolean = false
           OR u.es_veterinario = true)
      AND (v_buscar IS NULL OR v_buscar = '' OR
           internal.normalizar(u.nombres || ' ' || COALESCE(u.apellido_paterno,'') || ' ' ||
                               COALESCE(u.apellido_materno,'')) LIKE '%' || v_buscar || '%' OR
           internal.normalizar(u.email) LIKE '%' || v_buscar || '%' OR
           u.numero_documento LIKE '%' || COALESCE(p_filtros->>'buscar','') || '%')
    ORDER BY u.apellido_paterno NULLS LAST, u.nombres
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
-- app.fn_users_obtener
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_users_obtener(
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
  SELECT to_jsonb(x) INTO v_data FROM (
    SELECT u.id, u.codigo, u.email, u.nombres, u.apellido_paterno, u.apellido_materno,
           u.tipo_documento, u.numero_documento, u.telefono, u.foto_url,
           u.empresa_id, u.is_super_admin, u.rol_id, u.estado, u.ultimo_login_at,
           u.es_veterinario, u.colegiatura, u.especializacion_id, u.color_agenda,
           u.must_change_password, u.created_at,
           r.nombre AS rol_nombre, r.codigo AS rol_codigo,
           e.razon_social AS empresa_nombre,
           (SELECT COALESCE(jsonb_agg(p.codigo ORDER BY p.codigo), '[]'::jsonb)
              FROM core.rol_permisos rp
              JOIN core.permisos p ON p.id = rp.permiso_id
             WHERE rp.rol_id = u.rol_id) AS permisos
    FROM core.users u
    LEFT JOIN core.roles r ON r.id = u.rol_id
    LEFT JOIN core.empresas e ON e.id = u.empresa_id
    WHERE u.id = p_id AND u.deleted_at IS NULL
      AND (v_global OR u.empresa_id = v_emp)
  ) x;

  IF v_data IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Usuario no encontrado'));
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_users_crear
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_users_crear(
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
  v_emp       UUID;
  v_scope     core.scope_rol;
  v_rol_id    UUID := NULLIF(p_payload->>'rol_id','')::uuid;
  v_email     TEXT := lower(trim(p_payload->>'email'));
  v_doc       TEXT := p_payload->>'numero_documento';
  v_tipo_doc  core.tipo_documento_identidad := COALESCE((p_payload->>'tipo_documento')::core.tipo_documento_identidad, 'DNI');
  v_es_vet    BOOLEAN := COALESCE((p_payload->>'es_veterinario')::boolean, false);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'usuarios:crear');
  PERFORM internal.validar_payload(p_payload,
    ARRAY['email','password','nombres','apellido_paterno','numero_documento']);

  IF length(p_payload->>'password') < 8 THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'La contraseña debe tener al menos 8 caracteres','password'));
  END IF;

  IF v_tipo_doc = 'DNI' AND NOT internal.validar_dni(v_doc) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR','El DNI debe tener 8 dígitos','numero_documento'));
  END IF;

  IF EXISTS (SELECT 1 FROM core.users WHERE lower(email) = v_email AND deleted_at IS NULL) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('CONFLICT','Ya existe un usuario con ese correo','email'));
  END IF;

  IF EXISTS (SELECT 1 FROM core.users
              WHERE tipo_documento = v_tipo_doc AND numero_documento = v_doc AND deleted_at IS NULL) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('CONFLICT','Ya existe un usuario con ese documento','numero_documento'));
  END IF;

  IF v_es_vet AND COALESCE(p_payload->>'colegiatura','') = '' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'Un veterinario necesita número de colegiatura para firmar la historia clínica','colegiatura'));
  END IF;

  -- La sede se deriva del scope del rol: global ⇒ NULL, empresa ⇒ obligatoria.
  SELECT scope INTO v_scope FROM core.roles WHERE id = v_rol_id;
  IF v_scope IN ('global','global_restricted') THEN
    v_emp := NULL;
  ELSE
    v_emp := COALESCE(NULLIF(p_payload->>'empresa_id','')::uuid,
                      internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin));
    IF v_emp IS NULL THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('VALIDATION_ERROR','Debes indicar la sede del usuario','empresa_id'));
    END IF;
    PERFORM internal.assert_acceso_empresa(p_user_id, v_emp, p_is_super_admin);
  END IF;

  INSERT INTO core.users (
    codigo, email, password_hash, nombres, apellido_paterno, apellido_materno,
    tipo_documento, numero_documento, telefono, foto_url, empresa_id, rol_id,
    es_veterinario, colegiatura, especializacion_id, color_agenda,
    estado, must_change_password, created_by
  ) VALUES (
    COALESCE(NULLIF(p_payload->>'codigo',''),
             internal.siguiente_numero(COALESCE(v_emp, '00000000-0000-0000-0000-000000000000'::uuid), 'USR', 4)),
    v_email,
    crypt(p_payload->>'password', gen_salt('bf', 10)),
    p_payload->>'nombres',
    p_payload->>'apellido_paterno',
    p_payload->>'apellido_materno',
    v_tipo_doc, v_doc,
    p_payload->>'telefono',
    p_payload->>'foto_url',
    v_emp, v_rol_id,
    v_es_vet,
    NULLIF(p_payload->>'colegiatura',''),
    NULLIF(p_payload->>'especializacion_id','')::uuid,
    COALESCE(NULLIF(p_payload->>'color_agenda',''), '#07B162'),
    COALESCE((p_payload->>'estado')::core.estado_user, 'activo'),
    COALESCE((p_payload->>'must_change_password')::boolean, true),
    p_user_id
  ) RETURNING id INTO v_id;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'crear', 'users', v_id, NULL, p_payload - 'password');

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_users_actualizar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_users_actualizar(
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
  v_antes JSONB;
  v_emp   UUID;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'usuarios:editar');

  SELECT to_jsonb(u) - 'password_hash' - 'password_reset_token', u.empresa_id
    INTO v_antes, v_emp
  FROM core.users u WHERE u.id = p_id AND u.deleted_at IS NULL;

  IF v_antes IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Usuario no encontrado'));
  END IF;

  IF v_emp IS NOT NULL THEN
    PERFORM internal.assert_acceso_empresa(p_user_id, v_emp, p_is_super_admin);
  END IF;

  UPDATE core.users SET
    nombres            = COALESCE(p_payload->>'nombres', nombres),
    apellido_paterno   = COALESCE(p_payload->>'apellido_paterno', apellido_paterno),
    apellido_materno   = COALESCE(p_payload->>'apellido_materno', apellido_materno),
    telefono           = COALESCE(p_payload->>'telefono', telefono),
    foto_url           = COALESCE(p_payload->>'foto_url', foto_url),
    tipo_documento     = COALESCE((p_payload->>'tipo_documento')::core.tipo_documento_identidad, tipo_documento),
    numero_documento   = COALESCE(p_payload->>'numero_documento', numero_documento),
    es_veterinario     = COALESCE((p_payload->>'es_veterinario')::boolean, es_veterinario),
    colegiatura        = COALESCE(NULLIF(p_payload->>'colegiatura',''), colegiatura),
    especializacion_id = COALESCE(NULLIF(p_payload->>'especializacion_id','')::uuid, especializacion_id),
    color_agenda       = COALESCE(NULLIF(p_payload->>'color_agenda',''), color_agenda),
    updated_by         = p_user_id
  WHERE id = p_id;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'actualizar', 'users', p_id, v_antes, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_users_cambiar_estado
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_users_cambiar_estado(
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
  v_emp UUID;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'usuarios:editar');

  IF p_id = p_user_id THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE','No puedes cambiar el estado de tu propia cuenta'));
  END IF;

  SELECT empresa_id INTO v_emp FROM core.users WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Usuario no encontrado'));
  END IF;

  UPDATE core.users
     SET estado = p_estado::core.estado_user,
         intentos_fallidos = 0, bloqueado_hasta = NULL,
         updated_by = p_user_id
   WHERE id = p_id;

  -- Revocar sesiones activas al desactivar
  IF p_estado <> 'activo' THEN
    UPDATE core.sesiones SET revocado_at = now()
     WHERE user_id = p_id AND revocado_at IS NULL;
  END IF;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'cambiar_estado', 'users', p_id, NULL,
    jsonb_build_object('estado', p_estado));

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'estado', p_estado));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_users_cambiar_rol
-- Cambiar el rol puede exigir mover (o vaciar) la sede: el scope manda.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_users_cambiar_rol(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_id             UUID,
  p_rol_id         UUID,
  p_empresa_destino UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_scope core.scope_rol;
  v_emp   UUID;
BEGIN
  IF NOT p_is_super_admin THEN
    PERFORM internal.assert_permiso(p_user_id, 'usuarios:asignar_rol');
  END IF;

  SELECT scope INTO v_scope FROM core.roles WHERE id = p_rol_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Rol no encontrado','rol_id'));
  END IF;

  IF v_scope IN ('global','global_restricted') THEN
    v_emp := NULL;
  ELSE
    SELECT COALESCE(p_empresa_destino, empresa_id,
                    internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin))
      INTO v_emp
    FROM core.users WHERE id = p_id;

    IF v_emp IS NULL THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('VALIDATION_ERROR',
          'Este rol opera en una sede: indica cuál','empresa_id'));
    END IF;
  END IF;

  UPDATE core.users
     SET rol_id = p_rol_id, empresa_id = v_emp, updated_by = p_user_id
   WHERE id = p_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Usuario no encontrado'));
  END IF;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'cambiar_rol', 'users', p_id, NULL,
    jsonb_build_object('rol_id', p_rol_id, 'empresa_id', v_emp));

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_users_reset_password — el admin fija una contraseña temporal
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_users_reset_password(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_id             UUID,
  p_password_temp  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'usuarios:editar');

  IF length(p_password_temp) < 8 THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'La contraseña temporal debe tener al menos 8 caracteres','password_temp'));
  END IF;

  UPDATE core.users
     SET password_hash = crypt(p_password_temp, gen_salt('bf', 10)),
         must_change_password = true,
         intentos_fallidos = 0, bloqueado_hasta = NULL,
         updated_by = p_user_id
   WHERE id = p_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Usuario no encontrado'));
  END IF;

  UPDATE core.sesiones SET revocado_at = now()
   WHERE user_id = p_id AND revocado_at IS NULL;

  PERFORM internal.registrar_auditoria(
    p_user_id, p_empresa_id, 'reset_password_admin', 'users', p_id);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_users_eliminar — borrado lógico
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_users_eliminar(
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
  PERFORM internal.assert_permiso(p_user_id, 'usuarios:eliminar');

  IF p_id = p_user_id THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE','No puedes eliminar tu propia cuenta'));
  END IF;

  -- Un veterinario con historia clínica firmada no se borra: se desactiva,
  -- o la trazabilidad del acto médico queda huérfana.
  IF EXISTS (SELECT 1 FROM core.consultas WHERE veterinario_id = p_id LIMIT 1) THEN
    UPDATE core.users SET estado = 'inactivo', updated_by = p_user_id WHERE id = p_id;
    RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
      'id', p_id, 'desactivado', true,
      'mensaje', 'El usuario tiene historia clínica firmada: se desactivó en lugar de eliminarse.'));
  END IF;

  UPDATE core.users
     SET deleted_at = now(), estado = 'inactivo', updated_by = p_user_id
   WHERE id = p_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Usuario no encontrado'));
  END IF;

  PERFORM internal.registrar_auditoria(p_user_id, p_empresa_id, 'eliminar', 'users', p_id);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'eliminado', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_veterinarios_listar — atajo para selects de agenda / historia clínica
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_veterinarios_listar(
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
  v_global BOOLEAN := internal.es_acceso_global(p_user_id, p_is_super_admin);
  v_emp    UUID    := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_data   JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(x ORDER BY x.apellido_paterno, x.nombres), '[]'::jsonb) INTO v_data
  FROM (
    SELECT u.id, u.nombres, u.apellido_paterno, u.apellido_materno,
           u.colegiatura, u.color_agenda, u.foto_url, u.empresa_id,
           esp.nombre AS especializacion,
           (SELECT count(*) FROM core.citas c
             WHERE c.veterinario_id = u.id AND c.deleted_at IS NULL
               AND c.fecha_hora::date = CURRENT_DATE
               AND c.estado NOT IN ('cancelada','no_asistio')) AS citas_hoy
    FROM core.users u
    LEFT JOIN core.especializaciones esp ON esp.id = u.especializacion_id
    WHERE u.es_veterinario = true AND u.deleted_at IS NULL AND u.estado = 'activo'
      AND (v_global OR u.empresa_id = v_emp)
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;
