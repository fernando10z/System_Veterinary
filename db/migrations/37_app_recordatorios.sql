-- =============================================================================
-- 37_app_recordatorios.sql
-- El recordatorio deja de ser una nota y se vuelve un mensaje que se manda.
--
-- La cola de recordatorios existía desde el principio —la vacuna genera su
-- refuerzo, la consulta su control— pero no había forma de contactar a nadie:
-- recepción leía la lista y tipeaba el mensaje a mano, uno por uno.
--
-- En el Perú ese contacto se hace por WhatsApp, no por correo. Y se hace desde
-- el teléfono del mostrador, no desde una API de pago que una clínica de
-- barrio no va a contratar. Así que lo que aporta el ERP es lo que realmente
-- falta: el número en formato internacional y el texto ya redactado, listo
-- para abrir la conversación. El envío lo hace WhatsApp.
--
-- Cada clínica redacta sus plantillas: el tono con el que una veterinaria le
-- habla a sus clientes no lo decide el software.
--
-- Idempotente.
-- =============================================================================

SET search_path = app, internal, core, public;

-- -----------------------------------------------------------------------------
-- internal.telefono_whatsapp
--
-- Un número peruano se guarda como lo dicta el propietario ("987 654 321",
-- "01 445 5667") y WhatsApp lo quiere en formato internacional sin signos.
-- Un celular peruano tiene 9 dígitos y empieza con 9; un fijo de Lima, 7 u 8
-- con prefijo 01. WhatsApp sólo sirve para celulares, así que un fijo devuelve
-- NULL y la pantalla ofrece llamar en vez de escribir.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.telefono_whatsapp(p_telefono TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v TEXT := regexp_replace(COALESCE(p_telefono, ''), '[^0-9]', '', 'g');
BEGIN
  IF v = '' THEN RETURN NULL; END IF;

  -- Ya viene con código de país.
  IF length(v) = 11 AND left(v, 2) = '51' AND substr(v, 3, 1) = '9' THEN
    RETURN v;
  END IF;

  -- Celular peruano: 9 dígitos que empiezan en 9.
  IF length(v) = 9 AND left(v, 1) = '9' THEN
    RETURN '51' || v;
  END IF;

  -- Número extranjero ya internacionalizado (se guardó con "+").
  IF btrim(COALESCE(p_telefono, '')) LIKE '+%' AND length(v) BETWEEN 10 AND 15 THEN
    RETURN v;
  END IF;

  -- Fijo u otro formato: no hay WhatsApp al que escribir.
  RETURN NULL;
END;
$$;

-- -----------------------------------------------------------------------------
-- internal.render_plantilla — reemplaza las variables del texto
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.render_plantilla(p_texto TEXT, p_vars JSONB)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_out TEXT := COALESCE(p_texto, '');
  v_k   TEXT;
BEGIN
  FOR v_k IN SELECT jsonb_object_keys(COALESCE(p_vars, '{}'::jsonb)) LOOP
    v_out := replace(v_out, '{{' || v_k || '}}', COALESCE(p_vars->>v_k, ''));
  END LOOP;
  -- Lo que quedó sin reemplazar se borra: es preferible una frase corta a
  -- mandarle al propietario un "{{fecha}}" en el mensaje.
  RETURN btrim(regexp_replace(v_out, '\{\{[a-z_]+\}\}', '', 'g'));
END;
$$;

-- -----------------------------------------------------------------------------
-- internal.plantilla_de — la de la empresa, o el texto por defecto
--
-- Una clínica recién dada de alta no tiene plantillas y aun así tiene que
-- poder contactar a sus clientes desde el primer día.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.plantilla_de(p_empresa_id UUID, p_tipo TEXT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
DECLARE
  v_texto TEXT;
BEGIN
  SELECT texto INTO v_texto FROM core.plantillas_mensaje
   WHERE empresa_id = p_empresa_id AND tipo = p_tipo
     AND canal = 'whatsapp' AND estado = 'activo';

  IF v_texto IS NOT NULL THEN RETURN v_texto; END IF;

  RETURN CASE p_tipo
    WHEN 'vacuna' THEN
      'Hola {{propietario}}, te escribimos de {{clinica}}. A {{paciente}} le toca el refuerzo de su vacuna el {{fecha}}. ¿Coordinamos una cita?'
    WHEN 'desparasitacion' THEN
      'Hola {{propietario}}, te escribimos de {{clinica}}. A {{paciente}} le corresponde su desparasitación el {{fecha}}. ¿Te reservamos un horario?'
    WHEN 'control' THEN
      'Hola {{propietario}}, te escribimos de {{clinica}}. El control de {{paciente}} está previsto para el {{fecha}}. ¿Confirmamos la cita?'
    WHEN 'cita' THEN
      'Hola {{propietario}}, te recordamos la cita de {{paciente}} en {{clinica}} el {{fecha}}. Si no puedes asistir, avísanos y la reprogramamos.'
    WHEN 'cumpleanios' THEN
      '¡Hola {{propietario}}! Hoy {{paciente}} está de cumpleaños. Le mandamos un saludo de todo el equipo de {{clinica}}. 🎉'
    WHEN 'deuda' THEN
      'Hola {{propietario}}, te escribimos de {{clinica}} por el saldo pendiente de la atención de {{paciente}}. Cualquier duda, con gusto la vemos.'
    ELSE
      'Hola {{propietario}}, te escribimos de {{clinica}} por {{titulo}}.'
  END;
END;
$$;

-- -----------------------------------------------------------------------------
-- app.fn_recordatorios_listar
--
-- La cola de contactos del día, ya con el mensaje redactado y el número en
-- formato internacional. Se reemplaza la versión anterior, que además filtraba
-- por empresa a secas: gerencia, que no tiene empresa propia, veía sólo la
-- primera. La convención del sistema es `es_acceso_global OR empresa_id = …`.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_recordatorios_listar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_dias           INT DEFAULT 7
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
  PERFORM internal.assert_permiso(p_user_id, 'citas:listar');

  SELECT COALESCE(jsonb_agg(x ORDER BY x.fecha_objetivo), '[]'::jsonb) INTO v_data
  FROM (
    SELECT r.id, r.tipo, r.titulo, r.mensaje, r.fecha_objetivo, r.canal,
           r.enviado_at, r.completado,
           (r.fecha_objetivo - CURRENT_DATE) AS dias_restantes,
           r.cliente_id,
           trim(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'')) AS cliente,
           cl.telefono AS cliente_telefono, cl.correo AS cliente_correo,
           cl.acepta_marketing,
           r.mascota_id, m.nombre AS mascota, m.foto_url AS mascota_foto,
           internal.telefono_whatsapp(cl.telefono) AS whatsapp,
           -- El texto ya armado: recepción abre WhatsApp y manda, no redacta.
           internal.render_plantilla(
             internal.plantilla_de(r.empresa_id, r.tipo),
             jsonb_build_object(
               'propietario',      split_part(trim(cl.nombres), ' ', 1),
               'paciente',         COALESCE(m.nombre, 'tu mascota'),
               'clinica',          COALESCE(e.nombre_comercial, e.razon_social),
               'telefono_clinica', COALESCE(e.telefono, ''),
               'titulo',           r.titulo,
               'fecha',            to_char(r.fecha_objetivo, 'DD/MM/YYYY'))
           ) AS mensaje_sugerido
    FROM core.recordatorios r
    JOIN core.clientes cl ON cl.id = r.cliente_id
    JOIN core.empresas e  ON e.id = r.empresa_id
    LEFT JOIN core.mascotas m ON m.id = r.mascota_id
    WHERE r.completado = false
      AND (v_global OR r.empresa_id = v_emp)
      AND r.fecha_objetivo <= CURRENT_DATE + COALESCE(p_dias, 7)
      -- Un paciente fallecido no recibe recordatorios de refuerzo.
      AND (m.id IS NULL OR m.estado <> 'fallecido')
      AND cl.estado = 'activo' AND cl.deleted_at IS NULL
  ) x;

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_recordatorio_contactar
--
-- Se contactó al propietario. Marca el recordatorio como enviado y deja el
-- contacto en la bitácora del cliente, que es donde alguien va a buscar
-- "¿le avisamos o no?" tres semanas después.
--
-- No lo da por completado: enviado y respondido son cosas distintas. Se
-- completa cuando el propietario agenda, o a mano si no contesta.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_recordatorio_contactar(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_id             UUID,
  p_payload        JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_r   RECORD;
BEGIN
  SELECT * INTO v_r FROM core.recordatorios
   WHERE id = p_id
     AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, empresa_id);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Recordatorio no encontrado'));
  END IF;

  UPDATE core.recordatorios
     SET enviado_at = COALESCE(enviado_at, now()),
         completado = COALESCE((p_payload->>'completar')::boolean, completado)
   WHERE id = p_id;

  INSERT INTO core.comunicaciones (
    empresa_id, cliente_id, mascota_id, user_id, tipo, asunto, mensaje, fecha, created_by)
  VALUES (
    v_r.empresa_id, v_r.cliente_id, v_r.mascota_id, p_user_id,
    COALESCE((p_payload->>'canal')::core.tipo_comunicacion, 'whatsapp'),
    v_r.titulo,
    COALESCE(NULLIF(p_payload->>'mensaje',''), v_r.mensaje, v_r.titulo),
    now(), p_user_id);

  RETURN jsonb_build_object('ok', true,
    'data', jsonb_build_object('id', p_id, 'enviado', true));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- -----------------------------------------------------------------------------
-- app.sp_recordatorios_generar_citas
--
-- Los recordatorios de vacuna y control nacen del acto clínico. El de la cita
-- de mañana no: hay que salir a buscarlo. Esto arma la tanda del día y es
-- idempotente —`citas.recordatorio_enviado_at` impide que el propietario
-- reciba el mismo aviso tres veces porque alguien apretó el botón de nuevo.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sp_recordatorios_generar_citas(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_dias           INT DEFAULT 1
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp   UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_c     RECORD;
  v_n     INT := 0;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'citas:editar');

  FOR v_c IN
    SELECT c.id, c.empresa_id, c.cliente_id, c.mascota_id, c.fecha_hora,
           m.nombre AS mascota
      FROM core.citas c
      JOIN core.mascotas m ON m.id = c.mascota_id
     WHERE c.deleted_at IS NULL
       AND c.empresa_id = v_emp
       AND c.estado IN ('programada','confirmada')
       AND c.recordatorio_enviado_at IS NULL
       AND (c.fecha_hora AT TIME ZONE 'America/Lima')::date
           BETWEEN CURRENT_DATE AND CURRENT_DATE + COALESCE(p_dias, 1)
  LOOP
    INSERT INTO core.recordatorios (
      empresa_id, cliente_id, mascota_id, tipo, titulo, mensaje,
      fecha_objetivo, canal, entidad_ref, entidad_id)
    VALUES (
      v_c.empresa_id, v_c.cliente_id, v_c.mascota_id, 'cita',
      'Cita de ' || v_c.mascota,
      'Cita programada para el ' ||
        to_char(v_c.fecha_hora AT TIME ZONE 'America/Lima', 'DD/MM/YYYY a las HH24:MI') || '.',
      (v_c.fecha_hora AT TIME ZONE 'America/Lima')::date, 'whatsapp', 'citas', v_c.id);

    UPDATE core.citas SET recordatorio_enviado_at = now() WHERE id = v_c.id;
    v_n := v_n + 1;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('generados', v_n));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- PLANTILLAS: lectura y edición
-- =============================================================================

CREATE OR REPLACE FUNCTION app.fn_plantillas_mensaje_listar(
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
  v_emp  UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_data JSONB;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'citas:listar');

  -- Se listan TODOS los tipos, tengan plantilla propia o no: la que no se
  -- editó muestra el texto por defecto, que es el que se va a mandar.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'tipo',        t.tipo,
           'nombre',      t.nombre,
           'texto',       COALESCE(p.texto, internal.plantilla_de(v_emp, t.tipo)),
           'texto_defecto', internal.plantilla_de(NULL, t.tipo),
           'personalizada', p.id IS NOT NULL,
           'id',          p.id,
           'estado',      COALESCE(p.estado, 'activo')) ORDER BY t.orden), '[]'::jsonb)
    INTO v_data
    FROM (VALUES
      ('vacuna',          'Refuerzo de vacuna',   1),
      ('desparasitacion', 'Desparasitación',      2),
      ('control',         'Control posterior',    3),
      ('cita',            'Recordatorio de cita', 4),
      ('cumpleanios',     'Cumpleaños',           5),
      ('deuda',           'Saldo pendiente',      6)
    ) AS t(tipo, nombre, orden)
    LEFT JOIN core.plantillas_mensaje p
      ON p.empresa_id = v_emp AND p.tipo = t.tipo AND p.canal = 'whatsapp';

  RETURN jsonb_build_object('ok', true, 'data', v_data);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

CREATE OR REPLACE FUNCTION app.sp_plantilla_mensaje_guardar(
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
  v_emp UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'catalogos:editar');
  PERFORM internal.validar_payload(p_payload, ARRAY['tipo','texto']);

  INSERT INTO core.plantillas_mensaje (empresa_id, tipo, canal, nombre, texto, estado)
  VALUES (
    v_emp, p_payload->>'tipo', 'whatsapp',
    COALESCE(NULLIF(p_payload->>'nombre',''), p_payload->>'tipo'),
    p_payload->>'texto',
    COALESCE((p_payload->>'estado')::core.estado_generico, 'activo'))
  ON CONFLICT (empresa_id, tipo, canal) DO UPDATE
    SET texto = EXCLUDED.texto,
        nombre = EXCLUDED.nombre,
        estado = EXCLUDED.estado,
        updated_at = now()
  RETURNING id INTO v_id;

  PERFORM internal.registrar_auditoria(
    p_user_id, v_emp, 'guardar', 'plantillas_mensaje', v_id, NULL, p_payload);

  RETURN jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app TO vet_app_user;
