<template>
  <aside :class="['sidebar', isCollapsed ? 'is-collapsed' : '']">
    <div class="brand">
      <div class="brand-logo" aria-hidden="true">
        <PawPrint :size="19" />
      </div>
      <div v-if="!isCollapsed" class="brand-text">
        <div class="brand-name">{{ empresa?.nombre_comercial || "Vet Patitas" }}</div>
        <div class="brand-sub">ERP Veterinario</div>
      </div>
    </div>

    <div class="nav-scroll">
      <div v-for="sec in visibleSections" :key="sec.label">
        <div v-if="!isCollapsed" class="nav-section-label">{{ sec.label }}</div>
        <a
          v-for="it in sec.items"
          :key="it.to"
          :class="['nav-item', esActivo(it.to) ? 'active' : '']"
          :href="it.to"
          :title="isCollapsed ? it.label : ''"
          @click.prevent="$router.push(it.to)"
        >
          <component :is="it.icon" :size="16" class="icon" />
          <span v-if="!isCollapsed" class="label">{{ it.label }}</span>
        </a>
      </div>
    </div>

    <div class="sidebar-foot">
      <div class="avatar" :title="isCollapsed ? user?.nombre : ''">{{ user?.iniciales || "?" }}</div>
      <div v-if="!isCollapsed" class="who">
        <div class="n">{{ user?.nombre }}</div>
        <div class="r">{{ user?.cargo }}</div>
      </div>
    </div>
  </aside>
</template>

<script setup>
import { computed, onMounted, ref } from "vue";
import { useRoute } from "vue-router";
import { PawPrint } from "lucide-vue-next";
import { useAuth } from "../shared/composables/useAuth.js";
import { useSidebar } from "../shared/composables/useSidebar.js";
import { NAV_SECTIONS } from "../shared/config/navigation.js";
import { empresasApi } from "../modules/configuracion/api/empresas.api.js";

const route = useRoute();
const { user: userRef, hasPermission, isSuperAdmin } = useAuth();
const { isCollapsed } = useSidebar();
const user = computed(() => userRef.value);
const empresa = ref(null);

const visibleSections = computed(() =>
  NAV_SECTIONS.map((sec) => ({
    ...sec,
    items: sec.items.filter(
      (it) =>
        (!it.requirePermission || hasPermission(it.requirePermission)) &&
        (!it.requireSuperAdmin || isSuperAdmin.value),
    ),
  })).filter((sec) => sec.items.length > 0),
);

/**
 * Un item queda activo también en sus sub-rutas (/pacientes/:id resalta
 * "Pacientes"), pero /dashboard solo con coincidencia exacta para que no se
 * encienda con cualquier ruta.
 */
function esActivo(to) {
  if (to === "/dashboard") return route.path === to;
  return route.path === to || route.path.startsWith(to + "/");
}

onMounted(async () => {
  try {
    const r = await empresasApi.actual();
    empresa.value = r.data;
  } catch {
    // Un super admin sin sede asignada no rompe el sidebar: se usa el nombre por defecto.
  }
});
</script>

<style scoped>
.sidebar { transition: width 0.2s ease, padding 0.2s ease; }
.sidebar.is-collapsed { padding: 14px 8px; }

.brand-text { flex: 1; min-width: 0; }
.brand-logo { color: #fff; }

.sidebar.is-collapsed .brand { padding: 8px 4px 16px; justify-content: center; }
.sidebar.is-collapsed .brand-logo { margin: 0 auto; }

.nav-scroll {
  flex: 1;
  overflow-y: auto;
  overflow-x: hidden;
  margin-right: -4px;
  padding-right: 4px;
}

.sidebar.is-collapsed .nav-item { justify-content: center; padding: 9px 6px; }
.sidebar.is-collapsed .nav-item .icon { margin: 0; }
.sidebar.is-collapsed .sidebar-foot { justify-content: center; padding: 10px 4px; }
</style>
