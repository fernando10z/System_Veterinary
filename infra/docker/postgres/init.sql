-- =============================================================================
-- init.sql — se ejecuta UNA SOLA VEZ en el primer arranque del contenedor
-- (cuando /var/lib/postgresql/data está vacío).
--
-- Contrato: aquí NO van las migraciones. La BD la crea Postgres vía POSTGRES_DB.
-- El schema completo (extensions, schemas, tablas, SPs, seeds, grants) se
-- aplica desde fuera con:
--
--   bash db/scripts/apply-migrations.sh
--
-- Una única fuente de verdad para el schema evita que /docker-entrypoint-initdb.d
-- y db/migrations/ se desincronicen.
-- =============================================================================

SELECT 'postgres vet dev container listo' AS status;
