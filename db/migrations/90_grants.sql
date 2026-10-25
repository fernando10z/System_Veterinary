-- =============================================================================
-- 90_grants.sql — Rol de aplicación y permisos de acceso
--
-- El backend se conecta con `erp_veterinary_user`, que SOLO puede EXECUTE sobre app.*.
-- No tiene acceso directo a core: si un SP no expone algo, el backend no lo ve.
-- =============================================================================

-- El rol se crea SIN contraseña utilizable: una aleatoria que nadie conoce.
-- Así, si alguien despliega y olvida el paso del deploy, el rol no queda con una
-- contraseña adivinable — simplemente no se puede usar hasta fijarla.
-- La fija `apply-migrations.sh` cuando recibe VET_APP_PASSWORD (el compose de
-- producción lo hace en cada arranque); a mano:
--   ALTER ROLE erp_veterinary_user WITH PASSWORD '<secreto del gestor de credenciales>';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'erp_veterinary_user') THEN
    EXECUTE format(
      'CREATE ROLE erp_veterinary_user LOGIN PASSWORD %L',
      encode(gen_random_bytes(32), 'base64'));
  END IF;
END $$;

-- El nombre de la BD varía por entorno (vet_demo, vet_prod…): se resuelve en runtime.
DO $$
BEGIN
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO erp_veterinary_user', current_database());
END $$;

GRANT USAGE ON SCHEMA app TO erp_veterinary_user;

-- Postgres concede EXECUTE a PUBLIC sobre toda función nueva. Con eso, cualquier
-- rol que llegue a conectarse —uno de solo lectura para reportes, el de un
-- backup, uno creado a mano para depurar— podía llamar a los SPs de app.* y,
-- como son SECURITY DEFINER, actuar con los privilegios del owner. EXECUTE se
-- concede solo a quien se nombra.
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC;
-- También para las que se creen después. Tiene que ser el default global (sin
-- IN SCHEMA): los defaults por schema solo pueden AÑADIR privilegios a los
-- globales, no quitarlos.
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- Las funciones son SECURITY DEFINER: corren con los privilegios del owner y
-- son las únicas que tocan core/internal.
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app TO erp_veterinary_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT EXECUTE ON FUNCTIONS TO erp_veterinary_user;

-- Cerrar explícitamente todo lo demás
REVOKE ALL ON SCHEMA core     FROM erp_veterinary_user;
REVOKE ALL ON SCHEMA internal FROM erp_veterinary_user;
REVOKE ALL ON SCHEMA audit    FROM erp_veterinary_user;
REVOKE ALL ON ALL TABLES IN SCHEMA core FROM erp_veterinary_user;

-- Los helpers de `internal` solo los llaman los SPs, nunca el backend.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA internal FROM PUBLIC;

COMMENT ON SCHEMA app IS
  'Única superficie del backend. erp_veterinary_user solo tiene EXECUTE aquí.';
