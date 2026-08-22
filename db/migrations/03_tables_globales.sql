-- =============================================================================
-- 03_tables_globales.sql
-- Tablas SIN empresa_id: las únicas que comparten todas las empresas.
--
-- Criterio: aquí solo va lo que NO es dato de negocio de una empresa —
--   · la identidad del sistema (empresas, roles, permisos, usuarios)
--   · taxonomía de referencia (especies, razas, especializaciones), que solo
--     el super admin edita: es un catálogo del operador del ERP, no de una
--     empresa cliente
--   · infraestructura transversal (auditoría, correlativos, sesiones)
--
-- TODO lo demás —incluidos propietarios y pacientes— lleva empresa_id y vive
-- en 04_tables_per_empresa.sql. Cada empresa es un negocio independiente: su
-- cartera de clientes no es visible para las demás.
-- =============================================================================

SET search_path = core, public;

-- -----------------------------------------------------------------------------
-- empresas — cada fila es un negocio independiente
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
  -- Operación de la empresa
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

COMMENT ON TABLE core.empresas IS 'Empresas del ERP. Cada una es un negocio independiente; el multi-tenancy se resuelve por empresa_id.';

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
-- especies y razas (catálogo maestro)
-- -----------------------------------------------------------------------------
-- Taxonomía compartida por todas las empresas. Solo el super admin la edita:
-- es un catálogo de referencia del operador del ERP, no dato de negocio.
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
-- correlativos — numeración por empresa/tipo/serie
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
