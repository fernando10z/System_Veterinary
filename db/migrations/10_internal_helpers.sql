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
  -- El token vive 15 minutos. Si en ese rato al usuario se le dio de baja o se
  -- le desactivó la cuenta, el token sigue firmado y válido: la comprobación
  -- del permiso es el único punto donde eso se puede notar.
  SELECT is_super_admin, rol_id INTO v_is_super, v_rol_id
  FROM core.users
  WHERE id = p_user_id AND deleted_at IS NULL AND estado = 'activo';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La cuenta no está activa' USING ERRCODE = '42501';
  END IF;

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
-- internal.password_invalida
-- Devuelve el motivo por el que una contraseña no sirve, o NULL si sirve.
--
-- Ocho caracteres a secas dejaban pasar "12345678" y el propio correo. En una
-- clínica la clave se comparte de viva voz y se escribe con guantes: no tiene
-- sentido exigir símbolos raros, pero sí que no sea adivinable de un vistazo.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.password_invalida(
  p_password TEXT,
  p_email    TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_local TEXT;
BEGIN
  IF p_password IS NULL OR length(p_password) < 8 THEN
    RETURN 'La contraseña debe tener al menos 8 caracteres';
  END IF;
  IF p_password !~ '[A-Za-zÁÉÍÓÚáéíóúÑñ]' THEN
    RETURN 'La contraseña debe incluir al menos una letra';
  END IF;
  IF p_password !~ '[0-9]' THEN
    RETURN 'La contraseña debe incluir al menos un número';
  END IF;
  IF lower(p_password) IN (
       '12345678','123456789','contrasena','password','qwertyui','abc12345',
       'clinica1','veterinaria1','admin123','11111111') THEN
    RETURN 'Esa contraseña es demasiado común, elige otra';
  END IF;
  IF p_email IS NOT NULL THEN
    v_local := split_part(lower(p_email), '@', 1);
    IF length(v_local) >= 4 AND position(v_local IN lower(p_password)) > 0 THEN
      RETURN 'La contraseña no puede contener tu correo';
    END IF;
  END IF;
  RETURN NULL;
END;
$$;


-- -----------------------------------------------------------------------------
-- internal.sede_por_defecto
-- La sede principal de la empresa. Si no hay ninguna, la crea con los datos de
-- la propia empresa.
--
-- Crear desde una función de lectura es raro, y aquí está justificado: `sedes`
-- llegó cuando ya había clínicas operando, y el resto del sistema necesita
-- SIEMPRE una sede a la que colgar una cita o una caja. La alternativa era
-- obligar a cada instalación existente a crearla a mano antes de poder seguir
-- trabajando, o dejar `sede_id` en NULL y que los informes por local mintieran.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.sede_por_defecto(p_empresa_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF p_empresa_id IS NULL THEN RETURN NULL; END IF;

  SELECT id INTO v_id FROM core.sedes
   WHERE empresa_id = p_empresa_id AND es_principal AND deleted_at IS NULL;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;

  -- Puede haber sedes sin principal si alguien la borró: se toma la más antigua.
  SELECT id INTO v_id FROM core.sedes
   WHERE empresa_id = p_empresa_id AND deleted_at IS NULL
   ORDER BY created_at LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;

  -- El código sale del mismo contador que usará la pantalla de sedes. Ponerlo
  -- a mano como 'SEDE-01' dejaba el contador en cero, y la primera sede que
  -- creara la clínica a mano chocaba contra esta.
  INSERT INTO core.sedes (
    empresa_id, codigo, nombre, direccion, distrito, provincia, departamento,
    ubigeo, telefono, correo, serie_boleta, serie_factura, es_principal)
  SELECT e.id, internal.siguiente_numero(e.id, 'SEDE', 2), 'Sede principal',
         e.direccion_fiscal, e.distrito,
         e.provincia, e.departamento, e.ubigeo, e.telefono, e.correo,
         e.serie_boleta_default, e.serie_factura_default, true
    FROM core.empresas e WHERE e.id = p_empresa_id
  ON CONFLICT (empresa_id, codigo) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    SELECT id INTO v_id FROM core.sedes
     WHERE empresa_id = p_empresa_id AND deleted_at IS NULL
     ORDER BY created_at LIMIT 1;
  END IF;

  RETURN v_id;
END;
$$;


-- -----------------------------------------------------------------------------
-- internal.sede_efectiva
-- Sobre qué local se está operando.
--
-- Orden: la sede que pide el SP (validada contra la empresa, que si no sería la
-- vía para escribir en el local de otro) → la sede base del usuario → la
-- principal. Un recepcionista de Miraflores no tiene que elegir nada para que
-- su caja y sus citas caigan en Miraflores.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.sede_efectiva(
  p_user_id    UUID,
  p_empresa_id UUID,
  p_sede_id    UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF p_sede_id IS NOT NULL THEN
    SELECT id INTO v_id FROM core.sedes
     WHERE id = p_sede_id AND empresa_id = p_empresa_id AND deleted_at IS NULL;
    IF v_id IS NULL THEN
      RAISE EXCEPTION 'La sede indicada no existe en esta empresa' USING ERRCODE = '42501';
    END IF;
    RETURN v_id;
  END IF;

  SELECT u.sede_id INTO v_id
    FROM core.users u
    JOIN core.sedes s ON s.id = u.sede_id AND s.deleted_at IS NULL
   WHERE u.id = p_user_id AND u.empresa_id = p_empresa_id;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;

  RETURN internal.sede_por_defecto(p_empresa_id);
END;
$$;

-- -----------------------------------------------------------------------------
-- internal.tiene_permiso — variante que responde en vez de abortar.
-- assert_permiso corta la operación; esto sirve cuando el permiso no decide si
-- se puede entrar, sino cuánto se ve una vez dentro.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.tiene_permiso(
  p_user_id        UUID,
  p_codigo_permiso VARCHAR
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
  SELECT COALESCE(
    (SELECT u.is_super_admin FROM core.users u
      WHERE u.id = p_user_id AND u.deleted_at IS NULL AND u.estado = 'activo'),
    false)
  OR EXISTS (
    SELECT 1
    FROM core.users u
    JOIN core.rol_permisos rp ON rp.rol_id = u.rol_id
    JOIN core.permisos p ON p.id = rp.permiso_id
    WHERE u.id = p_user_id AND u.deleted_at IS NULL AND u.estado = 'activo'
      AND p.codigo = p_codigo_permiso);
$$;

-- -----------------------------------------------------------------------------
-- internal.usuario_objetivo
-- Resuelve sobre QUÉ usuario actúa una operación de RRHH.
--
-- Marcar asistencia o pedir un permiso son acciones de autoservicio: cualquiera
-- las hace para sí mismo. Hacerlas en nombre de otro es cosa de RRHH — si no,
-- cualquiera podría fichar por un compañero o meterle vacaciones que, una vez
-- aprobadas, le bloquean la agenda.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.usuario_objetivo(
  p_actor    UUID,
  p_target   UUID,
  p_empresa  UUID,
  p_permiso  VARCHAR DEFAULT 'rrhh:gestionar'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
DECLARE
  v_emp_target UUID;
BEGIN
  IF p_target IS NULL OR p_target = p_actor THEN RETURN p_actor; END IF;

  PERFORM internal.assert_permiso(p_actor, p_permiso);

  SELECT empresa_id INTO v_emp_target
  FROM core.users WHERE id = p_target AND deleted_at IS NULL;

  IF NOT FOUND
     OR (v_emp_target IS DISTINCT FROM p_empresa
         AND NOT internal.es_acceso_global(p_actor, false)) THEN
    RAISE EXCEPTION 'Sin acceso al legajo de ese usuario' USING ERRCODE = '42501';
  END IF;

  RETURN p_target;
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

  -- La IP y el agente los deja el backend como ajustes de sesión antes de
  -- llamar al SP (`app.client_ip`, `app.user_agent`). El segundo argumento de
  -- current_setting evita que reviente cuando no están: hay SPs que se llaman
  -- desde psql o desde un cron, y ahí simplemente no hay petición HTTP.
  INSERT INTO core.audit_log (
    user_id, empresa_id, accion, entidad, entidad_id, datos_antes, datos_despues, diff,
    ip, user_agent
  ) VALUES (
    p_user_id, p_empresa_id, p_accion, p_entidad, p_entidad_id, p_antes, p_despues, v_diff,
    NULLIF(current_setting('app.client_ip', true), ''),
    NULLIF(current_setting('app.user_agent', true), '')
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
-- internal.lotes_a_consumir — FEFO: qué lote sale primero
--
-- Devuelve la repartición de una salida entre los lotes del producto, del
-- vencimiento más próximo al más lejano. Un lote vencido no se dispensa: solo
-- lo consumen los movimientos que existen justamente para sacarlo del stock
-- (merma, vencimiento, ajuste negativo).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.lotes_a_consumir(
  p_producto_id UUID,
  p_cantidad    NUMERIC,
  p_incluir_vencidos BOOLEAN DEFAULT false
)
RETURNS TABLE (lote_id UUID, cantidad NUMERIC, costo_unitario NUMERIC)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
DECLARE
  v_resta NUMERIC := p_cantidad;
  v_lote  RECORD;
BEGIN
  FOR v_lote IN
    SELECT l.id, l.cantidad AS disponible, l.costo_unitario
      FROM core.lotes l
     WHERE l.producto_id = p_producto_id
       AND l.cantidad > 0
       AND (p_incluir_vencidos
            OR l.fecha_vencimiento IS NULL
            OR l.fecha_vencimiento >= CURRENT_DATE)
     ORDER BY l.fecha_vencimiento NULLS LAST, l.created_at
  LOOP
    EXIT WHEN v_resta <= 0;
    lote_id        := v_lote.id;
    cantidad       := LEAST(v_resta, v_lote.disponible);
    costo_unitario := v_lote.costo_unitario;
    v_resta        := v_resta - cantidad;
    RETURN NEXT;
  END LOOP;
END;
$$;

-- -----------------------------------------------------------------------------
-- internal.mover_stock
-- Única puerta de entrada para tocar inventario desde un SP: registra el
-- movimiento y deja que el trigger ajuste stock/lotes/denormalizado.
--
-- Si el producto maneja lotes y quien llama no indica uno, la salida se reparte
-- entre los lotes por FEFO y se registra un movimiento por lote. Así el kardex
-- dice de qué lote salió cada dosis —lo que hay que poder responder cuando un
-- laboratorio retira un lote del mercado— y el saldo del lote deja de mentir.
-- -----------------------------------------------------------------------------
-- -----------------------------------------------------------------------------
-- internal.registrar_kardex — escribe una fila del kardex
--
-- Separada de mover_stock porque una salida repartida entre lotes escribe
-- varias filas: una por lote. Nadie más debería llamarla: la puerta pública
-- sigue siendo internal.mover_stock.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.registrar_kardex(
  p_empresa_id  UUID,
  p_producto_id UUID,
  p_almacen_id  UUID,
  p_tipo        core.tipo_movimiento_inventario,
  p_motivo      core.motivo_movimiento,
  p_cantidad    NUMERIC,
  p_user_id     UUID,
  p_refs        JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO core.movimientos_inventario (
    empresa_id, producto_id, almacen_id, almacen_destino_id, lote_id,
    tipo, motivo, cantidad, costo_unitario,
    cliente_id, proveedor_id, mascota_id, consulta_id, comprobante_id, orden_compra_id,
    observaciones, created_by
  ) VALUES (
    p_empresa_id, p_producto_id, p_almacen_id,
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
  v_id       UUID;
  v_stock    NUMERIC;
  v_almacen  UUID;
  v_es_salida BOOLEAN;
  v_lotes    BOOLEAN;
  v_lote_ref UUID := NULLIF(p_refs->>'lote_id','')::uuid;
  v_saca_vencidos BOOLEAN;
  v_repartido NUMERIC := 0;
  v_tramo    RECORD;
BEGIN
  IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
    RAISE EXCEPTION 'La cantidad del movimiento debe ser mayor a cero' USING ERRCODE = 'P0001';
  END IF;

  v_almacen := COALESCE(p_almacen_id, (
    SELECT id FROM core.almacenes
     WHERE empresa_id = p_empresa_id AND es_principal = true LIMIT 1));

  v_es_salida := p_tipo IN ('salida','ajuste_negativo','merma','vencimiento','transferencia');

  -- Una salida no puede dejar el stock en negativo
  IF v_es_salida THEN
    SELECT COALESCE(SUM(cantidad), 0) INTO v_stock
      FROM core.stock WHERE producto_id = p_producto_id
       AND (v_almacen IS NULL OR almacen_id = v_almacen);
    IF v_stock < p_cantidad THEN
      RAISE EXCEPTION 'Stock insuficiente: disponible %, solicitado %', v_stock, p_cantidad
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  SELECT maneja_lotes INTO v_lotes FROM core.productos WHERE id = p_producto_id;

  -- Salida de un producto con lotes y sin lote indicado: se reparte por FEFO.
  IF v_es_salida AND COALESCE(v_lotes, false) AND v_lote_ref IS NULL
     AND p_tipo <> 'transferencia'
     AND EXISTS (SELECT 1 FROM core.lotes WHERE producto_id = p_producto_id AND cantidad > 0)
  THEN
    -- Los movimientos que existen para retirar producto vencido sí lo alcanzan;
    -- una salida clínica o una venta, no.
    v_saca_vencidos := p_tipo IN ('merma','vencimiento','ajuste_negativo');

    FOR v_tramo IN
      SELECT * FROM internal.lotes_a_consumir(p_producto_id, p_cantidad, v_saca_vencidos)
    LOOP
      v_id := internal.registrar_kardex(
        p_empresa_id, p_producto_id, v_almacen, p_tipo, p_motivo,
        v_tramo.cantidad, p_user_id,
        p_refs || jsonb_build_object(
          'lote_id', v_tramo.lote_id,
          'costo_unitario', COALESCE((p_refs->>'costo_unitario')::numeric, v_tramo.costo_unitario)));
      v_repartido := v_repartido + v_tramo.cantidad;
    END LOOP;

    IF v_repartido < p_cantidad THEN
      RAISE EXCEPTION
        'Stock insuficiente en lotes vigentes: disponible %, solicitado %. Revisa vencimientos.',
        v_repartido, p_cantidad USING ERRCODE = 'P0001';
    END IF;

    RETURN v_id;
  END IF;

  RETURN internal.registrar_kardex(
    p_empresa_id, p_producto_id, v_almacen, p_tipo, p_motivo,
    p_cantidad, p_user_id, p_refs);
END;
$$;

-- -----------------------------------------------------------------------------
-- internal.consumir_producto_clinico
--
-- Puerta única del consumo clínico: descuenta del inventario **y** deja el
-- consumo pendiente de cobro. Antes cada acto clínico llamaba a mover_stock por
-- su cuenta, así que la vacuna salía del almacén y no llegaba nunca a la
-- cuenta del propietario. Un solo camino evita esa fuga.
--
-- La mascota se deriva del acto cuando quien llama no la manda: un insumo
-- consumido en una consulta es, por definición, de ese paciente.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.consumir_producto_clinico(
  p_empresa_id  UUID,
  p_producto_id UUID,
  p_cantidad    NUMERIC,
  p_user_id     UUID,
  p_refs        JSONB DEFAULT '{}'::jsonb   -- mascota_id, consulta_id, cirugia_id,
                                            -- hospitalizacion_id, orden_servicio_id,
                                            -- almacen_id, precio_unitario, observaciones
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
DECLARE
  v_id      UUID;
  v_mascota UUID := NULLIF(p_refs->>'mascota_id','')::uuid;
  v_consulta UUID := NULLIF(p_refs->>'consulta_id','')::uuid;
  v_cirugia  UUID := NULLIF(p_refs->>'cirugia_id','')::uuid;
  v_hosp     UUID := NULLIF(p_refs->>'hospitalizacion_id','')::uuid;
  v_precio  NUMERIC(12,2);
BEGIN
  -- El paciente se hereda del acto clínico si no vino explícito.
  IF v_mascota IS NULL THEN
    v_mascota := COALESCE(
      (SELECT mascota_id FROM core.consultas         WHERE id = v_consulta),
      (SELECT mascota_id FROM core.cirugias          WHERE id = v_cirugia),
      (SELECT mascota_id FROM core.hospitalizaciones WHERE id = v_hosp));
  END IF;

  SELECT COALESCE(NULLIF(p_refs->>'precio_unitario','')::numeric, precio_venta)
    INTO v_precio
    FROM core.productos WHERE id = p_producto_id AND empresa_id = p_empresa_id;

  IF v_precio IS NULL THEN
    RAISE EXCEPTION 'Producto no encontrado' USING ERRCODE = 'P0002';
  END IF;

  PERFORM internal.mover_stock(
    p_empresa_id, p_producto_id, 'salida', 'uso_clinico', p_cantidad, p_user_id,
    NULLIF(p_refs->>'almacen_id','')::uuid,
    jsonb_build_object(
      'mascota_id', v_mascota,
      'consulta_id', v_consulta,
      'observaciones', COALESCE(p_refs->>'observaciones', 'Insumo usado en atención clínica')));

  INSERT INTO core.insumos_utilizados (
    empresa_id, producto_id, mascota_id, consulta_id, cirugia_id,
    hospitalizacion_id, orden_servicio_id, cantidad, precio_unitario, created_by
  ) VALUES (
    p_empresa_id, p_producto_id, v_mascota, v_consulta, v_cirugia, v_hosp,
    NULLIF(p_refs->>'orden_servicio_id','')::uuid,
    p_cantidad, v_precio, p_user_id
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;


-- -----------------------------------------------------------------------------
-- internal.cobertura_plan
-- ¿Este servicio, para este paciente, lo cubre su plan preventivo?
--
-- Devuelve qué suscripción aplica, qué beneficio, cuánto se paga al final y
-- cuánto se ahorró. Si el paciente no tiene plan, devuelve el precio de lista y
-- ya está: quien llama no tiene que saber si hay planes en esta clínica.
--
-- El orden importa. Primero el beneficio del servicio exacto —"4 consultas
-- incluidas"—, luego el de su categoría, y por último el descuento general del
-- plan. Un servicio incluido con el cupo agotado NO cae al descuento general
-- por accidente: cae al descuento del propio beneficio si lo tiene, y si no, al
-- general. Cualquier otra cosa sería regalar de más o cobrar de más, y las dos
-- se notan en el mostrador.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.cobertura_plan(
  p_empresa_id  UUID,
  p_mascota_id  UUID,
  p_servicio_id UUID,
  p_precio      NUMERIC,
  p_cantidad    NUMERIC DEFAULT 1
)
RETURNS TABLE (
  suscripcion_id UUID,
  beneficio_id   UUID,
  incluido       BOOLEAN,
  precio_final   NUMERIC,
  ahorro         NUMERIC,
  motivo         TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
DECLARE
  v_sus      RECORD;
  v_ben      RECORD;
  v_usado    NUMERIC := 0;
  v_cat      UUID;
  v_dto      NUMERIC := 0;
  v_precio   NUMERIC := COALESCE(p_precio, 0);
BEGIN
  suscripcion_id := NULL; beneficio_id := NULL; incluido := false;
  precio_final := v_precio; ahorro := 0; motivo := NULL;

  IF p_mascota_id IS NULL OR p_servicio_id IS NULL THEN
    RETURN NEXT; RETURN;
  END IF;

  SELECT s.id, s.plan_id, p.descuento_general_pct, p.nombre
    INTO v_sus
    FROM core.suscripciones s
    JOIN core.planes p ON p.id = s.plan_id
   WHERE s.mascota_id = p_mascota_id
     AND s.empresa_id = p_empresa_id
     AND s.estado = 'activa'
     AND CURRENT_DATE BETWEEN s.fecha_inicio AND s.fecha_fin
   LIMIT 1;

  IF v_sus.id IS NULL THEN
    RETURN NEXT; RETURN;
  END IF;

  suscripcion_id := v_sus.id;

  -- ---- 1. Beneficio del servicio exacto -------------------------------------
  SELECT b.* INTO v_ben
    FROM core.plan_beneficios b
   WHERE b.plan_id = v_sus.plan_id AND b.servicio_id = p_servicio_id;

  -- ---- 2. Si no, el de su categoría ------------------------------------------
  IF v_ben.id IS NULL THEN
    SELECT s.categoria_id INTO v_cat FROM core.servicios s WHERE s.id = p_servicio_id;
    IF v_cat IS NOT NULL THEN
      SELECT b.* INTO v_ben
        FROM core.plan_beneficios b
       WHERE b.plan_id = v_sus.plan_id AND b.categoria_id = v_cat
         AND b.servicio_id IS NULL
       LIMIT 1;
    END IF;
  END IF;

  IF v_ben.id IS NOT NULL THEN
    beneficio_id := v_ben.id;

    IF v_ben.tipo = 'servicio_incluido' THEN
      SELECT COALESCE(SUM(c.cantidad), 0) INTO v_usado
        FROM core.suscripcion_consumos c
       WHERE c.suscripcion_id = v_sus.id AND c.beneficio_id = v_ben.id;

      -- cantidad NULL = sin tope dentro de la vigencia.
      IF v_ben.cantidad IS NULL OR v_usado + p_cantidad <= v_ben.cantidad THEN
        incluido     := true;
        precio_final := 0;
        ahorro       := round(v_precio * p_cantidad, 2);
        motivo       := format('Incluido en %s', v_sus.nombre);
        RETURN NEXT; RETURN;
      END IF;

      -- Cupo agotado: queda el descuento, pero esto ya NO consume el beneficio.
      -- Se suelta el beneficio_id para que el contador no siga subiendo y la
      -- ficha del propietario no acabe diciendo "4 usadas de 3".
      motivo := format('Cupo agotado en %s (%s de %s usados)',
                       v_sus.nombre, trunc(v_usado), v_ben.cantidad);
      beneficio_id := NULL;
    END IF;

    v_dto := GREATEST(v_ben.descuento_pct, 0);
  END IF;

  -- ---- 3. Descuento general del plan -----------------------------------------
  IF v_dto = 0 THEN
    v_dto := COALESCE(v_sus.descuento_general_pct, 0);
    IF v_dto > 0 AND motivo IS NULL THEN
      motivo := format('%s%% de descuento por %s', v_dto, v_sus.nombre);
    END IF;
  ELSIF motivo IS NULL THEN
    motivo := format('%s%% de descuento por %s', v_dto, v_sus.nombre);
  END IF;

  IF v_dto > 0 THEN
    precio_final := round(v_precio * (1 - v_dto / 100.0), 2);
    ahorro       := round((v_precio - precio_final) * p_cantidad, 2);
  END IF;

  RETURN NEXT;
END;
$$;

-- -----------------------------------------------------------------------------
-- internal.registrar_cargo_servicio
--
-- Deja un servicio prestado como pendiente de cobro. La usan los actos que
-- tienen tarifa propia —vacunación, cirugía, día de hospitalización— para que
-- el trabajo hecho llegue a la cuenta del propietario sin que recepción tenga
-- que acordarse de agregarlo a mano.
--
-- Es idempotente por acto: llamarla dos veces sobre la misma cirugía no cobra
-- dos veces.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.registrar_cargo_servicio(
  p_empresa_id  UUID,
  p_servicio_id UUID,
  p_mascota_id  UUID,
  p_user_id     UUID,
  p_cantidad    NUMERIC DEFAULT 1,
  p_refs        JSONB DEFAULT '{}'::jsonb   -- consulta_id, cita_id, veterinario_id,
                                            -- descripcion, precio_unitario,
                                            -- origen_tabla, origen_id
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
DECLARE
  v_id      UUID;
  v_cliente UUID;
  v_precio  NUMERIC(12,2);
  v_tabla   TEXT := NULLIF(p_refs->>'origen_tabla','');
  v_origen  UUID := NULLIF(p_refs->>'origen_id','')::uuid;
  v_cob     RECORD;
BEGIN
  IF p_servicio_id IS NULL OR p_mascota_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT cliente_id INTO v_cliente FROM core.mascotas WHERE id = p_mascota_id;
  IF v_cliente IS NULL THEN RETURN NULL; END IF;

  SELECT COALESCE(NULLIF(p_refs->>'precio_unitario','')::numeric, s.precio)
    INTO v_precio
    FROM core.servicios s
   WHERE s.id = p_servicio_id AND s.empresa_id = p_empresa_id AND s.deleted_at IS NULL;

  IF v_precio IS NULL THEN RETURN NULL; END IF;

  -- Idempotencia: el mismo acto no se cobra dos veces aunque se reabra.
  IF v_tabla IS NOT NULL AND v_origen IS NOT NULL THEN
    SELECT id INTO v_id FROM core.ordenes_servicio
     WHERE empresa_id = p_empresa_id AND origen_tabla = v_tabla AND origen_id = v_origen
       AND estado <> 'anulado';
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  END IF;

  -- ¿Lo cubre el plan preventivo del paciente?
  --
  -- Aquí, y no en cada SP clínico, porque por esta función pasan TODOS los
  -- cargos del sistema: consulta, vacuna, desparasitación, cirugía, día de
  -- hospitalización y baño. Poner el plan en este punto es lo que hace que
  -- contratar uno cambie de verdad lo que el propietario paga, en vez de ser
  -- una etiqueta bonita en su ficha.
  SELECT * INTO v_cob
    FROM internal.cobertura_plan(p_empresa_id, p_mascota_id, p_servicio_id,
                                 v_precio, p_cantidad);

  INSERT INTO core.ordenes_servicio (
    empresa_id, codigo, mascota_id, cliente_id, servicio_id, veterinario_id,
    cita_id, consulta_id, cantidad, precio_unitario, descuento, total,
    descripcion, origen_tabla, origen_id, estado, created_by,
    suscripcion_id, cubierto_por_plan
  ) VALUES (
    p_empresa_id, internal.siguiente_numero(p_empresa_id, 'OS', 6),
    p_mascota_id, v_cliente, p_servicio_id,
    COALESCE(NULLIF(p_refs->>'veterinario_id','')::uuid, p_user_id),
    NULLIF(p_refs->>'cita_id','')::uuid,
    NULLIF(p_refs->>'consulta_id','')::uuid,
    p_cantidad, v_precio,
    COALESCE(v_cob.ahorro, 0),
    round(p_cantidad * COALESCE(v_cob.precio_final, v_precio), 2),
    -- El motivo va en la descripción: el propietario tiene derecho a ver por
    -- qué su consulta sale en cero, y el mostrador a poder explicárselo.
    COALESCE(p_refs->>'descripcion', '') ||
      CASE WHEN v_cob.motivo IS NOT NULL THEN ' — ' || v_cob.motivo ELSE '' END,
    v_tabla, v_origen, 'completado', p_user_id,
    v_cob.suscripcion_id, COALESCE(v_cob.incluido, false)
  ) RETURNING id INTO v_id;

  -- El consumo se anota solo cuando el plan puso algo: sin esto, el cupo de
  -- "4 consultas al año" nunca bajaría y el plan sería infinito.
  IF v_cob.suscripcion_id IS NOT NULL AND COALESCE(v_cob.ahorro, 0) > 0 THEN
    INSERT INTO core.suscripcion_consumos (
      suscripcion_id, beneficio_id, servicio_id, orden_servicio_id,
      cantidad, valor_cubierto, created_by)
    VALUES (v_cob.suscripcion_id, v_cob.beneficio_id, p_servicio_id, v_id,
            p_cantidad, v_cob.ahorro, p_user_id);
  END IF;

  RETURN v_id;
END;
$$;
