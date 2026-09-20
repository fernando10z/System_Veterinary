-- =============================================================================
-- 38_app_archivos.sql — Quién puede tocar qué objeto del almacén
--
-- Los archivos clínicos viven en MinIO, fuera de Postgres, así que el filtro por
-- empresa que llevan todas las lecturas no los alcanzaba: bastaba pedir una URL
-- prefirmada con la clave de otro para descargar la radiografía de un paciente
-- de otra clínica. La clave de un objeto es tan sensible como la fila que la
-- guarda, y la regla de acceso es de negocio: vive aquí, no en el controlador.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- app.fn_archivo_autorizar
-- Decide si el usuario puede subir o descargar el objeto indicado.
--
-- La clave tiene la forma `e_<uuid-empresa>/<area>/<aaaa>/<mm>/<epoch>_<nombre>`
-- (o `global/...` para lo que no cuelga de una empresa). De ahí sale a qué
-- empresa pertenece el objeto, que es lo único que el almacén no sabe.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_archivo_autorizar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_key            TEXT,
  p_modo           TEXT DEFAULT 'descargar'
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp     UUID    := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_global  BOOLEAN := internal.es_acceso_global(p_user_id, p_is_super_admin);
  v_prefijo TEXT;
  v_area    TEXT;
  v_emp_key UUID;
BEGIN
  IF p_key IS NULL OR btrim(p_key) = '' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR','Indica la clave del archivo','key'));
  END IF;

  -- Un objeto de MinIO no tiene rutas relativas: si aparecen, alguien está
  -- probando a salirse del prefijo de su empresa.
  IF p_key LIKE '%..%' OR p_key LIKE '//%' OR p_key LIKE '%//%'
     OR p_key LIKE '/%' OR length(p_key) > 512 THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR','La clave del archivo no es válida','key'));
  END IF;

  v_prefijo := split_part(p_key, '/', 1);
  v_area    := split_part(p_key, '/', 2);

  IF v_area = '' OR split_part(p_key, '/', 3) = '' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR','La clave del archivo no es válida','key'));
  END IF;

  -- ---- ¿de qué empresa es el objeto? ----------------------------------------
  IF v_prefijo = 'global' THEN
    IF NOT v_global THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('NOT_FOUND','Archivo no encontrado'));
    END IF;
  ELSIF v_prefijo ~ '^e_[0-9a-fA-F-]{36}$' THEN
    v_emp_key := substring(v_prefijo from 3)::uuid;
    -- Misma convención que el resto del ERP: si el registro es de otra empresa
    -- se responde NOT_FOUND, no FORBIDDEN, para no confirmar que existe.
    IF NOT v_global AND v_emp_key IS DISTINCT FROM v_emp THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('NOT_FOUND','Archivo no encontrado'));
    END IF;
  ELSE
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR','La clave del archivo no es válida','key'));
  END IF;

  -- ---- ¿el área existe, y quién entra en ella? ------------------------------
  IF v_area NOT IN ('clinico','documentos','resultados','consentimientos','logos') THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR',
        'Área de archivo no reconocida','area'));
  END IF;

  IF v_area = 'logos' THEN
    -- El logo sale impreso en cada receta y cada comprobante: lo lee todo el
    -- personal. Cambiarlo es configurar la empresa.
    IF p_modo <> 'descargar' THEN
      PERFORM internal.assert_permiso(p_user_id, 'empresa:configurar');
    END IF;
  ELSIF p_modo = 'descargar' THEN
    PERFORM internal.assert_permiso(p_user_id, 'clinico:ver');
  ELSE
    PERFORM internal.assert_permiso(p_user_id, 'clinico:registrar');
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'key',        p_key,
    'area',       v_area,
    'empresa_id', COALESCE(v_emp_key, v_emp)));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

COMMENT ON FUNCTION app.fn_archivo_autorizar IS
  'Autoriza subir/descargar un objeto de MinIO: empresa dueña, área y permiso.';
