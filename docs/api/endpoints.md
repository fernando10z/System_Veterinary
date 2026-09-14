# API REST

Base: `http://localhost:3100/api`. Todas las respuestas usan
`{ ok: true, data, meta? }` o `{ ok: false, error: { code, message, detail? } }`.

Salvo las marcadas como públicas, todas exigen `Authorization: Bearer <access_token>`.

**Convención de nombres.** El cuerpo de la petición y la respuesta usan
`snake_case`, igual que las columnas y los payloads de los SPs, para que el dato
viaje con el mismo nombre de punta a punta. Los parámetros de query usan
`camelCase` (`veterinarioId`, `pageSize`, `soloCriticos`): no son datos del
dominio sino opciones de la consulta.

**Texto de entrada.** El backend recorta y colapsa espacios antes de validar, y
la base normaliza documentos, nombres, teléfonos y correos al guardarlos
(ver [ADR-004](../decisions/004-normalizacion-en-la-base.md)). Pegar
`" 12.345.678 "` en el DNI funciona; se guarda `12345678`.

## Auth

| Método | Ruta | Notas |
|---|---|---|
| POST | `/auth/login` | Público. Devuelve `access_token`, `refresh_token`, `user`, `rol`, `permisos`, `empresa`. |
| POST | `/auth/refresh` | Público. Rota el refresh token. |
| POST | `/auth/logout` | Público. Revoca el refresh. |
| GET | `/auth/perfil` | Datos frescos del usuario en sesión. |
| POST | `/auth/cambiar-password` | |
| POST | `/auth/solicitar-reset` · `/auth/reset-password` | Públicos. |
| POST | `/auth/portal/login` | Público. Token del portal (`type=portal`). |

## Clínica

| Método | Ruta | Notas |
|---|---|---|
| GET | `/citas` | Filtros: `desde` `hasta` `estado` `veterinarioId` `mascotaId` `buscar`. |
| GET | `/citas/agenda-dia` | Conteo por estado del día. |
| GET | `/citas/disponibilidad` | Huecos libres: `veterinarioId` `fecha` `duracion`. |
| POST | `/citas` · PATCH `/citas/:id/reprogramar` · PATCH `/citas/:id/estado` | |
| GET | `/mascotas` · `/mascotas/:id` | Ficha con vacunas, tratamientos, curva de peso. |
| GET | `/mascotas/:id/historia` | Línea de tiempo; `tipo` la filtra. |
| GET | `/mascotas/:id/vacunas` | Carné con estado de cada refuerzo. |
| GET | `/clientes` · `/clientes/buscar` · `/clientes/:id` | Solo la cartera de la empresa del usuario. `buscar` también encuentra por nombre de mascota. |
| POST | `/clientes/:id/portal` | Activa el acceso del propietario. |
| POST | `/clinico/consultas` · PATCH `/clinico/consultas/:id` · PATCH `/clinico/consultas/:id/cerrar` | Cerrar exige diagnóstico y completa la cita. |
| POST | `/clinico/vacunas` · `/clinico/desparasitaciones` · `/clinico/tratamientos` | |
| POST | `/clinico/cirugias` · PATCH `/clinico/cirugias/:id/resultado` | Exige consentimiento firmado. |
| POST | `/clinico/hospitalizaciones` · `/clinico/hospitalizaciones/evoluciones` · PATCH `/:id/alta` | |
| POST | `/clinico/ordenes-servicio` · `/clinico/insumos` | Lo facturable de la atención. |
| GET | `/clinico/pendiente-facturar/:clienteId` | Alimenta la emisión de comprobantes. |

## Operación y administración

| Método | Ruta | Notas |
|---|---|---|
| GET | `/inventario/productos` · `/inventario/alertas` · `/inventario/movimientos` | `alertas` trae stock crítico, por vencer y vencidos. |
| POST | `/inventario/movimientos` · `/inventario/lotes` | Nunca deja stock negativo. |
| GET/POST | `/compras/proveedores` · `/compras/ordenes` | |
| POST | `/compras/ordenes/:id/recibir` | Sin cuerpo recibe todo lo pendiente. |
| POST | `/facturacion` | Sin `items` factura todo lo pendiente del cliente. |
| PATCH | `/facturacion/:id/anular` | Devuelve los ítems al pool de pendientes. |
| GET | `/facturacion/cuentas-por-cobrar` | Aging por tramo de mora. |
| POST | `/pagos` | Sin `aplicaciones` imputa a los comprobantes más antiguos. |
| POST | `/caja/abrir` · `/caja/movimientos` · PATCH `/caja/:id/cerrar` | El cierre es el arqueo. |
| GET | `/rrhh/equipo` · `/rrhh/asistencia` · `/rrhh/permisos` | |
| POST | `/rrhh/asistencia/marcar` | Marca entrada o salida según el estado del día. |
| GET | `/reportes/{ventas,clinico,inventario,ejecutivo}` | Rango `desde`/`hasta`. |
| GET | `/dashboard` · `/dashboard/recordatorios` | |
| GET | `/auditoria` | Bitácora con diff. |

## Portal del propietario

Requieren el token del portal.

| Método | Ruta |
|---|---|
| GET | `/portal/mis-mascotas` · `/portal/mis-citas` · `/portal/mis-comprobantes` |
| GET | `/portal/mascotas/:id/historial` |
| POST | `/portal/citas` · `/portal/cambiar-password` | La empresa de la cita la fija el SP desde el propietario; no se acepta en el cuerpo. |

## Archivos

| Método | Ruta | Notas |
|---|---|---|
| POST | `/archivos` | Multipart; devuelve `storage_key`. |
| GET | `/archivos/ticket-subida` | URL prefirmada para subir directo a MinIO. |
| GET | `/archivos/ticket-descarga` | URL temporal de descarga. |

## Códigos de error

| `code` | HTTP | Cuándo |
|---|---|---|
| `VALIDATION_ERROR` | 422 | Falta un campo o el valor no es válido |
| `BUSINESS_RULE` | 422 | Una regla de negocio lo impide |
| `NOT_FOUND` | 404 | El registro no existe, o pertenece a otra empresa (no se revela cuál de las dos) |
| `FORBIDDEN` | 403 | Sin permiso o sin acceso a la empresa |
| `UNAUTHORIZED` | 401 | Token ausente, inválido o expirado |
| `CONFLICT` | 409 | Duplicado (documento, código, caja abierta) |
