-- =============================================================================
-- 11_normalizacion.sql
-- Normalización de los datos que se guardan.
--
-- Por qué en la base y no en el backend: es la única capa por la que pasan
-- TODAS las escrituras. Si la normalización viviera en los SPs habría que
-- acordarse en cada uno, y un olvido guarda "44 556 677" junto a "44556677",
-- que ya no se detectan como duplicados ni se encuentran al buscar.
--
-- Regla: normalizar la FORMA, nunca el CONTENIDO. Se quitan espacios y se
-- unifican mayúsculas; no se corrigen nombres ni se inventan datos.
-- =============================================================================

SET search_path = internal, core, public;

-- -----------------------------------------------------------------------------
-- internal.normalizar_texto — recorta y colapsa espacios internos
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.normalizar_texto(p_valor TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF(regexp_replace(btrim(coalesce(p_valor, '')), '\s+', ' ', 'g'), '');
$$;

-- -----------------------------------------------------------------------------
-- internal.normalizar_nombre
-- Capitaliza respetando las partículas del castellano: "María de los Ángeles",
-- no "María De Los Ángeles". La partícula sí se capitaliza si abre el nombre.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.normalizar_nombre(p_valor TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_particulas TEXT[] := ARRAY['de','del','la','las','los','y','e','da','do','van','von','di'];
  v_palabras   TEXT[];
  v_salida     TEXT[] := '{}';
  v_p          TEXT;
  i            INT := 0;
BEGIN
  IF internal.normalizar_texto(p_valor) IS NULL THEN RETURN NULL; END IF;

  v_palabras := regexp_split_to_array(lower(internal.normalizar_texto(p_valor)), ' ');
  FOREACH v_p IN ARRAY v_palabras LOOP
    i := i + 1;
    IF i > 1 AND v_p = ANY (v_particulas) THEN
      v_salida := v_salida || v_p;
    ELSE
      -- initcap por palabra: respeta guiones ("Ana-María") y apóstrofes.
      v_salida := v_salida || initcap(v_p);
    END IF;
  END LOOP;

  RETURN array_to_string(v_salida, ' ');
END;
$$;

-- -----------------------------------------------------------------------------
-- internal.normalizar_documento — sin espacios, guiones ni puntos; en mayúsculas
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.normalizar_documento(p_valor TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF(upper(regexp_replace(coalesce(p_valor, ''), '[^A-Za-z0-9]', '', 'g')), '');
$$;

-- -----------------------------------------------------------------------------
-- internal.normalizar_telefono
-- Deja solo dígitos, conservando el "+" inicial del prefijo internacional.
-- "(01) 445-5667" y "014455667" pasan a ser el mismo valor.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.normalizar_telefono(p_valor TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF(
    CASE WHEN btrim(coalesce(p_valor, '')) LIKE '+%' THEN '+' ELSE '' END
      || regexp_replace(coalesce(p_valor, ''), '[^0-9]', '', 'g'),
    '');
$$;

-- -----------------------------------------------------------------------------
-- internal.normalizar_correo — recorta y pasa a minúsculas
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.normalizar_correo(p_valor TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF(lower(btrim(coalesce(p_valor, ''))), '');
$$;

-- -----------------------------------------------------------------------------
-- internal.normalizar_codigo — identificadores internos, siempre en mayúsculas
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.normalizar_codigo(p_valor TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF(upper(btrim(coalesce(p_valor, ''))), '');
$$;

-- =============================================================================
-- TRIGGERS
-- =============================================================================

-- ---------------------------------------------------------------------------
-- clientes
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.trg_normalizar_cliente()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = core, internal, public
AS $$
BEGIN
  NEW.numero_documento := internal.normalizar_documento(NEW.numero_documento);
  NEW.nombres          := internal.normalizar_nombre(NEW.nombres);
  NEW.apellido_paterno := internal.normalizar_nombre(NEW.apellido_paterno);
  NEW.apellido_materno := internal.normalizar_nombre(NEW.apellido_materno);
  -- La razón social se recorta pero NO se capitaliza: "SAC", "E.I.R.L." y las
  -- siglas de la marca son parte del nombre legal.
  NEW.razon_social     := internal.normalizar_texto(NEW.razon_social);
  NEW.telefono         := internal.normalizar_telefono(NEW.telefono);
  NEW.telefono_alterno := internal.normalizar_telefono(NEW.telefono_alterno);
  NEW.correo           := internal.normalizar_correo(NEW.correo);
  NEW.direccion        := internal.normalizar_texto(NEW.direccion);
  NEW.ubigeo           := internal.normalizar_codigo(NEW.ubigeo);
  NEW.codigo           := internal.normalizar_codigo(NEW.codigo);
  NEW.observaciones    := internal.normalizar_texto(NEW.observaciones);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_normalizar_cliente ON core.clientes;
CREATE TRIGGER tg_normalizar_cliente
  BEFORE INSERT OR UPDATE ON core.clientes
  FOR EACH ROW EXECUTE FUNCTION core.trg_normalizar_cliente();

-- ---------------------------------------------------------------------------
-- users
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.trg_normalizar_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = core, internal, public
AS $$
BEGIN
  NEW.email            := internal.normalizar_correo(NEW.email);
  NEW.numero_documento := internal.normalizar_documento(NEW.numero_documento);
  NEW.nombres          := internal.normalizar_nombre(NEW.nombres);
  NEW.apellido_paterno := internal.normalizar_nombre(NEW.apellido_paterno);
  NEW.apellido_materno := internal.normalizar_nombre(NEW.apellido_materno);
  NEW.telefono         := internal.normalizar_telefono(NEW.telefono);
  NEW.codigo           := internal.normalizar_codigo(NEW.codigo);
  NEW.colegiatura      := internal.normalizar_codigo(NEW.colegiatura);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_normalizar_user ON core.users;
CREATE TRIGGER tg_normalizar_user
  BEFORE INSERT OR UPDATE ON core.users
  FOR EACH ROW EXECUTE FUNCTION core.trg_normalizar_user();

-- ---------------------------------------------------------------------------
-- mascotas
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.trg_normalizar_mascota()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = core, internal, public
AS $$
BEGIN
  NEW.nombre              := internal.normalizar_nombre(NEW.nombre);
  NEW.color               := internal.normalizar_texto(NEW.color);
  NEW.microchip           := internal.normalizar_documento(NEW.microchip);
  NEW.num_placa           := internal.normalizar_codigo(NEW.num_placa);
  NEW.codigo              := internal.normalizar_codigo(NEW.codigo);
  NEW.alergias            := internal.normalizar_texto(NEW.alergias);
  NEW.condiciones_cronicas := internal.normalizar_texto(NEW.condiciones_cronicas);
  NEW.senias_particulares := internal.normalizar_texto(NEW.senias_particulares);
  NEW.observaciones       := internal.normalizar_texto(NEW.observaciones);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_normalizar_mascota ON core.mascotas;
CREATE TRIGGER tg_normalizar_mascota
  BEFORE INSERT OR UPDATE ON core.mascotas
  FOR EACH ROW EXECUTE FUNCTION core.trg_normalizar_mascota();

-- ---------------------------------------------------------------------------
-- proveedores
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.trg_normalizar_proveedor()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = core, internal, public
AS $$
BEGIN
  NEW.numero_documento := internal.normalizar_documento(NEW.numero_documento);
  NEW.razon_social     := internal.normalizar_texto(NEW.razon_social);
  NEW.nombre_comercial := internal.normalizar_texto(NEW.nombre_comercial);
  NEW.telefono         := internal.normalizar_telefono(NEW.telefono);
  NEW.correo           := internal.normalizar_correo(NEW.correo);
  NEW.direccion        := internal.normalizar_texto(NEW.direccion);
  NEW.codigo           := internal.normalizar_codigo(NEW.codigo);
  NEW.cuenta_bancaria  := internal.normalizar_documento(NEW.cuenta_bancaria);
  NEW.banco            := internal.normalizar_texto(NEW.banco);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_normalizar_proveedor ON core.proveedores;
CREATE TRIGGER tg_normalizar_proveedor
  BEFORE INSERT OR UPDATE ON core.proveedores
  FOR EACH ROW EXECUTE FUNCTION core.trg_normalizar_proveedor();

DROP TRIGGER IF EXISTS tg_normalizar_proveedor_contacto ON core.proveedor_contactos;
CREATE OR REPLACE FUNCTION core.trg_normalizar_contacto()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = core, internal, public
AS $$
BEGIN
  NEW.nombres  := internal.normalizar_nombre(NEW.nombres);
  NEW.cargo    := internal.normalizar_texto(NEW.cargo);
  NEW.telefono := internal.normalizar_telefono(NEW.telefono);
  NEW.correo   := internal.normalizar_correo(NEW.correo);
  RETURN NEW;
END;
$$;
CREATE TRIGGER tg_normalizar_proveedor_contacto
  BEFORE INSERT OR UPDATE ON core.proveedor_contactos
  FOR EACH ROW EXECUTE FUNCTION core.trg_normalizar_contacto();

-- ---------------------------------------------------------------------------
-- empresas
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.trg_normalizar_empresa()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = core, internal, public
AS $$
BEGIN
  NEW.ruc              := internal.normalizar_documento(NEW.ruc);
  NEW.razon_social     := internal.normalizar_texto(NEW.razon_social);
  NEW.nombre_comercial := internal.normalizar_texto(NEW.nombre_comercial);
  NEW.direccion_fiscal := internal.normalizar_texto(NEW.direccion_fiscal);
  NEW.telefono         := internal.normalizar_telefono(NEW.telefono);
  NEW.correo           := internal.normalizar_correo(NEW.correo);
  NEW.ubigeo           := internal.normalizar_codigo(NEW.ubigeo);
  NEW.serie_factura_default    := internal.normalizar_codigo(NEW.serie_factura_default);
  NEW.serie_boleta_default     := internal.normalizar_codigo(NEW.serie_boleta_default);
  NEW.serie_nota_venta_default := internal.normalizar_codigo(NEW.serie_nota_venta_default);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_normalizar_empresa ON core.empresas;
CREATE TRIGGER tg_normalizar_empresa
  BEFORE INSERT OR UPDATE ON core.empresas
  FOR EACH ROW EXECUTE FUNCTION core.trg_normalizar_empresa();

-- ---------------------------------------------------------------------------
-- catálogos: productos, servicios, especies, razas
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.trg_normalizar_producto()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = core, internal, public
AS $$
BEGIN
  NEW.codigo           := internal.normalizar_codigo(NEW.codigo);
  NEW.codigo_barras    := internal.normalizar_documento(NEW.codigo_barras);
  NEW.nombre           := internal.normalizar_texto(NEW.nombre);
  NEW.principio_activo := internal.normalizar_texto(NEW.principio_activo);
  NEW.laboratorio      := internal.normalizar_texto(NEW.laboratorio);
  NEW.presentacion     := internal.normalizar_texto(NEW.presentacion);
  NEW.unidad_medida    := internal.normalizar_codigo(NEW.unidad_medida);
  NEW.descripcion      := internal.normalizar_texto(NEW.descripcion);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_normalizar_producto ON core.productos;
CREATE TRIGGER tg_normalizar_producto
  BEFORE INSERT OR UPDATE ON core.productos
  FOR EACH ROW EXECUTE FUNCTION core.trg_normalizar_producto();

CREATE OR REPLACE FUNCTION core.trg_normalizar_servicio()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = core, internal, public
AS $$
BEGIN
  NEW.codigo      := internal.normalizar_codigo(NEW.codigo);
  NEW.nombre      := internal.normalizar_texto(NEW.nombre);
  NEW.descripcion := internal.normalizar_texto(NEW.descripcion);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_normalizar_servicio ON core.servicios;
CREATE TRIGGER tg_normalizar_servicio
  BEFORE INSERT OR UPDATE ON core.servicios
  FOR EACH ROW EXECUTE FUNCTION core.trg_normalizar_servicio();

CREATE OR REPLACE FUNCTION core.trg_normalizar_taxonomia()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = core, internal, public
AS $$
BEGIN
  NEW.nombre := internal.normalizar_texto(NEW.nombre);
  IF TG_TABLE_NAME = 'especies' THEN
    NEW.codigo := internal.normalizar_codigo(NEW.codigo);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_normalizar_especie ON core.especies;
CREATE TRIGGER tg_normalizar_especie
  BEFORE INSERT OR UPDATE ON core.especies
  FOR EACH ROW EXECUTE FUNCTION core.trg_normalizar_taxonomia();

DROP TRIGGER IF EXISTS tg_normalizar_raza ON core.razas;
CREATE TRIGGER tg_normalizar_raza
  BEFORE INSERT OR UPDATE ON core.razas
  FOR EACH ROW EXECUTE FUNCTION core.trg_normalizar_taxonomia();

-- =============================================================================
-- Normalización de lo ya almacenado
--
-- Un UPDATE que no cambia nada dispara igual el trigger BEFORE, así que basta
-- con "tocar" cada fila. Es idempotente: reaplicar la migración no altera nada
-- que ya esté normalizado.
-- =============================================================================
DO $$
DECLARE
  t TEXT;
  tablas TEXT[] := ARRAY['empresas','users','clientes','mascotas','proveedores',
                         'proveedor_contactos','productos','servicios','especies','razas'];
  n INT;
  total INT := 0;
BEGIN
  FOREACH t IN ARRAY tablas LOOP
    EXECUTE format('UPDATE core.%I SET id = id', t);
    GET DIAGNOSTICS n = ROW_COUNT;
    total := total + n;
  END LOOP;
  -- En una instalación nueva esto es 0: los datos aún no existen y el trigger
  -- los normaliza al insertarlos. En una actualización, limpia lo ya guardado.
  RAISE NOTICE 'Normalización aplicada a % filas existentes', total;
END $$;
