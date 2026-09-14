-- =============================================================================
-- 90_grants.sql — Rol de aplicación y permisos de acceso
--
-- El backend se conecta con `vet_app_user`, que SOLO puede EXECUTE sobre app.*.
-- No tiene acceso directo a core: si un SP no expone algo, el backend no lo ve.
-- =============================================================================

-- El rol se crea SIN contraseña utilizable: una aleatoria que nadie conoce.
-- Así, si alguien despliega y olvida el paso del deploy, el rol no queda con una
-- contraseña adivinable — simplemente no se puede usar hasta fijarla:
--   ALTER ROLE vet_app_user WITH PASSWORD '<secreto del gestor de credenciales>';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'vet_app_user') THEN
    EXECUTE format(
      'CREATE ROLE vet_app_user LOGIN PASSWORD %L',
      encode(gen_random_bytes(32), 'base64'));
  END IF;
END $$;

-- El nombre de la BD varía por entorno (vet_demo, vet_prod…): se resuelve en runtime.
DO $$
BEGIN
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO vet_app_user', current_database());
END $$;

GRANT USAGE ON SCHEMA app TO vet_app_user;

-- Las funciones son SECURITY DEFINER: corren con los privilegios del owner y
-- son las únicas que tocan core/internal.
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app TO vet_app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT EXECUTE ON FUNCTIONS TO vet_app_user;

-- Cerrar explícitamente todo lo demás
REVOKE ALL ON SCHEMA core     FROM vet_app_user;
REVOKE ALL ON SCHEMA internal FROM vet_app_user;
REVOKE ALL ON SCHEMA audit    FROM vet_app_user;
REVOKE ALL ON ALL TABLES IN SCHEMA core FROM vet_app_user;

-- Los helpers de `internal` solo los llaman los SPs, nunca el backend.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA internal FROM PUBLIC;

COMMENT ON SCHEMA app IS
  'Única superficie del backend. vet_app_user solo tiene EXECUTE aquí.';
