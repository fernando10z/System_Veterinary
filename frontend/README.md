# Frontend — ERP Veterinario

Vue 3 (`<script setup>`) + Vite + vue-router. Sin store global: el estado de sesión
vive en `shared/composables/useAuth.js` y cada página trae sus datos con su API.

## Anatomía de un módulo

```
modules/<dominio>/
├── api/<dominio>.api.js   funciones tipadas contra los endpoints reales
├── pages/                 pantallas enrutadas
└── components/            modales y piezas propias del módulo
```

Ninguna página llama a `fetch` directamente: todo pasa por `shared/api/client.js`,
que adjunta el token, renueva el access token con el refresh cuando expira y
normaliza el error a `{ message, code, status }`.

## Sistema de diseño

Dos hojas, en este orden:

- `styles/globals.css` — tokens (claro y oscuro), shell de la app, botones, paneles,
  modales, formularios. Es el mismo sistema de `System_ERP`.
- `styles/patterns.css` — patrones que repiten todas las pantallas: barra de filtros,
  tablas, pills de estado, avatares, línea de tiempo clínica, tarjetas de agenda.

Antes de escribir CSS en un `<style scoped>`, conviene revisar si el patrón ya existe:
que una lista de pacientes y una de comprobantes se vean iguales no es casualidad,
es que usan las mismas clases.

## Navegación

`shared/config/navigation.js` es la fuente única del menú. Cada item declara el
permiso que exige, y el Sidebar filtra con `hasPermission`. Agregar un módulo al
sistema es agregar una entrada ahí y una ruta en `router/index.js`.

## Comandos

```bash
npm run dev       # http://localhost:5174
npm run build
npm run preview
```

`VITE_API_BASE_URL` define a qué backend apunta (por defecto `http://localhost:3100/api`).
