-- =============================================================================
-- 34_app_pse.sql
-- Facturación electrónica: lo que la base aporta al envío de comprobantes a
-- SUNAT a través del PSE (The Factory HKA).
--
-- El reparto es el mismo que en el resto del sistema: la base decide qué se
-- puede enviar y guarda lo que volvió; el backend sólo habla HTTP con el
-- proveedor. Aquí no hay ninguna llamada a la red.
--
-- Idempotente.
-- =============================================================================

SET search_path = app, internal, core, public;

-- -----------------------------------------------------------------------------
-- app.fn_empresa_pse_config
--
-- Credenciales del proveedor para el conector del servidor. A diferencia de
-- fn_empresa_obtener —que nunca devuelve la clave— este SP SÍ entrega
-- `pse_password_enc` para que el backend la descifre. Uso exclusivo del
-- servicio de envío, por eso exige permiso de facturación.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_empresa_pse_config(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_empresa_target UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_target UUID := COALESCE(p_empresa_target,
                            internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin));
  v_data   JSONB;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'facturacion:emitir');

  IF v_target IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('VALIDATION_ERROR','No hay empresa objetivo'));
  END IF;

  -- Un administrador de empresa no puede leer las credenciales de otra.
  IF NOT internal.es_acceso_global(p_user_id, p_is_super_admin)
     AND v_target <> internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Empresa no encontrada'));
  END IF;

  SELECT jsonb_build_object(
    'empresa_id',        e.id,
    'ruc',               e.ruc,
    'ruc_pse',           COALESCE(NULLIF(e.pse_ruc,''), e.ruc),
    'razon_social',      e.razon_social,
    'nombre_comercial',  e.nombre_comercial,
    'direccion_fiscal',  e.direccion_fiscal,
    'ubigeo',            e.ubigeo,
    'urbanizacion',      e.urbanizacion,
    'distrito',          e.distrito,
    'provincia',         e.provincia,
    'departamento',      e.departamento,
    'endpoint',          e.pse_endpoint,
    'usuario',           e.pse_usuario,
    'password_enc',      e.pse_password_enc,
    'proveedor',         e.pse_proveedor,
    'emite_electronico', e.emite_electronico
  ) INTO v_data
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
-- app.fn_comprobante_pse_datos
--
-- Todo lo que el backend necesita para armar el documento electrónico, en una
-- sola lectura: cabecera, emisor, receptor e ítems ya con su código SUNAT.
--
-- Traduce aquí, y no en el backend, lo que es decisión de negocio:
--   · tipo de documento de identidad → catálogo 06 (DNI 1, CE 4, RUC 6, PAS 7)
--   · afectación al IGV              → catálogo 07 (10 gravado, 20 exonerado)
--   · unidad de medida               → catálogo 03 (NIU producto, ZZ servicio)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_comprobante_pse_datos(
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
  v_emp   UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_c     RECORD;
  v_cab   JSONB;
  v_items JSONB;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'facturacion:emitir');

  SELECT c.*, e.ruc, e.pse_ruc, e.razon_social, e.nombre_comercial, e.direccion_fiscal,
         e.ubigeo, e.urbanizacion, e.distrito, e.provincia, e.departamento,
         e.emite_electronico, e.igv_tasa,
         cl.tipo_documento AS cli_tipo_doc, cl.numero_documento AS cli_num_doc,
         COALESCE(NULLIF(cl.razon_social,''),
                  trim(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'') || ' ' ||
                       COALESCE(cl.apellido_materno,''))) AS cli_razon_social,
         cl.direccion AS cli_direccion, cl.ubigeo AS cli_ubigeo, cl.correo AS cli_correo,
         ref.serie AS ref_serie, ref.numero AS ref_numero, ref.tipo AS ref_tipo
    INTO v_c
    FROM core.comprobantes c
    JOIN core.empresas e ON e.id = c.empresa_id
    JOIN core.clientes cl ON cl.id = c.cliente_id
    LEFT JOIN core.comprobantes ref ON ref.id = c.documento_ref_id
   WHERE c.id = p_id AND c.deleted_at IS NULL
     AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, c.empresa_id);

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Comprobante no encontrado'));
  END IF;

  -- La nota de venta es un documento interno: no existe para SUNAT.
  IF v_c.tipo = 'nota_venta' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'Una nota de venta no se envía a SUNAT: es un documento interno'));
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'descripcion',         i.descripcion,
           'codigo',              i.codigo,
           'unidad_medida',       i.unidad_medida,
           'cantidad',            i.cantidad,
           'precio_unitario',     i.precio_unitario,
           'tipo_afectacion_igv', CASE WHEN i.afecto_igv THEN i.tipo_afectacion_igv ELSE '20' END,
           'igv_porcentaje',      round(COALESCE(v_c.igv_tasa, 0.18) * 100, 2),
           'subtotal',            i.subtotal,
           'igv',                 i.igv,
           'total',               i.total) ORDER BY i.orden), '[]'::jsonb)
    INTO v_items
    FROM core.comprobante_items i WHERE i.comprobante_id = p_id;

  v_cab := jsonb_build_object(
    'id', v_c.id,
    'tipo', v_c.tipo,
    'serie', v_c.serie,
    'numero', v_c.numero,
    'numero_completo', v_c.numero_completo,
    'estado', v_c.estado,
    'empresa_id', v_c.empresa_id,
    'emite_electronico', v_c.emite_electronico,
    'fecha_emision', to_char(v_c.fecha_emision AT TIME ZONE 'America/Lima', 'YYYY-MM-DD'),
    'hora_emision',  to_char(v_c.fecha_emision AT TIME ZONE 'America/Lima', 'HH24:MI:SS'),
    'fecha_vencimiento', v_c.fecha_vencimiento,
    'moneda', v_c.moneda,
    'tipo_cambio', COALESCE(v_c.tipo_cambio, 1),
    'subtotal', v_c.subtotal,
    'igv', v_c.igv,
    'total', v_c.total,
    'descuento_global', v_c.descuento_global,
    'observaciones', v_c.observaciones,
    'motivo_nota', v_c.motivo_nota,
    'codigo_tipo_nota', v_c.codigo_tipo_nota,
    'pse_request_id', v_c.pse_request_id,
    -- Gravado / exonerado salen de la afectación de cada línea, no de un total
    -- suelto: si un ítem va exonerado, su base no puede sumar al gravado.
    'subtotal_gravado', (
      SELECT COALESCE(SUM(i.subtotal), 0) FROM core.comprobante_items i
       WHERE i.comprobante_id = p_id AND i.afecto_igv),
    'subtotal_exonerado', (
      SELECT COALESCE(SUM(i.subtotal), 0) FROM core.comprobante_items i
       WHERE i.comprobante_id = p_id AND NOT i.afecto_igv),
    -- Contado o crédito: lo decide que el comprobante tenga vencimiento futuro.
    'forma_pago', CASE
      WHEN v_c.fecha_vencimiento IS NOT NULL
           AND v_c.fecha_vencimiento > (v_c.fecha_emision AT TIME ZONE 'America/Lima')::date
      THEN 'credito' ELSE 'contado' END,
    'emisor', jsonb_build_object(
      'ruc', COALESCE(NULLIF(v_c.pse_ruc,''), v_c.ruc),
      'razon_social', v_c.razon_social,
      'nombre_comercial', v_c.nombre_comercial,
      'direccion_fiscal', v_c.direccion_fiscal,
      'ubigeo', v_c.ubigeo,
      'urbanizacion', v_c.urbanizacion,
      'distrito', v_c.distrito,
      'provincia', v_c.provincia,
      'departamento', v_c.departamento),
    'cliente', jsonb_build_object(
      'tipo_documento', v_c.cli_tipo_doc,
      'numero_documento', v_c.cli_num_doc,
      'razon_social', v_c.cli_razon_social,
      'direccion', v_c.cli_direccion,
      'ubigeo', v_c.cli_ubigeo,
      'correo', v_c.cli_correo),
    'documento_ref', CASE WHEN v_c.ref_serie IS NOT NULL THEN jsonb_build_object(
      'tipo', v_c.ref_tipo, 'serie', v_c.ref_serie, 'numero', v_c.ref_numero) END);

  RETURN jsonb_build_object('ok', true,
    'data', jsonb_build_object('comprobante', v_cab, 'items', v_items));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_comprobante_marcar_enviado
-- Guarda el identificador del documento en el proveedor y el payload enviado.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_comprobante_marcar_enviado(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_id             UUID,
  p_request_id     VARCHAR,
  p_request        JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
BEGIN
  UPDATE core.comprobantes
     SET estado          = 'enviado_sunat',
         pse_request_id  = p_request_id,
         enviado_pse_at  = now(),
         updated_at = now(), updated_by = p_user_id
   WHERE id = p_id AND deleted_at IS NULL
     AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, empresa_id);

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Comprobante no encontrado'));
  END IF;

  INSERT INTO core.comprobante_pse_log (comprobante_id, operacion, request, exito, mensaje, created_by)
  VALUES (p_id, 'enviar', p_request, true, 'Enviado al PSE', p_user_id);

  RETURN jsonb_build_object('ok', true,
    'data', jsonb_build_object('id', p_id, 'estado', 'enviado_sunat'));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_comprobante_recibir_respuesta
-- Persiste lo que devolvió el PSE/SUNAT: estado, CDR, rutas de archivos.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_comprobante_recibir_respuesta(
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
  v_emp    UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_estado core.estado_comprobante := (p_payload->>'estado')::core.estado_comprobante;
BEGIN
  UPDATE core.comprobantes SET
    pse_response      = COALESCE(p_payload->'response', pse_response),
    xml_url           = COALESCE(NULLIF(p_payload->>'xml_url',''), xml_url),
    pdf_url           = COALESCE(NULLIF(p_payload->>'pdf_url',''), pdf_url),
    cdr_url           = COALESCE(NULLIF(p_payload->>'cdr_url',''), cdr_url),
    hash_cpe          = COALESCE(NULLIF(p_payload->>'hash_cpe',''), hash_cpe),
    sunat_codigo      = COALESCE(NULLIF(p_payload->>'sunat_codigo',''), sunat_codigo),
    sunat_mensaje     = COALESCE(NULLIF(p_payload->>'sunat_mensaje',''), sunat_mensaje),
    estado            = COALESCE(v_estado, estado),
    aceptado_sunat_at = CASE WHEN v_estado = 'aceptado_sunat'
                             THEN COALESCE(aceptado_sunat_at, now()) ELSE aceptado_sunat_at END,
    updated_at = now(), updated_by = p_user_id
  WHERE id = p_id AND deleted_at IS NULL
    AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, empresa_id);

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Comprobante no encontrado'));
  END IF;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'respuesta_sunat', 'comprobantes', p_id, NULL,
    jsonb_build_object('estado', v_estado, 'codigo', p_payload->>'sunat_codigo'));

  RETURN jsonb_build_object('ok', true,
    'data', jsonb_build_object('id', p_id, 'estado', COALESCE(v_estado::text, 'sin_cambio')));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_comprobante_pse_log
-- Bitácora del intento, exitoso o no. Se llama siempre, incluso si el envío
-- falló: la razón del rechazo es justo lo que hay que poder leer después.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_comprobante_pse_log(
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
  v_intento INT;
BEGIN
  SELECT COALESCE(MAX(intento), 0) + 1 INTO v_intento
    FROM core.comprobante_pse_log WHERE comprobante_id = p_id;

  INSERT INTO core.comprobante_pse_log (
    comprobante_id, intento, operacion, request, response, exito, mensaje, duracion_ms, created_by)
  VALUES (
    p_id, v_intento,
    COALESCE(p_payload->>'operacion', 'enviar'),
    p_payload->'request', p_payload->'response',
    COALESCE((p_payload->>'exito')::boolean, false),
    p_payload->>'mensaje',
    NULLIF(p_payload->>'duracion_ms','')::int,
    p_user_id);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('intento', v_intento));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_comprobantes_por_enviar
--
-- La cola de lo que numeró la clínica y todavía no llegó a SUNAT. Es la que
-- mira administración al cierre del día: un comprobante que se quedó acá es
-- una venta cobrada que la administración tributaria no vio.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_comprobantes_por_enviar(
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
  SELECT COALESCE(jsonb_agg(x ORDER BY x.fecha_emision), '[]'::jsonb) INTO v_data
  FROM (
    SELECT c.id, c.numero_completo, c.tipo, c.fecha_emision, c.total, c.estado,
           c.sunat_codigo, c.sunat_mensaje, c.enviado_pse_at,
           trim(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'')) AS cliente,
           (SELECT count(*) FROM core.comprobante_pse_log l WHERE l.comprobante_id = c.id) AS intentos
      FROM core.comprobantes c
      JOIN core.clientes cl ON cl.id = c.cliente_id
      JOIN core.empresas e  ON e.id = c.empresa_id
     WHERE c.deleted_at IS NULL
       AND c.tipo <> 'nota_venta'
       AND e.emite_electronico
       AND c.estado IN ('emitido','pendiente_envio','enviado_sunat','rechazado_sunat')
       AND (v_global OR c.empresa_id = v_emp)
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app TO vet_app_user;
