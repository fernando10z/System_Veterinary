# 003 — El portal del propietario usa una autenticación separada

## Contexto

El portal expone historia clínica y comprobantes a personas ajenas a la clínica. Lo
más simple habría sido reutilizar el JWT del backoffice con un rol "cliente".

## Decisión

El portal emite un token propio: **issuer y audience distintos** y `type: "portal"`.
Lo verifica `PortalAuthGuard`, no el guard del staff. Los SPs del portal
(`app.fn_portal_*`, `app.sp_portal_*`) reciben `cliente_id`, nunca un `user_id`.

## Consecuencias

**A favor**

- Un token del portal **falla** la verificación del guard del backoffice: no es
  cuestión de que un rol tenga pocos permisos, es que el token no valida.
- Los SPs del portal no comparten superficie con los del staff. `fn_portal_historial`
  excluye las notas internas del equipo por diseño, no por un filtro en la vista.
- Los propietarios viven en `core.clientes`, no en `core.users`: no ensucian el
  listado de personal ni el modelo de roles.

**En contra**

- Dos guards y dos clientes HTTP que mantener.
- El portal no reutiliza el refresh token rotativo del backoffice: usa un token de
  vida más larga (8 h) y vuelve a pedir credenciales al expirar.

**Alternativa descartada**

Un rol `cliente_portal` dentro de `core.users`: obligaba a que cada SP de lectura
recordara excluirlo, y cualquier olvido exponía datos internos. Un fallo de omisión
habría sido silencioso.
