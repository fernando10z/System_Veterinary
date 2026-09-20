-- =============================================================================
-- 35_app_impresion.sql
-- Los documentos que la clínica entrega en papel.
--
-- Una veterinaria firma y sella papeles todos los días: la receta, el carné de
-- vacunación, el consentimiento antes de operar, el alta, el certificado de
-- salud para viajar. Estaban todos en la base como datos, pero no había forma
-- de sacarlos impresos.
--
-- Cada SP devuelve el documento COMPLETO —emisor, paciente, propietario,
-- profesional que firma y contenido—, para que la vista de impresión no tenga
-- que componer nada de varias llamadas. Qué dice el papel es una decisión de
-- negocio y vive acá, no en el frontend.
--
-- Idempotente.
-- =============================================================================

SET search_path = app, internal, core, public;

-- -----------------------------------------------------------------------------
-- internal.membrete_empresa — la cabecera que llevan todos los documentos
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.membrete_empresa(p_empresa_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
  SELECT jsonb_build_object(
    'razon_social',     e.razon_social,
    'nombre_comercial', COALESCE(e.nombre_comercial, e.razon_social),
    'ruc',              e.ruc,
    'direccion',        e.direccion_fiscal,
    'distrito',         e.distrito,
    'telefono',         e.telefono,
    'correo',           e.correo,
    'logo_url',         e.logo_url)
  FROM core.empresas e WHERE e.id = p_empresa_id;
$$;

-- -----------------------------------------------------------------------------
-- internal.ficha_paciente — identificación del animal y de su propietario
--
-- Es el bloque que la autoridad mira primero en cualquier certificado: quién
-- es el animal, cómo se lo identifica y de quién es.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.ficha_paciente(p_mascota_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
  SELECT jsonb_build_object(
    'paciente', jsonb_build_object(
      'id',            m.id,
      'codigo',        m.codigo,
      'nombre',        m.nombre,
      'especie',       esp.nombre,
      'raza',          COALESCE(r.nombre, 'Mestizo'),
      'sexo',          m.sexo,
      'color',         m.color,
      'senias',        m.senias_particulares,
      'fecha_nacimiento', m.fecha_nacimiento,
      'edad',          internal.edad_mascota(m.fecha_nacimiento, m.edad_aproximada_meses),
      'peso_kg',       m.peso_kg,
      'microchip',     m.microchip,
      'esterilizado',  m.esterilizado,
      'alergias',      m.alergias,
      'condiciones_cronicas', m.condiciones_cronicas),
    'propietario', jsonb_build_object(
      'id',            cl.id,
      'nombre',        COALESCE(NULLIF(cl.razon_social,''),
                                trim(cl.nombres || ' ' || COALESCE(cl.apellido_paterno,'') || ' ' ||
                                     COALESCE(cl.apellido_materno,''))),
      'tipo_documento',   cl.tipo_documento,
      'numero_documento', cl.numero_documento,
      'direccion',     cl.direccion,
      'telefono',      cl.telefono,
      'correo',        cl.correo))
  FROM core.mascotas m
  JOIN core.clientes cl ON cl.id = m.cliente_id
  JOIN core.especies esp ON esp.id = m.especie_id
  LEFT JOIN core.razas r ON r.id = m.raza_id
  WHERE m.id = p_mascota_id;
$$;

-- -----------------------------------------------------------------------------
-- internal.firma_profesional — quién firma el documento
--
-- La colegiatura no es decorativa: una receta o un certificado sin el número
-- de colegiatura del médico veterinario no tiene validez.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.firma_profesional(p_user_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = core, internal, public
AS $$
  SELECT jsonb_build_object(
    'nombre', trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'') || ' ' ||
                   COALESCE(u.apellido_materno,'')),
    'colegiatura', u.colegiatura,
    'es_veterinario', u.es_veterinario,
    'especializacion', esp.nombre)
  FROM core.users u
  LEFT JOIN core.especializaciones esp ON esp.id = u.especializacion_id
  WHERE u.id = p_user_id;
$$;

-- =============================================================================
-- RECETA MÉDICO VETERINARIA
-- =============================================================================

-- -----------------------------------------------------------------------------
-- app.fn_doc_receta
--
-- Lo indicado en una consulta, en forma de receta. Marca aparte los productos
-- que requieren receta o son controlados: esos son los que el propietario no
-- puede comprar sin el papel, y los que la clínica tiene que poder sustentar.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_doc_receta(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_consulta_id    UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_c   RECORD;
  v_med JSONB;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clinico:ver');

  SELECT c.* INTO v_c FROM core.consultas c
   WHERE c.id = p_consulta_id AND c.deleted_at IS NULL
     AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, c.empresa_id);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Consulta no encontrada'));
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'medicamento',      t.medicamento,
           'principio_activo', COALESCE(t.principio_activo, pr.principio_activo),
           'presentacion',     pr.presentacion,
           'dosis',            t.dosis,
           'via',              t.via,
           'frecuencia_horas', t.frecuencia_horas,
           'duracion_dias',    t.duracion_dias,
           'indicaciones',     t.indicaciones,
           'requiere_receta',  COALESCE(pr.requiere_receta, false),
           'controlado',       COALESCE(pr.controlado, false))
           ORDER BY t.created_at), '[]'::jsonb) INTO v_med
    FROM core.tratamientos t
    LEFT JOIN core.productos pr ON pr.id = t.producto_id
   WHERE t.consulta_id = p_consulta_id;

  RETURN jsonb_build_object('ok', true, 'data',
    internal.ficha_paciente(v_c.mascota_id) || jsonb_build_object(
      'tipo_documento', 'receta',
      'emisor',      internal.membrete_empresa(v_c.empresa_id),
      'profesional', internal.firma_profesional(v_c.veterinario_id),
      'consulta', jsonb_build_object(
        'id', v_c.id, 'codigo', v_c.codigo, 'fecha', v_c.fecha,
        'motivo', v_c.motivo, 'diagnostico', v_c.diagnostico,
        'peso_kg', v_c.peso_kg,
        'prescripcion', v_c.prescripcion,
        'indicaciones_casa', v_c.indicaciones_casa,
        'proxima_visita', v_c.proxima_visita,
        'cerrada', v_c.estado = 'cerrada'),
      'medicamentos', v_med,
      -- Si hay algo controlado, el papel tiene que decirlo: cambia cómo se
      -- despacha y cómo se archiva.
      'tiene_controlados', EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_med) m WHERE (m->>'controlado')::boolean)));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- CARNÉ DE VACUNACIÓN
-- =============================================================================

-- -----------------------------------------------------------------------------
-- app.fn_doc_carne_vacunacion
--
-- El carné que el propietario lleva encima. La antirrábica va destacada: es la
-- que piden las municipalidades, los parques y cualquier traslado del animal.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_doc_carne_vacunacion(
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
  v_global BOOLEAN := internal.es_acceso_global(p_user_id, p_is_super_admin);
  v_emp    UUID    := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_m      RECORD;
  v_vac    JSONB;
  v_desp   JSONB;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clinico:ver');

  SELECT m.* INTO v_m FROM core.mascotas m
   WHERE m.id = p_mascota_id AND m.deleted_at IS NULL
     AND (v_global OR m.empresa_id = v_emp);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Paciente no encontrado'));
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'nombre_vacuna',    v.nombre_vacuna,
           'laboratorio',      v.laboratorio,
           'lote',             v.lote,
           'fecha_aplicacion', v.fecha_aplicacion,
           'dosis_numero',     v.dosis_numero,
           'proximo_refuerzo', v.proximo_refuerzo,
           'via',              v.via,
           'veterinario',      trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')),
           'colegiatura',      u.colegiatura,
           -- Se compara sin tildes: la vacuna se registra como "Antirrábica",
           -- "antirrabica" o "Rabia" según quién la cargue.
           'antirrabica',      internal.normalizar(v.nombre_vacuna) LIKE '%rabi%',
           'situacion', CASE
             WHEN v.proximo_refuerzo IS NULL             THEN 'sin_refuerzo'
             WHEN v.proximo_refuerzo < CURRENT_DATE      THEN 'vencida'
             WHEN v.proximo_refuerzo <= CURRENT_DATE + 30 THEN 'por_vencer'
             ELSE 'vigente' END)
           ORDER BY v.fecha_aplicacion DESC), '[]'::jsonb) INTO v_vac
    FROM core.vacunas v
    LEFT JOIN core.users u ON u.id = v.veterinario_id
   WHERE v.mascota_id = p_mascota_id
     AND (v_global OR v.empresa_id = v_emp);

  -- El carné peruano lleva también la desparasitación: es lo que se revisa
  -- junto con la vacuna en cualquier control.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'producto',         d.producto_nombre,
           'tipo',             d.tipo,
           'dosis',            d.dosis,
           'fecha_aplicacion', d.fecha_aplicacion,
           'proxima_dosis',    d.proxima_dosis)
           ORDER BY d.fecha_aplicacion DESC), '[]'::jsonb) INTO v_desp
    FROM core.desparasitaciones d
   WHERE d.mascota_id = p_mascota_id
     AND (v_global OR d.empresa_id = v_emp);

  RETURN jsonb_build_object('ok', true, 'data',
    internal.ficha_paciente(p_mascota_id) || jsonb_build_object(
      'tipo_documento', 'carne_vacunacion',
      'emisor', internal.membrete_empresa(v_m.empresa_id),
      'vacunas', v_vac,
      'desparasitaciones', v_desp,
      'antirrabica_vigente', EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_vac) v
         WHERE (v->>'antirrabica')::boolean
           AND (v->>'situacion') IN ('vigente','por_vencer','sin_refuerzo'))));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- CONSENTIMIENTO INFORMADO PARA CIRUGÍA
-- =============================================================================

-- -----------------------------------------------------------------------------
-- app.fn_doc_consentimiento
--
-- El papel que el propietario firma antes de que el animal entre a quirófano.
-- El SP no lo da por firmado: devuelve el documento para imprimir. Marcarlo
-- firmado sigue siendo un acto aparte, y sin él la cirugía no se cierra.
--
-- El texto sale de las cláusulas de la empresa (core.clausulas): cada clínica
-- redacta el suyo y su abogado lo revisa una vez, no en cada operación.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_doc_consentimiento(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_cirugia_id     UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_cir RECORD;
  v_cla JSONB;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clinico:ver');

  SELECT c.*, s.nombre AS servicio, s.precio AS servicio_precio
    INTO v_cir
    FROM core.cirugias c
    LEFT JOIN core.servicios s ON s.id = c.servicio_id
   WHERE c.id = p_cirugia_id
     AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, c.empresa_id);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Cirugía no encontrada'));
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'titulo', cl.titulo, 'contenido', cl.contenido) ORDER BY cl.orden), '[]'::jsonb)
    INTO v_cla
    FROM core.clausulas cl
   WHERE cl.empresa_id = v_cir.empresa_id
     AND cl.tipo = 'consentimiento' AND cl.estado = 'activo';

  RETURN jsonb_build_object('ok', true, 'data',
    internal.ficha_paciente(v_cir.mascota_id) || jsonb_build_object(
      'tipo_documento', 'consentimiento',
      'emisor',      internal.membrete_empresa(v_cir.empresa_id),
      'profesional', internal.firma_profesional(v_cir.cirujano_id),
      'anestesista', internal.firma_profesional(v_cir.anestesista_id),
      'cirugia', jsonb_build_object(
        'id', v_cir.id, 'codigo', v_cir.codigo, 'nombre', v_cir.nombre,
        'descripcion', v_cir.descripcion,
        'fecha_programada', v_cir.fecha_programada,
        'anestesia_tipo', v_cir.anestesia_tipo,
        'servicio', v_cir.servicio,
        'precio_referencial', v_cir.servicio_precio,
        'estado', v_cir.estado,
        'consentimiento_firmado', v_cir.consentimiento_firmado),
      'clausulas', v_cla));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- ALTA HOSPITALARIA (EPICRISIS)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- app.fn_doc_alta_hospitalaria
--
-- El resumen que se lleva el propietario cuando retira al animal: por qué
-- ingresó, qué se le hizo, cómo evolucionó y qué cuidados siguen en casa.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_doc_alta_hospitalaria(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_hospitalizacion_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = core, app, internal, public
AS $$
DECLARE
  v_emp  UUID := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_h    RECORD;
  v_evo  JSONB;
  v_med  JSONB;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clinico:ver');

  SELECT h.* INTO v_h FROM core.hospitalizaciones h
   WHERE h.id = p_hospitalizacion_id
     AND internal.es_de_empresa(p_user_id, p_is_super_admin, v_emp, h.empresa_id);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Hospitalización no encontrada'));
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'fecha_hora', e.fecha_hora,
           'temperatura_c', e.temperatura_c,
           'frecuencia_cardiaca', e.frecuencia_cardiaca,
           'frecuencia_respiratoria', e.frecuencia_respiratoria,
           'come', e.come, 'orina', e.orina, 'defeca', e.defeca,
           'nota', e.nota,
           'registrado_por', trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')))
           ORDER BY e.fecha_hora), '[]'::jsonb) INTO v_evo
    FROM core.hospitalizacion_evoluciones e
    LEFT JOIN core.users u ON u.id = e.user_id
   WHERE e.hospitalizacion_id = p_hospitalizacion_id;

  -- Lo que se le administró durante el internamiento.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'producto', pr.nombre, 'cantidad', iu.cantidad, 'fecha', iu.fecha)
           ORDER BY iu.fecha), '[]'::jsonb) INTO v_med
    FROM core.insumos_utilizados iu
    JOIN core.productos pr ON pr.id = iu.producto_id
   WHERE iu.hospitalizacion_id = p_hospitalizacion_id;

  RETURN jsonb_build_object('ok', true, 'data',
    internal.ficha_paciente(v_h.mascota_id) || jsonb_build_object(
      'tipo_documento', 'alta_hospitalaria',
      'emisor',      internal.membrete_empresa(v_h.empresa_id),
      'profesional', internal.firma_profesional(v_h.veterinario_id),
      'hospitalizacion', jsonb_build_object(
        'id', v_h.id, 'codigo', v_h.codigo, 'jaula', v_h.jaula,
        'motivo', v_h.motivo, 'diagnostico', v_h.diagnostico,
        'fecha_ingreso', v_h.fecha_ingreso, 'fecha_alta', v_h.fecha_alta,
        'indicaciones_alta', v_h.indicaciones_alta,
        'estado', v_h.estado,
        'dias', GREATEST(1, CEIL(EXTRACT(EPOCH FROM (
                  COALESCE(v_h.fecha_alta, now()) - v_h.fecha_ingreso)) / 86400.0)::int)),
      'evoluciones', v_evo,
      'medicacion', v_med));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- CERTIFICADO DE SALUD ANIMAL
-- =============================================================================

-- -----------------------------------------------------------------------------
-- app.fn_doc_certificado_salud
--
-- El certificado que se pide para viajar, mudarse o inscribir al animal. En el
-- Perú, el certificado sanitario de exportación lo emite SENASA, pero SENASA lo
-- emite CONTRA este documento: un certificado de un médico veterinario
-- colegiado, con la vacunación antirrábica vigente y la desparasitación
-- reciente. Por eso el SP arma justo esos tres bloques y avisa si algo falta,
-- en vez de dejar que el papel salga incompleto y el viaje se caiga en la
-- ventanilla.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_doc_certificado_salud(
  p_user_id        UUID,
  p_empresa_id     UUID,
  p_is_super_admin BOOLEAN,
  p_mascota_id     UUID,
  p_payload        JSONB DEFAULT '{}'::jsonb
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
  v_m        RECORD;
  v_rabia    RECORD;
  v_desp     RECORD;
  v_consulta RECORD;
  -- El literal se castea al concatenar: sin el ::text, Postgres resuelve
  -- `anyarray || anyarray` e intenta leer la frase como un array.
  v_faltas   TEXT[] := ARRAY[]::TEXT[];
  v_firma    JSONB;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clinico:ver');

  SELECT m.* INTO v_m FROM core.mascotas m
   WHERE m.id = p_mascota_id AND m.deleted_at IS NULL
     AND (v_global OR m.empresa_id = v_emp);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Paciente no encontrado'));
  END IF;

  -- Quien firma es el veterinario indicado, o el usuario si es veterinario.
  v_firma := internal.firma_profesional(
    COALESCE(NULLIF(p_payload->>'veterinario_id','')::uuid, p_user_id));

  IF NOT COALESCE((v_firma->>'es_veterinario')::boolean, false)
     OR COALESCE(v_firma->>'colegiatura','') = '' THEN
    v_faltas := v_faltas || 'El certificado lo firma un médico veterinario colegiado'::text;
  END IF;

  SELECT v.* INTO v_rabia FROM core.vacunas v
   WHERE v.mascota_id = p_mascota_id
     AND internal.normalizar(v.nombre_vacuna) LIKE '%rabi%'
     AND (v_global OR v.empresa_id = v_emp)
   ORDER BY v.fecha_aplicacion DESC LIMIT 1;

  IF v_rabia.id IS NULL THEN
    v_faltas := v_faltas || 'No hay vacunación antirrábica registrada'::text;
  ELSIF v_rabia.proximo_refuerzo IS NOT NULL AND v_rabia.proximo_refuerzo < CURRENT_DATE THEN
    v_faltas := v_faltas || 'La vacunación antirrábica está vencida'::text;
  END IF;

  SELECT d.* INTO v_desp FROM core.desparasitaciones d
   WHERE d.mascota_id = p_mascota_id
     AND (v_global OR d.empresa_id = v_emp)
   ORDER BY d.fecha_aplicacion DESC LIMIT 1;

  IF v_desp.id IS NULL THEN
    v_faltas := v_faltas || 'No hay desparasitación registrada'::text;
  ELSIF v_desp.fecha_aplicacion < CURRENT_DATE - 180 THEN
    v_faltas := v_faltas || 'La última desparasitación tiene más de 6 meses'::text;
  END IF;

  -- El examen clínico que sustenta el certificado: la última consulta cerrada.
  SELECT c.* INTO v_consulta FROM core.consultas c
   WHERE c.mascota_id = p_mascota_id AND c.estado = 'cerrada' AND c.deleted_at IS NULL
     AND (v_global OR c.empresa_id = v_emp)
   ORDER BY c.fecha DESC LIMIT 1;

  IF v_consulta.id IS NULL THEN
    v_faltas := v_faltas || 'No hay un examen clínico cerrado que sustente el certificado'::text;
  ELSIF v_consulta.fecha < now() - INTERVAL '10 days' THEN
    v_faltas := v_faltas || 'El último examen clínico tiene más de 10 días'::text;
  END IF;

  RETURN jsonb_build_object('ok', true, 'data',
    internal.ficha_paciente(p_mascota_id) || jsonb_build_object(
      'tipo_documento', 'certificado_salud',
      'emisor',      internal.membrete_empresa(v_m.empresa_id),
      'profesional', v_firma,
      'fecha_emision', CURRENT_DATE,
      'motivo',  COALESCE(NULLIF(p_payload->>'motivo',''), 'Viaje'),
      'destino', NULLIF(p_payload->>'destino',''),
      'antirrabica', CASE WHEN v_rabia.id IS NOT NULL THEN jsonb_build_object(
        'nombre_vacuna', v_rabia.nombre_vacuna, 'laboratorio', v_rabia.laboratorio,
        'lote', v_rabia.lote, 'fecha_aplicacion', v_rabia.fecha_aplicacion,
        'proximo_refuerzo', v_rabia.proximo_refuerzo) END,
      'desparasitacion', CASE WHEN v_desp.id IS NOT NULL THEN jsonb_build_object(
        'producto', v_desp.producto_nombre, 'tipo', v_desp.tipo,
        'fecha_aplicacion', v_desp.fecha_aplicacion) END,
      'examen_clinico', CASE WHEN v_consulta.id IS NOT NULL THEN jsonb_build_object(
        'fecha', v_consulta.fecha, 'peso_kg', v_consulta.peso_kg,
        'temperatura_c', v_consulta.temperatura_c,
        'examen_fisico', v_consulta.examen_fisico,
        'diagnostico', v_consulta.diagnostico) END,
      -- Lo que impide que el certificado sirva. El documento se devuelve igual
      -- —el veterinario decide—, pero la pantalla lo advierte antes de imprimir.
      'observaciones_previas', to_jsonb(v_faltas),
      'apto', array_length(v_faltas, 1) IS NULL));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

-- =============================================================================
-- HISTORIA CLÍNICA COMPLETA
-- =============================================================================

-- -----------------------------------------------------------------------------
-- app.fn_doc_historia_clinica
--
-- La historia completa del paciente para imprimir o derivar a otro colega.
-- Un propietario tiene derecho a llevarse la historia de su animal, y una
-- derivación sin historia obliga al siguiente veterinario a empezar de cero.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.fn_doc_historia_clinica(
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
  v_global BOOLEAN := internal.es_acceso_global(p_user_id, p_is_super_admin);
  v_emp    UUID    := internal.empresa_efectiva(p_user_id, p_empresa_id, p_is_super_admin);
  v_m      RECORD;
  v_cons   JSONB;
  v_linea  JSONB;
BEGIN
  PERFORM internal.assert_permiso(p_user_id, 'clinico:ver');

  SELECT m.* INTO v_m FROM core.mascotas m
   WHERE m.id = p_mascota_id AND m.deleted_at IS NULL
     AND (v_global OR m.empresa_id = v_emp);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false,
      'error', internal.error_jsonb('NOT_FOUND','Paciente no encontrado'));
  END IF;

  -- Sólo las consultas cerradas: un borrador no es un documento clínico.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'codigo', c.codigo, 'fecha', c.fecha, 'motivo', c.motivo,
           'anamnesis', c.anamnesis, 'peso_kg', c.peso_kg,
           'temperatura_c', c.temperatura_c,
           'frecuencia_cardiaca', c.frecuencia_cardiaca,
           'frecuencia_respiratoria', c.frecuencia_respiratoria,
           'mucosas', c.mucosas, 'condicion_corporal', c.condicion_corporal,
           'examen_fisico', c.examen_fisico,
           'diagnostico', c.diagnostico,
           'diagnostico_diferencial', c.diagnostico_diferencial,
           'pronostico', c.pronostico,
           'plan_terapeutico', c.plan_terapeutico,
           'prescripcion', c.prescripcion,
           'indicaciones_casa', c.indicaciones_casa,
           'veterinario', trim(u.nombres || ' ' || COALESCE(u.apellido_paterno,'')),
           'colegiatura', u.colegiatura)
           ORDER BY c.fecha DESC), '[]'::jsonb) INTO v_cons
    FROM core.consultas c
    LEFT JOIN core.users u ON u.id = c.veterinario_id
   WHERE c.mascota_id = p_mascota_id AND c.deleted_at IS NULL AND c.estado = 'cerrada'
     AND (v_global OR c.empresa_id = v_emp);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'fecha', h.fecha, 'tipo_evento', h.tipo_evento,
           'titulo', h.titulo, 'resumen', h.resumen)
           ORDER BY h.fecha DESC), '[]'::jsonb) INTO v_linea
    FROM core.historia_clinica h
   WHERE h.mascota_id = p_mascota_id
     AND (v_global OR h.empresa_id = v_emp);

  RETURN jsonb_build_object('ok', true, 'data',
    internal.ficha_paciente(p_mascota_id) || jsonb_build_object(
      'tipo_documento', 'historia_clinica',
      'emisor', internal.membrete_empresa(v_m.empresa_id),
      'fecha_emision', CURRENT_DATE,
      'consultas', v_cons,
      'linea_tiempo', v_linea,
      'vacunas', (app.fn_doc_carne_vacunacion(
                    p_user_id, p_empresa_id, p_is_super_admin, p_mascota_id)->'data'->'vacunas')));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', internal.error_jsonb(SQLSTATE, SQLERRM));
END;
$$;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app TO vet_app_user;
