-- =============================================================================
-- 01_schemas.sql
-- Schemas del ERP Veterinario. El backend SOLO accede a `app`.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS core;       -- tablas, ENUMs, triggers
CREATE SCHEMA IF NOT EXISTS app;        -- SPs y FNs públicas (única superficie del backend)
CREATE SCHEMA IF NOT EXISTS internal;   -- helpers privados (validaciones, cálculos, auditoría)
CREATE SCHEMA IF NOT EXISTS audit;      -- tablas de auditoría adicionales si se requieren separadas

COMMENT ON SCHEMA core     IS 'Tablas, ENUMs y triggers. NUNCA accedido directamente por el backend.';
COMMENT ON SCHEMA app      IS 'Stored procedures y functions públicas. Única superficie del backend.';
COMMENT ON SCHEMA internal IS 'Helpers privados reutilizados por SPs/FNs públicas.';
COMMENT ON SCHEMA audit    IS 'Auditoría dedicada (core.audit_log vive en core para coherencia de FKs).';
