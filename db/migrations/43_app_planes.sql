-- =============================================================================
-- 43_app_planes.sql — Planes preventivos
--
-- No confundir con `esquemas_vacunacion`, que ya existía: eso es el protocolo
-- clínico —qué vacuna toca a las seis semanas y cuándo el refuerzo— y es
-- medicina. Esto es lo comercial: el propietario paga una cuota y a cambio el
-- año de salud de su animal está cubierto.
--
-- Para la clínica es la diferencia entre un cliente que aparece cuando el perro
-- ya está enfermo y uno que viene tres veces al año. Y es ingreso que no
-- depende de que alguien se enferme.
--
-- La cobertura se aplica en `internal.registrar_cargo_servicio`, por donde pasan
-- todos los cargos: contratar un plan cambia lo que se cobra, no solo lo que
-- dice la ficha.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- app.sp_plan_guardar — el plan y sus beneficios, en una sola llamada
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_plan_guardar(
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
  v_ben   JSONB;
  v_n     INT := 0;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'planes:gestionar');
  PERFORM internal.validar_payload(p_payload, ARRAY['nombre']);

  IF v_id IS NOT NULL THEN
    SELECT to_jsonb(p) INTO v_antes FROM core.planes p
     WHERE p.id = v_id AND p.deleted_at IS NULL;
    IF v_antes IS NULL
       OR NOT internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp,
                                     (v_antes->>'empresa_id')::uuid) THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('NOT_FOUND','Plan no encontrado'));
    END IF;
  END IF;

  IF v_id IS NULL THEN
    INSERT INTO core.planes (
      empresa_id, codigo, nombre, descripcion, periodicidad, precio, vigencia_meses,
      especie_id, edad_min_meses, edad_max_meses, descuento_general_pct, color, created_by)
    VALUES (
      v_emp,
      COALESCE(NULLIF(p_payload->>'codigo',''), internal.siguiente_numero(v_emp, 'PLAN', 3)),
      p_payload->>'nombre', p_payload->>'descripcion',
      COALESCE((p_payload->>'periodicidad')::core.periodicidad_plan, 'mensual'),
      COALESCE(NULLIF(p_payload->>'precio','')::numeric, 0),
      COALESCE(NULLIF(p_payload->>'vigencia_meses','')::int, 12),
      NULLIF(p_payload->>'especie_id','')::uuid,
      NULLIF(p_payload->>'edad_min_meses','')::int,
      NULLIF(p_payload->>'edad_max_meses','')::int,
      COALESCE(NULLIF(p_payload->>'descuento_general_pct','')::numeric, 0),
      NULLIF(p_payload->>'color',''), p_user_id)
    RETURNING id INTO v_id;
  ELSE
    UPDATE core.planes SET
      nombre        = COALESCE(p_payload->>'nombre', nombre),
      descripcion   = COALESCE(p_payload->>'descripcion', descripcion),
      periodicidad  = COALESCE((p_payload->>'periodicidad')::core.periodicidad_plan, periodicidad),
      precio        = COALESCE(NULLIF(p_payload->>'precio','')::numeric, precio),
      vigencia_meses = COALESCE(NULLIF(p_payload->>'vigencia_meses','')::int, vigencia_meses),
      especie_id    = COALESCE(NULLIF(p_payload->>'especie_id','')::uuid, especie_id),
      edad_min_meses = COALESCE(NULLIF(p_payload->>'edad_min_meses','')::int, edad_min_meses),
      edad_max_meses = COALESCE(NULLIF(p_payload->>'edad_max_meses','')::int, edad_max_meses),
      descuento_general_pct = COALESCE(NULLIF(p_payload->>'descuento_general_pct','')::numeric,
                                       descuento_general_pct),
      color         = COALESCE(NULLIF(p_payload->>'color',''), color),
      estado        = COALESCE((p_payload->>'estado')::core.estado_generico, estado),
      updated_by    = p_user_id
    WHERE id = v_id;
  END IF;

  -- Los beneficios se actualizan en su sitio, NO se borran y se rehacen.
  --
  -- Borrar pone a NULL el `beneficio_id` de cada consumo ya registrado, así que
  -- un simple cambio de precio en el plan le devolvía a todos los suscriptores
  -- el cupo entero: las tres consultas que ya se habían usado volvían a estar
  -- disponibles. Un plan se edita a mitad de año; los contadores tienen que
  -- sobrevivir a esa edición.
  IF p_payload ? 'beneficios' THEN
    -- Los beneficios por CATEGORÍA no tienen clave estable (servicio_id va
    -- NULL y dos NULL nunca chocan en un índice único), así que esos sí se
    -- rehacen. Son siempre descuentos, que no llevan cupo que perder.
    DELETE FROM core.plan_beneficios WHERE plan_id = v_id AND servicio_id IS NULL;

    FOR v_ben IN SELECT * FROM jsonb_array_elements(p_payload->'beneficios') LOOP
      INSERT INTO core.plan_beneficios (
        plan_id, tipo, servicio_id, categoria_id, cantidad, descuento_pct, descripcion, orden)
      VALUES (
        v_id,
        COALESCE((v_ben->>'tipo')::core.tipo_beneficio_plan, 'servicio_incluido'),
        NULLIF(v_ben->>'servicio_id','')::uuid,
        NULLIF(v_ben->>'categoria_id','')::uuid,
        NULLIF(v_ben->>'cantidad','')::int,
        COALESCE(NULLIF(v_ben->>'descuento_pct','')::numeric, 0),
        v_ben->>'descripcion',
        v_n)
      ON CONFLICT (plan_id, servicio_id) DO UPDATE SET
        tipo          = EXCLUDED.tipo,
        categoria_id  = EXCLUDED.categoria_id,
        cantidad      = EXCLUDED.cantidad,
        descuento_pct = EXCLUDED.descuento_pct,
        descripcion   = EXCLUDED.descripcion,
        orden         = EXCLUDED.orden;
      v_n := v_n + 1;
    END LOOP;

    -- Lo que ya no está en la lista sí se va: el beneficio dejó de existir y
    -- que su consumo quede sin referencia es lo correcto.
    DELETE FROM core.plan_beneficios b
     WHERE b.plan_id = v_id
       AND b.servicio_id IS NOT NULL
       AND NOT EXISTS (
             SELECT 1 FROM jsonb_array_elements(p_payload->'beneficios') x
              WHERE NULLIF(x->>'servicio_id','')::uuid = b.servicio_id);
  END IF;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, CASE WHEN v_antes IS NULL THEN 'crear' ELSE 'actualizar' END,
    'planes', v_id, v_antes, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id, 'beneficios', v_n));

EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('CONFLICT','Ya existe un plan con ese código','codigo'));
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_planes_listar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_planes_listar(
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
  PERFORM internal.assert_permiso(p_user_id, 'planes:ver');

  SELECT COALESCE(jsonb_agg(x ORDER BY x.precio), '[]'::jsonb) INTO v_data
  FROM (
    SELECT p.id, p.codigo, p.nombre, p.descripcion, p.periodicidad, p.precio,
           p.vigencia_meses, p.especie_id, p.edad_min_meses, p.edad_max_meses,
           p.descuento_general_pct, p.color, p.estado,
           e.nombre AS especie,
           (SELECT count(*) FROM core.suscripciones s
             WHERE s.plan_id = p.id AND s.estado = 'activa')      AS suscritos,
           -- Lo que este plan factura al mes, para saber cuál vender.
           (SELECT COALESCE(SUM(s.precio_pactado), 0) FROM core.suscripciones s
             WHERE s.plan_id = p.id AND s.estado = 'activa')      AS ingreso_recurrente,
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id', b.id, 'tipo', b.tipo, 'servicio_id', b.servicio_id,
                     'servicio', sv.nombre, 'categoria_id', b.categoria_id,
                     'categoria', ca.nombre, 'cantidad', b.cantidad,
                     'descuento_pct', b.descuento_pct, 'descripcion', b.descripcion)
                   ORDER BY b.orden), '[]'::jsonb)
              FROM core.plan_beneficios b
              LEFT JOIN core.servicios sv ON sv.id = b.servicio_id
              LEFT JOIN core.categorias ca ON ca.id = b.categoria_id
             WHERE b.plan_id = p.id) AS beneficios
    FROM core.planes p
    LEFT JOIN core.especies e ON e.id = p.especie_id
    WHERE p.deleted_at IS NULL
      AND (v_global OR p.empresa_id = v_emp)
      AND (p_filtros->>'estado' IS NULL OR p.estado::text = p_filtros->>'estado')
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_plan_eliminar — baja lógica
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_plan_eliminar(
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
  v_emp UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_p   RECORD;
  v_act INT;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'planes:gestionar');

  SELECT * INTO v_p FROM core.planes WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND
     OR NOT internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, v_p.empresa_id) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Plan no encontrado'));
  END IF;

  SELECT count(*) INTO v_act FROM core.suscripciones
   WHERE plan_id = p_id AND estado = 'activa';
  IF v_act > 0 THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        format('El plan tiene %s suscripción(es) activa(s). Desactívalo para dejar de venderlo: '
               'quien ya lo contrató conserva su cobertura hasta que venza.', v_act)));
  END IF;

  UPDATE core.planes SET deleted_at = now(), estado = 'inactivo', updated_by = p_user_id
   WHERE id = p_id;

  PERFORM internal.registrar_auditoria(p_user_id, v_emp, 'eliminar', 'planes', p_id);
  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('eliminado', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_suscripcion_crear — se le vende el plan a un paciente
--
-- Se suscribe la mascota, no el propietario: quien se vacuna es el animal, y un
-- cliente con tres perros puede tener a uno en plan y a los otros no.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_suscripcion_crear(
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
  v_emp     UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_id      UUID;
  v_plan    RECORD;
  v_m       RECORD;
  v_meses   INT;
  v_inicio  DATE := COALESCE(NULLIF(p_payload->>'fecha_inicio','')::date, CURRENT_DATE);
  v_precio  NUMERIC(12,2);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'planes:vender');
  PERFORM internal.validar_payload(p_payload, ARRAY['plan_id','mascota_id']);

  SELECT * INTO v_plan FROM core.planes
   WHERE id = (p_payload->>'plan_id')::uuid AND deleted_at IS NULL
     AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, empresa_id);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Plan no encontrado'));
  END IF;
  IF v_plan.estado <> 'activo' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE','Ese plan ya no se vende'));
  END IF;

  SELECT m.id, m.cliente_id, m.especie_id, m.estado,
         internal.edad_mascota(m.fecha_nacimiento) AS edad
    INTO v_m
    FROM core.mascotas m
   WHERE m.id = (p_payload->>'mascota_id')::uuid AND m.deleted_at IS NULL
     AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, m.empresa_id);
  IF v_m.id IS NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Paciente no encontrado'));
  END IF;
  IF v_m.estado = 'fallecido' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE','El paciente figura como fallecido'));
  END IF;

  -- Vender un "Plan Cachorro" a un perro de diez años es un error que se
  -- descubre cuando toca aplicar un beneficio que no le corresponde.
  IF v_plan.especie_id IS NOT NULL AND v_m.especie_id IS DISTINCT FROM v_plan.especie_id THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        'Ese plan es para otra especie'));
  END IF;

  v_meses := COALESCE((v_m.edad->>'meses')::int, NULL);
  IF v_meses IS NOT NULL THEN
    IF v_plan.edad_min_meses IS NOT NULL AND v_meses < v_plan.edad_min_meses THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('BUSINESS_RULE',
          format('El plan es desde %s meses y el paciente tiene %s', v_plan.edad_min_meses, v_meses)));
    END IF;
    IF v_plan.edad_max_meses IS NOT NULL AND v_meses > v_plan.edad_max_meses THEN
      RETURN jsonb_build_object('ok', false,
        'error', internal.error_jsonb('BUSINESS_RULE',
          format('El plan es hasta %s meses y el paciente tiene %s', v_plan.edad_max_meses, v_meses)));
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM core.suscripciones
              WHERE mascota_id = v_m.id AND estado = 'activa') THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('CONFLICT',
        'Ese paciente ya tiene un plan activo. Cancélalo o espera a que venza.'));
  END IF;

  v_precio := COALESCE(NULLIF(p_payload->>'precio_pactado','')::numeric, v_plan.precio);

  INSERT INTO core.suscripciones (
    empresa_id, plan_id, mascota_id, cliente_id, codigo, fecha_inicio, fecha_fin,
    precio_pactado, periodicidad, proximo_cobro, notas, renovada_de, created_by)
  VALUES (
    v_emp, v_plan.id, v_m.id, v_m.cliente_id,
    internal.siguiente_numero(v_emp, 'SUS', 6),
    v_inicio,
    v_inicio + (v_plan.vigencia_meses || ' months')::interval - INTERVAL '1 day',
    v_precio,
    COALESCE((p_payload->>'periodicidad')::core.periodicidad_plan, v_plan.periodicidad),
    v_inicio + CASE COALESCE((p_payload->>'periodicidad')::core.periodicidad_plan, v_plan.periodicidad)
                 WHEN 'mensual'    THEN INTERVAL '1 month'
                 WHEN 'trimestral' THEN INTERVAL '3 months'
                 WHEN 'semestral'  THEN INTERVAL '6 months'
                 ELSE INTERVAL '1 year' END,
    p_payload->>'notas',
    NULLIF(p_payload->>'renovada_de','')::uuid,
    p_user_id)
  RETURNING id INTO v_id;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'crear', 'suscripciones', v_id, NULL, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'id', v_id, 'plan', v_plan.nombre, 'precio', v_precio));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_suscripcion_cancelar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_suscripcion_cancelar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_id             UUID,
  p_motivo         TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_s   RECORD;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'planes:vender');

  SELECT * INTO v_s FROM core.suscripciones WHERE id = p_id;
  IF NOT FOUND
     OR NOT internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, v_s.empresa_id) THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Suscripción no encontrada'));
  END IF;
  IF v_s.estado <> 'activa' THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('BUSINESS_RULE',
        format('La suscripción ya está %s', v_s.estado)));
  END IF;

  UPDATE core.suscripciones
     SET estado = 'cancelada', motivo_baja = p_motivo, updated_by = p_user_id
   WHERE id = p_id;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'cancelar', 'suscripciones', p_id, NULL,
    jsonb_build_object('motivo', p_motivo));

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_suscripciones_listar — la cartera de planes
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_suscripciones_listar(
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
  v_dias   INT     := COALESCE(NULLIF(p_filtros->>'por_vencer_dias','')::int, NULL);
  v_data   JSONB;
  v_meta   JSONB;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'planes:ver');

  SELECT COALESCE(jsonb_agg(x ORDER BY x.fecha_fin), '[]'::jsonb) INTO v_data
  FROM (
    SELECT s.id, s.codigo, s.estado, s.fecha_inicio, s.fecha_fin, s.precio_pactado,
           s.periodicidad, s.proximo_cobro, s.notas,
           (s.fecha_fin - CURRENT_DATE) AS dias_restantes,
           p.id AS plan_id, p.nombre AS plan, p.color,
           jsonb_build_object('id', m.id, 'nombre', m.nombre, 'foto_url', m.foto_url,
                              'especie', esp.nombre) AS mascota,
           jsonb_build_object('id', c.id,
                              'nombre', trim(c.nombres || ' ' || COALESCE(c.apellido_paterno,'')),
                              'telefono', c.telefono) AS propietario,
           -- Lo que lleva ahorrado: el mejor argumento para que renueve.
           (SELECT COALESCE(SUM(sc.valor_cubierto), 0)
              FROM core.suscripcion_consumos sc WHERE sc.suscripcion_id = s.id) AS ahorrado,
           (SELECT count(*) FROM core.suscripcion_consumos sc
             WHERE sc.suscripcion_id = s.id) AS usos
    FROM core.suscripciones s
    JOIN core.planes p   ON p.id = s.plan_id
    JOIN core.mascotas m ON m.id = s.mascota_id
    JOIN core.clientes c ON c.id = s.cliente_id
    LEFT JOIN core.especies esp ON esp.id = m.especie_id
    WHERE (v_global OR s.empresa_id = v_emp)
      AND (p_filtros->>'estado'     IS NULL OR s.estado::text = p_filtros->>'estado')
      AND (p_filtros->>'plan_id'    IS NULL OR s.plan_id = (p_filtros->>'plan_id')::uuid)
      AND (p_filtros->>'mascota_id' IS NULL OR s.mascota_id = (p_filtros->>'mascota_id')::uuid)
      AND (p_filtros->>'cliente_id' IS NULL OR s.cliente_id = (p_filtros->>'cliente_id')::uuid)
      AND (v_dias IS NULL
           OR (s.estado = 'activa' AND s.fecha_fin <= CURRENT_DATE + v_dias))
  ) x;

  SELECT jsonb_build_object(
    'activas',     count(*) FILTER (WHERE s.estado = 'activa'),
    'por_vencer',  count(*) FILTER (WHERE s.estado = 'activa'
                                      AND s.fecha_fin <= CURRENT_DATE + 30),
    'vencidas',    count(*) FILTER (WHERE s.estado = 'vencida'),
    'recurrente',  COALESCE(SUM(s.precio_pactado) FILTER (WHERE s.estado = 'activa'), 0))
  INTO v_meta
  FROM core.suscripciones s
  WHERE (v_global OR s.empresa_id = v_emp);

  RETURN jsonb_build_object('ok', true, 'data', v_data, 'meta', v_meta);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_suscripcion_estado — qué le queda al paciente
--
-- Lo que se le enseña al propietario cuando pregunta "¿y esto qué me cubre?".
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_suscripcion_estado(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_mascota_id     UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp  UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_s    RECORD;
  v_data JSONB;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'planes:ver');

  SELECT s.*, p.nombre AS plan, p.color, p.descuento_general_pct
    INTO v_s
    FROM core.suscripciones s
    JOIN core.planes p ON p.id = s.plan_id
   WHERE s.mascota_id = p_mascota_id
     AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, s.empresa_id)
     AND s.estado = 'activa'
   LIMIT 1;

  IF v_s.id IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'data', NULL);
  END IF;

  SELECT jsonb_build_object(
    'id', v_s.id, 'codigo', v_s.codigo, 'plan', v_s.plan, 'color', v_s.color,
    'fecha_inicio', v_s.fecha_inicio, 'fecha_fin', v_s.fecha_fin,
    'dias_restantes', v_s.fecha_fin - CURRENT_DATE,
    'precio_pactado', v_s.precio_pactado,
    'descuento_general_pct', v_s.descuento_general_pct,
    'ahorrado', (SELECT COALESCE(SUM(valor_cubierto), 0)
                   FROM core.suscripcion_consumos WHERE suscripcion_id = v_s.id),
    'beneficios', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'beneficio_id', b.id,
               'tipo',         b.tipo,
               'servicio',     COALESCE(sv.nombre, ca.nombre, b.descripcion),
               'incluidas',    b.cantidad,
               'usadas',       COALESCE(u.usadas, 0),
               'restantes',    CASE WHEN b.cantidad IS NULL THEN NULL
                                    ELSE GREATEST(b.cantidad - COALESCE(u.usadas, 0), 0) END,
               'descuento_pct', b.descuento_pct)
             ORDER BY b.orden), '[]'::jsonb)
        FROM core.plan_beneficios b
        LEFT JOIN core.servicios  sv ON sv.id = b.servicio_id
        LEFT JOIN core.categorias ca ON ca.id = b.categoria_id
        LEFT JOIN LATERAL (
          SELECT SUM(c.cantidad) AS usadas FROM core.suscripcion_consumos c
           WHERE c.suscripcion_id = v_s.id AND c.beneficio_id = b.id) u ON true
       WHERE b.plan_id = v_s.plan_id)
  ) INTO v_data;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_suscripciones_vencer — cierra las que pasaron de fecha
--
-- Sin esto, una suscripción vencida sigue en 'activa' y sigue cubriendo. Se
-- llama desde el trabajo diario del backend, y es idempotente.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_suscripciones_vencer(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_n   INT;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'planes:ver');

  UPDATE core.suscripciones
     SET estado = 'vencida'
   WHERE empresa_id = v_emp AND estado = 'activa' AND fecha_fin < CURRENT_DATE;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('vencidas', v_n));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

COMMENT ON FUNCTION app.fn_suscripcion_estado IS
  'Lo que le queda al paciente de su plan: beneficios usados, restantes y ahorro.';
