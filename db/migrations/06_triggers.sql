-- =============================================================================
-- 06_triggers.sql
-- Triggers de integridad y denormalización controlada.
-- =============================================================================

SET search_path = core, internal, public;

-- -----------------------------------------------------------------------------
-- touch_updated_at — mantiene updated_at sin que cada SP tenga que acordarse
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.trg_touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DO $$
DECLARE
  t TEXT;
  tablas TEXT[] := ARRAY[
    'empresas','roles','especializaciones','users','clientes','especies','razas','mascotas',
    'mascotas_extraviadas','categorias','servicios','esquemas_vacunacion','horarios_atencion',
    'consultorios','clausulas','citas','historia_clinica','consultas','vacunas','tratamientos',
    'cirugias','hospitalizaciones','notas_medicas','ordenes_servicio','almacenes','productos',
    'lotes','stock','proveedores','proveedor_contactos','ordenes_compra','comprobantes',
    'cajas','contratos_personal','disponibilidad','asistencia','permisos_laborales'
  ];
BEGIN
  FOREACH t IN ARRAY tablas LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS tg_%1$s_updated_at ON core.%1$s;
       CREATE TRIGGER tg_%1$s_updated_at BEFORE UPDATE ON core.%1$s
       FOR EACH ROW EXECUTE FUNCTION core.trg_touch_updated_at();', t);
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- users: el scope del rol determina si empresa_id debe ser NULL o NOT NULL.
-- Un rol global/global_restricted ve todas las empresas, así que NO puede
-- estar anclado a una.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.trg_users_validate_rol_scope()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_scope core.scope_rol;
BEGIN
  IF NEW.rol_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT scope INTO v_scope FROM core.roles WHERE id = NEW.rol_id;

  IF v_scope IN ('global','global_restricted') AND NEW.empresa_id IS NOT NULL THEN
    RAISE EXCEPTION 'Un rol con alcance % no puede estar asignado a una empresa concreta', v_scope
      USING ERRCODE = 'P0001';
  END IF;

  IF v_scope = 'empresa' AND NEW.empresa_id IS NULL THEN
    RAISE EXCEPTION 'Un rol con alcance de empresa requiere empresa_id'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_users_validate_rol_scope ON core.users;
CREATE TRIGGER tg_users_validate_rol_scope
  BEFORE INSERT OR UPDATE OF rol_id, empresa_id ON core.users
  FOR EACH ROW EXECUTE FUNCTION core.trg_users_validate_rol_scope();

-- -----------------------------------------------------------------------------
-- stock: al insertar un movimiento se ajusta core.stock y el denormalizado
-- productos.stock_actual. Un solo lugar mueve stock → no hay descuadres.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.trg_movimiento_aplicar_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_delta   NUMERIC(12,2);
  v_almacen UUID;
BEGIN
  v_delta := CASE NEW.tipo
    WHEN 'entrada'          THEN  NEW.cantidad
    WHEN 'ajuste_positivo'  THEN  NEW.cantidad
    WHEN 'salida'           THEN -NEW.cantidad
    WHEN 'ajuste_negativo'  THEN -NEW.cantidad
    WHEN 'merma'            THEN -NEW.cantidad
    WHEN 'vencimiento'      THEN -NEW.cantidad
    WHEN 'transferencia'    THEN -NEW.cantidad
  END;

  v_almacen := COALESCE(NEW.almacen_id, (
    SELECT id FROM core.almacenes
     WHERE empresa_id = NEW.empresa_id AND es_principal = true
     LIMIT 1));

  IF v_almacen IS NOT NULL THEN
    INSERT INTO core.stock (empresa_id, producto_id, almacen_id, cantidad)
    VALUES (NEW.empresa_id, NEW.producto_id, v_almacen, v_delta)
    ON CONFLICT (producto_id, almacen_id)
    DO UPDATE SET cantidad = core.stock.cantidad + v_delta, updated_at = now();

    -- El destino de una transferencia recibe la cantidad completa
    IF NEW.tipo = 'transferencia' AND NEW.almacen_destino_id IS NOT NULL THEN
      INSERT INTO core.stock (empresa_id, producto_id, almacen_id, cantidad)
      VALUES (NEW.empresa_id, NEW.producto_id, NEW.almacen_destino_id, NEW.cantidad)
      ON CONFLICT (producto_id, almacen_id)
      DO UPDATE SET cantidad = core.stock.cantidad + NEW.cantidad, updated_at = now();
    END IF;
  END IF;

  -- Lote: mismo delta (salvo transferencia, que no cambia el total del lote)
  IF NEW.lote_id IS NOT NULL AND NEW.tipo <> 'transferencia' THEN
    UPDATE core.lotes SET cantidad = cantidad + v_delta, updated_at = now()
     WHERE id = NEW.lote_id;
  END IF;

  -- Denormalizado del producto: suma de todos sus almacenes
  UPDATE core.productos p
     SET stock_actual = COALESCE((
           SELECT SUM(s.cantidad) FROM core.stock s WHERE s.producto_id = p.id
         ), 0),
         updated_at = now()
   WHERE p.id = NEW.producto_id;

  NEW.saldo_despues := (SELECT stock_actual FROM core.productos WHERE id = NEW.producto_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_movimiento_aplicar_stock ON core.movimientos_inventario;
CREATE TRIGGER tg_movimiento_aplicar_stock
  BEFORE INSERT ON core.movimientos_inventario
  FOR EACH ROW EXECUTE FUNCTION core.trg_movimiento_aplicar_stock();

-- -----------------------------------------------------------------------------
-- asistencia: calcula horas trabajadas al marcar la salida
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.trg_asistencia_horas()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.hora_entrada IS NOT NULL AND NEW.hora_salida IS NOT NULL THEN
    NEW.horas_trabajadas := round(
      EXTRACT(EPOCH FROM (NEW.hora_salida - NEW.hora_entrada)) / 3600.0, 2);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_asistencia_horas ON core.asistencia;
CREATE TRIGGER tg_asistencia_horas
  BEFORE INSERT OR UPDATE ON core.asistencia
  FOR EACH ROW EXECUTE FUNCTION core.trg_asistencia_horas();

-- -----------------------------------------------------------------------------
-- evaluaciones: promedio de los cuatro criterios
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.trg_evaluacion_promedio()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.promedio := round((
    COALESCE(NEW.puntualidad,0) + COALESCE(NEW.eficiencia,0) +
    COALESCE(NEW.calidad_atencion,0) + COALESCE(NEW.trabajo_equipo,0)
  )::numeric / NULLIF((
    (NEW.puntualidad IS NOT NULL)::int + (NEW.eficiencia IS NOT NULL)::int +
    (NEW.calidad_atencion IS NOT NULL)::int + (NEW.trabajo_equipo IS NOT NULL)::int
  ), 0), 2);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_evaluacion_promedio ON core.evaluaciones_personal;
CREATE TRIGGER tg_evaluacion_promedio
  BEFORE INSERT OR UPDATE ON core.evaluaciones_personal
  FOR EACH ROW EXECUTE FUNCTION core.trg_evaluacion_promedio();

-- -----------------------------------------------------------------------------
-- consultas: el peso registrado en consulta actualiza el peso de la mascota.
-- Así la ficha del paciente siempre muestra el último peso sin subconsulta.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.trg_consulta_sync_peso()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.peso_kg IS NOT NULL AND NEW.peso_kg > 0 THEN
    UPDATE core.mascotas
       SET peso_kg = NEW.peso_kg, updated_at = now()
     WHERE id = NEW.mascota_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_consulta_sync_peso ON core.consultas;
CREATE TRIGGER tg_consulta_sync_peso
  AFTER INSERT OR UPDATE OF peso_kg ON core.consultas
  FOR EACH ROW EXECUTE FUNCTION core.trg_consulta_sync_peso();

-- -----------------------------------------------------------------------------
-- mascotas: marcar fallecida cierra automáticamente sus tratamientos activos
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.trg_mascota_fallecida()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.estado = 'fallecido' AND OLD.estado <> 'fallecido' THEN
    UPDATE core.tratamientos SET estado = 'suspendido', updated_at = now()
     WHERE mascota_id = NEW.id AND estado = 'activo';
    UPDATE core.citas SET estado = 'cancelada',
           motivo_cancelacion = 'Paciente fallecido', updated_at = now()
     WHERE mascota_id = NEW.id
       AND estado IN ('programada','confirmada')
       AND fecha_hora > now();
    UPDATE core.recordatorios SET completado = true
     WHERE mascota_id = NEW.id AND completado = false;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_mascota_fallecida ON core.mascotas;
CREATE TRIGGER tg_mascota_fallecida
  AFTER UPDATE OF estado ON core.mascotas
  FOR EACH ROW EXECUTE FUNCTION core.trg_mascota_fallecida();

-- -----------------------------------------------------------------------------
-- comprobante_items: recalcula los totales de la cabecera en cada cambio
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.trg_comprobante_recalcular()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_comprobante UUID := COALESCE(NEW.comprobante_id, OLD.comprobante_id);
BEGIN
  UPDATE core.comprobantes c
     SET subtotal = COALESCE(t.subtotal, 0),
         igv      = COALESCE(t.igv, 0),
         total    = COALESCE(t.total, 0) - c.descuento_global,
         saldo_pendiente = (COALESCE(t.total, 0) - c.descuento_global) - COALESCE((
           SELECT SUM(pa.monto_aplicado) FROM core.pago_aplicaciones pa
            WHERE pa.comprobante_id = c.id), 0),
         updated_at = now()
    FROM (
      SELECT SUM(subtotal) AS subtotal, SUM(igv) AS igv, SUM(total) AS total
        FROM core.comprobante_items WHERE comprobante_id = v_comprobante
    ) t
   WHERE c.id = v_comprobante;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS tg_comprobante_recalcular ON core.comprobante_items;
CREATE TRIGGER tg_comprobante_recalcular
  AFTER INSERT OR UPDATE OR DELETE ON core.comprobante_items
  FOR EACH ROW EXECUTE FUNCTION core.trg_comprobante_recalcular();
