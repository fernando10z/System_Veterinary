-- =============================================================================
-- 98_seeds_base.sql — Datos de referencia que necesita cualquier instalación
--
-- Idempotente: se puede reaplicar sin duplicar. Incluye SOLO lo que es igual en
-- todas las clínicas:
--   1. Catálogo de permisos
--   2. Roles del sistema y su matriz de permisos
--   3. Especializaciones, especies y razas (maestros)
--
-- Aquí NO se crean empresas ni usuarios. Este archivo corre en producción en
-- cada despliegue: un usuario con una contraseña conocida aquí sería una puerta
-- abierta en cada clínica instalada, y un `ON CONFLICT ... DO UPDATE` sobre su
-- hash la volvía a abrir cada vez que alguien la cerraba.
--
--   · Primer super admin de producción:  db/scripts/crear-superadmin.sh
--   · Empresas y usuarios de demostración: db/seeds/ (solo con SEED_DEMO=1)
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
  ('empresas:gestionar',   'empresas',    'gestionar',  'Administrar empresas'),
  -- Configurar la PROPIA empresa (series, IGV, datos fiscales, credenciales del
  -- PSE) es distinto de administrar el padrón de empresas: lo primero lo hace el
  -- administrador de la clínica, lo segundo solo el super administrador.
  ('empresa:configurar',   'empresas',    'configurar', 'Configurar los datos y series de su empresa'),
  -- Cambiar a mano el estado de un comprobante ante SUNAT (cargar el CDR, marcar
  -- aceptado) decide lo que la clínica declara: no es cosa de mostrador.
  ('facturacion:sunat',    'facturacion', 'sunat',      'Cargar o corregir la respuesta de SUNAT'),
  -- Peluquería: recibir y entregar es mostrador; ver la ficha lo necesita
  -- también el veterinario, que es quien atiende los hallazgos.
  ('peluqueria:ver',       'peluqueria',  'ver',        'Ver el tablero de peluquería'),
  ('peluqueria:operar',    'peluqueria',  'operar',     'Recibir, trabajar y entregar en peluquería'),
  -- Planes preventivos: diseñarlos es de gerencia, venderlos es de mostrador.
  ('planes:ver',           'planes',      'ver',        'Ver planes y suscripciones'),
  ('planes:gestionar',     'planes',      'gestionar',  'Crear y editar planes preventivos'),
  ('planes:vender',        'planes',      'vender',     'Suscribir pacientes a un plan')
ON CONFLICT (codigo) DO UPDATE
  SET modulo = EXCLUDED.modulo, accion = EXCLUDED.accion, descripcion = EXCLUDED.descripcion;

-- =============================================================================
-- 2. ROLES
-- =============================================================================
INSERT INTO core.roles (codigo, nombre, descripcion, scope, is_sistema) VALUES
  ('super_admin',  'Super administrador', 'Acceso total a todas las empresas',                  'global',            true),
  ('gerente',      'Gerencia',            'Visibilidad de todas las empresas, sin administración','global_restricted', true),
  ('admin_empresa',   'Administrador de empresa','Gestiona por completo una empresa',                  'empresa',           true),
  ('veterinario',  'Veterinario',         'Atiende pacientes y firma historia clínica',       'empresa',           true),
  ('recepcion',    'Recepción',           'Agenda, clientes y cobros de mostrador',           'empresa',           true),
  ('almacen',      'Almacén',             'Inventario y compras',                            'empresa',           true),
  ('contador',     'Contabilidad',        'Facturación, cobranzas y reportes',                'empresa',           true),
  ('peluquero',    'Peluquería',          'Baño, corte y entrega; sin acceso clínico ni a caja','empresa',          true)
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
                   'auditoria:ver','peluqueria:ver','planes:ver');

-- Administrador de empresa: todo dentro de su empresa.
DELETE FROM core.rol_permisos WHERE rol_id = (SELECT id FROM core.roles WHERE codigo = 'admin_empresa');
INSERT INTO core.rol_permisos (rol_id, permiso_id)
SELECT r.id, p.id FROM core.roles r, core.permisos p
WHERE r.codigo = 'admin_empresa' AND p.codigo <> 'empresas:gestionar';

-- Veterinario: clínica y agenda; nada de dinero.
DELETE FROM core.rol_permisos WHERE rol_id = (SELECT id FROM core.roles WHERE codigo = 'veterinario');
INSERT INTO core.rol_permisos (rol_id, permiso_id)
SELECT r.id, p.id FROM core.roles r, core.permisos p
WHERE r.codigo = 'veterinario'
  AND p.codigo IN ('dashboard:ver','clientes:listar','clientes:crear','clientes:editar',
                   'mascotas:listar','mascotas:crear','mascotas:editar',
                   'citas:listar','citas:crear','citas:editar',
                   'clinico:ver','clinico:registrar',
                   'inventario:ver','inventario:mover','reportes:ver','rrhh:ver',
                   'peluqueria:ver','planes:ver');

-- Recepción: la puerta de entrada — agenda, clientes y cobro de mostrador.
DELETE FROM core.rol_permisos WHERE rol_id = (SELECT id FROM core.roles WHERE codigo = 'recepcion');
INSERT INTO core.rol_permisos (rol_id, permiso_id)
SELECT r.id, p.id FROM core.roles r, core.permisos p
WHERE r.codigo = 'recepcion'
  AND p.codigo IN ('dashboard:ver','clientes:listar','clientes:crear','clientes:editar',
                   'mascotas:listar','mascotas:crear','mascotas:editar',
                   'citas:listar','citas:crear','citas:editar','citas:eliminar',
                   'clinico:ver','facturacion:ver','facturacion:emitir',
                   'pagos:ver','pagos:registrar','caja:operar','caja:ver','inventario:ver',
                   'peluqueria:ver','peluqueria:operar','planes:ver','planes:vender');

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
                   'facturacion:anular','facturacion:sunat','pagos:ver','pagos:registrar',
                   'pagos:anular','caja:ver','compras:ver','compras:pagar','inventario:ver',
                   'reportes:ver','reportes:ejecutivo','auditoria:ver','planes:ver');

-- Peluquería: su tablero, la agenda y la ficha del paciente para saber a qué
-- se enfrenta. Nada de historia clínica, nada de dinero.
DELETE FROM core.rol_permisos WHERE rol_id = (SELECT id FROM core.roles WHERE codigo = 'peluquero');
INSERT INTO core.rol_permisos (rol_id, permiso_id)
SELECT r.id, p.id FROM core.roles r, core.permisos p
WHERE r.codigo = 'peluquero'
  AND p.codigo IN ('dashboard:ver','clientes:listar','mascotas:listar','citas:listar',
                   'peluqueria:ver','peluqueria:operar','inventario:ver');

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

-- Razas del catálogo global: empresa_id NULL. Cada empresa puede agregar las
-- suyas después desde Configuración → Catálogos.
INSERT INTO core.razas (especie_id, empresa_id, nombre, tamanio_referencia, peso_min_kg, peso_max_kg, esperanza_vida)
SELECT e.id, NULL, r.nombre, r.tam::core.tamanio_mascota, r.pmin, r.pmax, r.vida
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
-- El índice es parcial (solo las globales): la cláusula WHERE es obligatoria
-- para que Postgres pueda inferirlo.
ON CONFLICT (especie_id, lower(nombre)) WHERE empresa_id IS NULL DO NOTHING;

