# ADR-006 · El permiso se comprueba dentro del stored procedure

**Estado:** aceptada · **Fecha:** 2026-09-20

## Contexto

El ERP tenía un modelo de roles completo: 45 permisos con código
`modulo:accion`, siete roles del sistema con su reparto pensado —el veterinario
sin acceso al dinero, recepción sin acceso a las compras, gerencia que lo ve
todo y no administra nada—, un `RolesGuard` montado como `APP_GUARD` y un
decorador `@Roles()` listo para usar.

No lo usaba ningún controlador. Ni uno.

Las escrituras sí comprobaban: 77 de los 97 SP llamaban a
`internal.assert_permiso`. Las lecturas, no: 74 de 77 funciones `fn_` filtraban
por empresa y por nada más. El resultado, medido contra el sistema corriendo:
con el token de recepción se leían el reporte ejecutivo con los márgenes, las
órdenes de compra con los precios de cada proveedor, el legajo del equipo y sus
vacaciones, y la lista de usuarios. El menú del frontend ocultaba esas pantallas
—`navigation.js` ya filtraba por permiso—, así que la clínica creía que estaban
cerradas. Estaban ocultas, que no es lo mismo.

Faltaban además dos permisos que el modelo no distinguía: cualquier usuario de
la empresa podía cambiar el IGV, las series y las credenciales del PSE
(`sp_empresa_actualizar` solo verificaba que fueras de la empresa), y cualquiera
con `facturacion:emitir` podía marcar a mano un comprobante como aceptado por
SUNAT sin haberlo enviado, con lo que salía de la cola de pendientes y no se
declaraba nunca.

## Decisión

**La comprobación del permiso vive en el SP, junto a la consulta que devuelve el
dato.** Todo SP de lectura y de escritura abre con
`PERFORM internal.assert_permiso(p_user_id, '<modulo>:<accion>')`.

El controlador no comprueba nada. No es descuido: es que no tiene con qué. El
rol de un usuario vive en `core.rol_permisos` y se edita en caliente; lo que
lleva el JWT es una foto de hasta quince minutos atrás. Comprobar en el guard
significa decidir con datos viejos, y mantener dos listas de permisos —la del
decorador y la de la base— que se separan a la primera pantalla nueva.

Tres helpers, según lo que decida el permiso:

- `internal.assert_permiso` aborta. Es el caso normal: se entra o no se entra.
- `internal.tiene_permiso` responde `boolean`, para cuando el permiso no decide
  si se entra sino **cuánto se ve**. Un veterinario tiene `rrhh:ver` para
  consultar sus propias horas; sin `rrhh:gestionar` no ve las de sus compañeros
  ni el motivo por el que alguien pidió el día libre.
- `internal.usuario_objetivo` cubre el autoservicio. Fichar la entrada o pedir
  vacaciones se hace para uno mismo; hacerlo en nombre de otro exige
  `rrhh:gestionar`. Sin esto, cualquiera fichaba por un compañero o le metía
  unas vacaciones que, una vez aprobadas, le bloqueaban la agenda.

Dos permisos nuevos para separar lo que estaba junto:

| Permiso | Separa |
|---|---|
| `empresa:configurar` | Configurar la **propia** clínica (series, IGV, datos fiscales, credenciales del PSE) de administrar el padrón de empresas, que sigue siendo `empresas:gestionar` y solo lo tiene el super admin. |
| `facturacion:sunat` | Cargar o corregir a mano la respuesta de SUNAT, de emitir un comprobante. Emitir lo hace el mostrador; decidir qué se declara, no. |

`assert_permiso` comprueba además `deleted_at IS NULL AND estado = 'activo'`. Un
usuario dado de baja conserva el token hasta que expira; la baja tiene efecto en
la siguiente llamada.

## Consecuencias

**A favor**

- Un permiso revocado surte efecto en la siguiente llamada, sin reiniciar el
  backend ni esperar a que caduque el token.
- La regla está donde está el dato. Un SP nuevo que olvide la línea se nota al
  revisarlo: todos los de al lado la tienen en la primera línea del cuerpo.
- No hay dos fuentes de verdad que mantener sincronizadas.
- `scripts/verificar-api.sh` ejercita la matriz rol × endpoint (sección 7) con
  usuarios reales de cada rol. Antes pasaba 134 comprobaciones sin tocar el
  tema: probaba a conciencia que la empresa A no viera a la B, y nunca que
  recepción no hiciera de contador.

**En contra**

- El backend responde `403` después de haber ido a la base. Es un viaje de más
  para una petición que va a ser rechazada; a cambio, la respuesta es correcta.
- El router del frontend repite el filtro del menú para no pasear al usuario a
  una pantalla que responderá `403` a todo. Es duplicación deliberada y de
  cortesía: la del servidor es la que manda.

## Alternativas descartadas

**Usar `@Roles()` en los controladores.** Es lo que el código ya tenía montado.
Ata el permiso al nombre del rol en vez de al permiso, así que un rol nuevo
—"auxiliar de peluquería"— obliga a tocar y volver a desplegar el backend, y
deja fuera lo que el ERP ya sabe hacer: roles a medida con permisos a medida.

**Meter los permisos en el JWT y comprobarlos en el guard.** Evita el viaje a la
base, y a cambio un permiso retirado sigue valiendo hasta quince minutos. En un
ERP donde el permiso que se retira con prisa es el de anular comprobantes, esos
quince minutos son exactamente los que importan.

**Row Level Security de Postgres.** Encaja con el filtro por empresa, no con el
de permisos: RLS decide sobre filas, y aquí la mitad de las reglas son sobre
columnas y operaciones —ver el margen, cargar el CDR, cambiar una serie—.
Habrían convivido dos mecanismos para el mismo problema.
