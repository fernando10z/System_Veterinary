-- =============================================================================
-- 03_tables_client_global.sql
-- Tablas Client-Global: sin empresa_id. Compartidas por TODAS las sedes de la
-- cadena veterinaria (identidad, cartera de propietarios y sus mascotas,
-- catálogos maestros de especies/razas).
--
-- Criterio: un propietario y su mascota son los mismos aunque se atiendan en
-- otra sede. La ATENCIÓN (cita, consulta, factura) sí es por sede.
-- =============================================================================

SET search_path = core, public;

-- -----------------------------------------------------------------------------
-- empresas — cada fila es una sede/clínica de la cadena
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.empresas (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ruc                     VARCHAR(11) NOT NULL UNIQUE,
  razon_social            VARCHAR(255) NOT NULL,
  nombre_comercial        VARCHAR(255),
  direccion_fiscal        TEXT,
  ubigeo                  VARCHAR(6),
  telefono                VARCHAR(30),
  correo                  VARCHAR(150),
  logo_url                TEXT,
  -- Facturación electrónica (PSE/OSE)
  pse_endpoint            TEXT,
  pse_usuario             VARCHAR(150),
  pse_password_enc        TEXT,
  serie_factura_default   VARCHAR(10),
  serie_boleta_default    VARCHAR(10),
  serie_nota_venta_default VARCHAR(10),
  igv_tasa                NUMERIC(5,4) NOT NULL DEFAULT 0.1800,
  moneda_default          core.moneda_codigo NOT NULL DEFAULT 'PEN',
  -- Operación de la sede
  aforo_consultorios      INT NOT NULL DEFAULT 1,
  duracion_cita_min       INT NOT NULL DEFAULT 30,
  estado                  core.estado_empresa NOT NULL DEFAULT 'activa',
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at              TIMESTAMPTZ,
  created_by              UUID,
  updated_by              UUID
);
CREATE INDEX IF NOT EXISTS ix_empresas_estado     ON core.empresas (estado) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_empresas_razon_trgm ON core.empresas USING gin (razon_social gin_trgm_ops);

COMMENT ON TABLE core.empresas IS 'Sedes / clínicas veterinarias. El multi-tenancy del ERP se resuelve por empresa_id.';

-- -----------------------------------------------------------------------------
-- roles / permisos
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.roles (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo      VARCHAR(50) NOT NULL UNIQUE,
  nombre      VARCHAR(100) NOT NULL,
  descripcion TEXT,
  scope       core.scope_rol NOT NULL DEFAULT 'empresa',
  is_sistema  BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS core.permisos (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo      VARCHAR(100) NOT NULL UNIQUE,   -- formato modulo:accion
  modulo      VARCHAR(50)  NOT NULL,
  accion      VARCHAR(50)  NOT NULL,
  descripcion TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_permisos_modulo ON core.permisos (modulo);

CREATE TABLE IF NOT EXISTS core.rol_permisos (
  rol_id     UUID NOT NULL REFERENCES core.roles(id)    ON DELETE CASCADE,
  permiso_id UUID NOT NULL REFERENCES core.permisos(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (rol_id, permiso_id)
);
CREATE INDEX IF NOT EXISTS ix_rol_permisos_permiso ON core.rol_permisos (permiso_id);

-- -----------------------------------------------------------------------------
-- especializaciones veterinarias (catálogo maestro)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.especializaciones (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo      VARCHAR(50) NOT NULL UNIQUE,
  nombre      VARCHAR(150) NOT NULL,
  descripcion TEXT,
  estado      core.estado_generico NOT NULL DEFAULT 'activo',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- users — personal del sistema (staff clínico y administrativo)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.users (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo                 VARCHAR(20),
  email                  VARCHAR(150) NOT NULL UNIQUE,
  password_hash          TEXT NOT NULL,
  nombres                VARCHAR(150) NOT NULL,
  apellido_paterno       VARCHAR(100) NOT NULL,
  apellido_materno       VARCHAR(100),
  tipo_documento         core.tipo_documento_identidad NOT NULL DEFAULT 'DNI',
  numero_documento       VARCHAR(20) NOT NULL,
  telefono               VARCHAR(30),
  foto_url               TEXT,
  empresa_id             UUID REFERENCES core.empresas(id),
  is_super_admin         BOOLEAN NOT NULL DEFAULT false,
  rol_id                 UUID REFERENCES core.roles(id),
  -- Datos propios del profesional veterinario (NULL para staff no clínico)
  es_veterinario         BOOLEAN NOT NULL DEFAULT false,
  colegiatura            VARCHAR(30),
  especializacion_id     UUID REFERENCES core.especializaciones(id),
  color_agenda           VARCHAR(7),          -- color del profesional en el calendario
  -- Estado y seguridad
  estado                 core.estado_user NOT NULL DEFAULT 'activo',
  ultimo_login_at        TIMESTAMPTZ,
  intentos_fallidos      INT NOT NULL DEFAULT 0,
  bloqueado_hasta        TIMESTAMPTZ,
  password_reset_token   VARCHAR(255),
  password_reset_expires TIMESTAMPTZ,
  must_change_password   BOOLEAN NOT NULL DEFAULT false,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at             TIMESTAMPTZ,
  created_by             UUID,
  updated_by             UUID,
  CONSTRAINT uq_users_documento UNIQUE (tipo_documento, numero_documento),
  CONSTRAINT ck_users_super_admin_empresa
    CHECK (NOT (is_super_admin = true AND empresa_id IS NOT NULL)),
  -- Un veterinario necesita colegiatura registrada para firmar historia clínica
  CONSTRAINT ck_users_veterinario_colegiatura
    CHECK (es_veterinario = false OR colegiatura IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS ix_users_empresa      ON core.users (empresa_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_users_rol          ON core.users (rol_id);
CREATE INDEX IF NOT EXISTS ix_users_estado       ON core.users (estado) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_users_email_lower  ON core.users (lower(email));
CREATE INDEX IF NOT EXISTS ix_users_veterinario  ON core.users (es_veterinario) WHERE deleted_at IS NULL AND es_veterinario = true;

-- -----------------------------------------------------------------------------
-- clientes — propietarios de mascotas (cartera global de la cadena)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.clientes (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
  -- Sede donde se registró (informativo: el cliente es visible en toda la cadena)
  empresa_origen_id      UUID REFERENCES core.empresas(id),
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
  CONSTRAINT uq_clientes_documento UNIQUE (tipo_documento, numero_documento)
);
CREATE INDEX IF NOT EXISTS ix_clientes_estado     ON core.clientes (estado) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_clientes_nombre_trgm ON core.clientes USING gin (nombres gin_trgm_ops);
CREATE INDEX IF NOT EXISTS ix_clientes_doc_trgm   ON core.clientes USING gin (numero_documento gin_trgm_ops);
CREATE INDEX IF NOT EXISTS ix_clientes_telefono   ON core.clientes (telefono);

COMMENT ON TABLE core.clientes IS 'Propietarios de mascotas. Cartera compartida entre sedes.';

-- -----------------------------------------------------------------------------
-- especies y razas (catálogo maestro)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.especies (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo       VARCHAR(30) NOT NULL UNIQUE,
  nombre       VARCHAR(80) NOT NULL,
  nombre_cria  VARCHAR(80),            -- "cachorro", "gatito"…
  icono        VARCHAR(40),            -- nombre del icono lucide para la UI
  estado       core.estado_generico NOT NULL DEFAULT 'activo',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS core.razas (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  especie_id        UUID NOT NULL REFERENCES core.especies(id) ON DELETE CASCADE,
  nombre            VARCHAR(120) NOT NULL,
  tamanio_referencia core.tamanio_mascota,
  peso_min_kg       NUMERIC(6,2),
  peso_max_kg       NUMERIC(6,2),
  esperanza_vida    INT,               -- años, para alertas geriátricas
  estado            core.estado_generico NOT NULL DEFAULT 'activo',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_razas_especie_nombre UNIQUE (especie_id, nombre)
);
CREATE INDEX IF NOT EXISTS ix_razas_especie ON core.razas (especie_id);

-- -----------------------------------------------------------------------------
-- mascotas — los pacientes
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.mascotas (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo              VARCHAR(20),               -- historia clínica: HC-000001
  cliente_id          UUID NOT NULL REFERENCES core.clientes(id) ON DELETE RESTRICT,
  nombre              VARCHAR(100) NOT NULL,
  especie_id          UUID NOT NULL REFERENCES core.especies(id),
  raza_id             UUID REFERENCES core.razas(id),
  raza_libre          VARCHAR(120),              -- cuando la raza no está en catálogo (mestizo)
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
  empresa_origen_id   UUID REFERENCES core.empresas(id),
  estado              core.estado_mascota NOT NULL DEFAULT 'activo',
  fecha_fallecimiento DATE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at          TIMESTAMPTZ,
  created_by          UUID,
  updated_by          UUID,
  CONSTRAINT ck_mascotas_microchip_unico CHECK (microchip IS NULL OR length(microchip) >= 8)
);
CREATE INDEX IF NOT EXISTS ix_mascotas_cliente  ON core.mascotas (cliente_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_mascotas_especie  ON core.mascotas (especie_id);
CREATE INDEX IF NOT EXISTS ix_mascotas_estado   ON core.mascotas (estado) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_mascotas_nombre_trgm ON core.mascotas USING gin (nombre gin_trgm_ops);
CREATE UNIQUE INDEX IF NOT EXISTS uq_mascotas_microchip
  ON core.mascotas (microchip) WHERE microchip IS NOT NULL AND deleted_at IS NULL;

COMMENT ON TABLE core.mascotas IS 'Pacientes. Una mascota pertenece a un propietario y su historia clínica es única en toda la cadena.';

-- -----------------------------------------------------------------------------
-- mascotas_extraviadas — reporte de mascota perdida / encontrada
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.mascotas_extraviadas (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
CREATE INDEX IF NOT EXISTS ix_mascotas_extraviadas_mascota ON core.mascotas_extraviadas (mascota_id);

-- -----------------------------------------------------------------------------
-- audit_log — bitácora transversal
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.audit_log (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID,
  empresa_id     UUID,
  accion         VARCHAR(60)  NOT NULL,
  entidad        VARCHAR(80)  NOT NULL,
  entidad_id     UUID,
  datos_antes    JSONB,
  datos_despues  JSONB,
  diff           JSONB,
  ip             VARCHAR(45),
  user_agent     TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_audit_log_entidad ON core.audit_log (entidad, entidad_id);
CREATE INDEX IF NOT EXISTS ix_audit_log_user    ON core.audit_log (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_audit_log_empresa ON core.audit_log (empresa_id, created_at DESC);

-- -----------------------------------------------------------------------------
-- correlativos — numeración por sede/tipo/serie
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.correlativos (
  empresa_id     UUID NOT NULL,
  tipo_documento VARCHAR(40) NOT NULL,
  serie          VARCHAR(10) NOT NULL,
  ultimo_numero  INT NOT NULL DEFAULT 0,
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (empresa_id, tipo_documento, serie)
);

-- -----------------------------------------------------------------------------
-- refresh_tokens revocados / sesiones (respaldo de Redis)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.sesiones (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
  jti         VARCHAR(64) NOT NULL UNIQUE,
  ip          VARCHAR(45),
  user_agent  TEXT,
  expira_at   TIMESTAMPTZ NOT NULL,
  revocado_at TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_sesiones_user ON core.sesiones (user_id) WHERE revocado_at IS NULL;

-- -----------------------------------------------------------------------------
-- notificaciones — bandeja interna del staff
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.notificaciones (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID REFERENCES core.users(id) ON DELETE CASCADE,
  empresa_id  UUID REFERENCES core.empresas(id),
  canal       core.canal_notificacion NOT NULL DEFAULT 'sistema',
  titulo      VARCHAR(200) NOT NULL,
  cuerpo      TEXT,
  url         TEXT,
  entidad     VARCHAR(80),
  entidad_id  UUID,
  leida_at    TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_notificaciones_user ON core.notificaciones (user_id, created_at DESC)
  WHERE leida_at IS NULL;
