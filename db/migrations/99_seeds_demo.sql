-- =============================================================================
-- 99_seeds_demo.sql — Datos de demostración (operación de una clínica real)
--
-- Propietarios, pacientes, agenda, historia clínica, ventas y cobros, para que
-- el sistema se pueda mostrar con contenido creíble desde el primer arranque.
-- Idempotente: si ya hay clientes cargados, no hace nada.
-- =============================================================================

SET search_path = core, internal, app, public;

DO $$
DECLARE
  v_emp     UUID;
  v_super   UUID;
  v_vet1    UUID;
  v_vet2    UUID;
  v_recep   UUID;
  v_canino  UUID;
  v_felino  UUID;
  v_cli     UUID;
  v_mas     UUID;
  v_cita    UUID;
  v_cons    UUID;
  v_caja    UUID;
  v_comp    UUID;
  r         RECORD;
  v_i       INT;
  v_fecha   TIMESTAMPTZ;
BEGIN
  IF EXISTS (SELECT 1 FROM core.clientes LIMIT 1) THEN
    RAISE NOTICE 'Ya hay clientes cargados: se omiten los datos de demostración.';
    RETURN;
  END IF;

  SELECT id INTO v_emp    FROM core.empresas WHERE ruc = '20601234567';
  SELECT id INTO v_super  FROM core.users WHERE email = 'admin@vetpatitas.pe';
  SELECT id INTO v_vet1   FROM core.users WHERE email = 'jperez@vetpatitas.pe';
  SELECT id INTO v_vet2   FROM core.users WHERE email = 'mrojas@vetpatitas.pe';
  SELECT id INTO v_recep  FROM core.users WHERE email = 'recepcion@vetpatitas.pe';
  SELECT id INTO v_canino FROM core.especies WHERE codigo = 'CANINO';
  SELECT id INTO v_felino FROM core.especies WHERE codigo = 'FELINO';

  -- ---------------------------------------------------------------------------
  -- Propietarios y sus mascotas
  -- ---------------------------------------------------------------------------
  FOR r IN
    SELECT * FROM (VALUES
      ('DNI','44556677','Carla','Zevallos','Ruiz','987654321','carla.zevallos@gmail.com','Av. Pardo 455, Miraflores'),
      ('DNI','41223344','Miguel','Torres','Nuñez','986112233','mtorres@outlook.com','Jr. Berlín 210, Miraflores'),
      ('DNI','43887766','Sofía','Camacho','León','985443322','sofia.camacho@gmail.com','Av. Benavides 1890, Surco'),
      ('DNI','40998877','Diego','Ramírez','Ochoa','984556677','dramirez@gmail.com','Calle Bolívar 780, Miraflores'),
      ('DNI','45667788','Valeria','Huamán','Castro','983221144','valeria.h@hotmail.com','Av. Angamos Este 1520, Surquillo'),
      ('DNI','42334455','Renzo','Aguilar','Ponce','982778899','renzo.aguilar@gmail.com','Jr. Colón 340, Miraflores'),
      ('DNI','46778899','Paola','Ninahuanca','Silva','981334455','paola.n@gmail.com','Av. Petit Thouars 4200, San Isidro'),
      ('RUC','20601122334','Refugio Huellitas','','', '980112233','contacto@huellitas.org','Av. Universitaria 3400, Los Olivos'),
      ('DNI','47889900','Gonzalo','Medina','Rojas','979445566','gmedina@gmail.com','Calle Manuel Bonilla 120, Miraflores'),
      ('DNI','48990011','Ximena','Bravo','Ríos','978556677','xbravo@gmail.com','Av. La Mar 2300, Magdalena')
    ) AS t(tipo_doc, doc, nombres, ap, am, tel, correo, dir)
  LOOP
    INSERT INTO core.clientes (
      codigo, tipo_documento, numero_documento, nombres, apellido_paterno, apellido_materno,
      razon_social, telefono, correo, direccion, empresa_origen_id, created_by)
    VALUES (
      internal.siguiente_numero(v_emp, 'CLI', 5),
      r.tipo_doc::core.tipo_documento_identidad, r.doc, r.nombres,
      NULLIF(r.ap,''), NULLIF(r.am,''),
      CASE WHEN r.tipo_doc = 'RUC' THEN r.nombres END,
      r.tel, r.correo, r.dir, v_emp, v_super);
  END LOOP;

  -- Portal habilitado para dos propietarios (demo del área de clientes)
  UPDATE core.clientes
     SET portal_acceso = true,
         portal_password_hash = crypt('Mascota2026!', gen_salt('bf', 10))
   WHERE numero_documento IN ('44556677','41223344');

  -- ---- Pacientes ------------------------------------------------------------
  FOR r IN
    SELECT * FROM (VALUES
      ('44556677','Luna',   'CANINO','Golden Retriever',  'hembra', 'Dorado',        '2021-03-14', 28.4, true,  'Ninguna conocida'),
      ('44556677','Simón',  'FELINO','Siamés',            'macho',  'Crema y marrón','2022-07-02',  4.8, true,  NULL),
      ('41223344','Rocky',  'CANINO','Bulldog Francés',   'macho',  'Atigrado',      '2020-11-20', 12.1, false, 'Alergia alimentaria al pollo'),
      ('43887766','Maya',   'CANINO','Mestizo',           'hembra', 'Negro',         '2019-05-08', 18.7, true,  NULL),
      ('40998877','Thor',   'CANINO','Pastor Alemán',     'macho',  'Negro y fuego', '2018-09-30', 34.2, false, NULL),
      ('45667788','Nala',   'FELINO','Mestizo',           'hembra', 'Naranja',       '2023-01-17',  3.6, true,  NULL),
      ('42334455','Coco',   'CANINO','Poodle',            'macho',  'Blanco',        '2017-04-25',  6.3, true,  'Sensibilidad a la ivermectina'),
      ('46778899','Milo',   'FELINO','Persa',             'macho',  'Gris',          '2021-12-11',  5.1, true,  NULL),
      ('20601122334','Bruno','CANINO','Mestizo',          'macho',  'Marrón',        '2022-02-05', 21.5, false, NULL),
      ('20601122334','Chispa','CANINO','Mestizo',         'hembra', 'Blanco y negro','2023-06-19', 14.8, false, NULL),
      ('47889900','Kira',   'CANINO','Husky Siberiano',   'hembra', 'Gris y blanco', '2020-08-14', 22.9, true,  NULL),
      ('48990011','Pelusa', 'FELINO','Angora',            'hembra', 'Blanco',        '2019-10-03',  4.2, true,  'Asma felino diagnosticado')
    ) AS t(doc, nombre, especie, raza, sexo, color, nacimiento, peso, esteril, alergias)
  LOOP
    SELECT id INTO v_cli FROM core.clientes WHERE numero_documento = r.doc;

    INSERT INTO core.mascotas (
      codigo, cliente_id, nombre, especie_id, raza_id, sexo, color,
      fecha_nacimiento, peso_kg, esterilizado, alergias, empresa_origen_id, created_by)
    VALUES (
      internal.siguiente_numero(v_emp, 'HC', 6), v_cli, r.nombre,
      (SELECT id FROM core.especies WHERE codigo = r.especie),
      (SELECT ra.id FROM core.razas ra
        JOIN core.especies e ON e.id = ra.especie_id
       WHERE e.codigo = r.especie AND ra.nombre = r.raza),
      r.sexo::core.sexo_mascota, r.color, r.nacimiento::date, r.peso,
      r.esteril, r.alergias, v_emp, v_super);
  END LOOP;

  -- ---------------------------------------------------------------------------
  -- Agenda: citas repartidas entre ayer, hoy y los próximos días
  -- ---------------------------------------------------------------------------
  v_i := 0;
  FOR r IN SELECT m.id AS mascota_id, m.cliente_id FROM core.mascotas m ORDER BY m.created_at LOOP
    v_i := v_i + 1;

    -- Citas pasadas (atendidas)
    v_fecha := date_trunc('day', now()) - ((v_i % 5) + 1) * INTERVAL '1 day' + INTERVAL '10 hours' + (v_i * INTERVAL '35 minutes');
    INSERT INTO core.citas (
      empresa_id, codigo, cliente_id, mascota_id, veterinario_id, servicio_id,
      fecha_hora, duracion_min, motivo, estado, origen, created_by)
    VALUES (
      v_emp, internal.siguiente_numero(v_emp, 'CIT', 6), r.cliente_id, r.mascota_id,
      CASE WHEN v_i % 2 = 0 THEN v_vet1 ELSE v_vet2 END,
      (SELECT id FROM core.servicios WHERE empresa_id = v_emp AND codigo = 'SRV-0001'),
      v_fecha, 30,
      (ARRAY['Control anual','Decaimiento y falta de apetito','Vómitos desde ayer',
             'Chequeo preventivo','Cojera de miembro posterior','Revisión de piel'])[1 + (v_i % 6)],
      'completada', 'mostrador', v_recep)
    RETURNING id INTO v_cita;

    -- Consulta asociada a la cita atendida
    INSERT INTO core.consultas (
      empresa_id, codigo, mascota_id, cliente_id, veterinario_id, cita_id, fecha,
      motivo, anamnesis, peso_kg, temperatura_c, frecuencia_cardiaca,
      frecuencia_respiratoria, mucosas, condicion_corporal, examen_fisico,
      diagnostico, plan_terapeutico, indicaciones_casa, estado, created_by)
    SELECT
      v_emp, internal.siguiente_numero(v_emp, 'CON', 6), r.mascota_id, r.cliente_id,
      CASE WHEN v_i % 2 = 0 THEN v_vet1 ELSE v_vet2 END, v_cita, v_fecha,
      c.motivo,
      'El propietario refiere el cuadro desde hace ' || (1 + v_i % 4) || ' días.',
      m.peso_kg, 38.0 + ((v_i % 12) * 0.1), 90 + (v_i % 40), 20 + (v_i % 15),
      'rosadas', 4 + (v_i % 3),
      'Paciente alerta, hidratado. Auscultación cardiopulmonar sin hallazgos relevantes.',
      (ARRAY['Gastroenteritis leve','Dermatitis alérgica','Sano — control preventivo',
             'Otitis externa','Contusión de miembro posterior','Sobrepeso grado 2'])[1 + (v_i % 6)],
      'Tratamiento sintomático y control en 7 días.',
      'Dieta blanda por 3 días. Regresar si el cuadro empeora.',
      'cerrada', CASE WHEN v_i % 2 = 0 THEN v_vet1 ELSE v_vet2 END
    FROM core.citas c JOIN core.mascotas m ON m.id = c.mascota_id
    WHERE c.id = v_cita
    RETURNING id INTO v_cons;

    -- El seed inserta las consultas directamente (no vía SP), así que el evento
    -- de la línea de tiempo hay que registrarlo aquí a mano.
    PERFORM internal.registrar_evento_clinico(
      v_emp, r.mascota_id, r.cliente_id,
      CASE WHEN v_i % 2 = 0 THEN v_vet1 ELSE v_vet2 END,
      'consulta',
      'Consulta: ' || (SELECT left(motivo, 120) FROM core.consultas WHERE id = v_cons),
      (SELECT diagnostico FROM core.consultas WHERE id = v_cons),
      v_cons, v_cita, v_fecha);

    -- Orden de servicio facturable de esa consulta
    INSERT INTO core.ordenes_servicio (
      empresa_id, codigo, mascota_id, cliente_id, servicio_id, veterinario_id,
      cita_id, consulta_id, cantidad, precio_unitario, total, estado, fecha, created_by)
    SELECT v_emp, internal.siguiente_numero(v_emp, 'OS', 6), r.mascota_id, r.cliente_id,
           s.id, CASE WHEN v_i % 2 = 0 THEN v_vet1 ELSE v_vet2 END,
           v_cita, v_cons, 1, s.precio, s.precio, 'completado', v_fecha, v_recep
    FROM core.servicios s WHERE s.empresa_id = v_emp AND s.codigo = 'SRV-0001';

    -- Vacunación en la mitad de los pacientes
    IF v_i % 2 = 1 THEN
      INSERT INTO core.vacunas (
        empresa_id, mascota_id, veterinario_id, consulta_id, nombre_vacuna,
        laboratorio, lote, fecha_aplicacion, dosis_numero, proximo_refuerzo, created_by)
      VALUES (
        v_emp, r.mascota_id, v_vet1, v_cons,
        CASE WHEN v_i % 4 = 1 THEN 'Antirrábica' ELSE 'Quíntuple canina' END,
        'Zoetis', 'LT-2026-' || lpad(v_i::text, 3, '0'),
        (v_fecha)::date, 1,
        (v_fecha)::date + INTERVAL '1 year', v_vet1);

      PERFORM internal.registrar_evento_clinico(
        v_emp, r.mascota_id, r.cliente_id, v_vet1, 'vacuna',
        'Vacuna: ' || CASE WHEN v_i % 4 = 1 THEN 'Antirrábica' ELSE 'Quíntuple canina' END,
        'Próximo refuerzo en 12 meses', NULL, v_cita, v_fecha);
    END IF;

    -- Citas futuras: agenda de hoy y de los próximos días
    v_fecha := date_trunc('day', now()) + ((v_i % 4)) * INTERVAL '1 day'
               + INTERVAL '9 hours' + (v_i * INTERVAL '40 minutes');
    INSERT INTO core.citas (
      empresa_id, codigo, cliente_id, mascota_id, veterinario_id, servicio_id,
      consultorio_id, fecha_hora, duracion_min, motivo, prioridad, estado, origen, created_by)
    VALUES (
      v_emp, internal.siguiente_numero(v_emp, 'CIT', 6), r.cliente_id, r.mascota_id,
      CASE WHEN v_i % 2 = 0 THEN v_vet2 ELSE v_vet1 END,
      (SELECT id FROM core.servicios WHERE empresa_id = v_emp
        AND codigo = (ARRAY['SRV-0001','SRV-0004','SRV-0007','SRV-0016'])[1 + (v_i % 4)]),
      (SELECT id FROM core.consultorios WHERE empresa_id = v_emp AND nombre = 'Consultorio 1'),
      v_fecha, 30,
      (ARRAY['Control de tratamiento','Vacunación programada','Desparasitación',
             'Baño medicado','Revisión post-operatoria'])[1 + (v_i % 5)],
      CASE WHEN v_i = 3 THEN 'urgencia' ELSE 'normal' END::core.prioridad_cita,
      (ARRAY['programada','confirmada','confirmada','programada'])[1 + (v_i % 4)]::core.estado_cita,
      (ARRAY['mostrador','telefono','whatsapp','portal'])[1 + (v_i % 4)]::core.origen_cita,
      v_recep);
  END LOOP;

  -- ---------------------------------------------------------------------------
  -- Hospitalización en curso (para que el módulo tenga contenido)
  -- ---------------------------------------------------------------------------
  SELECT id INTO v_mas FROM core.mascotas WHERE nombre = 'Thor';
  INSERT INTO core.hospitalizaciones (
    empresa_id, codigo, mascota_id, veterinario_id, jaula, motivo, diagnostico,
    fecha_ingreso, estado, created_by)
  VALUES (
    v_emp, internal.siguiente_numero(v_emp, 'HOSP', 5), v_mas, v_vet2, 'J-03',
    'Deshidratación severa por cuadro gastroentérico',
    'Gastroenteritis aguda con deshidratación grado II',
    now() - INTERVAL '18 hours', 'en_observacion', v_vet2);

  PERFORM internal.registrar_evento_clinico(
    v_emp, v_mas, (SELECT cliente_id FROM core.mascotas WHERE id = v_mas), v_vet2,
    'hospitalizacion', 'Ingreso a hospitalización',
    'Deshidratación severa por cuadro gastroentérico', NULL, NULL,
    now() - INTERVAL '18 hours');

  INSERT INTO core.hospitalizacion_evoluciones (
    hospitalizacion_id, user_id, fecha_hora, temperatura_c,
    frecuencia_cardiaca, come, orina, defeca, nota)
  SELECT h.id, v_vet2, now() - (g * INTERVAL '6 hours'),
         38.6 - (g * 0.2), 110 - (g * 5), g > 1, true, g > 2,
         (ARRAY['Ingreso. Se instaura fluidoterapia.',
                'Mejora del estado de hidratación. Tolera agua.',
                'Come dieta blanda sin vomitar. Se mantiene fluido.'])[g]
  FROM core.hospitalizaciones h, generate_series(1, 3) g
  WHERE h.mascota_id = v_mas;

  -- ---------------------------------------------------------------------------
  -- Cirugía programada
  -- ---------------------------------------------------------------------------
  SELECT id INTO v_mas FROM core.mascotas WHERE nombre = 'Chispa';
  INSERT INTO core.cirugias (
    empresa_id, codigo, mascota_id, cirujano_id, anestesista_id, consultorio_id,
    servicio_id, nombre, descripcion, fecha_programada, anestesia_tipo,
    consentimiento_firmado, estado, created_by)
  VALUES (
    v_emp, internal.siguiente_numero(v_emp, 'CIR', 5), v_mas, v_vet2, v_vet1,
    (SELECT id FROM core.consultorios WHERE empresa_id = v_emp AND nombre = 'Quirófano'),
    (SELECT id FROM core.servicios WHERE empresa_id = v_emp AND codigo = 'SRV-0008'),
    'Ovariohisterectomía', 'Esterilización electiva',
    date_trunc('day', now()) + INTERVAL '2 days' + INTERVAL '11 hours',
    'Inhalatoria (isoflurano)', true, 'programada', v_vet2);

  PERFORM internal.registrar_evento_clinico(
    v_emp, v_mas, (SELECT cliente_id FROM core.mascotas WHERE id = v_mas), v_vet2,
    'cirugia', 'Cirugía programada: Ovariohisterectomía', 'Esterilización electiva');

  -- ---------------------------------------------------------------------------
  -- Caja del día + facturación de lo atendido
  -- ---------------------------------------------------------------------------
  INSERT INTO core.cajas (empresa_id, numero, user_apertura_id, monto_apertura, observaciones)
  VALUES (v_emp, internal.siguiente_numero(v_emp, 'CAJA', 5), v_recep, 200.00, 'Apertura de turno')
  RETURNING id INTO v_caja;

  -- Emitir un comprobante por cada cliente con servicios pendientes
  FOR r IN
    SELECT DISTINCT os.cliente_id FROM core.ordenes_servicio os
     WHERE os.empresa_id = v_emp AND os.facturado = false
  LOOP
    SELECT (app.sp_comprobante_emitir(
      v_super, v_emp, true,
      jsonb_build_object('cliente_id', r.cliente_id, 'tipo', 'boleta', 'caja_id', v_caja)
    )->'data'->>'id')::uuid INTO v_comp;

    -- Dos tercios se cobran; el resto queda como cuenta por cobrar
    IF v_comp IS NOT NULL AND random() < 0.66 THEN
      PERFORM app.sp_pago_registrar(
        v_recep, v_emp, false,
        jsonb_build_object(
          'cliente_id', r.cliente_id,
          'monto', (SELECT total FROM core.comprobantes WHERE id = v_comp),
          'metodo', (ARRAY['efectivo','tarjeta','yape'])[1 + floor(random() * 3)::int],
          'caja_id', v_caja));
    END IF;
  END LOOP;

  -- ---------------------------------------------------------------------------
  -- Comunicaciones y turnos del equipo
  -- ---------------------------------------------------------------------------
  INSERT INTO core.comunicaciones (empresa_id, cliente_id, user_id, tipo, asunto, mensaje, fecha)
  SELECT v_emp, c.id, v_recep, 'whatsapp',
         'Recordatorio de cita',
         'Se envió recordatorio de la cita programada. El propietario confirmó asistencia.',
         now() - INTERVAL '1 day'
  FROM core.clientes c LIMIT 5;

  -- Turnos de los veterinarios para las próximas dos semanas
  INSERT INTO core.disponibilidad (empresa_id, user_id, fecha, hora_inicio, hora_fin, tipo)
  SELECT v_emp, u.id, d::date, '09:00'::time, '18:00'::time, 'laboral'
  FROM core.users u,
       generate_series(CURRENT_DATE, CURRENT_DATE + 14, '1 day'::interval) d
  WHERE u.empresa_id = v_emp AND u.es_veterinario = true
    AND EXTRACT(DOW FROM d) BETWEEN 1 AND 6;

  -- Asistencia de los últimos 10 días hábiles
  INSERT INTO core.asistencia (empresa_id, user_id, fecha, hora_entrada, hora_salida, estado)
  SELECT v_emp, u.id, d::date,
         ('08:5' || (floor(random() * 9))::text)::time,
         ('18:0' || (floor(random() * 9))::text)::time,
         CASE WHEN random() < 0.12 THEN 'tardanza' ELSE 'puntual' END::core.estado_asistencia
  FROM core.users u,
       generate_series(CURRENT_DATE - 10, CURRENT_DATE - 1, '1 day'::interval) d
  WHERE u.empresa_id = v_emp AND EXTRACT(DOW FROM d) BETWEEN 1 AND 6
  ON CONFLICT (user_id, fecha) DO NOTHING;

  RAISE NOTICE 'Datos de demostración cargados.';
END $$;
