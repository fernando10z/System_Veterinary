-- =============================================================================
-- 10_internal_helpers.sql
-- Helpers privados del schema `internal`. Los reutilizan todos los SPs/FNs
-- públicas. NO accesibles directamente por el backend.
-- =============================================================================

SET search_path = internal, core, public;

-- -----------------------------------------------------------------------------
-- internal.error_jsonb — bloque de error estándar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.error_jsonb(
  p_code    TEXT,
  p_message TEXT,
  p_field   TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'code', p_code, 'message', p_message, 'field', p_field
  ));
$$;

-- -----------------------------------------------------------------------------
-- internal.es_acceso_global
-- true si el usuario es super admin o su rol tiene scope global/global_restricted.
--
-- ⚠️ REGLA: toda función de lectura filtra con
--     (internal.es_acceso_global(p_user_id, p_is_super_admin) OR x.empresa_id = v_emp)
-- NUNCA con `p_is_super_admin` a secas: eso ocultaría datos a gerencia.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.es_acceso_global(
  p_user_id        UUID,
  p_is_super_admin BOOLEAN DEFAULT false
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
DECLARE
  v_scope core.scope_rol;
  v_super BOOLEAN;
BEGIN
  IF p_is_super_admin = true THEN RETURN true; END IF;
  IF p_user_id IS NULL THEN RETURN false; END IF;

  SELECT u.is_super_admin, r.scope INTO v_super, v_scope
  FROM core.users u
  LEFT JOIN core.roles r ON r.id = u.rol_id
  WHERE u.id = p_user_id AND u.deleted_at IS NULL;

  IF v_super = true THEN RETURN true; END IF;
  RETURN COALESCE(v_scope IN ('global','global_restricted'), false);
END;
$$;

-- -----------------------------------------------------------------------------
-- internal.empresa_efectiva
-- Resuelve la empresa sobre la que opera la llamada. Un super admin sin empresa
-- asignada toma la primera activa (o la que venga explícita en el SP).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.empresa_efectiva(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN DEFAULT false
)
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
DECLARE
  v_emp UUID;
BEGIN
  IF p_empresa_id IS NOT NULL THEN RETURN p_empresa_id; END IF;

  SELECT empresa_id INTO v_emp FROM core.users WHERE id = p_user_id;
  IF v_emp IS NOT NULL THEN RETURN v_emp; END IF;

  IF internal.es_acceso_global(p_user_id, p_is_super_admin) THEN
    SELECT id INTO v_emp FROM core.empresas
     WHERE estado = 'activa' AND deleted_at IS NULL
     ORDER BY created_at LIMIT 1;
  END IF;

  RETURN v_emp;
END;
$$;

-- -----------------------------------------------------------------------------
-- internal.es_de_empresa
-- ¿El registro pertenece a la empresa desde la que se está operando?
--
-- Se usa en TODO SP que recibe el id de un registro. Sin esta comprobación, un
-- usuario de la empresa A podría modificar un registro de la empresa B con solo
-- conocer su UUID: el permiso lo tiene (es admin de SU empresa) y el id existe.
--
-- Convención: cuando devuelve false se responde NOT_FOUND, no FORBIDDEN, para no
-- revelar que el registro existe en otra empresa.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.es_de_empresa(
  p_user_id          UUID,
  p_is_super_admin   BOOLEAN,
  p_empresa_contexto UUID,
  p_empresa_registro UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
  SELECT p_empresa_registro IS NOT NULL
     AND (internal.es_acceso_global(p_user_id, p_is_super_admin)
          OR p_empresa_registro = p_empresa_contexto);
$$;

-- -----------------------------------------------------------------------------
-- internal.assert_acceso_empresa
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.assert_acceso_empresa(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
DECLARE
  v_empresa_user UUID;
BEGIN
  IF internal.es_acceso_global(p_user_id, p_is_super_admin) THEN RETURN; END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario no autenticado' USING ERRCODE = '42501';
  END IF;

  SELECT empresa_id INTO v_empresa_user
  FROM core.users WHERE id = p_user_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Usuario no existe' USING ERRCODE = '42501';
  END IF;

  IF v_empresa_user IS NULL OR v_empresa_user <> p_empresa_id THEN
    RAISE EXCEPTION 'Sin acceso a la empresa indicada' USING ERRCODE = '42501';
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- internal.assert_permiso
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.assert_permiso(
  p_user_id        UUID,
  p_codigo_permiso VARCHAR
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
DECLARE
  v_is_super BOOLEAN;
  v_rol_id   UUID;
  v_existe   INT;
BEGIN
  SELECT is_super_admin, rol_id INTO v_is_super, v_rol_id
  FROM core.users WHERE id = p_user_id;

  IF v_is_super = true THEN RETURN; END IF;

  IF v_rol_id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin rol asignado' USING ERRCODE = '42501';
  END IF;

  SELECT 1 INTO v_existe
  FROM core.rol_permisos rp
  JOIN core.permisos p ON p.id = rp.permiso_id
  WHERE rp.rol_id = v_rol_id AND p.codigo = p_codigo_permiso
  LIMIT 1;

  IF v_existe IS NULL THEN
    RAISE EXCEPTION 'Permiso requerido: %', p_codigo_permiso USING ERRCODE = '42501';
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- internal.registrar_auditoria — inserta en core.audit_log con diff calculado
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.registrar_auditoria(
  p_user_id    UUID,
  p_empresa_id UUID,
  p_accion     VARCHAR,
  p_entidad    VARCHAR,
  p_entidad_id UUID,
  p_antes      JSONB DEFAULT NULL,
  p_despues    JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
DECLARE
  v_id   UUID;
  v_diff JSONB := '{}'::jsonb;
  v_key  TEXT;
BEGIN
  IF p_antes IS NOT NULL AND p_despues IS NOT NULL THEN
    FOR v_key IN
      SELECT k FROM jsonb_object_keys(p_antes) AS k
      UNION
      SELECT k FROM jsonb_object_keys(p_despues) AS k
    LOOP
      IF (p_antes->v_key) IS DISTINCT FROM (p_despues->v_key) THEN
        v_diff := v_diff || jsonb_build_object(
          v_key, jsonb_build_object('antes', p_antes->v_key, 'despues', p_despues->v_key));
      END IF;
    END LOOP;
  ELSIF p_despues IS NOT NULL THEN
    v_diff := jsonb_build_object('_creado', p_despues);
  ELSIF p_antes IS NOT NULL THEN
    v_diff := jsonb_build_object('_eliminado', p_antes);
  END IF;

  INSERT INTO core.audit_log (
    user_id, empresa_id, accion, entidad, entidad_id, datos_antes, datos_despues, diff
  ) VALUES (
    p_user_id, p_empresa_id, p_accion, p_entidad, p_entidad_id, p_antes, p_despues, v_diff
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- internal.siguiente_numero_documento / siguiente_numero
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.siguiente_numero_documento(
  p_empresa_id     UUID,
  p_tipo_documento VARCHAR,
  p_serie          VARCHAR
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
DECLARE
  v_numero INT;
BEGIN
  INSERT INTO core.correlativos (empresa_id, tipo_documento, serie, ultimo_numero)
  VALUES (p_empresa_id, p_tipo_documento, p_serie, 0)
  ON CONFLICT DO NOTHING;

  UPDATE core.correlativos
     SET ultimo_numero = ultimo_numero + 1, updated_at = now()
   WHERE empresa_id = p_empresa_id
     AND tipo_documento = p_tipo_documento
     AND serie = p_serie
   RETURNING ultimo_numero INTO v_numero;

  RETURN v_numero;
END;
$$;

CREATE OR REPLACE FUNCTION internal.siguiente_numero(
  p_empresa_id UUID,
  p_prefijo    VARCHAR,
  p_ancho      INT DEFAULT 6
)
RETURNS VARCHAR
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
DECLARE
  v_numero INT;
BEGIN
  v_numero := internal.siguiente_numero_documento(p_empresa_id, p_prefijo, '0001');
  RETURN p_prefijo || '-' || lpad(v_numero::text, p_ancho, '0');
END;
$$;

-- -----------------------------------------------------------------------------
-- internal.calcular_igv
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.calcular_igv(
  p_base NUMERIC,
  p_tasa NUMERIC DEFAULT 0.18
)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT round(COALESCE(p_base,0) * COALESCE(p_tasa, 0.18), 2);
$$;

-- -----------------------------------------------------------------------------
-- internal.recalcular_saldo_comprobante
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.recalcular_saldo_comprobante(p_comprobante_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
DECLARE
  v_total    NUMERIC(14,2);
  v_aplicado NUMERIC(14,2);
  v_saldo    NUMERIC(14,2);
BEGIN
  SELECT total INTO v_total FROM core.comprobantes WHERE id = p_comprobante_id;
  IF v_total IS NULL THEN RETURN; END IF;

  SELECT COALESCE(SUM(pa.monto_aplicado), 0) INTO v_aplicado
  FROM core.pago_aplicaciones pa
  JOIN core.pagos p ON p.id = pa.pago_id AND p.anulado_at IS NULL
  WHERE pa.comprobante_id = p_comprobante_id;

  v_saldo := v_total - v_aplicado;

  UPDATE core.comprobantes
     SET saldo_pendiente = v_saldo,
         estado_pago = CASE
           WHEN v_saldo <= 0   THEN 'pagado'::core.estado_pago
           WHEN v_aplicado > 0 THEN 'parcial'::core.estado_pago
           ELSE 'pendiente'::core.estado_pago
         END,
         updated_at = now()
   WHERE id = p_comprobante_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- internal.registrar_evento_clinico
-- Toda tabla clínica llama aquí para dejar su rastro en la línea de tiempo.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.registrar_evento_clinico(
  p_empresa_id     UUID,
  p_mascota_id     UUID,
  p_cliente_id     UUID,
  p_veterinario_id UUID,
  p_tipo           core.tipo_evento_clinico,
  p_titulo         VARCHAR,
  p_resumen        TEXT DEFAULT NULL,
  p_entidad_id     UUID DEFAULT NULL,
  p_cita_id        UUID DEFAULT NULL,
  p_fecha          TIMESTAMPTZ DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO core.historia_clinica (
    empresa_id, mascota_id, cliente_id, veterinario_id, cita_id,
    tipo_evento, fecha, titulo, resumen, entidad_id, created_by
  ) VALUES (
    p_empresa_id, p_mascota_id, p_cliente_id, p_veterinario_id, p_cita_id,
    p_tipo, COALESCE(p_fecha, now()), p_titulo, p_resumen, p_entidad_id, p_veterinario_id
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- internal.edad_mascota — devuelve la edad legible y en meses
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.edad_mascota(
  p_fecha_nacimiento DATE,
  p_edad_aprox_meses INT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_meses INT;
  v_anios INT;
  v_resto INT;
BEGIN
  IF p_fecha_nacimiento IS NOT NULL THEN
    v_meses := (EXTRACT(YEAR FROM age(CURRENT_DATE, p_fecha_nacimiento)) * 12
              + EXTRACT(MONTH FROM age(CURRENT_DATE, p_fecha_nacimiento)))::int;
  ELSIF p_edad_aprox_meses IS NOT NULL THEN
    v_meses := p_edad_aprox_meses;
  ELSE
    RETURN jsonb_build_object('meses', NULL, 'texto', 'Edad desconocida');
  END IF;

  v_anios := v_meses / 12;
  v_resto := v_meses % 12;

  RETURN jsonb_build_object(
    'meses', v_meses,
    'anios', v_anios,
    'texto', CASE
      WHEN v_anios = 0 THEN v_resto || ' ' || CASE WHEN v_resto = 1 THEN 'mes' ELSE 'meses' END
      WHEN v_resto = 0 THEN v_anios || ' ' || CASE WHEN v_anios = 1 THEN 'año' ELSE 'años' END
      ELSE v_anios || ' ' || CASE WHEN v_anios = 1 THEN 'año' ELSE 'años' END
           || ' ' || v_resto || ' ' || CASE WHEN v_resto = 1 THEN 'mes' ELSE 'meses' END
    END
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- internal.validar_dni / validar_ruc (dígito verificador SUNAT)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.validar_dni(p_dni VARCHAR)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_dni IS NOT NULL AND length(p_dni) = 8 AND p_dni ~ '^[0-9]{8}$';
$$;

CREATE OR REPLACE FUNCTION internal.validar_ruc(p_ruc VARCHAR)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_pesos INT[] := ARRAY[5,4,3,2,7,6,5,4,3,2];
  v_suma  INT := 0;
  v_dv    INT;
  v_calc  INT;
  i       INT;
BEGIN
  IF p_ruc IS NULL OR length(p_ruc) <> 11 OR p_ruc !~ '^[0-9]{11}$' THEN
    RETURN false;
  END IF;
  IF substring(p_ruc,1,2) NOT IN ('10','15','16','17','20') THEN RETURN false; END IF;

  FOR i IN 1..10 LOOP
    v_suma := v_suma + (substring(p_ruc, i, 1)::int * v_pesos[i]);
  END LOOP;

  v_calc := 11 - (v_suma % 11);
  v_calc := CASE v_calc WHEN 11 THEN 1 WHEN 10 THEN 0 ELSE v_calc END;
  v_dv   := substring(p_ruc, 11, 1)::int;

  RETURN v_calc = v_dv;
END;
$$;

-- -----------------------------------------------------------------------------
-- internal.validar_payload — exige claves obligatorias en un JSONB
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.validar_payload(
  p_payload JSONB,
  p_claves  TEXT[]
)
RETURNS VOID
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_clave TEXT;
BEGIN
  IF p_payload IS NULL THEN
    RAISE EXCEPTION 'Payload requerido' USING ERRCODE = 'P0001';
  END IF;
  FOREACH v_clave IN ARRAY p_claves LOOP
    IF NOT (p_payload ? v_clave) OR (p_payload->>v_clave) IS NULL THEN
      RAISE EXCEPTION 'Campo obligatorio faltante: %', v_clave USING ERRCODE = 'P0001';
    END IF;
  END LOOP;
END;
$$;

-- -----------------------------------------------------------------------------
-- internal.normalizar — texto sin tildes ni mayúsculas, para buscar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.normalizar(p_texto TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(unaccent(coalesce(p_texto, '')));
$$;

-- -----------------------------------------------------------------------------
-- internal.hay_solapamiento_cita
-- Un veterinario no puede tener dos citas encimadas en la misma empresa.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.hay_solapamiento_cita(
  p_empresa_id     UUID,
  p_veterinario_id UUID,
  p_inicio         TIMESTAMPTZ,
  p_duracion_min   INT,
  p_excluir_cita   UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM core.citas c
    WHERE c.empresa_id = p_empresa_id
      AND c.veterinario_id = p_veterinario_id
      AND c.deleted_at IS NULL
      AND c.estado NOT IN ('cancelada','no_asistio')
      AND (p_excluir_cita IS NULL OR c.id <> p_excluir_cita)
      AND tstzrange(c.fecha_hora, c.fecha_hora + (c.duracion_min || ' minutes')::interval)
          && tstzrange(p_inicio, p_inicio + (p_duracion_min || ' minutes')::interval)
  );
$$;

-- -----------------------------------------------------------------------------
-- internal.mover_stock
-- Única puerta de entrada para tocar inventario desde un SP: registra el
-- movimiento y deja que el trigger ajuste stock/lotes/denormalizado.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.mover_stock(
  p_empresa_id  UUID,
  p_producto_id UUID,
  p_tipo        core.tipo_movimiento_inventario,
  p_motivo      core.motivo_movimiento,
  p_cantidad    NUMERIC,
  p_user_id     UUID,
  p_almacen_id  UUID DEFAULT NULL,
  p_refs        JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
DECLARE
  v_id      UUID;
  v_stock   NUMERIC;
  v_almacen UUID;
BEGIN
  IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
    RAISE EXCEPTION 'La cantidad del movimiento debe ser mayor a cero' USING ERRCODE = 'P0001';
  END IF;

  v_almacen := COALESCE(p_almacen_id, (
    SELECT id FROM core.almacenes
     WHERE empresa_id = p_empresa_id AND es_principal = true LIMIT 1));

  -- Una salida no puede dejar el stock en negativo
  IF p_tipo IN ('salida','ajuste_negativo','merma','vencimiento','transferencia') THEN
    SELECT COALESCE(SUM(cantidad), 0) INTO v_stock
      FROM core.stock WHERE producto_id = p_producto_id
       AND (v_almacen IS NULL OR almacen_id = v_almacen);
    IF v_stock < p_cantidad THEN
      RAISE EXCEPTION 'Stock insuficiente: disponible %, solicitado %', v_stock, p_cantidad
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  INSERT INTO core.movimientos_inventario (
    empresa_id, producto_id, almacen_id, almacen_destino_id, lote_id,
    tipo, motivo, cantidad, costo_unitario,
    cliente_id, proveedor_id, mascota_id, consulta_id, comprobante_id, orden_compra_id,
    observaciones, created_by
  ) VALUES (
    p_empresa_id, p_producto_id, v_almacen,
    NULLIF(p_refs->>'almacen_destino_id','')::uuid,
    NULLIF(p_refs->>'lote_id','')::uuid,
    p_tipo, p_motivo, p_cantidad,
    COALESCE((p_refs->>'costo_unitario')::numeric, 0),
    NULLIF(p_refs->>'cliente_id','')::uuid,
    NULLIF(p_refs->>'proveedor_id','')::uuid,
    NULLIF(p_refs->>'mascota_id','')::uuid,
    NULLIF(p_refs->>'consulta_id','')::uuid,
    NULLIF(p_refs->>'comprobante_id','')::uuid,
    NULLIF(p_refs->>'orden_compra_id','')::uuid,
    p_refs->>'observaciones', p_user_id
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;
