<template>
  <div :class="['app', isCollapsed ? 'sidebar-collapsed' : '']">
    <Sidebar />
    <main class="main">
      <Topbar />
      <div class="page">
        <router-view />
      </div>
    </main>
  </div>
</template>

<script setup>
import Sidebar from "./Sidebar.vue";
import Topbar from "./Topbar.vue";
import { useSidebar } from "../shared/composables/useSidebar.js";

const { isCollapsed } = useSidebar();
</script>

<style scoped>
/* El layout se maneja desde globals.css:
   - .app es un grid de 2 columnas (sidebar + contenido) centrado en --ancho-app
   - .sidebar es sticky con height:100vh → no scrollea con el body
   - .page centra el contenido en --ancho-contenido
*/
</style>
