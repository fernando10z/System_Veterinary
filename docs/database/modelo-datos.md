# Modelo de datos

60 tablas en `core`, repartidas entre lo que es común a toda la cadena y lo que
pertenece a una sede.

## Client-global (sin `empresa_id`)

Comparten todas las sedes:

| Tabla | Notas |
|---|---|
| `empresas` | Cada fila es una sede. El multi-tenancy se resuelve por `empresa_id`. |
| `roles`, `permisos`, `rol_permisos` | El `scope` del rol define el alcance del usuario. |
| `users` | Staff. Los veterinarios llevan `colegiatura` (obligatoria por CHECK). |
| `clientes` | Propietarios. La cartera es de la cadena: el mismo dueño en cualquier sede. |
| `especies`, `razas` | Catálogo maestro con peso de referencia y esperanza de vida. |
| `mascotas` | Pacientes. Historia clínica única en toda la cadena. |
| `audit_log`, `correlativos`, `sesiones`, `notificaciones` | Transversales. |

**Por qué clientes y mascotas son globales**: un propietario que va a otra sede es el
mismo propietario, y su mascota llega con su historia. Duplicar el registro por sede
obligaría a reconciliar dos historias clínicas del mismo animal.

## Por sede (`empresa_id`)

| Dominio | Tablas |
|---|---|
| Catálogos | `categorias`, `servicios`, `esquemas_vacunacion`, `horarios_atencion`, `consultorios`, `clausulas` |
| Agenda | `citas`, `citas_historial`, `citas_lista_espera` |
| Historia clínica | `historia_clinica`, `consultas`, `vacunas`, `desparasitaciones`, `tratamientos`, `cirugias`, `hospitalizaciones`, `hospitalizacion_evoluciones`, `examenes`, `notas_medicas`, `documentos_medicos`, `ordenes_servicio` |
| Inventario | `almacenes`, `productos`, `lotes`, `stock`, `movimientos_inventario`, `insumos_utilizados` |
| Compras | `proveedores`, `proveedor_contactos`, `ordenes_compra`, `orden_compra_items`, `pagos_proveedor` |
| Facturación | `comprobantes`, `comprobante_items`, `pagos`, `pago_aplicaciones` |
| Caja | `cajas`, `movimientos_caja` |
| Personal | `contratos_personal`, `disponibilidad`, `asistencia`, `permisos_laborales`, `evaluaciones_personal` |
| CRM | `comunicaciones`, `recordatorios` |

## Decisiones del modelo

**`historia_clinica` como índice de eventos.** No duplica el contenido: guarda tipo,
fecha, título, resumen y el `entidad_id` de la fila real. Ver el detalle es ir a la
tabla específica; ver la historia es leer solo esta.

**`ordenes_servicio` separa el acto de la factura.** Un servicio prestado existe
aunque todavía no se cobre. Al facturar se marca `facturado = true`; al anular el
comprobante vuelve a quedar pendiente. Sin esa separación, anular una boleta borraría
la evidencia de que el servicio se prestó.

**`stock` por almacén + denormalizado en `productos`.** La verdad está en `core.stock`
(producto × almacén). `productos.stock_actual` es la suma, mantenida por el trigger,
para que listar el catálogo no exija un `SUM` por fila.

**`comprobantes.numero_completo` es una columna generada.** `serie || '-' || numero`
con relleno de ceros, calculada por Postgres: no hay forma de que el número mostrado
difiera del almacenado.

**Los correlativos se toman con `UPDATE … RETURNING`.** Eso bloquea la fila y evita
que dos cajeros emitan el mismo número al mismo tiempo.

**Borrado lógico donde hay historia.** Pacientes, clientes, usuarios, productos y
servicios con movimientos no se eliminan: se desactivan. El SP lo decide y lo informa
en la respuesta, para que la UI pueda explicarlo.

## Triggers

| Trigger | Qué garantiza |
|---|---|
| `tg_*_updated_at` | `updated_at` correcto sin que cada SP se acuerde. |
| `trg_users_validate_rol_scope` | Un rol global no puede quedar anclado a una sede. |
| `tg_movimiento_aplicar_stock` | Stock, lote y denormalizado siempre coherentes con el kardex. |
| `tg_consulta_sync_peso` | El peso de la ficha es el de la última consulta. |
| `tg_mascota_fallecida` | Suspende tratamientos, cancela citas futuras y apaga recordatorios. |
| `tg_comprobante_recalcular` | Los totales de la cabecera siempre cuadran con sus ítems. |
| `tg_asistencia_horas` | Calcula horas trabajadas al marcar la salida. |
