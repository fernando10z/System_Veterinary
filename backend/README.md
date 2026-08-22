# Backend — ERP Veterinario

NestJS 10 + Fastify + `pg`. **No contiene lógica de negocio**: valida la entrada,
resuelve el contexto del usuario e invoca el stored procedure correspondiente.

## Anatomía de un módulo

```
modules/<dominio>/
├── <dominio>.controller.ts   rutas + DTOs, devuelve { ok, data, meta }
├── <dominio>.service.ts      arma el SpContext desde el JWT
├── <dominio>.repository.ts   único lugar que nombra SPs
├── <dominio>.module.ts
└── dto/                      validación con class-validator, mensajes en español
```

El flujo siempre es el mismo:

```
Controller → Service (ctx) → Repository (nombre del SP) → SpExecutorService → PostgreSQL
```

## Reglas al agregar un endpoint

1. El **repository** es el único que nombra SPs. Si un método necesita otro SP, se
   agrega ahí, no en el service.
2. Los parámetros `jsonb` se envían con `jsonbArg()`: node-postgres convierte los
   arrays de JS a arrays de Postgres, no a JSON, y eso rompe el parámetro.
3. Los DTO usan `class-validator` con mensajes en español: el usuario final es
   personal de clínica.
4. `whitelist: true` en el `ValidationPipe` descarta lo que no esté en el DTO. Si un
   campo no llega al SP, casi siempre falta declararlo en el DTO.
5. Para lecturas paginadas se usa `sp.callRaw` y se propaga `meta` al cliente.

## Autenticación

Dos guards independientes:

- `JwtAuthGuard` (global) — backoffice. `@Public()` lo desactiva por endpoint.
- `PortalAuthGuard` — portal del propietario. Verifica contra otro issuer/audience y
  exige `type === "portal"`. Un token del portal no sirve en el backoffice.

El refresh token se guarda en una whitelist de Redis por `jti` y **rota** en cada uso:
así una sesión concreta se puede revocar sin esperar a que expire.

## Comandos

```bash
npm run start:dev     # watch
npm run build
npm run start:prod
npm run db:migrate    # aplica las migraciones de ../db
```
