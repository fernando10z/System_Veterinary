-- =============================================================================
-- 39_app_sedes.sql — Los locales de una clínica
--
-- Ver el comentario de `core.sedes` en 04_tables_per_empresa.sql para la línea
-- que separa lo que comparten los locales de lo que no.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Relleno para instalaciones que ya existían
--
-- El trigger cubre lo que se inserte de aquí en adelante; esto cubre lo de
-- antes. En una base recién creada no hay empresas todavía y no hace nada.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  r RECORD;
  v_sede UUID;
  t TEXT;
  tablas TEXT[] := ARRAY[
    'consultorios','almacenes','horarios_atencion','citas','cajas',
    'consultas','hospitalizaciones','comprobantes','peluqueria_ordenes'
  ];
BEGIN
  FOR r IN SELECT id FROM core.empresas WHERE deleted_at IS NULL LOOP
    v_sede := internal.sede_por_defecto(r.id);
    FOREACH t IN ARRAY tablas LOOP
      EXECUTE format(
        'UPDATE core.%I SET sede_id = $1 WHERE empresa_id = $2 AND sede_id IS NULL', t)
        USING v_sede, r.id;
    END LOOP;
    UPDATE core.users SET sede_id = v_sede
     WHERE empresa_id = r.id AND sede_id IS NULL AND deleted_at IS NULL;
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- app.fn_sedes_listar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_sedes_listar(
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
  SELECT COALESCE(jsonb_agg(x ORDER BY x.es_principal DESC, x.nombre), '[]'::jsonb) INTO v_data
  FROM (
    SELECT s.id, s.codigo, s.nombre, s.direccion, s.distrito, s.provincia,
           s.departamento, s.telefono, s.correo, s.serie_boleta, s.serie_factura,
           s.es_principal, s.estado, s.empresa_id,
           (SELECT count(*) FROM core.users u
             WHERE u.sede_id = s.id AND u.deleted_at IS NULL)         AS personal,
           (SELECT count(*) FROM core.consultorios c
             WHERE c.sede_id = s.id AND c.estado = 'activo')          AS consultorios,
           (SELECT count(*) FROM core.citas ci
             WHERE ci.sede_id = s.id AND ci.deleted_at IS NULL
               AND ci.fecha_hora::date = CURRENT_DATE)                AS citas_hoy
    FROM core.sedes s
    WHERE s.deleted_at IS NULL
      AND (v_global OR s.empresa_id = v_emp)
      AND (p_filtros->>'estado' IS NULL OR s.estado::text = p_filtros->>'estado')
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_sede_guardar — alta y edición
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_sede_guardar(
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
  v_emp   UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_id    UUID := NULLIF(p_payload->>'id','')::uuid;
  v_antes JSONB;
  v_princ BOOLEAN := COALESCE((p_payload->>'es_principal')::boolean, false);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'empresa:configurar');
  PERFORM internal.validar_payload(p_payload, ARRAY['nombre']);

  IF v_id IS NOT NULL THEN
    SELECT to_jsonb(s) INTO v_antes FROM core.sedes s
     WHERE s.id = v_id AND s.deleted_at IS NULL;
    IF v_antes IS NULL
       OR NOT internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp,
                                     (v_antes->>'empresa_id')::uuid) THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('NOT_FOUND','Sede no encontrada'));
    END IF;
  END IF;

  -- Solo puede haber una principal: marcar una nueva desmarca la anterior.
  IF v_princ THEN
    UPDATE core.sedes SET es_principal = false
     WHERE empresa_id = v_emp AND es_principal
       AND (v_id IS NULL OR id <> v_id);
  END IF;

  IF v_id IS NULL THEN
    INSERT INTO core.sedes (
      empresa_id, codigo, nombre, direccion, distrito, provincia, departamento,
      ubigeo, telefono, correo, serie_boleta, serie_factura, es_principal, created_by)
    VALUES (
      v_emp,
      COALESCE(NULLIF(p_payload->>'codigo',''),
               internal.siguiente_numero(v_emp, 'SEDE', 2)),
      p_payload->>'nombre', p_payload->>'direccion', p_payload->>'distrito',
      p_payload->>'provincia', p_payload->>'departamento', p_payload->>'ubigeo',
      p_payload->>'telefono', p_payload->>'correo',
      NULLIF(p_payload->>'serie_boleta',''), NULLIF(p_payload->>'serie_factura',''),
      -- La primera sede de una empresa es la principal, se pida o no.
      v_princ OR NOT EXISTS (SELECT 1 FROM core.sedes
                              WHERE empresa_id = v_emp AND deleted_at IS NULL),
      p_user_id)
    RETURNING id INTO v_id;
  ELSE
    UPDATE core.sedes SET
      codigo        = COALESCE(NULLIF(p_payload->>'codigo',''), codigo),
      nombre        = COALESCE(p_payload->>'nombre', nombre),
      direccion     = COALESCE(p_payload->>'direccion', direccion),
      distrito      = COALESCE(p_payload->>'distrito', distrito),
      provincia     = COALESCE(p_payload->>'provincia', provincia),
      departamento  = COALESCE(p_payload->>'departamento', departamento),
      ubigeo        = COALESCE(p_payload->>'ubigeo', ubigeo),
      telefono      = COALESCE(p_payload->>'telefono', telefono),
      correo        = COALESCE(p_payload->>'correo', correo),
      serie_boleta  = COALESCE(NULLIF(p_payload->>'serie_boleta',''), serie_boleta),
      serie_factura = COALESCE(NULLIF(p_payload->>'serie_factura',''), serie_factura),
      estado        = COALESCE((p_payload->>'estado')::core.estado_generico, estado),
      es_principal  = CASE WHEN v_princ THEN true ELSE es_principal END,
      updated_by    = p_user_id
    WHERE id = v_id;
  END IF;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, CASE WHEN v_antes IS NULL THEN 'crear' ELSE 'actualizar' END,
    'sedes', v_id, v_antes, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('CONFLICT','Ya existe una sede con ese código','codigo'));
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_sede_eliminar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_sede_eliminar(
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
  v_emp   UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_sede  RECORD;
  v_citas INT;
  v_caja  INT;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'empresa:configurar');

  SELECT * INTO v_sede FROM core.sedes WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND
     OR NOT internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, v_sede.empresa_id) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Sede no encontrada'));
  END IF;

  IF v_sede.es_principal THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'La sede principal no se puede eliminar. Marca otra como principal primero.'));
  END IF;

  -- Una caja abierta significa dinero sin cuadrar en ese mostrador.
  SELECT count(*) INTO v_caja FROM core.cajas
   WHERE sede_id = p_id AND estado = 'abierta';
  IF v_caja > 0 THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'La sede tiene una caja abierta. Ciérrala antes de dar de baja el local.'));
  END IF;

  SELECT count(*) INTO v_citas FROM core.citas
   WHERE sede_id = p_id AND deleted_at IS NULL
     AND fecha_hora >= now() AND estado IN ('programada','confirmada');
  IF v_citas > 0 THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        format('La sede tiene %s cita(s) futura(s). Reprográmalas o cancélalas primero.', v_citas)));
  END IF;

  UPDATE core.sedes SET deleted_at = now(), estado = 'inactivo', updated_by = p_user_id
   WHERE id = p_id;

  PERFORM internal.registrar_auditoria(p_user_id, v_emp, 'eliminar', 'sedes', p_id);
  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('eliminado', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

COMMENT ON FUNCTION app.fn_sedes_listar IS 'Locales de la empresa con su carga del día.';
