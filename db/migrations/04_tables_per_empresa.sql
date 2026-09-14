-- =============================================================================
-- 04_tables_per_empresa.sql
-- Tablas con empresa_id: TODO el dato de negocio.
--
-- Cada empresa es un negocio independiente. Su cartera de propietarios, sus
-- pacientes, su agenda, su historia clínica, su inventario, sus compras, su
-- facturación y su caja son suyos y no los ve ninguna otra empresa.
--
-- El aislamiento no se resuelve en la UI ni en el backend: cada función de
-- lectura filtra con
--     (internal.es_acceso_global(p_user_id, p_is_super_admin) OR x.empresa_id = v_emp)
-- así que un bug en el cliente no puede exponer datos de otra empresa.
-- =============================================================================

SET search_path = core, public;

-- =============================================================================
-- CARTERA: PROPIETARIOS Y PACIENTES
-- =============================================================================

-- -----------------------------------------------------------------------------
-- clientes — propietarios de mascotas
--
-- El documento es único DENTRO de cada empresa, no globalmente: dos negocios
-- independientes pueden atender a la misma persona sin verse entre sí, y cada
-- uno mantiene su propia ficha.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.clientes (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id             UUID NOT NULL REFERENCES core.empresas(id) ON DELETE RESTRICT,
  codigo                 VARCHAR(20),
  tipo_documento         core.tipo_documento_identidad NOT NULL DEFAULT 'DNI',
  numero_documento       VARCHAR(20) NOT NULL,
  nombres                VARCHAR(150) NOT NULL,
  apellido_paterno       VARCHAR(100),
  apellido_materno       VARCHAR(100),
  razon_social           VARCHAR(255),          -- si factura a nombre de empresa (RUC)
  telefono               VARCHAR(30),
  telefono_alterno       VARCHAR(30),
  correo                 VARCHAR(150),
  direccion              TEXT,
  ubigeo                 VARCHAR(6),
  fecha_nacimiento       DATE,
  -- Comercial
  linea_credito          NUMERIC(14,2) NOT NULL DEFAULT 0,
  dias_credito           INT NOT NULL DEFAULT 0,
  acepta_marketing       BOOLEAN NOT NULL DEFAULT true,
  -- Portal del propietario
  portal_acceso          BOOLEAN NOT NULL DEFAULT false,
  portal_password_hash   TEXT,
  portal_ultimo_login_at TIMESTAMPTZ,
  estado                 core.estado_cliente NOT NULL DEFAULT 'activo',
  observaciones          TEXT,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at             TIMESTAMPTZ,
  created_by             UUID,
  updated_by             UUID,
  CONSTRAINT uq_clientes_documento UNIQUE (empresa_id, tipo_documento, numero_documento)
);
CREATE INDEX IF NOT EXISTS ix_clientes_empresa    ON core.clientes (empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_clientes_estado     ON core.clientes (empresa_id, estado) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_clientes_nombre_trgm ON core.clientes USING gin (nombres gin_trgm_ops);
CREATE INDEX IF NOT EXISTS ix_clientes_doc_trgm   ON core.clientes USING gin (numero_documento gin_trgm_ops);
CREATE INDEX IF NOT EXISTS ix_clientes_telefono   ON core.clientes (telefono);

COMMENT ON TABLE core.clientes IS
  'Propietarios de mascotas. Cartera privada de cada empresa.';

-- -----------------------------------------------------------------------------
-- mascotas — los pacientes
--
-- empresa_id se hereda del propietario y lo fija el SP: una mascota no puede
-- pertenecer a una empresa distinta de la de su dueño.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.mascotas (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id          UUID NOT NULL REFERENCES core.empresas(id) ON DELETE RESTRICT,
  codigo              VARCHAR(20),               -- historia clínica: HC-000001
  cliente_id          UUID NOT NULL REFERENCES core.clientes(id) ON DELETE RESTRICT,
  nombre              VARCHAR(100) NOT NULL,
  especie_id          UUID NOT NULL REFERENCES core.especies(id),
  raza_id             UUID REFERENCES core.razas(id),
  sexo                core.sexo_mascota NOT NULL DEFAULT 'desconocido',
  color               VARCHAR(80),
  senias_particulares TEXT,
  fecha_nacimiento    DATE,
  edad_aproximada_meses INT,                     -- cuando no se conoce la fecha exacta
  peso_kg             NUMERIC(6,2),              -- último peso registrado (denormalizado)
  tamanio             core.tamanio_mascota,
  esterilizado        BOOLEAN NOT NULL DEFAULT false,
  fecha_esterilizacion DATE,
  microchip           VARCHAR(40),
  num_placa           VARCHAR(40),
  foto_url            TEXT,
  -- Alertas clínicas: se muestran en rojo en cada atención
  alergias            TEXT,
  condiciones_cronicas TEXT,
  observaciones       TEXT,
  estado              core.estado_mascota NOT NULL DEFAULT 'activo',
  fecha_fallecimiento DATE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at          TIMESTAMPTZ,
  created_by          UUID,
  updated_by          UUID,
  CONSTRAINT ck_mascotas_microchip_unico CHECK (microchip IS NULL OR length(microchip) >= 8)
);
CREATE INDEX IF NOT EXISTS ix_mascotas_empresa  ON core.mascotas (empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_mascotas_cliente  ON core.mascotas (cliente_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_mascotas_especie  ON core.mascotas (especie_id);
CREATE INDEX IF NOT EXISTS ix_mascotas_estado   ON core.mascotas (empresa_id, estado) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_mascotas_nombre_trgm ON core.mascotas USING gin (nombre gin_trgm_ops);

-- El microchip es único dentro de la empresa. Globalmente no puede serlo: dos
-- negocios independientes pueden atender al mismo animal y cada uno lo registra.
CREATE UNIQUE INDEX IF NOT EXISTS uq_mascotas_microchip
  ON core.mascotas (empresa_id, microchip) WHERE microchip IS NOT NULL AND deleted_at IS NULL;

COMMENT ON TABLE core.mascotas IS
  'Pacientes. Pertenecen a una empresa a través de su propietario.';

-- -----------------------------------------------------------------------------
-- mascotas_extraviadas — reporte de mascota perdida / encontrada
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.mascotas_extraviadas (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  mascota_id      UUID NOT NULL REFERENCES core.mascotas(id) ON DELETE CASCADE,
  fecha_extravio  DATE NOT NULL,
  zona            VARCHAR(255),
  descripcion     TEXT,
  contacto        VARCHAR(150),
  recompensa      NUMERIC(12,2),
  encontrado      BOOLEAN NOT NULL DEFAULT false,
  fecha_hallazgo  DATE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by      UUID
);
CREATE INDEX IF NOT EXISTS ix_mascotas_extraviadas ON core.mascotas_extraviadas (empresa_id, mascota_id);

-- =============================================================================
-- CATÁLOGOS OPERATIVOS POR SEDE
-- =============================================================================

-- -----------------------------------------------------------------------------
-- categorias — árbol único para servicios y productos (discriminado por `ambito`)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.categorias (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  ambito      VARCHAR(20) NOT NULL CHECK (ambito IN ('servicio','producto','proveedor')),
  codigo      VARCHAR(40) NOT NULL,
  nombre      VARCHAR(120) NOT NULL,
  descripcion TEXT,
  padre_id    UUID REFERENCES core.categorias(id) ON DELETE SET NULL,
  orden       INT NOT NULL DEFAULT 0,
  estado      core.estado_generico NOT NULL DEFAULT 'activo',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_categorias_codigo UNIQUE (empresa_id, ambito, codigo)
);
CREATE INDEX IF NOT EXISTS ix_categorias_empresa ON core.categorias (empresa_id, ambito) WHERE estado = 'activo';

-- -----------------------------------------------------------------------------
-- servicios — catálogo clínico y comercial de la empresa
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.servicios (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  codigo            VARCHAR(40) NOT NULL,
  nombre            VARCHAR(180) NOT NULL,
  descripcion       TEXT,
  tipo              core.tipo_servicio NOT NULL DEFAULT 'consulta',
  categoria_id      UUID REFERENCES core.categorias(id) ON DELETE SET NULL,
  precio            NUMERIC(12,2) NOT NULL DEFAULT 0,
  costo_estimado    NUMERIC(12,2) NOT NULL DEFAULT 0,
  duracion_min      INT NOT NULL DEFAULT 30,
  requiere_ayuno    BOOLEAN NOT NULL DEFAULT false,
  requiere_cita     BOOLEAN NOT NULL DEFAULT true,
  afecto_igv        BOOLEAN NOT NULL DEFAULT true,
  -- Un servicio de vacunación puede quedar ligado al producto-vacuna que consume
  producto_id       UUID,
  estado            core.estado_generico NOT NULL DEFAULT 'activo',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at        TIMESTAMPTZ,
  created_by        UUID,
  updated_by        UUID,
  CONSTRAINT uq_servicios_codigo UNIQUE (empresa_id, codigo)
);
CREATE INDEX IF NOT EXISTS ix_servicios_empresa ON core.servicios (empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_servicios_tipo    ON core.servicios (empresa_id, tipo) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_servicios_nombre_trgm ON core.servicios USING gin (nombre gin_trgm_ops);

-- -----------------------------------------------------------------------------
-- esquemas de vacunación — protocolo por especie (define los refuerzos)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.esquemas_vacunacion (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id     UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  especie_id     UUID NOT NULL REFERENCES core.especies(id),
  nombre         VARCHAR(150) NOT NULL,
  descripcion    TEXT,
  obligatoria    BOOLEAN NOT NULL DEFAULT false,
  edad_inicio_semanas INT,
  intervalo_dias INT,                 -- días hasta el siguiente refuerzo
  dosis_totales  INT NOT NULL DEFAULT 1,
  revacunacion_meses INT,             -- refuerzo anual = 12
  estado         core.estado_generico NOT NULL DEFAULT 'activo',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_esquemas_vac_empresa ON core.esquemas_vacunacion (empresa_id, especie_id);

-- -----------------------------------------------------------------------------
-- horarios de atención de la empresa
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.horarios_atencion (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  dia_semana  INT NOT NULL CHECK (dia_semana BETWEEN 0 AND 6),  -- 0 = domingo
  hora_inicio TIME NOT NULL,
  hora_fin    TIME NOT NULL,
  activo      BOOLEAN NOT NULL DEFAULT true,
  es_guardia  BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ck_horarios_rango CHECK (hora_fin > hora_inicio)
);
CREATE INDEX IF NOT EXISTS ix_horarios_empresa ON core.horarios_atencion (empresa_id, dia_semana);

-- -----------------------------------------------------------------------------
-- consultorios / boxes de atención
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.consultorios (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  nombre      VARCHAR(80) NOT NULL,
  tipo        VARCHAR(40) NOT NULL DEFAULT 'consulta',  -- consulta | quirofano | hospitalizacion | grooming
  capacidad   INT NOT NULL DEFAULT 1,
  estado      core.estado_generico NOT NULL DEFAULT 'activo',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_consultorios_nombre UNIQUE (empresa_id, nombre)
);

-- -----------------------------------------------------------------------------
-- clausulas de contrato / consentimientos informados
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.clausulas (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  tipo        VARCHAR(40) NOT NULL DEFAULT 'consentimiento',  -- consentimiento | politica | contrato
  titulo      VARCHAR(255) NOT NULL,
  contenido   TEXT NOT NULL,
  orden       INT NOT NULL DEFAULT 0,
  estado      core.estado_generico NOT NULL DEFAULT 'activo',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_clausulas_empresa ON core.clausulas (empresa_id, tipo);

-- =============================================================================
-- AGENDA CLÍNICA
-- =============================================================================

CREATE TABLE IF NOT EXISTS core.citas (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  codigo          VARCHAR(20),
  cliente_id      UUID NOT NULL REFERENCES core.clientes(id) ON DELETE RESTRICT,
  mascota_id      UUID NOT NULL REFERENCES core.mascotas(id) ON DELETE RESTRICT,
  veterinario_id  UUID REFERENCES core.users(id),
  servicio_id     UUID REFERENCES core.servicios(id),
  consultorio_id  UUID REFERENCES core.consultorios(id),
  fecha_hora      TIMESTAMPTZ NOT NULL,
  duracion_min    INT NOT NULL DEFAULT 30,
  motivo          TEXT,
  prioridad       core.prioridad_cita NOT NULL DEFAULT 'normal',
  origen          core.origen_cita NOT NULL DEFAULT 'mostrador',
  estado          core.estado_cita NOT NULL DEFAULT 'programada',
  -- Trazabilidad de la sala de espera
  hora_llegada    TIMESTAMPTZ,
  hora_atencion   TIMESTAMPTZ,
  hora_salida     TIMESTAMPTZ,
  recordatorio_enviado_at TIMESTAMPTZ,
  motivo_cancelacion TEXT,
  observaciones   TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at      TIMESTAMPTZ,
  created_by      UUID,
  updated_by      UUID
);
CREATE INDEX IF NOT EXISTS ix_citas_empresa_fecha ON core.citas (empresa_id, fecha_hora) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_citas_veterinario   ON core.citas (veterinario_id, fecha_hora) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_citas_mascota       ON core.citas (mascota_id, fecha_hora DESC);
CREATE INDEX IF NOT EXISTS ix_citas_cliente       ON core.citas (cliente_id, fecha_hora DESC);
CREATE INDEX IF NOT EXISTS ix_citas_estado        ON core.citas (empresa_id, estado) WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS core.citas_historial (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cita_id           UUID NOT NULL REFERENCES core.citas(id) ON DELETE CASCADE,
  accion            core.accion_cita NOT NULL,
  fecha_hora_antes  TIMESTAMPTZ,
  fecha_hora_despues TIMESTAMPTZ,
  motivo            TEXT,
  user_id           UUID,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_citas_historial_cita ON core.citas_historial (cita_id, created_at DESC);

-- Lista de espera: cliente que quiere adelantar su cita si se libera un cupo
CREATE TABLE IF NOT EXISTS core.citas_lista_espera (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id     UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  cliente_id     UUID NOT NULL REFERENCES core.clientes(id) ON DELETE CASCADE,
  mascota_id     UUID NOT NULL REFERENCES core.mascotas(id) ON DELETE CASCADE,
  servicio_id    UUID REFERENCES core.servicios(id),
  veterinario_id UUID REFERENCES core.users(id),
  desde          DATE NOT NULL,
  hasta          DATE,
  nota           TEXT,
  atendido       BOOLEAN NOT NULL DEFAULT false,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_lista_espera_empresa ON core.citas_lista_espera (empresa_id, desde) WHERE atendido = false;

-- =============================================================================
-- HISTORIA CLÍNICA
-- =============================================================================

-- Evento único de la línea de tiempo de la mascota. Todas las tablas clínicas
-- apuntan aquí, así el historial se arma con una sola consulta ordenada.
CREATE TABLE IF NOT EXISTS core.historia_clinica (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id     UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  mascota_id     UUID NOT NULL REFERENCES core.mascotas(id) ON DELETE CASCADE,
  cliente_id     UUID NOT NULL REFERENCES core.clientes(id) ON DELETE RESTRICT,
  veterinario_id UUID REFERENCES core.users(id),
  cita_id        UUID REFERENCES core.citas(id) ON DELETE SET NULL,
  tipo_evento    core.tipo_evento_clinico NOT NULL,
  fecha          TIMESTAMPTZ NOT NULL DEFAULT now(),
  titulo         VARCHAR(255) NOT NULL,
  resumen        TEXT,
  entidad_id     UUID,          -- fila de la tabla específica (consulta, vacuna…)
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by     UUID
);
CREATE INDEX IF NOT EXISTS ix_historia_mascota ON core.historia_clinica (mascota_id, fecha DESC);
CREATE INDEX IF NOT EXISTS ix_historia_empresa ON core.historia_clinica (empresa_id, fecha DESC);
CREATE INDEX IF NOT EXISTS ix_historia_tipo    ON core.historia_clinica (mascota_id, tipo_evento);

COMMENT ON TABLE core.historia_clinica IS 'Línea de tiempo unificada del paciente. Cada tabla clínica registra aquí su evento.';

-- -----------------------------------------------------------------------------
-- consultas — el acto médico (SOAP: subjetivo, objetivo, análisis, plan)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.consultas (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  codigo            VARCHAR(20),
  mascota_id        UUID NOT NULL REFERENCES core.mascotas(id) ON DELETE RESTRICT,
  cliente_id        UUID NOT NULL REFERENCES core.clientes(id) ON DELETE RESTRICT,
  veterinario_id    UUID NOT NULL REFERENCES core.users(id),
  cita_id           UUID REFERENCES core.citas(id) ON DELETE SET NULL,
  fecha             TIMESTAMPTZ NOT NULL DEFAULT now(),
  motivo            TEXT NOT NULL,
  anamnesis         TEXT,                 -- lo que relata el propietario (S)
  -- Constantes fisiológicas (O)
  peso_kg           NUMERIC(6,2),
  temperatura_c     NUMERIC(4,1),
  frecuencia_cardiaca INT,
  frecuencia_respiratoria INT,
  mucosas           VARCHAR(60),
  tllc_seg          NUMERIC(3,1),         -- tiempo de llenado capilar
  condicion_corporal INT CHECK (condicion_corporal BETWEEN 1 AND 9),
  examen_fisico     TEXT,
  -- Análisis y plan (A/P)
  diagnostico       TEXT,
  diagnostico_diferencial TEXT,
  pronostico        VARCHAR(60),
  plan_terapeutico  TEXT,
  prescripcion      TEXT,
  indicaciones_casa TEXT,
  proxima_visita    DATE,
  estado            core.estado_consulta NOT NULL DEFAULT 'borrador',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at        TIMESTAMPTZ,
  created_by        UUID,
  updated_by        UUID
);
CREATE INDEX IF NOT EXISTS ix_consultas_mascota ON core.consultas (mascota_id, fecha DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_consultas_empresa ON core.consultas (empresa_id, fecha DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_consultas_vet     ON core.consultas (veterinario_id, fecha DESC);

-- -----------------------------------------------------------------------------
-- vacunas aplicadas
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.vacunas (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id         UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  mascota_id         UUID NOT NULL REFERENCES core.mascotas(id) ON DELETE CASCADE,
  veterinario_id     UUID REFERENCES core.users(id),
  consulta_id        UUID REFERENCES core.consultas(id) ON DELETE SET NULL,
  esquema_id         UUID REFERENCES core.esquemas_vacunacion(id),
  producto_id        UUID,               -- lote consumido del inventario
  nombre_vacuna      VARCHAR(150) NOT NULL,
  laboratorio        VARCHAR(120),
  lote               VARCHAR(60),
  fecha_aplicacion   DATE NOT NULL,
  dosis_numero       INT NOT NULL DEFAULT 1,
  proximo_refuerzo   DATE,
  via                core.via_administracion NOT NULL DEFAULT 'subcutanea',
  reaccion_adversa   TEXT,
  observaciones      TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by         UUID
);
CREATE INDEX IF NOT EXISTS ix_vacunas_mascota  ON core.vacunas (mascota_id, fecha_aplicacion DESC);
CREATE INDEX IF NOT EXISTS ix_vacunas_refuerzo ON core.vacunas (empresa_id, proximo_refuerzo)
  WHERE proximo_refuerzo IS NOT NULL;

-- -----------------------------------------------------------------------------
-- desparasitaciones
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.desparasitaciones (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id       UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  mascota_id       UUID NOT NULL REFERENCES core.mascotas(id) ON DELETE CASCADE,
  veterinario_id   UUID REFERENCES core.users(id),
  consulta_id      UUID REFERENCES core.consultas(id) ON DELETE SET NULL,
  producto_id      UUID,
  producto_nombre  VARCHAR(150) NOT NULL,
  tipo             VARCHAR(20) NOT NULL DEFAULT 'interna',  -- interna | externa | mixta
  dosis            VARCHAR(80),
  fecha_aplicacion DATE NOT NULL,
  proxima_dosis    DATE,
  observaciones    TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by       UUID
);
CREATE INDEX IF NOT EXISTS ix_desparasitaciones_mascota ON core.desparasitaciones (mascota_id, fecha_aplicacion DESC);

-- -----------------------------------------------------------------------------
-- tratamientos (medicación indicada)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.tratamientos (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id     UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  mascota_id     UUID NOT NULL REFERENCES core.mascotas(id) ON DELETE CASCADE,
  consulta_id    UUID REFERENCES core.consultas(id) ON DELETE SET NULL,
  veterinario_id UUID REFERENCES core.users(id),
  producto_id    UUID,
  medicamento    VARCHAR(200) NOT NULL,
  principio_activo VARCHAR(200),
  dosis          VARCHAR(120) NOT NULL,
  via            core.via_administracion NOT NULL DEFAULT 'oral',
  frecuencia_horas INT,
  duracion_dias  INT,
  fecha_inicio   DATE NOT NULL,
  fecha_fin      DATE,
  indicaciones   TEXT,
  estado         core.estado_tratamiento NOT NULL DEFAULT 'activo',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by     UUID
);
CREATE INDEX IF NOT EXISTS ix_tratamientos_mascota ON core.tratamientos (mascota_id, fecha_inicio DESC);
CREATE INDEX IF NOT EXISTS ix_tratamientos_activos ON core.tratamientos (empresa_id, estado) WHERE estado = 'activo';

-- -----------------------------------------------------------------------------
-- cirugías
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.cirugias (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  codigo            VARCHAR(20),
  mascota_id        UUID NOT NULL REFERENCES core.mascotas(id) ON DELETE RESTRICT,
  cirujano_id       UUID REFERENCES core.users(id),
  anestesista_id    UUID REFERENCES core.users(id),
  consultorio_id    UUID REFERENCES core.consultorios(id),
  servicio_id       UUID REFERENCES core.servicios(id),
  cita_id           UUID REFERENCES core.citas(id) ON DELETE SET NULL,
  nombre            VARCHAR(200) NOT NULL,
  descripcion       TEXT,
  fecha_programada  TIMESTAMPTZ,
  fecha_inicio      TIMESTAMPTZ,
  fecha_fin         TIMESTAMPTZ,
  anestesia_tipo    VARCHAR(120),
  anestesia_dosis   VARCHAR(120),
  hallazgos         TEXT,
  complicaciones    TEXT,
  resultado         TEXT,
  cuidados_post     TEXT,
  consentimiento_firmado BOOLEAN NOT NULL DEFAULT false,
  estado            core.estado_cirugia NOT NULL DEFAULT 'programada',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by        UUID,
  updated_by        UUID
);
CREATE INDEX IF NOT EXISTS ix_cirugias_mascota ON core.cirugias (mascota_id, fecha_programada DESC);
CREATE INDEX IF NOT EXISTS ix_cirugias_empresa ON core.cirugias (empresa_id, estado);

-- -----------------------------------------------------------------------------
-- hospitalizaciones
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.hospitalizaciones (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  codigo            VARCHAR(20),
  mascota_id        UUID NOT NULL REFERENCES core.mascotas(id) ON DELETE RESTRICT,
  veterinario_id    UUID REFERENCES core.users(id),
  consultorio_id    UUID REFERENCES core.consultorios(id),
  jaula             VARCHAR(40),
  motivo            TEXT NOT NULL,
  diagnostico       TEXT,
  fecha_ingreso     TIMESTAMPTZ NOT NULL DEFAULT now(),
  fecha_alta        TIMESTAMPTZ,
  indicaciones_alta TEXT,
  estado            core.estado_hospitalizacion NOT NULL DEFAULT 'ingresado',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by        UUID
);
CREATE INDEX IF NOT EXISTS ix_hospitalizaciones_empresa ON core.hospitalizaciones (empresa_id, estado);
CREATE INDEX IF NOT EXISTS ix_hospitalizaciones_mascota ON core.hospitalizaciones (mascota_id, fecha_ingreso DESC);

-- Registro de evolución durante la hospitalización (turnos, constantes)
CREATE TABLE IF NOT EXISTS core.hospitalizacion_evoluciones (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  hospitalizacion_id  UUID NOT NULL REFERENCES core.hospitalizaciones(id) ON DELETE CASCADE,
  user_id             UUID REFERENCES core.users(id),
  fecha_hora          TIMESTAMPTZ NOT NULL DEFAULT now(),
  temperatura_c       NUMERIC(4,1),
  frecuencia_cardiaca INT,
  frecuencia_respiratoria INT,
  come                BOOLEAN,
  orina               BOOLEAN,
  defeca              BOOLEAN,
  nota                TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_hosp_evol ON core.hospitalizacion_evoluciones (hospitalizacion_id, fecha_hora DESC);

-- -----------------------------------------------------------------------------
-- exámenes de laboratorio / imagen
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.examenes (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id     UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  mascota_id     UUID NOT NULL REFERENCES core.mascotas(id) ON DELETE CASCADE,
  consulta_id    UUID REFERENCES core.consultas(id) ON DELETE SET NULL,
  servicio_id    UUID REFERENCES core.servicios(id),
  veterinario_id UUID REFERENCES core.users(id),
  tipo           VARCHAR(60) NOT NULL,          -- hemograma | bioquimica | radiografia | ecografia…
  nombre         VARCHAR(200) NOT NULL,
  fecha_solicitud TIMESTAMPTZ NOT NULL DEFAULT now(),
  fecha_resultado TIMESTAMPTZ,
  resultado       TEXT,
  valores        JSONB,                          -- {"hematocrito": 42, "ref": "37-55"}
  interpretacion TEXT,
  archivo_url    TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by     UUID
);
CREATE INDEX IF NOT EXISTS ix_examenes_mascota ON core.examenes (mascota_id, fecha_solicitud DESC);

-- -----------------------------------------------------------------------------
-- notas médicas y documentos adjuntos
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.notas_medicas (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  mascota_id  UUID NOT NULL REFERENCES core.mascotas(id) ON DELETE CASCADE,
  user_id     UUID REFERENCES core.users(id),
  nota        TEXT NOT NULL,
  destacada   BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_notas_mascota ON core.notas_medicas (mascota_id, created_at DESC);

CREATE TABLE IF NOT EXISTS core.documentos_medicos (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id     UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  mascota_id     UUID NOT NULL REFERENCES core.mascotas(id) ON DELETE CASCADE,
  consulta_id    UUID REFERENCES core.consultas(id) ON DELETE SET NULL,
  tipo           VARCHAR(60) NOT NULL DEFAULT 'otro',  -- receta | consentimiento | radiografia | resultado
  titulo         VARCHAR(255) NOT NULL,
  descripcion    TEXT,
  storage_key    TEXT NOT NULL,        -- objeto en MinIO
  mime_type      VARCHAR(120),
  tamanio_bytes  BIGINT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by     UUID
);
CREATE INDEX IF NOT EXISTS ix_documentos_mascota ON core.documentos_medicos (mascota_id, created_at DESC);

-- -----------------------------------------------------------------------------
-- órdenes de servicio — servicios ejecutados sobre el paciente (facturables)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.ordenes_servicio (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id     UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  codigo         VARCHAR(20),
  mascota_id     UUID NOT NULL REFERENCES core.mascotas(id) ON DELETE RESTRICT,
  cliente_id     UUID NOT NULL REFERENCES core.clientes(id) ON DELETE RESTRICT,
  servicio_id    UUID NOT NULL REFERENCES core.servicios(id),
  veterinario_id UUID REFERENCES core.users(id),
  cita_id        UUID REFERENCES core.citas(id) ON DELETE SET NULL,
  consulta_id    UUID REFERENCES core.consultas(id) ON DELETE SET NULL,
  cantidad       NUMERIC(10,2) NOT NULL DEFAULT 1,
  precio_unitario NUMERIC(12,2) NOT NULL DEFAULT 0,
  descuento      NUMERIC(12,2) NOT NULL DEFAULT 0,
  total          NUMERIC(12,2) NOT NULL DEFAULT 0,
  descripcion    TEXT,
  estado         core.estado_orden_servicio NOT NULL DEFAULT 'pendiente',
  facturado      BOOLEAN NOT NULL DEFAULT false,
  comprobante_id UUID,
  fecha          TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by     UUID
);
CREATE INDEX IF NOT EXISTS ix_ordenes_servicio_empresa ON core.ordenes_servicio (empresa_id, fecha DESC);
CREATE INDEX IF NOT EXISTS ix_ordenes_servicio_mascota ON core.ordenes_servicio (mascota_id, fecha DESC);
CREATE INDEX IF NOT EXISTS ix_ordenes_servicio_pend    ON core.ordenes_servicio (empresa_id, cliente_id)
  WHERE facturado = false AND estado <> 'anulado';

-- =============================================================================
-- INVENTARIO
-- =============================================================================

CREATE TABLE IF NOT EXISTS core.almacenes (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  codigo      VARCHAR(30) NOT NULL,
  nombre      VARCHAR(120) NOT NULL,
  ubicacion   VARCHAR(255),
  es_principal BOOLEAN NOT NULL DEFAULT false,
  estado      core.estado_generico NOT NULL DEFAULT 'activo',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_almacenes_codigo UNIQUE (empresa_id, codigo)
);

CREATE TABLE IF NOT EXISTS core.productos (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  codigo            VARCHAR(40) NOT NULL,
  codigo_barras     VARCHAR(60),
  nombre            VARCHAR(200) NOT NULL,
  descripcion       TEXT,
  tipo              core.tipo_producto NOT NULL DEFAULT 'insumo',
  categoria_id      UUID REFERENCES core.categorias(id) ON DELETE SET NULL,
  principio_activo  VARCHAR(200),
  laboratorio       VARCHAR(120),
  presentacion      VARCHAR(120),          -- "Frasco 100 ml", "Caja x 10 tabletas"
  unidad_medida     VARCHAR(20) NOT NULL DEFAULT 'UND',
  requiere_receta   BOOLEAN NOT NULL DEFAULT false,
  controlado        BOOLEAN NOT NULL DEFAULT false,   -- psicotrópico / estupefaciente
  refrigerado       BOOLEAN NOT NULL DEFAULT false,
  -- Precios
  precio_compra     NUMERIC(12,2) NOT NULL DEFAULT 0,
  precio_venta      NUMERIC(12,2) NOT NULL DEFAULT 0,
  margen_pct        NUMERIC(6,2),
  afecto_igv        BOOLEAN NOT NULL DEFAULT true,
  -- Control de stock (denormalizado; la verdad está en core.stock)
  stock_actual      NUMERIC(12,2) NOT NULL DEFAULT 0,
  stock_minimo      NUMERIC(12,2) NOT NULL DEFAULT 0,
  stock_maximo      NUMERIC(12,2),
  maneja_lotes      BOOLEAN NOT NULL DEFAULT false,
  estado            core.estado_generico NOT NULL DEFAULT 'activo',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at        TIMESTAMPTZ,
  created_by        UUID,
  updated_by        UUID,
  CONSTRAINT uq_productos_codigo UNIQUE (empresa_id, codigo)
);
CREATE INDEX IF NOT EXISTS ix_productos_empresa ON core.productos (empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_productos_nombre_trgm ON core.productos USING gin (nombre gin_trgm_ops);
CREATE INDEX IF NOT EXISTS ix_productos_critico ON core.productos (empresa_id)
  WHERE deleted_at IS NULL AND stock_actual <= stock_minimo;

CREATE TABLE IF NOT EXISTS core.lotes (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id     UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  producto_id    UUID NOT NULL REFERENCES core.productos(id) ON DELETE CASCADE,
  numero_lote    VARCHAR(60) NOT NULL,
  fecha_vencimiento DATE,
  cantidad       NUMERIC(12,2) NOT NULL DEFAULT 0,
  costo_unitario NUMERIC(12,2) NOT NULL DEFAULT 0,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_lotes UNIQUE (producto_id, numero_lote)
);
CREATE INDEX IF NOT EXISTS ix_lotes_vencimiento ON core.lotes (empresa_id, fecha_vencimiento)
  WHERE cantidad > 0;

CREATE TABLE IF NOT EXISTS core.stock (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id   UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  producto_id  UUID NOT NULL REFERENCES core.productos(id) ON DELETE CASCADE,
  almacen_id   UUID NOT NULL REFERENCES core.almacenes(id) ON DELETE CASCADE,
  cantidad     NUMERIC(12,2) NOT NULL DEFAULT 0,
  reservado    NUMERIC(12,2) NOT NULL DEFAULT 0,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_stock UNIQUE (producto_id, almacen_id)
);
CREATE INDEX IF NOT EXISTS ix_stock_empresa ON core.stock (empresa_id, almacen_id);

CREATE TABLE IF NOT EXISTS core.movimientos_inventario (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id     UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  producto_id    UUID NOT NULL REFERENCES core.productos(id) ON DELETE RESTRICT,
  almacen_id     UUID REFERENCES core.almacenes(id),
  almacen_destino_id UUID REFERENCES core.almacenes(id),
  lote_id        UUID REFERENCES core.lotes(id),
  tipo           core.tipo_movimiento_inventario NOT NULL,
  motivo         core.motivo_movimiento NOT NULL,
  cantidad       NUMERIC(12,2) NOT NULL,
  costo_unitario NUMERIC(12,2) NOT NULL DEFAULT 0,
  saldo_despues  NUMERIC(12,2),
  -- Referencias cruzadas según el origen del movimiento
  cliente_id     UUID REFERENCES core.clientes(id),
  proveedor_id   UUID,
  mascota_id     UUID REFERENCES core.mascotas(id),
  consulta_id    UUID REFERENCES core.consultas(id),
  comprobante_id UUID,
  orden_compra_id UUID,
  observaciones  TEXT,
  fecha          TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by     UUID,
  CONSTRAINT ck_movimientos_cantidad CHECK (cantidad > 0)
);
CREATE INDEX IF NOT EXISTS ix_movimientos_empresa  ON core.movimientos_inventario (empresa_id, fecha DESC);
CREATE INDEX IF NOT EXISTS ix_movimientos_producto ON core.movimientos_inventario (producto_id, fecha DESC);

-- Insumos consumidos en un acto clínico (descuentan stock y son facturables)
CREATE TABLE IF NOT EXISTS core.insumos_utilizados (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id     UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  producto_id    UUID NOT NULL REFERENCES core.productos(id) ON DELETE RESTRICT,
  mascota_id     UUID REFERENCES core.mascotas(id),
  consulta_id    UUID REFERENCES core.consultas(id) ON DELETE CASCADE,
  cirugia_id     UUID REFERENCES core.cirugias(id) ON DELETE CASCADE,
  hospitalizacion_id UUID REFERENCES core.hospitalizaciones(id) ON DELETE CASCADE,
  orden_servicio_id  UUID REFERENCES core.ordenes_servicio(id) ON DELETE SET NULL,
  cantidad       NUMERIC(12,2) NOT NULL,
  precio_unitario NUMERIC(12,2) NOT NULL DEFAULT 0,
  facturado      BOOLEAN NOT NULL DEFAULT false,
  fecha          TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by     UUID
);
CREATE INDEX IF NOT EXISTS ix_insumos_consulta ON core.insumos_utilizados (consulta_id);
CREATE INDEX IF NOT EXISTS ix_insumos_empresa  ON core.insumos_utilizados (empresa_id, fecha DESC);

-- =============================================================================
-- COMPRAS
-- =============================================================================

CREATE TABLE IF NOT EXISTS core.proveedores (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  codigo            VARCHAR(30),
  tipo_documento    core.tipo_documento_identidad NOT NULL DEFAULT 'RUC',
  numero_documento  VARCHAR(20) NOT NULL,
  razon_social      VARCHAR(255) NOT NULL,
  nombre_comercial  VARCHAR(255),
  categoria_id      UUID REFERENCES core.categorias(id) ON DELETE SET NULL,
  direccion         TEXT,
  telefono          VARCHAR(30),
  correo            VARCHAR(150),
  web               VARCHAR(200),
  dias_credito      INT NOT NULL DEFAULT 0,
  cuenta_bancaria   VARCHAR(60),
  banco             VARCHAR(80),
  estado            core.estado_proveedor NOT NULL DEFAULT 'activo',
  observaciones     TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at        TIMESTAMPTZ,
  created_by        UUID,
  updated_by        UUID,
  CONSTRAINT uq_proveedores_doc UNIQUE (empresa_id, numero_documento)
);
CREATE INDEX IF NOT EXISTS ix_proveedores_empresa ON core.proveedores (empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_proveedores_razon_trgm ON core.proveedores USING gin (razon_social gin_trgm_ops);

CREATE TABLE IF NOT EXISTS core.proveedor_contactos (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  proveedor_id UUID NOT NULL REFERENCES core.proveedores(id) ON DELETE CASCADE,
  nombres      VARCHAR(150) NOT NULL,
  cargo        VARCHAR(100),
  telefono     VARCHAR(30),
  correo       VARCHAR(150),
  es_principal BOOLEAN NOT NULL DEFAULT false,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_proveedor_contactos ON core.proveedor_contactos (proveedor_id);

CREATE TABLE IF NOT EXISTS core.ordenes_compra (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  numero            VARCHAR(30) NOT NULL,
  proveedor_id      UUID NOT NULL REFERENCES core.proveedores(id) ON DELETE RESTRICT,
  almacen_id        UUID REFERENCES core.almacenes(id),
  fecha_emision     DATE NOT NULL DEFAULT CURRENT_DATE,
  fecha_estimada    DATE,
  fecha_recepcion   DATE,
  moneda            core.moneda_codigo NOT NULL DEFAULT 'PEN',
  subtotal          NUMERIC(14,2) NOT NULL DEFAULT 0,
  igv               NUMERIC(14,2) NOT NULL DEFAULT 0,
  total             NUMERIC(14,2) NOT NULL DEFAULT 0,
  saldo_pendiente   NUMERIC(14,2) NOT NULL DEFAULT 0,
  estado            core.estado_orden_compra NOT NULL DEFAULT 'borrador',
  estado_pago       core.estado_pago NOT NULL DEFAULT 'pendiente',
  observaciones     TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at        TIMESTAMPTZ,
  created_by        UUID,
  updated_by        UUID,
  CONSTRAINT uq_ordenes_compra_numero UNIQUE (empresa_id, numero)
);
CREATE INDEX IF NOT EXISTS ix_ordenes_compra_empresa ON core.ordenes_compra (empresa_id, fecha_emision DESC)
  WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_ordenes_compra_proveedor ON core.ordenes_compra (proveedor_id);

CREATE TABLE IF NOT EXISTS core.orden_compra_items (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  orden_compra_id  UUID NOT NULL REFERENCES core.ordenes_compra(id) ON DELETE CASCADE,
  producto_id      UUID NOT NULL REFERENCES core.productos(id) ON DELETE RESTRICT,
  descripcion      VARCHAR(255),
  cantidad         NUMERIC(12,2) NOT NULL,
  cantidad_recibida NUMERIC(12,2) NOT NULL DEFAULT 0,
  precio_unitario  NUMERIC(12,2) NOT NULL,
  descuento        NUMERIC(12,2) NOT NULL DEFAULT 0,
  subtotal         NUMERIC(14,2) NOT NULL DEFAULT 0,
  numero_lote      VARCHAR(60),
  fecha_vencimiento DATE,
  orden            INT NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS ix_oc_items ON core.orden_compra_items (orden_compra_id);

CREATE TABLE IF NOT EXISTS core.pagos_proveedor (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  proveedor_id    UUID NOT NULL REFERENCES core.proveedores(id) ON DELETE RESTRICT,
  orden_compra_id UUID REFERENCES core.ordenes_compra(id) ON DELETE SET NULL,
  numero          VARCHAR(30),
  metodo          core.metodo_pago NOT NULL DEFAULT 'transferencia',
  monto           NUMERIC(14,2) NOT NULL,
  moneda          core.moneda_codigo NOT NULL DEFAULT 'PEN',
  referencia      VARCHAR(120),
  comprobante_url TEXT,
  fecha_pago      TIMESTAMPTZ NOT NULL DEFAULT now(),
  anulado_at      TIMESTAMPTZ,
  observaciones   TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by      UUID
);
CREATE INDEX IF NOT EXISTS ix_pagos_proveedor ON core.pagos_proveedor (empresa_id, fecha_pago DESC);

-- =============================================================================
-- FACTURACIÓN Y COBRANZA
-- =============================================================================

CREATE TABLE IF NOT EXISTS core.comprobantes (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id        UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  tipo              core.tipo_comprobante NOT NULL DEFAULT 'boleta',
  serie             VARCHAR(10) NOT NULL,
  numero            INT NOT NULL,
  numero_completo   VARCHAR(30) GENERATED ALWAYS AS (serie || '-' || lpad(numero::text, 8, '0')) STORED,
  cliente_id        UUID NOT NULL REFERENCES core.clientes(id) ON DELETE RESTRICT,
  mascota_id        UUID REFERENCES core.mascotas(id),
  cita_id           UUID REFERENCES core.citas(id) ON DELETE SET NULL,
  consulta_id       UUID REFERENCES core.consultas(id) ON DELETE SET NULL,
  caja_id           UUID,
  fecha_emision     TIMESTAMPTZ NOT NULL DEFAULT now(),
  fecha_vencimiento DATE,
  moneda            core.moneda_codigo NOT NULL DEFAULT 'PEN',
  tipo_cambio       NUMERIC(8,4),
  subtotal          NUMERIC(14,2) NOT NULL DEFAULT 0,
  descuento_global  NUMERIC(14,2) NOT NULL DEFAULT 0,
  igv               NUMERIC(14,2) NOT NULL DEFAULT 0,
  total             NUMERIC(14,2) NOT NULL DEFAULT 0,
  saldo_pendiente   NUMERIC(14,2) NOT NULL DEFAULT 0,
  estado            core.estado_comprobante NOT NULL DEFAULT 'borrador',
  estado_pago       core.estado_pago NOT NULL DEFAULT 'pendiente',
  -- SUNAT / PSE
  hash_cpe          VARCHAR(255),
  xml_url           TEXT,
  pdf_url           TEXT,
  cdr_url           TEXT,
  sunat_codigo      VARCHAR(20),
  sunat_mensaje     TEXT,
  -- Nota de crédito: documento que modifica
  documento_ref_id  UUID REFERENCES core.comprobantes(id),
  motivo_nota       TEXT,
  observaciones     TEXT,
  anulado_at        TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at        TIMESTAMPTZ,
  created_by        UUID,
  updated_by        UUID,
  CONSTRAINT uq_comprobantes_numero UNIQUE (empresa_id, tipo, serie, numero)
);
CREATE INDEX IF NOT EXISTS ix_comprobantes_empresa ON core.comprobantes (empresa_id, fecha_emision DESC)
  WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_comprobantes_cliente ON core.comprobantes (cliente_id, fecha_emision DESC);
CREATE INDEX IF NOT EXISTS ix_comprobantes_pend    ON core.comprobantes (empresa_id, estado_pago)
  WHERE deleted_at IS NULL AND estado_pago <> 'pagado';

CREATE TABLE IF NOT EXISTS core.comprobante_items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  comprobante_id  UUID NOT NULL REFERENCES core.comprobantes(id) ON DELETE CASCADE,
  tipo_item       core.tipo_item_comprobante NOT NULL DEFAULT 'servicio',
  servicio_id     UUID REFERENCES core.servicios(id),
  producto_id     UUID REFERENCES core.productos(id),
  orden_servicio_id UUID REFERENCES core.ordenes_servicio(id),
  codigo          VARCHAR(40),
  descripcion     VARCHAR(500) NOT NULL,
  cantidad        NUMERIC(12,2) NOT NULL DEFAULT 1,
  precio_unitario NUMERIC(12,4) NOT NULL DEFAULT 0,
  descuento       NUMERIC(12,2) NOT NULL DEFAULT 0,
  afecto_igv      BOOLEAN NOT NULL DEFAULT true,
  subtotal        NUMERIC(14,2) NOT NULL DEFAULT 0,
  igv             NUMERIC(14,2) NOT NULL DEFAULT 0,
  total           NUMERIC(14,2) NOT NULL DEFAULT 0,
  orden           INT NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS ix_comprobante_items ON core.comprobante_items (comprobante_id);

CREATE TABLE IF NOT EXISTS core.pagos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id      UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  cliente_id      UUID NOT NULL REFERENCES core.clientes(id) ON DELETE RESTRICT,
  caja_id         UUID,
  numero          VARCHAR(30),
  metodo          core.metodo_pago NOT NULL DEFAULT 'efectivo',
  monto           NUMERIC(14,2) NOT NULL,
  moneda          core.moneda_codigo NOT NULL DEFAULT 'PEN',
  referencia      VARCHAR(120),        -- nº operación / voucher
  fecha_pago      TIMESTAMPTZ NOT NULL DEFAULT now(),
  anulado_at      TIMESTAMPTZ,
  observaciones   TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by      UUID,
  CONSTRAINT ck_pagos_monto CHECK (monto > 0)
);
CREATE INDEX IF NOT EXISTS ix_pagos_empresa ON core.pagos (empresa_id, fecha_pago DESC);
CREATE INDEX IF NOT EXISTS ix_pagos_cliente ON core.pagos (cliente_id, fecha_pago DESC);

-- Aplicación de un pago a uno o varios comprobantes (permite pagos a cuenta)
CREATE TABLE IF NOT EXISTS core.pago_aplicaciones (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pago_id        UUID NOT NULL REFERENCES core.pagos(id) ON DELETE CASCADE,
  comprobante_id UUID NOT NULL REFERENCES core.comprobantes(id) ON DELETE CASCADE,
  monto_aplicado NUMERIC(14,2) NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ck_aplicacion_monto CHECK (monto_aplicado > 0)
);
CREATE INDEX IF NOT EXISTS ix_pago_aplicaciones_comp ON core.pago_aplicaciones (comprobante_id);
CREATE INDEX IF NOT EXISTS ix_pago_aplicaciones_pago ON core.pago_aplicaciones (pago_id);

-- =============================================================================
-- CAJA
-- =============================================================================

CREATE TABLE IF NOT EXISTS core.cajas (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id       UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  numero           VARCHAR(30),
  user_apertura_id UUID NOT NULL REFERENCES core.users(id),
  user_cierre_id   UUID REFERENCES core.users(id),
  fecha_apertura   TIMESTAMPTZ NOT NULL DEFAULT now(),
  fecha_cierre     TIMESTAMPTZ,
  monto_apertura   NUMERIC(14,2) NOT NULL DEFAULT 0,
  -- Totales calculados al cerrar
  total_ingresos   NUMERIC(14,2) NOT NULL DEFAULT 0,
  total_egresos    NUMERIC(14,2) NOT NULL DEFAULT 0,
  total_efectivo   NUMERIC(14,2) NOT NULL DEFAULT 0,
  total_tarjeta    NUMERIC(14,2) NOT NULL DEFAULT 0,
  total_digital    NUMERIC(14,2) NOT NULL DEFAULT 0,
  monto_esperado   NUMERIC(14,2) NOT NULL DEFAULT 0,
  monto_contado    NUMERIC(14,2),
  diferencia       NUMERIC(14,2),
  estado           core.estado_caja NOT NULL DEFAULT 'abierta',
  observaciones    TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_cajas_empresa ON core.cajas (empresa_id, fecha_apertura DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_caja_abierta_por_user
  ON core.cajas (empresa_id, user_apertura_id) WHERE estado = 'abierta';

CREATE TABLE IF NOT EXISTS core.movimientos_caja (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id  UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  caja_id     UUID NOT NULL REFERENCES core.cajas(id) ON DELETE CASCADE,
  tipo        core.tipo_movimiento_caja NOT NULL,
  metodo      core.metodo_pago NOT NULL DEFAULT 'efectivo',
  concepto    VARCHAR(255) NOT NULL,
  monto       NUMERIC(14,2) NOT NULL,
  pago_id     UUID REFERENCES core.pagos(id) ON DELETE SET NULL,
  comprobante_id UUID REFERENCES core.comprobantes(id) ON DELETE SET NULL,
  fecha       TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by  UUID,
  CONSTRAINT ck_mov_caja_monto CHECK (monto > 0)
);
CREATE INDEX IF NOT EXISTS ix_mov_caja ON core.movimientos_caja (caja_id, fecha);

-- =============================================================================
-- PERSONAL CLÍNICO (RRHH)
-- =============================================================================

CREATE TABLE IF NOT EXISTS core.contratos_personal (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id   UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
  tipo         core.tipo_contrato_empleado NOT NULL DEFAULT 'plazo_fijo',
  cargo        VARCHAR(120),
  fecha_inicio DATE NOT NULL,
  fecha_fin    DATE,
  salario      NUMERIC(12,2),
  moneda       core.moneda_codigo NOT NULL DEFAULT 'PEN',
  documento_url TEXT,
  vigente      BOOLEAN NOT NULL DEFAULT true,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_contratos_personal ON core.contratos_personal (empresa_id, user_id);

CREATE TABLE IF NOT EXISTS core.disponibilidad (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id   UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
  fecha        DATE NOT NULL,
  hora_inicio  TIME NOT NULL,
  hora_fin     TIME NOT NULL,
  tipo         core.tipo_disponibilidad NOT NULL DEFAULT 'laboral',
  consultorio_id UUID REFERENCES core.consultorios(id),
  nota         TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ck_disponibilidad_rango CHECK (hora_fin > hora_inicio)
);
CREATE INDEX IF NOT EXISTS ix_disponibilidad ON core.disponibilidad (empresa_id, fecha, user_id);

CREATE TABLE IF NOT EXISTS core.asistencia (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id   UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
  fecha        DATE NOT NULL,
  hora_entrada TIME,
  hora_salida  TIME,
  horas_trabajadas NUMERIC(5,2),
  estado       core.estado_asistencia NOT NULL DEFAULT 'puntual',
  observaciones TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_asistencia UNIQUE (user_id, fecha)
);
CREATE INDEX IF NOT EXISTS ix_asistencia_empresa ON core.asistencia (empresa_id, fecha DESC);

CREATE TABLE IF NOT EXISTS core.permisos_laborales (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id    UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
  tipo          core.tipo_permiso_laboral NOT NULL DEFAULT 'personal',
  fecha_inicio  DATE NOT NULL,
  fecha_fin     DATE NOT NULL,
  hora_inicio   TIME,
  hora_fin      TIME,
  motivo        TEXT,
  estado        core.estado_solicitud NOT NULL DEFAULT 'pendiente',
  aprobado_por  UUID REFERENCES core.users(id),
  aprobado_at   TIMESTAMPTZ,
  comentario_aprobacion TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ck_permisos_rango CHECK (fecha_fin >= fecha_inicio)
);
CREATE INDEX IF NOT EXISTS ix_permisos_laborales ON core.permisos_laborales (empresa_id, estado, fecha_inicio);

CREATE TABLE IF NOT EXISTS core.evaluaciones_personal (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id       UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  user_id          UUID NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
  evaluador_id     UUID REFERENCES core.users(id),
  periodo          VARCHAR(20) NOT NULL,     -- "2026-S1"
  fecha            DATE NOT NULL DEFAULT CURRENT_DATE,
  puntualidad      INT CHECK (puntualidad BETWEEN 1 AND 5),
  eficiencia       INT CHECK (eficiencia BETWEEN 1 AND 5),
  calidad_atencion INT CHECK (calidad_atencion BETWEEN 1 AND 5),
  trabajo_equipo   INT CHECK (trabajo_equipo BETWEEN 1 AND 5),
  promedio         NUMERIC(3,2),
  observaciones    TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_evaluaciones ON core.evaluaciones_personal (empresa_id, user_id, fecha DESC);

-- =============================================================================
-- CRM LIGERO: seguimiento al propietario
-- =============================================================================

CREATE TABLE IF NOT EXISTS core.comunicaciones (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id   UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  cliente_id   UUID NOT NULL REFERENCES core.clientes(id) ON DELETE CASCADE,
  mascota_id   UUID REFERENCES core.mascotas(id) ON DELETE SET NULL,
  user_id      UUID REFERENCES core.users(id),
  tipo         core.tipo_comunicacion NOT NULL DEFAULT 'llamada',
  asunto       VARCHAR(255),
  mensaje      TEXT NOT NULL,
  requiere_seguimiento BOOLEAN NOT NULL DEFAULT false,
  fecha_seguimiento DATE,
  fecha        TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by   UUID
);
CREATE INDEX IF NOT EXISTS ix_comunicaciones_cliente ON core.comunicaciones (cliente_id, fecha DESC);
CREATE INDEX IF NOT EXISTS ix_comunicaciones_seguim  ON core.comunicaciones (empresa_id, fecha_seguimiento)
  WHERE requiere_seguimiento = true;

-- Recordatorios automáticos (refuerzo de vacuna, control post-operatorio…)
CREATE TABLE IF NOT EXISTS core.recordatorios (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id   UUID NOT NULL REFERENCES core.empresas(id) ON DELETE CASCADE,
  cliente_id   UUID NOT NULL REFERENCES core.clientes(id) ON DELETE CASCADE,
  mascota_id   UUID REFERENCES core.mascotas(id) ON DELETE CASCADE,
  tipo         VARCHAR(40) NOT NULL,   -- vacuna | desparasitacion | control | cita | cumpleanios
  titulo       VARCHAR(200) NOT NULL,
  mensaje      TEXT,
  fecha_objetivo DATE NOT NULL,
  canal        core.canal_notificacion NOT NULL DEFAULT 'whatsapp',
  enviado_at   TIMESTAMPTZ,
  completado   BOOLEAN NOT NULL DEFAULT false,
  entidad_ref  VARCHAR(60),
  entidad_id   UUID,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_recordatorios_pend ON core.recordatorios (empresa_id, fecha_objetivo)
  WHERE completado = false;

-- =============================================================================
-- FKs diferidas (tablas declaradas después de ser referenciadas)
-- =============================================================================
DO $$ BEGIN
  ALTER TABLE core.servicios
    ADD CONSTRAINT fk_servicios_producto FOREIGN KEY (producto_id) REFERENCES core.productos(id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE core.vacunas
    ADD CONSTRAINT fk_vacunas_producto FOREIGN KEY (producto_id) REFERENCES core.productos(id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE core.tratamientos
    ADD CONSTRAINT fk_tratamientos_producto FOREIGN KEY (producto_id) REFERENCES core.productos(id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE core.desparasitaciones
    ADD CONSTRAINT fk_desparasitaciones_producto FOREIGN KEY (producto_id) REFERENCES core.productos(id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE core.ordenes_servicio
    ADD CONSTRAINT fk_ordenes_servicio_comprobante FOREIGN KEY (comprobante_id) REFERENCES core.comprobantes(id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE core.movimientos_inventario
    ADD CONSTRAINT fk_movimientos_proveedor FOREIGN KEY (proveedor_id) REFERENCES core.proveedores(id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE core.movimientos_inventario
    ADD CONSTRAINT fk_movimientos_comprobante FOREIGN KEY (comprobante_id) REFERENCES core.comprobantes(id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE core.movimientos_inventario
    ADD CONSTRAINT fk_movimientos_oc FOREIGN KEY (orden_compra_id) REFERENCES core.ordenes_compra(id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE core.comprobantes
    ADD CONSTRAINT fk_comprobantes_caja FOREIGN KEY (caja_id) REFERENCES core.cajas(id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE core.pagos
    ADD CONSTRAINT fk_pagos_caja FOREIGN KEY (caja_id) REFERENCES core.cajas(id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
