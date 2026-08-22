-- =============================================================================
-- 02_enums.sql
-- ENUMs nativos PostgreSQL en schema core.
-- Convención: se crean con DO/EXCEPTION para que la migración sea idempotente.
-- =============================================================================

SET search_path = core, public;

-- ---------------------------------------------------------------------------
-- Identidad y acceso
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE core.tipo_documento_identidad AS ENUM ('DNI','CE','RUC','PASAPORTE');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.estado_user AS ENUM ('activo','inactivo','bloqueado','solicitud');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.estado_empresa AS ENUM ('activa','suspendida','cerrada');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Alcance de visibilidad del rol. Réplica del modelo del ERP:
--   global            → super admin, ve todas las sedes
--   global_restricted → gerencia/contabilidad, ven todas las sedes sin privilegios de super admin
--   empresa           → personal de una sede concreta
DO $$ BEGIN
  CREATE TYPE core.scope_rol AS ENUM ('global','global_restricted','empresa');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------------------------------------------------------------------------
-- Clientes (propietarios) y pacientes (mascotas)
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE core.estado_cliente AS ENUM ('activo','inactivo','bloqueado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.sexo_mascota AS ENUM ('macho','hembra','desconocido');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.estado_mascota AS ENUM ('activo','inactivo','fallecido','extraviado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.tamanio_mascota AS ENUM ('toy','pequenio','mediano','grande','gigante');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.tipo_comunicacion AS ENUM ('llamada','correo','whatsapp','sms','presencial','otro');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------------------------------------------------------------------------
-- Agenda clínica
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE core.estado_cita AS ENUM
    ('programada','confirmada','en_espera','en_atencion','completada','cancelada','no_asistio');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.origen_cita AS ENUM ('mostrador','telefono','whatsapp','portal','recurrente');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.accion_cita AS ENUM
    ('creada','confirmada','reprogramada','cancelada','atendida','no_asistio');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.prioridad_cita AS ENUM ('normal','preferente','urgencia','emergencia');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------------------------------------------------------------------------
-- Historia clínica
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE core.estado_consulta AS ENUM ('borrador','cerrada','anulada');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.tipo_evento_clinico AS ENUM
    ('consulta','vacuna','desparasitacion','tratamiento','cirugia','hospitalizacion',
     'examen','nota','documento','peso');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.estado_tratamiento AS ENUM ('activo','completado','suspendido');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.estado_cirugia AS ENUM ('programada','en_quirofano','realizada','cancelada');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.estado_hospitalizacion AS ENUM ('ingresado','en_observacion','alta','fallecido','derivado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.estado_orden_servicio AS ENUM ('pendiente','en_curso','completado','anulado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.via_administracion AS ENUM
    ('oral','subcutanea','intramuscular','intravenosa','topica','oftalmica','otica','inhalatoria','rectal');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------------------------------------------------------------------------
-- Catálogo comercial e inventario
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE core.tipo_servicio AS ENUM
    ('consulta','vacunacion','cirugia','laboratorio','imagen','grooming','hospitalizacion','desparasitacion','otro');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.tipo_producto AS ENUM ('medicamento','insumo','alimento','accesorio','vacuna','otro');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.tipo_movimiento_inventario AS ENUM
    ('entrada','salida','ajuste_positivo','ajuste_negativo','transferencia','merma','vencimiento');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.motivo_movimiento AS ENUM
    ('compra','venta','uso_clinico','donacion','ajuste_inventario','devolucion','vencido','traslado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------------------------------------------------------------------------
-- Compras
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE core.estado_proveedor AS ENUM ('activo','inactivo','bloqueado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.estado_orden_compra AS ENUM
    ('borrador','enviada','en_transito','recibida_parcial','recibida','cancelada');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------------------------------------------------------------------------
-- Facturación y cobranza
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE core.tipo_comprobante AS ENUM
    ('factura','boleta','nota_venta','nota_credito','nota_debito');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.estado_comprobante AS ENUM
    ('borrador','emitido','enviado_sunat','aceptado_sunat','rechazado_sunat','anulado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.moneda_codigo AS ENUM ('PEN','USD');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.metodo_pago AS ENUM
    ('efectivo','tarjeta','transferencia','yape','plin','deposito','credito','mixto');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.estado_pago AS ENUM ('pendiente','parcial','pagado','anulado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.tipo_item_comprobante AS ENUM ('servicio','producto','otro');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------------------------------------------------------------------------
-- Caja
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE core.estado_caja AS ENUM ('abierta','cerrada','cuadrada');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.tipo_movimiento_caja AS ENUM ('ingreso','egreso');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------------------------------------------------------------------------
-- Personal clínico (RRHH)
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE core.tipo_contrato_empleado AS ENUM ('indefinido','plazo_fijo','locacion','practicante','freelance');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.estado_asistencia AS ENUM ('puntual','tardanza','falta','justificada');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.tipo_disponibilidad AS ENUM ('laboral','guardia','libre','vacaciones','permiso','capacitacion');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.tipo_permiso_laboral AS ENUM ('personal','vacaciones','medico','duelo','capacitacion');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.estado_solicitud AS ENUM ('pendiente','aprobado','rechazado','cancelado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------------------------------------------------------------------------
-- Transversales
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE core.estado_generico AS ENUM ('activo','inactivo');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE core.canal_notificacion AS ENUM ('sistema','correo','whatsapp','sms');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
