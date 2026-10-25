<template>
  <div :class="['app', isCollapsed && !isMobile ? 'sidebar-collapsed' : '', mobileOpen ? 'menu-abierto' : '']">
    <Sidebar />
    <div v-if="isMobile && mobileOpen" class="sidebar-backdrop" aria-hidden="true" @click="closeMobile"></div>
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
import { watch, onMounted, onUnmounted } from "vue";
import { useRoute } from "vue-router";
import { useSidebar } from "../shared/composables/useSidebar.js";

const { isCollapsed, isMobile, mobileOpen, closeMobile } = useSidebar();
const route = useRoute();

// En celular el menú se cierra al navegar y con Escape.
watch(() => route.fullPath, closeMobile);
function onKey(e) { if (e.key === "Escape" && mobileOpen.value) closeMobile(); }
onMounted(() => window.addEventListener("keydown", onKey));
onUnmounted(() => window.removeEventListener("keydown", onKey));
</script>

<style scoped>
/* El layout se maneja desde globals.css:
   - .app es un grid de 2 columnas (sidebar + contenido) centrado en --ancho-app
   - .sidebar es sticky con height:100vh → no scrollea con el body
   - .page centra el contenido en --ancho-contenido
*/
</style>
