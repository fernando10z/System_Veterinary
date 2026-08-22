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
   - .sidebar es position:fixed → no scrollea con el body
   - .main lleva margin-left para hacerle espacio (244px / 64px collapsed)
*/
</style>
