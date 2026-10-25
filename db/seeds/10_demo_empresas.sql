-- =============================================================================
-- db/seeds/10_demo_empresas.sql — Empresas, usuarios y catálogos de DEMOSTRACIÓN
--
-- No es una migración: lo aplica `apply-migrations.sh` solo con SEED_DEMO=1
-- (reset-dev.sh y exportar-snapshot.sh lo activan). En producción no corre.
--
-- Todos los usuarios usan la contraseña Demo2026!. Si el usuario ya existe NO
-- se le reescribe la contraseña: reaplicar las semillas no puede reabrir una
-- cuenta cuya clave alguien ya cambió.
-- =============================================================================

SET search_path = core, internal, app, public;

-- =============================================================================
-- 4. SEDE DEMO + USUARIOS + CATÁLOGOS OPERATIVOS
-- =============================================================================
DO $$
DECLARE
  v_emp        UUID;
  v_emp2       UUID;
  v_super      UUID;
  v_admin      UUID;
  v_vet1       UUID;
  v_vet2       UUID;
  v_recep      UUID;
  v_almacen_u  UUID;
  v_almacen    UUID;
  v_cat_serv   UUID;
  v_cat_est    UUID;
  v_esp_can    UUID;
  v_cat_med    UUID;
  v_cat_alim   UUID;
  v_cat_prov   UUID;
  v_canino     UUID;
  v_felino     UUID;
BEGIN
  SELECT id INTO v_canino FROM core.especies WHERE codigo = 'CANINO';
  SELECT id INTO v_felino FROM core.especies WHERE codigo = 'FELINO';

  -- ---- Sedes ----------------------------------------------------------------
  INSERT INTO core.empresas (
    ruc, razon_social, nombre_comercial, direccion_fiscal, ubigeo, telefono, correo,
    serie_factura_default, serie_boleta_default, serie_nota_venta_default,
    aforo_consultorios, duracion_cita_min)
  VALUES (
    '20601234567', 'Clínica Veterinaria Patitas S.A.C.', 'Vet Patitas',
    'Av. Larco 1234, Miraflores', '150122', '014455667', 'contacto@vetpatitas.pe',
    'F001', 'B001', 'NV01', 3, 30)
  ON CONFLICT (ruc) DO UPDATE SET razon_social = EXCLUDED.razon_social
  RETURNING id INTO v_emp;

  INSERT INTO core.empresas (
    ruc, razon_social, nombre_comercial, direccion_fiscal, ubigeo, telefono, correo,
    serie_factura_default, serie_boleta_default, aforo_consultorios, duracion_cita_min)
  VALUES (
    '20609876543', 'Centro Veterinario Huellitas E.I.R.L.', 'Vet Huellitas',
    'Av. Javier Prado Este 456, San Isidro', '150131', '014455668', 'contacto@vethuellitas.pe',
    'F002', 'B002', 2, 30)
  ON CONFLICT (ruc) DO UPDATE SET razon_social = EXCLUDED.razon_social
  RETURNING id INTO v_emp2;

  -- ---- Almacén y consultorios ----------------------------------------------
  INSERT INTO core.almacenes (empresa_id, codigo, nombre, ubicacion, es_principal)
  VALUES (v_emp, 'ALM-01', 'Almacén principal', 'Trastienda', true)
  ON CONFLICT (empresa_id, codigo) DO NOTHING;
  SELECT id INTO v_almacen FROM core.almacenes WHERE empresa_id = v_emp AND codigo = 'ALM-01';

  INSERT INTO core.almacenes (empresa_id, codigo, nombre, ubicacion, es_principal)
  VALUES (v_emp, 'ALM-02', 'Botiquín de quirófano', 'Quirófano', false)
  ON CONFLICT (empresa_id, codigo) DO NOTHING;

  INSERT INTO core.almacenes (empresa_id, codigo, nombre, es_principal)
  VALUES (v_emp2, 'ALM-01', 'Almacén principal', true)
  ON CONFLICT (empresa_id, codigo) DO NOTHING;

  INSERT INTO core.consultorios (empresa_id, nombre, tipo) VALUES
    (v_emp, 'Consultorio 1', 'consulta'),
    (v_emp, 'Consultorio 2', 'consulta'),
    (v_emp, 'Quirófano',     'quirofano'),
    (v_emp, 'Hospitalización','hospitalizacion'),
    (v_emp, 'Sala de grooming','grooming')
  ON CONFLICT DO NOTHING;

  INSERT INTO core.consultorios (empresa_id, nombre, tipo) VALUES
    (v_emp2, 'Consultorio 1', 'consulta'),
    (v_emp2, 'Consultorio 2', 'consulta')
  ON CONFLICT DO NOTHING;

  -- ---- Horario de atención (lun-sáb) ---------------------------------------
  DELETE FROM core.horarios_atencion WHERE empresa_id = v_emp;
  INSERT INTO core.horarios_atencion (empresa_id, dia_semana, hora_inicio, hora_fin, activo)
  SELECT v_emp, d, '09:00'::time, '20:00'::time, true FROM generate_series(1, 5) d;
  INSERT INTO core.horarios_atencion (empresa_id, dia_semana, hora_inicio, hora_fin, activo)
  VALUES (v_emp, 6, '09:00', '14:00', true);

  -- ---- Categorías -----------------------------------------------------------
  INSERT INTO core.categorias (empresa_id, ambito, codigo, nombre, orden) VALUES
    (v_emp, 'servicio', 'CONSULTAS',  'Consultas',           1),
    (v_emp, 'servicio', 'PREVENTIVA', 'Medicina preventiva', 2),
    (v_emp, 'servicio', 'CIRUGIA',    'Cirugía',             3),
    (v_emp, 'servicio', 'DIAGNOSTICO','Diagnóstico',         4),
    (v_emp, 'servicio', 'ESTETICA',   'Estética y grooming', 5),
    (v_emp, 'producto', 'MEDICAMENTO','Medicamentos',        1),
    (v_emp, 'producto', 'INSUMO',     'Insumos médicos',     2),
    (v_emp, 'producto', 'ALIMENTO',   'Alimento balanceado', 3),
    (v_emp, 'producto', 'ACCESORIO',  'Accesorios',          4),
    (v_emp, 'proveedor','LABORATORIO','Laboratorios',        1),
    (v_emp, 'proveedor','DISTRIBUIDOR','Distribuidores',     2)
  ON CONFLICT (empresa_id, ambito, codigo) DO NOTHING;

  SELECT id INTO v_cat_serv FROM core.categorias WHERE empresa_id = v_emp AND codigo = 'CONSULTAS';
  SELECT id INTO v_cat_est  FROM core.categorias WHERE empresa_id = v_emp AND codigo = 'ESTETICA';
  SELECT id INTO v_esp_can  FROM core.especies WHERE codigo = 'CANINO';
  SELECT id INTO v_cat_med  FROM core.categorias WHERE empresa_id = v_emp AND codigo = 'MEDICAMENTO';
  SELECT id INTO v_cat_alim FROM core.categorias WHERE empresa_id = v_emp AND codigo = 'ALIMENTO';
  SELECT id INTO v_cat_prov FROM core.categorias WHERE empresa_id = v_emp AND codigo = 'LABORATORIO';

  -- ---- Usuarios -------------------------------------------------------------
  -- Contraseña de todos los usuarios demo: Demo2026!
  INSERT INTO core.users (
    codigo, email, password_hash, nombres, apellido_paterno, apellido_materno,
    tipo_documento, numero_documento, telefono, empresa_id, is_super_admin, rol_id,
    es_veterinario, colegiatura, especializacion_id, color_agenda, estado)
  VALUES (
    'USR-0001', 'admin@vetpatitas.pe', crypt('Demo2026!', gen_salt('bf', 10)),
    'Fernando', 'Carbajal', 'Ríos', 'DNI', '10000001', '999000001',
    NULL, true, (SELECT id FROM core.roles WHERE codigo = 'super_admin'),
    false, NULL, NULL, '#07B162', 'activo')
  ON CONFLICT (email) DO NOTHING;
  SELECT id INTO v_super FROM core.users WHERE email = 'admin@vetpatitas.pe';

  INSERT INTO core.users (
    codigo, email, password_hash, nombres, apellido_paterno, apellido_materno,
    tipo_documento, numero_documento, telefono, empresa_id, rol_id,
    es_veterinario, colegiatura, especializacion_id, color_agenda, estado)
  VALUES (
    'USR-0002', 'administracion@vetpatitas.pe', crypt('Demo2026!', gen_salt('bf', 10)),
    'Lucía', 'Mendoza', 'Paredes', 'DNI', '10000002', '999000002',
    v_emp, (SELECT id FROM core.roles WHERE codigo = 'admin_empresa'),
    false, NULL, NULL, '#2D7EE5', 'activo')
  ON CONFLICT (email) DO NOTHING;
  SELECT id INTO v_admin FROM core.users WHERE email = 'administracion@vetpatitas.pe';

  INSERT INTO core.users (
    codigo, email, password_hash, nombres, apellido_paterno, apellido_materno,
    tipo_documento, numero_documento, telefono, empresa_id, rol_id,
    es_veterinario, colegiatura, especializacion_id, color_agenda, estado)
  VALUES (
    'USR-0003', 'jperez@vetpatitas.pe', crypt('Demo2026!', gen_salt('bf', 10)),
    'Jorge', 'Pérez', 'Salas', 'DNI', '10000003', '999000003',
    v_emp, (SELECT id FROM core.roles WHERE codigo = 'veterinario'),
    true, 'CMVP-8421',
    (SELECT id FROM core.especializaciones WHERE codigo = 'MEDICINA_GENERAL'),
    '#07B162', 'activo')
  ON CONFLICT (email) DO NOTHING;
  SELECT id INTO v_vet1 FROM core.users WHERE email = 'jperez@vetpatitas.pe';

  INSERT INTO core.users (
    codigo, email, password_hash, nombres, apellido_paterno, apellido_materno,
    tipo_documento, numero_documento, telefono, empresa_id, rol_id,
    es_veterinario, colegiatura, especializacion_id, color_agenda, estado)
  VALUES (
    'USR-0004', 'mrojas@vetpatitas.pe', crypt('Demo2026!', gen_salt('bf', 10)),
    'María', 'Rojas', 'Quispe', 'DNI', '10000004', '999000004',
    v_emp, (SELECT id FROM core.roles WHERE codigo = 'veterinario'),
    true, 'CMVP-9137',
    (SELECT id FROM core.especializaciones WHERE codigo = 'CIRUGIA'),
    '#8359E5', 'activo')
  ON CONFLICT (email) DO NOTHING;
  SELECT id INTO v_vet2 FROM core.users WHERE email = 'mrojas@vetpatitas.pe';

  INSERT INTO core.users (
    codigo, email, password_hash, nombres, apellido_paterno, apellido_materno,
    tipo_documento, numero_documento, telefono, empresa_id, rol_id, color_agenda, estado)
  VALUES (
    'USR-0005', 'recepcion@vetpatitas.pe', crypt('Demo2026!', gen_salt('bf', 10)),
    'Andrea', 'Vargas', 'Luna', 'DNI', '10000005', '999000005',
    v_emp, (SELECT id FROM core.roles WHERE codigo = 'recepcion'), '#E89A1F', 'activo')
  ON CONFLICT (email) DO NOTHING;
  SELECT id INTO v_recep FROM core.users WHERE email = 'recepcion@vetpatitas.pe';

  INSERT INTO core.users (
    codigo, email, password_hash, nombres, apellido_paterno, apellido_materno,
    tipo_documento, numero_documento, telefono, empresa_id, rol_id, color_agenda, estado)
  VALUES (
    'USR-0006', 'almacen@vetpatitas.pe', crypt('Demo2026!', gen_salt('bf', 10)),
    'Ricardo', 'Flores', 'Tapia', 'DNI', '10000006', '999000006',
    v_emp, (SELECT id FROM core.roles WHERE codigo = 'almacen'), '#DC4040', 'activo')
  ON CONFLICT (email) DO NOTHING;
  SELECT id INTO v_almacen_u FROM core.users WHERE email = 'almacen@vetpatitas.pe';

  INSERT INTO core.users (
    codigo, email, password_hash, nombres, apellido_paterno, apellido_materno,
    tipo_documento, numero_documento, telefono, empresa_id, rol_id, estado)
  VALUES (
    'USR-0007', 'gerencia@vetpatitas.pe', crypt('Demo2026!', gen_salt('bf', 10)),
    'Patricia', 'Soto', 'Aguirre', 'DNI', '10000007', '999000007',
    NULL, (SELECT id FROM core.roles WHERE codigo = 'gerente'), 'activo')
  ON CONFLICT (email) DO NOTHING;

  -- ---- Servicios ------------------------------------------------------------
  INSERT INTO core.servicios (empresa_id, codigo, nombre, descripcion, tipo, categoria_id,
                              precio, costo_estimado, duracion_min, requiere_ayuno, created_by)
  VALUES
    (v_emp, 'SRV-0001', 'Consulta general',            'Evaluación clínica completa',        'consulta',      v_cat_serv,  60.00, 15.00, 30, false, v_super),
    (v_emp, 'SRV-0002', 'Consulta de urgencia',        'Atención inmediata fuera de agenda',  'consulta',      v_cat_serv, 120.00, 30.00, 45, false, v_super),
    (v_emp, 'SRV-0003', 'Control post-operatorio',     'Revisión de herida y retiro de puntos','consulta',     v_cat_serv,  40.00, 10.00, 20, false, v_super),
    (v_emp, 'SRV-0004', 'Vacunación antirrábica',      'Aplicación de vacuna antirrábica',    'vacunacion',    NULL,        45.00, 18.00, 15, false, v_super),
    (v_emp, 'SRV-0005', 'Vacuna quíntuple canina',     'Refuerzo quíntuple',                  'vacunacion',    NULL,        65.00, 28.00, 15, false, v_super),
    (v_emp, 'SRV-0006', 'Vacuna triple felina',        'Refuerzo triple felina',              'vacunacion',    NULL,        70.00, 30.00, 15, false, v_super),
    (v_emp, 'SRV-0007', 'Desparasitación interna',     'Antiparasitario oral según peso',     'desparasitacion',NULL,       35.00, 12.00, 10, false, v_super),
    (v_emp, 'SRV-0008', 'Esterilización canina hembra','Ovariohisterectomía',                 'cirugia',       NULL,       450.00,150.00,120, true,  v_super),
    (v_emp, 'SRV-0009', 'Esterilización canina macho', 'Orquiectomía',                        'cirugia',       NULL,       320.00,100.00, 90, true,  v_super),
    (v_emp, 'SRV-0010', 'Esterilización felina',       'Castración de gato',                  'cirugia',       NULL,       260.00, 85.00, 75, true,  v_super),
    (v_emp, 'SRV-0011', 'Profilaxis dental',           'Limpieza dental con anestesia',       'cirugia',       NULL,       280.00, 90.00, 60, true,  v_super),
    (v_emp, 'SRV-0012', 'Hemograma completo',          'Análisis hematológico',               'laboratorio',   NULL,        85.00, 35.00, 20, true,  v_super),
    (v_emp, 'SRV-0013', 'Perfil bioquímico',           'Función renal y hepática',            'laboratorio',   NULL,       140.00, 60.00, 20, true,  v_super),
    (v_emp, 'SRV-0014', 'Radiografía digital',         'Estudio radiográfico 2 proyecciones', 'imagen',        NULL,       120.00, 40.00, 30, false, v_super),
    (v_emp, 'SRV-0015', 'Ecografía abdominal',         'Ultrasonido abdominal completo',      'imagen',        NULL,       160.00, 50.00, 40, true,  v_super),
    (v_emp, 'SRV-0016', 'Baño medicado',               'Baño con shampoo terapéutico',        'grooming',      NULL,        55.00, 15.00, 60, false, v_super),
    (v_emp, 'SRV-0017', 'Corte y peinado',             'Grooming estético completo',          'grooming',      NULL,        75.00, 20.00, 90, false, v_super),
    (v_emp, 'SRV-0018', 'Día de hospitalización',      'Internamiento con monitoreo',         'hospitalizacion',NULL,      180.00, 60.00,  0, false, v_super),
    -- Carta de peluquería. Se cobra por servicio y no por paquete cerrado
    -- porque en la práctica cada animal lleva una combinación distinta: el
    -- schnauzer entra a corte de raza, el labrador a baño y deslanado.
    (v_emp, 'SRV-0019', 'Baño e higiene',              'Baño, secado y cepillado',            'grooming',      v_cat_est,   45.00, 12.00, 60, false, v_super),
    (v_emp, 'SRV-0020', 'Corte de raza',               'Corte según estándar de la raza',     'grooming',      v_cat_est,  110.00, 25.00,120, false, v_super),
    (v_emp, 'SRV-0021', 'Deslanado',                   'Retiro de subpelo muerto',            'grooming',      v_cat_est,   90.00, 20.00, 90, false, v_super),
    (v_emp, 'SRV-0022', 'Corte de uñas',               'Corte y limado',                      'grooming',      v_cat_est,   15.00,  3.00, 10, false, v_super),
    (v_emp, 'SRV-0023', 'Limpieza de oídos',           'Higiene del conducto auditivo',       'grooming',      v_cat_est,   20.00,  5.00, 10, false, v_super),
    (v_emp, 'SRV-0024', 'Vaciado de glándulas anales', 'Drenaje manual de sacos anales',      'grooming',      v_cat_est,   25.00,  5.00, 10, false, v_super),
    (v_emp, 'SRV-0025', 'Baño antipulgas',             'Baño con shampoo ectoparasiticida',   'grooming',      v_cat_est,   70.00, 22.00, 75, false, v_super)
  ON CONFLICT (empresa_id, codigo) DO NOTHING;

  -- ---- Planes preventivos ---------------------------------------------------
  -- Tres tramos de vida, que es como se venden en la práctica: el cachorro
  -- necesita el esquema completo de vacunas en su primer año, el adulto una
  -- revisión y sus refuerzos, y el senior análisis que detecten a tiempo lo que
  -- a esa edad aparece sin avisar.
  --
  -- Los precios son de referencia para la demostración; cada clínica pone los
  -- suyos. Lo que importa es la estructura: cuota mensual, cupos por beneficio
  -- y un descuento general sobre todo lo demás.
  INSERT INTO core.planes (empresa_id, codigo, nombre, descripcion, periodicidad,
                           precio, vigencia_meses, especie_id, edad_min_meses,
                           edad_max_meses, descuento_general_pct, color, created_by)
  VALUES
    (v_emp, 'PLAN-CACHORRO', 'Plan Cachorro',
     'El primer año completo: esquema de vacunación, desparasitaciones y controles.',
     'mensual', 89.00, 12, v_esp_can, 0, 12, 20.00, '#22c55e', v_super),
    (v_emp, 'PLAN-ADULTO', 'Plan Adulto',
     'Medicina preventiva del año: controles, refuerzos y desparasitación.',
     'mensual', 69.00, 12, NULL, 12, 84, 15.00, '#3b82f6', v_super),
    (v_emp, 'PLAN-SENIOR', 'Plan Senior',
     'A partir de los 7 años: más controles y análisis para ver venir lo que a esa edad no avisa.',
     'mensual', 119.00, 12, NULL, 84, NULL, 15.00, '#a855f7', v_super)
  ON CONFLICT (empresa_id, codigo) DO NOTHING;

  -- Beneficios. NO se borran y se rehacen: las migraciones se reaplican en cada
  -- despliegue, y `suscripcion_consumos.beneficio_id` se pone a NULL al borrar
  -- el beneficio. Es decir, un DELETE aquí le reiniciaba a cada suscriptor el
  -- contador de "3 consultas usadas de 3" y le regalaba el cupo otra vez.
  INSERT INTO core.plan_beneficios (plan_id, tipo, servicio_id, cantidad, descripcion, orden)
  SELECT p.id, 'servicio_incluido', s.id, b.cant, b.texto, b.orden
  FROM core.planes p
  JOIN (VALUES
    ('PLAN-CACHORRO', 'SRV-0001', 4, '4 consultas generales',            1),
    ('PLAN-CACHORRO', 'SRV-0004', 1, 'Vacuna antirrábica',               2),
    ('PLAN-CACHORRO', 'SRV-0005', 3, 'Esquema quíntuple (3 dosis)',      3),
    ('PLAN-CACHORRO', 'SRV-0007', 4, '4 desparasitaciones',              4),
    ('PLAN-CACHORRO', 'SRV-0019', 2, '2 baños e higiene',                5),
    ('PLAN-ADULTO',   'SRV-0001', 3, '3 consultas generales',            1),
    ('PLAN-ADULTO',   'SRV-0004', 1, 'Refuerzo antirrábico anual',       2),
    ('PLAN-ADULTO',   'SRV-0005', 1, 'Refuerzo quíntuple anual',         3),
    ('PLAN-ADULTO',   'SRV-0007', 2, '2 desparasitaciones',              4),
    ('PLAN-ADULTO',   'SRV-0019', 2, '2 baños e higiene',                5),
    ('PLAN-SENIOR',   'SRV-0001', 4, '4 consultas geriátricas',          1),
    ('PLAN-SENIOR',   'SRV-0004', 1, 'Refuerzo antirrábico anual',       2),
    ('PLAN-SENIOR',   'SRV-0007', 2, '2 desparasitaciones',              3),
    ('PLAN-SENIOR',   'SRV-0012', 1, 'Hemograma completo anual',         4),
    ('PLAN-SENIOR',   'SRV-0013', 1, 'Perfil bioquímico anual',          5)
  ) AS b(plan, srv, cant, texto, orden) ON b.plan = p.codigo
  JOIN core.servicios s ON s.empresa_id = v_emp AND s.codigo = b.srv
  WHERE p.empresa_id = v_emp
  ON CONFLICT (plan_id, servicio_id) DO NOTHING;


  -- ---- Esquemas de vacunación ----------------------------------------------
  INSERT INTO core.esquemas_vacunacion (
    empresa_id, especie_id, nombre, descripcion, obligatoria,
    edad_inicio_semanas, intervalo_dias, dosis_totales, revacunacion_meses)
  VALUES
    (v_emp, v_canino, 'Antirrábica canina',  'Obligatoria por normativa',           true,  12, 365, 1, 12),
    (v_emp, v_canino, 'Quíntuple canina',    'Moquillo, parvovirus, hepatitis…',    true,   6,  21, 3, 12),
    (v_emp, v_canino, 'Tos de las perreras', 'Bordetella bronchiseptica',           false, 12, 365, 1, 12),
    (v_emp, v_felino, 'Antirrábica felina',  'Obligatoria por normativa',           true,  12, 365, 1, 12),
    (v_emp, v_felino, 'Triple felina',       'Rinotraqueítis, calicivirus, panleuc.',true,  8,  21, 2, 12),
    (v_emp, v_felino, 'Leucemia felina',     'Previa prueba de descarte',           false, 9,   21, 2, 12)
  ON CONFLICT DO NOTHING;

  -- ---- Consentimientos ------------------------------------------------------
  INSERT INTO core.clausulas (empresa_id, tipo, titulo, contenido, orden) VALUES
    (v_emp, 'consentimiento', 'Consentimiento informado quirúrgico',
     'Autorizo al equipo médico de la clínica a realizar el procedimiento quirúrgico indicado, '
     'así como la administración de anestesia y los procedimientos complementarios que resulten '
     'necesarios. Declaro haber sido informado de los riesgos inherentes al acto anestésico y '
     'quirúrgico, y de que no existe garantía de resultado.', 1),
    (v_emp, 'consentimiento', 'Autorización de hospitalización',
     'Autorizo el internamiento de mi mascota y los tratamientos que el médico veterinario '
     'tratante considere necesarios durante su permanencia. Me comprometo a cubrir los costos '
     'derivados de la hospitalización.', 2),
    (v_emp, 'politica', 'Política de cancelación de citas',
     'Las citas pueden reprogramarse o cancelarse hasta 4 horas antes del horario reservado. '
     'La inasistencia reiterada sin aviso puede restringir la reserva anticipada.', 3)
  ON CONFLICT DO NOTHING;

  -- ---- Proveedores ----------------------------------------------------------
  INSERT INTO core.proveedores (
    empresa_id, codigo, tipo_documento, numero_documento, razon_social, nombre_comercial,
    categoria_id, direccion, telefono, correo, dias_credito, banco, created_by)
  VALUES
    (v_emp, 'PRV-0001', 'RUC', '20512345678', 'Distribuidora Veterinaria Andina S.A.C.', 'DistriVet',
     v_cat_prov, 'Av. Colonial 2450, Lima', '013344556', 'ventas@distrivet.pe', 30, 'BCP', v_super),
    (v_emp, 'PRV-0002', 'RUC', '20487654321', 'Laboratorios Zoetis Perú S.A.', 'Zoetis',
     v_cat_prov, 'Av. Canaval y Moreyra 380, San Isidro', '012223344', 'pedidos@zoetis.pe', 45, 'BBVA', v_super),
    (v_emp, 'PRV-0003', 'RUC', '20556677889', 'Nutrición Animal del Perú S.A.C.', 'NutriPet',
     NULL, 'Av. Argentina 1500, Callao', '014455667', 'contacto@nutripet.pe', 15, 'Interbank', v_super)
  ON CONFLICT (empresa_id, numero_documento) DO NOTHING;

  -- ---- Productos ------------------------------------------------------------
  INSERT INTO core.productos (
    empresa_id, codigo, nombre, tipo, categoria_id, principio_activo, laboratorio,
    presentacion, unidad_medida, requiere_receta, refrigerado,
    precio_compra, precio_venta, stock_minimo, maneja_lotes, created_by)
  VALUES
    (v_emp, 'PRD-0001', 'Vacuna antirrábica canina',   'vacuna',      NULL,      'Virus rábico inactivado', 'Zoetis',   'Frasco 1 dosis',      'UND', true,  true,  18.00,  45.00, 20, true,  v_super),
    (v_emp, 'PRD-0002', 'Vacuna quíntuple canina',     'vacuna',      NULL,      'Vanguard Plus 5',         'Zoetis',   'Frasco 1 dosis',      'UND', true,  true,  28.00,  65.00, 15, true,  v_super),
    (v_emp, 'PRD-0003', 'Vacuna triple felina',        'vacuna',      NULL,      'Felocell 3',              'Zoetis',   'Frasco 1 dosis',      'UND', true,  true,  30.00,  70.00, 10, true,  v_super),
    (v_emp, 'PRD-0004', 'Amoxicilina 500 mg',          'medicamento', v_cat_med, 'Amoxicilina',             'Genérico', 'Caja x 20 tabletas',  'CAJA',true,  false, 22.00,  48.00, 10, true,  v_super),
    (v_emp, 'PRD-0005', 'Meloxicam 1,5 mg/ml',         'medicamento', v_cat_med, 'Meloxicam',               'Boehringer','Frasco 10 ml',       'UND', true,  false, 35.00,  72.00,  8, true,  v_super),
    (v_emp, 'PRD-0006', 'Ivermectina inyectable',      'medicamento', v_cat_med, 'Ivermectina 1%',          'Agrovet',  'Frasco 50 ml',        'UND', true,  false, 28.00,  60.00,  6, true,  v_super),
    (v_emp, 'PRD-0007', 'Antiparasitario oral',        'medicamento', v_cat_med, 'Praziquantel + Pirantel', 'Bayer',    'Caja x 4 tabletas',   'CAJA',false, false, 14.00,  32.00, 15, true,  v_super),
    (v_emp, 'PRD-0008', 'Suero fisiológico 0,9%',      'insumo',      NULL,      'Cloruro de sodio',        'Genérico', 'Bolsa 500 ml',        'UND', false, false,  6.50,  15.00, 25, false, v_super),
    (v_emp, 'PRD-0009', 'Jeringa 5 ml estéril',        'insumo',      NULL,      NULL,                      'Nipro',    'Unidad',              'UND', false, false,  0.60,   1.50, 100,false, v_super),
    (v_emp, 'PRD-0010', 'Gasa estéril 10x10',          'insumo',      NULL,      NULL,                      'Genérico', 'Paquete x 10',        'PQT', false, false,  3.50,   8.00, 30, false, v_super),
    (v_emp, 'PRD-0011', 'Sutura absorbible 3/0',       'insumo',      NULL,      'Ácido poliglicólico',     'Ethicon',  'Sobre unidad',        'UND', false, false, 12.00,  26.00, 20, true,  v_super),
    (v_emp, 'PRD-0012', 'Alimento medicado renal 3 kg','alimento',    v_cat_alim,NULL,                      'Royal Canin','Bolsa 3 kg',        'UND', false, false, 78.00, 145.00,  6, false, v_super),
    (v_emp, 'PRD-0013', 'Alimento cachorro 15 kg',     'alimento',    v_cat_alim,NULL,                      'Pro Plan', 'Bolsa 15 kg',         'UND', false, false,145.00, 235.00,  4, false, v_super),
    (v_emp, 'PRD-0014', 'Shampoo medicado clorhexidina','medicamento',v_cat_med, 'Clorhexidina 2%',         'Virbac',   'Frasco 250 ml',       'UND', false, false, 32.00,  68.00,  8, false, v_super),
    (v_emp, 'PRD-0015', 'Collar isabelino mediano',    'accesorio',   NULL,      NULL,                      'Genérico', 'Unidad',              'UND', false, false, 12.00,  28.00, 10, false, v_super)
  ON CONFLICT (empresa_id, codigo) DO NOTHING;

  -- Stock inicial: una entrada por producto para que el kardex tenga origen
  INSERT INTO core.movimientos_inventario (
    empresa_id, producto_id, almacen_id, tipo, motivo, cantidad, costo_unitario,
    observaciones, created_by)
  SELECT v_emp, p.id, v_almacen, 'entrada', 'ajuste_inventario',
         CASE p.tipo WHEN 'insumo' THEN 120 WHEN 'alimento' THEN 12 ELSE 40 END,
         p.precio_compra, 'Carga inicial de inventario', v_super
  FROM core.productos p
  WHERE p.empresa_id = v_emp
    AND NOT EXISTS (SELECT 1 FROM core.movimientos_inventario mv WHERE mv.producto_id = p.id);


  -- ---- Usuarios de la empresa 2 ---------------------------------------------
  -- Sin usuarios propios la empresa 2 no sería operable: solo entraría el
  -- super_admin, y entonces la demo no probaría el aislamiento real (que es
  -- justamente lo que se quiere mostrar).
  INSERT INTO core.users (
    codigo, email, password_hash, nombres, apellido_paterno, apellido_materno,
    tipo_documento, numero_documento, telefono, empresa_id, rol_id,
    es_veterinario, colegiatura, especializacion_id, color_agenda, estado)
  VALUES (
    'USR-0101', 'administracion@vethuellitas.pe', crypt('Demo2026!', gen_salt('bf', 10)),
    'Carmen', 'Ibáñez', 'Delgado', 'DNI', '10000101', '999000101',
    v_emp2, (SELECT id FROM core.roles WHERE codigo = 'admin_empresa'),
    false, NULL, NULL, '#2D7EE5', 'activo')
  ON CONFLICT (email) DO NOTHING;

  INSERT INTO core.users (
    codigo, email, password_hash, nombres, apellido_paterno, apellido_materno,
    tipo_documento, numero_documento, telefono, empresa_id, rol_id,
    es_veterinario, colegiatura, especializacion_id, color_agenda, estado)
  VALUES (
    'USR-0102', 'dvaldez@vethuellitas.pe', crypt('Demo2026!', gen_salt('bf', 10)),
    'Diego', 'Valdez', 'Cornejo', 'DNI', '10000102', '999000102',
    v_emp2, (SELECT id FROM core.roles WHERE codigo = 'veterinario'),
    true, 'CMVP-7755',
    (SELECT id FROM core.especializaciones WHERE codigo = 'MEDICINA_GENERAL'),
    '#07B162', 'activo')
  ON CONFLICT (email) DO NOTHING;

  INSERT INTO core.users (
    codigo, email, password_hash, nombres, apellido_paterno, apellido_materno,
    tipo_documento, numero_documento, telefono, empresa_id, rol_id, color_agenda, estado)
  VALUES (
    'USR-0103', 'recepcion@vethuellitas.pe', crypt('Demo2026!', gen_salt('bf', 10)),
    'Sofía', 'Ramírez', 'Ochoa', 'DNI', '10000103', '999000103',
    v_emp2, (SELECT id FROM core.roles WHERE codigo = 'recepcion'), '#E89A1F', 'activo')
  ON CONFLICT (email) DO NOTHING;

  -- ---------------------------------------------------------------------------
  -- EMPRESA 2: catálogo propio
  --
  -- Cada empresa es un negocio independiente: no hereda nada de la primera.
  -- Se le carga un catálogo mínimo para que sea operable desde el día uno y
  -- para que la demo muestre el aislamiento con datos reales a ambos lados.
  -- ---------------------------------------------------------------------------
  INSERT INTO core.categorias (empresa_id, ambito, codigo, nombre, orden) VALUES
    (v_emp2, 'servicio', 'CONSULTAS',   'Consultas',           1),
    (v_emp2, 'servicio', 'PREVENTIVA',  'Medicina preventiva', 2),
    (v_emp2, 'producto', 'MEDICAMENTO', 'Medicamentos',        1),
    (v_emp2, 'producto', 'INSUMO',      'Insumos médicos',     2)
  ON CONFLICT (empresa_id, ambito, codigo) DO NOTHING;

  INSERT INTO core.servicios (empresa_id, codigo, nombre, descripcion, tipo,
                              precio, costo_estimado, duracion_min, created_by)
  VALUES
    (v_emp2, 'SRV-0001', 'Consulta general',       'Evaluación clínica completa', 'consulta',       70.00, 18.00, 30, v_super),
    (v_emp2, 'SRV-0002', 'Consulta de urgencia',   'Atención inmediata',          'consulta',      140.00, 35.00, 45, v_super),
    (v_emp2, 'SRV-0003', 'Vacunación antirrábica', 'Aplicación de antirrábica',   'vacunacion',     50.00, 18.00, 15, v_super),
    (v_emp2, 'SRV-0004', 'Desparasitación',        'Antiparasitario según peso',  'desparasitacion',40.00, 12.00, 10, v_super),
    (v_emp2, 'SRV-0005', 'Baño medicado',          'Shampoo terapéutico',         'grooming',       65.00, 15.00, 60, v_super)
  ON CONFLICT (empresa_id, codigo) DO NOTHING;

  INSERT INTO core.productos (empresa_id, codigo, nombre, tipo, presentacion,
                              unidad_medida, precio_compra, precio_venta,
                              stock_minimo, created_by)
  VALUES
    (v_emp2, 'PRD-0001', 'Vacuna antirrábica canina', 'vacuna',      'Frasco 1 dosis',     'UND', 18.00, 50.00, 15, v_super),
    (v_emp2, 'PRD-0002', 'Amoxicilina 500 mg',        'medicamento', 'Caja x 20 tabletas', 'CAJA',22.00, 52.00, 10, v_super),
    (v_emp2, 'PRD-0003', 'Jeringa 5 ml estéril',      'insumo',      'Unidad',             'UND',  0.60,  1.60, 80, v_super),
    (v_emp2, 'PRD-0004', 'Suero fisiológico 0,9%',    'insumo',      'Bolsa 500 ml',       'UND',  6.50, 16.00, 20, v_super)
  ON CONFLICT (empresa_id, codigo) DO NOTHING;

  INSERT INTO core.movimientos_inventario (
    empresa_id, producto_id, almacen_id, tipo, motivo, cantidad, costo_unitario,
    observaciones, created_by)
  SELECT v_emp2, p.id,
         (SELECT id FROM core.almacenes WHERE empresa_id = v_emp2 AND es_principal LIMIT 1),
         'entrada', 'ajuste_inventario',
         CASE p.tipo WHEN 'insumo' THEN 100 ELSE 30 END,
         p.precio_compra, 'Carga inicial de inventario', v_super
  FROM core.productos p
  WHERE p.empresa_id = v_emp2
    AND NOT EXISTS (SELECT 1 FROM core.movimientos_inventario mv WHERE mv.producto_id = p.id);

  -- Horario propio de la segunda empresa
  DELETE FROM core.horarios_atencion WHERE empresa_id = v_emp2;
  INSERT INTO core.horarios_atencion (empresa_id, dia_semana, hora_inicio, hora_fin, activo)
  SELECT v_emp2, d, '10:00'::time, '19:00'::time, true FROM generate_series(1, 5) d;

  RAISE NOTICE 'Seeds base aplicados. Empresa 1: %  ·  Empresa 2: %', v_emp, v_emp2;
END $$;
