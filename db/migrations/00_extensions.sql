-- =============================================================================
-- 00_extensions.sql
-- ERP Veterinario - Extensiones PostgreSQL requeridas
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid(), crypt(), gen_salt()
CREATE EXTENSION IF NOT EXISTS pg_trgm;    -- búsqueda fuzzy (similarity, ILIKE acelerado)
CREATE EXTENSION IF NOT EXISTS unaccent;   -- normalización de acentos (buscar "cirugia" y hallar "cirugía")
CREATE EXTENSION IF NOT EXISTS btree_gin;  -- índices compuestos GIN sobre tipos comunes
