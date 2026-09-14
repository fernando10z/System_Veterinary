# Modelo de datos

60 tablas en `core`. **46 llevan `empresa_id`**: cada empresa es un negocio
independiente y no ve el dato de las demás.

## Sin `empresa_id` (compartido por todas las empresas)

| Tabla | Por qué es compartida |
|---|---|
| `empresas` | Cada fila es una empresa. Es la raíz del multi-tenancy. |
| `roles`, `permisos`, `rol_permisos` | Modelo de identidad del sistema, no dato de negocio. El `scope` del rol define el alcance del usuario. |
| `users` | Staff. `empresa_id` es NULL solo para los roles globales. Los veterinarios llevan `colegiatura` (obligatoria por CHECK). |
| `especies`, `razas`, `especializaciones` | Taxonomía de referencia. Solo la edita el super admin: es el catálogo del operador del ERP. |
| `audit_log`, `correlativos`, `sesiones`, `notificaciones` | Infraestructura transversal. |

Las tablas de detalle (`comprobante_items`, `citas_historial`, `pago_aplicaciones`,
`orden_compra_items`, `proveedor_contactos`, `hospitalizacion_evoluciones`) tampoco
la llevan: cuelgan por FK de un padre que sí la tiene y se borran en cascada con él.

## Con `empresa_id`

| Dominio | Tablas |
|---|---|
| Cartera | `clientes`, `mascotas`, `mascotas_extraviadas` |
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

**El documento del propietario es único por empresa, no globalmente.**
`UNIQUE (empresa_id, tipo_documento, numero_documento)`. La misma persona puede ser
cliente de dos empresas con una ficha distinta en cada una. El microchip sigue la
misma regla. Ver [ADR-002](../decisions/002-cartera-por-empresa.md).

**`mascotas.empresa_id` se hereda del propietario dentro del SP**, nunca del payload.
Eso hace imposible que una mascota quede en una empresa distinta a la de su dueño,
incluso si alguien manipula la petición.

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

## Normalización

El dato se limpia **al entrar**, no al consultarlo. Las funciones viven en
`internal` (`11_normalizacion.sql`) y se aplican con triggers `BEFORE INSERT OR
UPDATE`, así que da igual si el registro llega por un SP, por una carga masiva o
por un `UPDATE` a mano en una consola: sale normalizado igual.

| Función | Qué hace | Ejemplo |
|---|---|---|
| `normalizar_texto` | Recorta y colapsa espacios internos | `'  a   b '` → `'a b'` |
| `normalizar_nombre` | Capitaliza respetando partículas castellanas | `'DE LA cruz'` → `'De la Cruz'` |
| `normalizar_documento` | Deja solo dígitos | `' 12-345.678 '` → `'12345678'` |
| `normalizar_telefono` | Deja dígitos y el `+` inicial | `'(01) 445-5667'` → `'014455667'` |
| `normalizar_correo` | Recorta y pasa a minúsculas | `'  A@GMAIL.COM '` → `'a@gmail.com'` |
| `normalizar_codigo` | Recorta y pasa a mayúsculas | `' prd-01 '` → `'PRD-01'` |

Llevan trigger: `clientes`, `users`, `mascotas`, `proveedores`,
`proveedor_contactos`, `empresas`, `productos`, `servicios`, `especies` y `razas`.

**Por qué importa para la unicidad.** El documento es único por empresa. Sin
normalizar, `12345678` y `12.345.678` son dos filas distintas y la misma persona
queda duplicada en la cartera. Por eso los SPs que validan o buscan por documento
normalizan **antes** de comparar (`sp_cliente_crear`, `sp_users_crear`,
`sp_proveedor_guardar`, `sp_empresa_crear`): si validaran el texto crudo,
`12.345.678` se rechazaría por «no son 8 dígitos» y además esquivaría el chequeo
de duplicado, que compara contra valores ya normalizados.

El backend hace su parte antes de validar el DTO (`SanearEntradaPipe`): recorta,
colapsa espacios y convierte `""` en `null`. No toca contraseñas ni campos de
texto libre clínico, donde el espacio es parte del contenido.

## Triggers

| Trigger | Qué garantiza |
|---|---|
| `tg_*_updated_at` | `updated_at` correcto sin que cada SP se acuerde. |
| `trg_users_validate_rol_scope` | Un rol global no puede quedar anclado a una empresa. |
| `tg_movimiento_aplicar_stock` | Stock, lote y denormalizado siempre coherentes con el kardex. |
| `tg_consulta_sync_peso` | El peso de la ficha es el de la última consulta. |
| `tg_mascota_fallecida` | Suspende tratamientos, cancela citas futuras y apaga recordatorios. |
| `tg_comprobante_recalcular` | Los totales de la cabecera siempre cuadran con sus ítems. |
| `tg_asistencia_horas` | Calcula horas trabajadas al marcar la salida. |
| `tg_*_normalizar` | Documentos, nombres, teléfonos, correos y códigos guardados en una sola forma. |
