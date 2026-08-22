-- =============================================================================
-- 99_seeds.sql — Datos semilla
--
-- Idempotente: se puede reaplicar sin duplicar. Incluye:
--   1. Catálogo de permisos y roles del sistema
--   2. Especializaciones, especies y razas (maestros)
--   3. Sede demo + usuarios + catálogos operativos
--   4. Datos de demostración (clientes, pacientes, agenda, ventas)
-- =============================================================================

SET search_path = core, internal, app, public;

-- =============================================================================
-- 1. PERMISOS
-- =============================================================================
INSERT INTO core.permisos (codigo, modulo, accion, descripcion) VALUES
  ('dashboard:ver',        'dashboard',   'ver',        'Ver el panel de control'),
  ('clientes:listar',      'clientes',    'listar',     'Ver el directorio de propietarios'),
  ('clientes:crear',       'clientes',    'crear',      'Registrar propietarios'),
  ('clientes:editar',      'clientes',    'editar',     'Editar datos de propietarios'),
  ('clientes:eliminar',    'clientes',    'eliminar',   'Dar de baja propietarios'),
  ('mascotas:listar',      'mascotas',    'listar',     'Ver el listado de pacientes'),
  ('mascotas:crear',       'mascotas',    'crear',      'Registrar pacientes'),
  ('mascotas:editar',      'mascotas',    'editar',     'Editar la ficha del paciente'),
  ('mascotas:eliminar',    'mascotas',    'eliminar',   'Dar de baja pacientes'),
  ('citas:listar',         'citas',       'listar',     'Ver la agenda'),
  ('citas:crear',          'citas',       'crear',      'Agendar citas'),
  ('citas:editar',         'citas',       'editar',     'Reprogramar y cambiar estado de citas'),
  ('citas:eliminar',       'citas',       'eliminar',   'Eliminar citas'),
  ('clinico:ver',          'clinico',     'ver',        'Ver la historia clínica'),
  ('clinico:registrar',    'clinico',     'registrar',  'Registrar actos clínicos'),
  ('servicios:gestionar',  'servicios',   'gestionar',  'Administrar el catálogo de servicios'),
  ('catalogos:gestionar',  'catalogos',   'gestionar',  'Administrar catálogos maestros'),
  ('inventario:ver',       'inventario',  'ver',        'Consultar inventario y stock'),
  ('inventario:gestionar', 'inventario',  'gestionar',  'Administrar productos y almacenes'),
  ('inventario:mover',     'inventario',  'mover',      'Registrar movimientos de stock'),
  ('compras:ver',          'compras',     'ver',        'Ver proveedores y órdenes de compra'),
  ('compras:gestionar',    'compras',     'gestionar',  'Crear y editar órdenes de compra'),
  ('compras:recibir',      'compras',     'recibir',    'Recibir mercadería'),
  ('compras:pagar',        'compras',     'pagar',      'Registrar pagos a proveedores'),
  ('facturacion:ver',      'facturacion', 'ver',        'Consultar comprobantes'),
  ('facturacion:emitir',   'facturacion', 'emitir',     'Emitir comprobantes de venta'),
  ('facturacion:anular',   'facturacion', 'anular',     'Anular comprobantes'),
  ('pagos:ver',            'pagos',       'ver',        'Consultar cobros'),
  ('pagos:registrar',      'pagos',       'registrar',  'Registrar cobros de clientes'),
  ('pagos:anular',         'pagos',       'anular',     'Anular cobros'),
  ('caja:operar',          'caja',        'operar',     'Abrir, mover y cerrar caja'),
  ('caja:ver',             'caja',        'ver',        'Ver arqueos de caja'),
  ('rrhh:ver',             'rrhh',        'ver',        'Ver información del equipo'),
  ('rrhh:gestionar',       'rrhh',        'gestionar',  'Administrar turnos, contratos y evaluaciones'),
  ('rrhh:aprobar',         'rrhh',        'aprobar',    'Aprobar permisos y vacaciones'),
  ('reportes:ver',         'reportes',    'ver',        'Ver reportes operativos'),
  ('reportes:ejecutivo',   'reportes',    'ejecutivo',  'Ver el reporte ejecutivo'),
  ('usuarios:listar',      'usuarios',    'listar',     'Ver los usuarios del sistema'),
  ('usuarios:crear',       'usuarios',    'crear',      'Crear usuarios'),
  ('usuarios:editar',      'usuarios',    'editar',     'Editar usuarios'),
  ('usuarios:eliminar',    'usuarios',    'eliminar',   'Eliminar usuarios'),
  ('usuarios:asignar_rol', 'usuarios',    'asignar_rol','Cambiar el rol de un usuario'),
  ('auditoria:ver',        'auditoria',   'ver',        'Ver la bitácora del sistema'),
  ('empresas:gestionar',   'empresas',    'gestionar',  'Administrar sedes')
ON CONFLICT (codigo) DO UPDATE
  SET modulo = EXCLUDED.modulo, accion = EXCLUDED.accion, descripcion = EXCLUDED.descripcion;

-- =============================================================================
-- 2. ROLES
-- =============================================================================
INSERT INTO core.roles (codigo, nombre, descripcion, scope, is_sistema) VALUES
  ('super_admin',  'Super administrador', 'Acceso total a todas las sedes',                  'global',            true),
  ('gerente',      'Gerencia',            'Visibilidad de toda la cadena, sin administración','global_restricted', true),
  ('admin_sede',   'Administrador de sede','Gestiona por completo una sede',                  'empresa',           true),
  ('veterinario',  'Veterinario',         'Atiende pacientes y firma historia clínica',       'empresa',           true),
  ('recepcion',    'Recepción',           'Agenda, clientes y cobros de mostrador',           'empresa',           true),
  ('almacen',      'Almacén',             'Inventario y compras',                            'empresa',           true),
  ('contador',     'Contabilidad',        'Facturación, cobranzas y reportes',                'empresa',           true)
ON CONFLICT (codigo) DO UPDATE
  SET nombre = EXCLUDED.nombre, descripcion = EXCLUDED.descripcion, scope = EXCLUDED.scope;

-- ---- Asignación de permisos por rol -----------------------------------------
-- super_admin no necesita filas: internal.assert_permiso lo deja pasar siempre.

-- Gerencia: ve todo, no administra usuarios ni catálogos.
DELETE FROM core.rol_permisos WHERE rol_id = (SELECT id FROM core.roles WHERE codigo = 'gerente');
INSERT INTO core.rol_permisos (rol_id, permiso_id)
SELECT r.id, p.id FROM core.roles r, core.permisos p
WHERE r.codigo = 'gerente'
  AND p.codigo IN ('dashboard:ver','clientes:listar','mascotas:listar','citas:listar',
                   'clinico:ver','inventario:ver','compras:ver','facturacion:ver',
                   'pagos:ver','caja:ver','rrhh:ver','reportes:ver','reportes:ejecutivo',
                   'auditoria:ver');

-- Administrador de sede: todo dentro de su sede.
DELETE FROM core.rol_permisos WHERE rol_id = (SELECT id FROM core.roles WHERE codigo = 'admin_sede');
INSERT INTO core.rol_permisos (rol_id, permiso_id)
SELECT r.id, p.id FROM core.roles r, core.permisos p
WHERE r.codigo = 'admin_sede' AND p.codigo <> 'empresas:gestionar';

-- Veterinario: clínica y agenda; nada de dinero.
DELETE FROM core.rol_permisos WHERE rol_id = (SELECT id FROM core.roles WHERE codigo = 'veterinario');
INSERT INTO core.rol_permisos (rol_id, permiso_id)
SELECT r.id, p.id FROM core.roles r, core.permisos p
WHERE r.codigo = 'veterinario'
  AND p.codigo IN ('dashboard:ver','clientes:listar','clientes:crear','clientes:editar',
                   'mascotas:listar','mascotas:crear','mascotas:editar',
                   'citas:listar','citas:crear','citas:editar',
                   'clinico:ver','clinico:registrar',
                   'inventario:ver','inventario:mover','reportes:ver','rrhh:ver');

-- Recepción: la puerta de entrada — agenda, clientes y cobro de mostrador.
DELETE FROM core.rol_permisos WHERE rol_id = (SELECT id FROM core.roles WHERE codigo = 'recepcion');
INSERT INTO core.rol_permisos (rol_id, permiso_id)
SELECT r.id, p.id FROM core.roles r, core.permisos p
WHERE r.codigo = 'recepcion'
  AND p.codigo IN ('dashboard:ver','clientes:listar','clientes:crear','clientes:editar',
                   'mascotas:listar','mascotas:crear','mascotas:editar',
                   'citas:listar','citas:crear','citas:editar','citas:eliminar',
                   'clinico:ver','facturacion:ver','facturacion:emitir',
                   'pagos:ver','pagos:registrar','caja:operar','caja:ver','inventario:ver');

-- Almacén: inventario y compras.
DELETE FROM core.rol_permisos WHERE rol_id = (SELECT id FROM core.roles WHERE codigo = 'almacen');
INSERT INTO core.rol_permisos (rol_id, permiso_id)
SELECT r.id, p.id FROM core.roles r, core.permisos p
WHERE r.codigo = 'almacen'
  AND p.codigo IN ('dashboard:ver','inventario:ver','inventario:gestionar','inventario:mover',
                   'compras:ver','compras:gestionar','compras:recibir','reportes:ver');

-- Contabilidad: facturación, cobranzas y reportes.
DELETE FROM core.rol_permisos WHERE rol_id = (SELECT id FROM core.roles WHERE codigo = 'contador');
INSERT INTO core.rol_permisos (rol_id, permiso_id)
SELECT r.id, p.id FROM core.roles r, core.permisos p
WHERE r.codigo = 'contador'
  AND p.codigo IN ('dashboard:ver','clientes:listar','facturacion:ver','facturacion:emitir',
                   'facturacion:anular','pagos:ver','pagos:registrar','pagos:anular',
                   'caja:ver','compras:ver','compras:pagar','reportes:ver','reportes:ejecutivo',
                   'auditoria:ver');

-- =============================================================================
-- 3. MAESTROS: especializaciones, especies, razas
-- =============================================================================
INSERT INTO core.especializaciones (codigo, nombre, descripcion) VALUES
  ('MEDICINA_GENERAL', 'Medicina general',      'Consulta y medicina preventiva'),
  ('CIRUGIA',          'Cirugía',               'Cirugía de tejidos blandos y ortopedia'),
  ('DERMATOLOGIA',     'Dermatología',          'Enfermedades de piel y anexos'),
  ('CARDIOLOGIA',      'Cardiología',           'Enfermedades cardiovasculares'),
  ('ODONTOLOGIA',      'Odontología',           'Salud bucal y profilaxis dental'),
  ('OFTALMOLOGIA',     'Oftalmología',          'Enfermedades oculares'),
  ('TRAUMATOLOGIA',    'Traumatología',         'Lesiones óseas y articulares'),
  ('EXOTICOS',         'Animales exóticos',     'Aves, reptiles y pequeños mamíferos'),
  ('IMAGENOLOGIA',     'Diagnóstico por imagen','Radiografía y ecografía')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO core.especies (codigo, nombre, nombre_cria, icono) VALUES
  ('CANINO',   'Canino',   'Cachorro', 'Dog'),
  ('FELINO',   'Felino',   'Gatito',   'Cat'),
  ('AVE',      'Ave',      'Polluelo', 'Bird'),
  ('ROEDOR',   'Roedor',   'Cría',     'Rat'),
  ('CONEJO',   'Conejo',   'Gazapo',   'Rabbit'),
  ('REPTIL',   'Reptil',   'Cría',     'Turtle'),
  ('EQUINO',   'Equino',   'Potrillo', 'Rabbit'),
  ('OTRO',     'Otro',     'Cría',     'PawPrint')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO core.razas (especie_id, nombre, tamanio_referencia, peso_min_kg, peso_max_kg, esperanza_vida)
SELECT e.id, r.nombre, r.tam::core.tamanio_mascota, r.pmin, r.pmax, r.vida
FROM core.especies e
JOIN (VALUES
  ('CANINO','Mestizo',            'mediano',  5.0, 30.0, 14),
  ('CANINO','Labrador Retriever', 'grande',  25.0, 36.0, 12),
  ('CANINO','Golden Retriever',   'grande',  25.0, 34.0, 12),
  ('CANINO','Pastor Alemán',      'grande',  22.0, 40.0, 11),
  ('CANINO','Bulldog Francés',    'pequenio', 8.0, 14.0, 11),
  ('CANINO','Poodle',             'pequenio', 3.0,  8.0, 15),
  ('CANINO','Chihuahua',          'toy',      1.5,  3.0, 16),
  ('CANINO','Shih Tzu',           'pequenio', 4.0,  7.5, 14),
  ('CANINO','Beagle',             'mediano',  9.0, 11.0, 13),
  ('CANINO','Schnauzer',          'mediano',  6.0,  9.0, 14),
  ('CANINO','Yorkshire Terrier',  'toy',      2.0,  3.5, 15),
  ('CANINO','Rottweiler',         'grande',  35.0, 60.0, 10),
  ('CANINO','Border Collie',      'mediano', 14.0, 20.0, 13),
  ('CANINO','Cocker Spaniel',     'mediano', 12.0, 15.0, 13),
  ('CANINO','Pug',                'pequenio', 6.0,  8.0, 13),
  ('CANINO','Husky Siberiano',    'grande',  16.0, 27.0, 12),
  ('FELINO','Mestizo',            'mediano',  3.0,  6.0, 15),
  ('FELINO','Siamés',             'mediano',  2.5,  5.5, 16),
  ('FELINO','Persa',              'mediano',  3.0,  5.5, 15),
  ('FELINO','Angora',             'mediano',  2.5,  5.0, 15),
  ('FELINO','Maine Coon',         'grande',   5.0, 11.0, 13),
  ('FELINO','Bengalí',            'mediano',  4.0,  7.0, 15),
  ('FELINO','Esfinge',            'mediano',  3.5,  5.0, 14),
  ('AVE',   'Canario',            'toy',      0.02, 0.03, 10),
  ('AVE',   'Periquito',          'toy',      0.03, 0.04, 12),
  ('AVE',   'Cacatúa',            'pequenio', 0.3,  1.2,  40),
  ('AVE',   'Loro',               'pequenio', 0.4,  1.5,  50),
  ('ROEDOR','Hámster',            'toy',      0.02, 0.2,   3),
  ('ROEDOR','Cuy',                'pequenio', 0.7,  1.2,   6),
  ('ROEDOR','Chinchilla',         'pequenio', 0.4,  0.8,  15),
  ('CONEJO','Mini Lop',           'pequenio', 1.3,  2.5,   9),
  ('CONEJO','Cabeza de León',     'pequenio', 1.2,  1.8,   9),
  ('REPTIL','Tortuga terrestre',  'pequenio', 0.5,  5.0,  50),
  ('REPTIL','Iguana',             'mediano',  1.0,  8.0,  15)
) AS r(especie, nombre, tam, pmin, pmax, vida) ON r.especie = e.codigo
ON CONFLICT (especie_id, nombre) DO NOTHING;

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
    '20601234567', 'Clínica Veterinaria Patitas S.A.C.', 'Vet Patitas — Miraflores',
    'Av. Larco 1234, Miraflores', '150122', '014455667', 'contacto@vetpatitas.pe',
    'F001', 'B001', 'NV01', 3, 30)
  ON CONFLICT (ruc) DO UPDATE SET razon_social = EXCLUDED.razon_social
  RETURNING id INTO v_emp;

  INSERT INTO core.empresas (
    ruc, razon_social, nombre_comercial, direccion_fiscal, ubigeo, telefono, correo,
    serie_factura_default, serie_boleta_default, aforo_consultorios, duracion_cita_min)
  VALUES (
    '20609876543', 'Clínica Veterinaria Patitas S.A.C.', 'Vet Patitas — San Isidro',
    'Av. Javier Prado Este 456, San Isidro', '150131', '014455668', 'sanisidro@vetpatitas.pe',
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
  ON CONFLICT (empresa_id, nombre) DO NOTHING;

  INSERT INTO core.consultorios (empresa_id, nombre, tipo) VALUES
    (v_emp2, 'Consultorio 1', 'consulta'),
    (v_emp2, 'Consultorio 2', 'consulta')
  ON CONFLICT (empresa_id, nombre) DO NOTHING;

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
  ON CONFLICT (email) DO UPDATE SET password_hash = EXCLUDED.password_hash
  RETURNING id INTO v_super;

  INSERT INTO core.users (
    codigo, email, password_hash, nombres, apellido_paterno, apellido_materno,
    tipo_documento, numero_documento, telefono, empresa_id, rol_id,
    es_veterinario, colegiatura, especializacion_id, color_agenda, estado)
  VALUES (
    'USR-0002', 'administracion@vetpatitas.pe', crypt('Demo2026!', gen_salt('bf', 10)),
    'Lucía', 'Mendoza', 'Paredes', 'DNI', '10000002', '999000002',
    v_emp, (SELECT id FROM core.roles WHERE codigo = 'admin_sede'),
    false, NULL, NULL, '#2D7EE5', 'activo')
  ON CONFLICT (email) DO UPDATE SET password_hash = EXCLUDED.password_hash
  RETURNING id INTO v_admin;

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
  ON CONFLICT (email) DO UPDATE SET password_hash = EXCLUDED.password_hash
  RETURNING id INTO v_vet1;

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
  ON CONFLICT (email) DO UPDATE SET password_hash = EXCLUDED.password_hash
  RETURNING id INTO v_vet2;

  INSERT INTO core.users (
    codigo, email, password_hash, nombres, apellido_paterno, apellido_materno,
    tipo_documento, numero_documento, telefono, empresa_id, rol_id, color_agenda, estado)
  VALUES (
    'USR-0005', 'recepcion@vetpatitas.pe', crypt('Demo2026!', gen_salt('bf', 10)),
    'Andrea', 'Vargas', 'Luna', 'DNI', '10000005', '999000005',
    v_emp, (SELECT id FROM core.roles WHERE codigo = 'recepcion'), '#E89A1F', 'activo')
  ON CONFLICT (email) DO UPDATE SET password_hash = EXCLUDED.password_hash
  RETURNING id INTO v_recep;

  INSERT INTO core.users (
    codigo, email, password_hash, nombres, apellido_paterno, apellido_materno,
    tipo_documento, numero_documento, telefono, empresa_id, rol_id, color_agenda, estado)
  VALUES (
    'USR-0006', 'almacen@vetpatitas.pe', crypt('Demo2026!', gen_salt('bf', 10)),
    'Ricardo', 'Flores', 'Tapia', 'DNI', '10000006', '999000006',
    v_emp, (SELECT id FROM core.roles WHERE codigo = 'almacen'), '#DC4040', 'activo')
  ON CONFLICT (email) DO UPDATE SET password_hash = EXCLUDED.password_hash
  RETURNING id INTO v_almacen_u;

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
    (v_emp, 'SRV-0018', 'Día de hospitalización',      'Internamiento con monitoreo',         'hospitalizacion',NULL,      180.00, 60.00,  0, false, v_super)
  ON CONFLICT (empresa_id, codigo) DO NOTHING;

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

  RAISE NOTICE 'Seeds base aplicados. Sede principal: %', v_emp;
END $$;
