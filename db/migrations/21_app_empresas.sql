-- =============================================================================
-- 21_app_empresas.sql — Empresas (cada una es un negocio independiente)
-- =============================================================================

SET search_path = app, internal, core, public;

-- -----------------------------------------------------------------------------
-- app.fn_empresa_listar
-- Un usuario con acceso global ve todas las empresas; el resto solo la suya.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_empresa_listar(
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
  v_buscar TEXT    := internal.normalizar(p_filtros->>'buscar');
  v_data   JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(x ORDER BY x.razon_social), '[]'::jsonb) INTO v_data
  FROM (
    SELECT e.id, e.ruc, e.razon_social, e.nombre_comercial, e.direccion_fiscal,
           e.telefono, e.correo, e.logo_url, e.estado,
           e.serie_factura_default, e.serie_boleta_default, e.igv_tasa,
           e.aforo_consultorios, e.duracion_cita_min, e.created_at,
           (SELECT count(*) FROM core.users u
             WHERE u.empresa_id = e.id AND u.deleted_at IS NULL) AS total_personal,
           (SELECT count(*) FROM core.citas c
             WHERE c.empresa_id = e.id AND c.deleted_at IS NULL
               AND c.fecha_hora::date = CURRENT_DATE) AS citas_hoy
    FROM core.empresas e
    WHERE e.deleted_at IS NULL
      AND (v_global OR e.id = v_emp)
      AND (p_filtros->>'estado' IS NULL OR e.estado::text = p_filtros->>'estado')
      AND (v_buscar IS NULL OR v_buscar = '' OR
           internal.normalizar(e.razon_social) LIKE '%' || v_buscar || '%' OR
           e.ruc LIKE '%' || v_buscar || '%')
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_empresa_obtener
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_empresa_obtener(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_id             UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_target UUID := COALESCE(p_id, internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin));
  v_data   JSONB;
BEGIN
  PERFORM internal.assert_acceso_empresa(p_user_id, v_target, p_is_super_admin);

  SELECT to_jsonb(e) - 'pse_password_enc' INTO v_data
  FROM core.empresas e WHERE e.id = v_target AND e.deleted_at IS NULL;

  IF v_data IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Empresa no encontrada'));
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_empresa_crear — solo super admin
-- Autoprovisiona lo mínimo para operar: almacén principal y un consultorio.
-- No hereda catálogo de otras empresas: son negocios independientes.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_empresa_crear(
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
  v_ruc TEXT := p_payload->>'ruc';
BEGIN
  IF NOT p_is_super_admin THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('FORBIDDEN','Solo un super administrador puede crear empresas'));
  END IF;

  PERFORM internal.validar_payload(p_payload, ARRAY['ruc','razon_social']);

  IF NOT internal.validar_ruc(v_ruc) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR','El RUC no es válido','ruc'));
  END IF;

  IF EXISTS (SELECT 1 FROM core.empresas WHERE ruc = v_ruc AND deleted_at IS NULL) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('CONFLICT','Ya existe una empresa con ese RUC','ruc'));
  END IF;

  INSERT INTO core.empresas (
    ruc, razon_social, nombre_comercial, direccion_fiscal, ubigeo,
    telefono, correo, logo_url, serie_factura_default, serie_boleta_default,
    serie_nota_venta_default, aforo_consultorios, duracion_cita_min, created_by
  ) VALUES (
    v_ruc,
    p_payload->>'razon_social',
    p_payload->>'nombre_comercial',
    p_payload->>'direccion_fiscal',
    p_payload->>'ubigeo',
    p_payload->>'telefono',
    p_payload->>'correo',
    p_payload->>'logo_url',
    COALESCE(p_payload->>'serie_factura_default','F001'),
    COALESCE(p_payload->>'serie_boleta_default','B001'),
    COALESCE(p_payload->>'serie_nota_venta_default','NV01'),
    COALESCE((p_payload->>'aforo_consultorios')::int, 1),
    COALESCE((p_payload->>'duracion_cita_min')::int, 30),
    p_user_id
  ) RETURNING id INTO v_id;

  -- Almacén principal: sin él, ningún movimiento de inventario tiene destino.
  INSERT INTO core.almacenes (empresa_id, codigo, nombre, es_principal)
  VALUES (v_id, 'ALM-01', 'Almacén principal', true);

  -- Un consultorio para que la agenda funcione desde el día uno.
  INSERT INTO core.consultorios (empresa_id, nombre, tipo)
  VALUES (v_id, 'Consultorio 1', 'consulta');

  PERFORM internal.registrar_auditoria(
    p_user_id, v_id, 'crear', 'empresas', v_id, NULL, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_empresa_actualizar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_empresa_actualizar(
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
BEGIN
  PERFORM internal.assert_acceso_empresa(p_user_id, p_id, p_is_super_admin);

  SELECT to_jsonb(e) - 'pse_password_enc' INTO v_antes
  FROM core.empresas e WHERE e.id = p_id AND e.deleted_at IS NULL;

  IF v_antes IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Empresa no encontrada'));
  END IF;

  UPDATE core.empresas SET
    razon_social      = COALESCE(p_payload->>'razon_social', razon_social),
    nombre_comercial  = COALESCE(p_payload->>'nombre_comercial', nombre_comercial),
    direccion_fiscal  = COALESCE(p_payload->>'direccion_fiscal', direccion_fiscal),
    ubigeo            = COALESCE(p_payload->>'ubigeo', ubigeo),
    telefono          = COALESCE(p_payload->>'telefono', telefono),
    correo            = COALESCE(p_payload->>'correo', correo),
    logo_url          = COALESCE(p_payload->>'logo_url', logo_url),
    serie_factura_default = COALESCE(p_payload->>'serie_factura_default', serie_factura_default),
    serie_boleta_default  = COALESCE(p_payload->>'serie_boleta_default', serie_boleta_default),
    serie_nota_venta_default = COALESCE(p_payload->>'serie_nota_venta_default', serie_nota_venta_default),
    igv_tasa          = COALESCE((p_payload->>'igv_tasa')::numeric, igv_tasa),
    aforo_consultorios = COALESCE((p_payload->>'aforo_consultorios')::int, aforo_consultorios),
    duracion_cita_min = COALESCE((p_payload->>'duracion_cita_min')::int, duracion_cita_min),
    pse_endpoint      = COALESCE(p_payload->>'pse_endpoint', pse_endpoint),
    pse_usuario       = COALESCE(p_payload->>'pse_usuario', pse_usuario),
    pse_password_enc  = COALESCE(p_payload->>'pse_password_enc', pse_password_enc),
    estado            = COALESCE((p_payload->>'estado')::core.estado_empresa, estado),
    updated_by        = p_user_id
  WHERE id = p_id;

  PERFORM internal.registrar_auditoria(
    p_user_id, p_id, 'actualizar', 'empresas', p_id, v_antes, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;
