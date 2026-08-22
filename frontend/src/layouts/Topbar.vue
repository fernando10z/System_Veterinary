<template>
  <div class="topbar">
    <button
      class="icon-btn sidebar-toggle"
      :title="isCollapsed ? 'Expandir menú' : 'Contraer menú'"
      :aria-label="isCollapsed ? 'Expandir menú' : 'Contraer menú'"
      @click="toggleSidebar"
    >
      <PanelLeftOpen v-if="isCollapsed" :size="16" />
      <PanelLeftClose v-else :size="16" />
    </button>

    <div class="crumbs">
      <span v-for="(c, i) in crumbs" :key="i" class="crumb-wrap">
        <span v-if="i > 0" class="sep"><ChevronRight :size="12" /></span>
        <router-link v-if="c.to" :to="c.to" class="c">{{ c.label }}</router-link>
        <span v-else :class="['c', i === crumbs.length - 1 ? 'current' : '']">{{ c.label }}</span>
      </span>
    </div>

    <div class="spacer" />

    <!-- Caja abierta: el cajero necesita verlo sin entrar al módulo -->
    <router-link v-if="caja" to="/caja" class="caja-chip" title="Tienes una caja abierta">
      <Wallet :size="13" />
      <span class="mono">{{ fmtSoles(caja.efectivo + Number(caja.monto_apertura || 0)) }}</span>
    </router-link>

    <div ref="notiRoot" class="noti-wrap">
      <button class="icon-btn" aria-label="Notificaciones" @click="toggleNotis">
        <Bell :size="15" />
        <span v-if="noLeidas > 0" class="noti-dot">{{ noLeidas > 9 ? "9+" : noLeidas }}</span>
      </button>
      <Transition name="pop">
        <div v-if="notisOpen" class="pop-menu noti-menu">
          <div class="pop-head">
            <span>Notificaciones</span>
            <button v-if="noLeidas > 0" class="link-mini" @click="marcarTodas">
              Marcar todas
            </button>
          </div>
          <div v-if="!notis.length" class="pop-empty">Sin notificaciones</div>
          <button
            v-for="n in notis"
            :key="n.id"
            :class="['noti-item', n.leida_at ? '' : 'unread']"
            @click="abrirNoti(n)"
          >
            <div class="t">{{ n.titulo }}</div>
            <div v-if="n.cuerpo" class="b">{{ n.cuerpo }}</div>
            <div class="f">{{ fmtFechaHora(n.created_at) }}</div>
          </button>
        </div>
      </Transition>
    </div>

    <button
      class="icon-btn theme-btn"
      :aria-label="isDark ? 'Activar modo claro' : 'Activar modo oscuro'"
      :title="isDark ? 'Modo claro' : 'Modo oscuro'"
      @click="toggle"
    >
      <Transition name="theme-swap" mode="out-in">
        <Sun v-if="!isDark" key="sun" :size="15" />
        <Moon v-else key="moon" :size="15" />
      </Transition>
    </button>

    <div ref="userRoot" class="user-wrap">
      <button
        class="topbar-avatar"
        aria-label="Menú de usuario"
        :aria-expanded="userOpen"
        @click="userOpen = !userOpen"
      >
        {{ user?.iniciales || "?" }}
      </button>
      <Transition name="pop">
        <div v-if="userOpen" class="pop-menu user-menu">
          <div class="user-info">
            <div class="user-avatar-lg">{{ user?.iniciales || "?" }}</div>
            <div class="user-meta">
              <div class="user-name">{{ user?.nombre }}</div>
              <div class="user-role">{{ user?.cargo }}</div>
            </div>
          </div>
          <div class="user-sep" />
          <button class="user-action" @click="irACambiarPassword">
            <KeyRound :size="14" /> Cambiar contraseña
          </button>
          <button class="user-action danger" @click="handleLogout">
            <LogOut :size="14" /> Cerrar sesión
          </button>
        </div>
      </Transition>
    </div>
  </div>
</template>

<script setup>
import { computed, ref, onMounted, onBeforeUnmount } from "vue";
import { useRoute, useRouter } from "vue-router";
import {
  Sun, Moon, ChevronRight, PanelLeftClose, PanelLeftOpen, LogOut,
  Bell, Wallet, KeyRound,
} from "lucide-vue-next";
import { useAuth } from "../shared/composables/useAuth.js";
import { useTheme } from "../shared/composables/useTheme.js";
import { useSidebar } from "../shared/composables/useSidebar.js";
import { NAV_SECTIONS } from "../shared/config/navigation.js";
import { notificacionesApi } from "../modules/auditoria/api/auditoria.api.js";
import { cajaApi } from "../modules/pagos/api/pagos.api.js";
import { fmtSoles, fmtFechaHora } from "../shared/components/ui/format.js";

const route = useRoute();
const router = useRouter();
const { user: userRef, logout, hasPermission } = useAuth();
const { theme, toggle } = useTheme();
const { isCollapsed, toggle: toggleSidebar } = useSidebar();

const user = computed(() => userRef.value);
const isDark = computed(() => theme.value === "dark");

/** Etiquetas legibles a partir del propio menú: una sola fuente de verdad. */
const RUTA_LABEL = Object.fromEntries(
  NAV_SECTIONS.flatMap((s) => s.items.map((i) => [i.to, i.label])),
);

const crumbs = computed(() => {
  const path = route.path;
  const base = Object.keys(RUTA_LABEL)
    .filter((k) => path === k || path.startsWith(k + "/"))
    .sort((a, b) => b.length - a.length)[0];

  const out = [{ label: "Panel", to: path === "/dashboard" ? undefined : "/dashboard" }];
  if (!base || base === "/dashboard") return out;

  const enDetalle = path !== base;
  out.push({ label: RUTA_LABEL[base], to: enDetalle ? base : undefined });
  if (enDetalle) out.push({ label: route.meta?.titulo || "Detalle" });
  return out;
});

// ---- notificaciones ----
const notis = ref([]);
const noLeidas = ref(0);
const notisOpen = ref(false);
const notiRoot = ref(null);
let timer = null;

async function cargarNotis() {
  try {
    const r = await notificacionesApi.listar({ limit: 15 });
    notis.value = r.data ?? [];
    noLeidas.value = r.meta?.no_leidas ?? 0;
  } catch {
    // La bandeja es accesoria: si falla, la topbar sigue usable.
  }
}
function toggleNotis() {
  notisOpen.value = !notisOpen.value;
  if (notisOpen.value) cargarNotis();
}
async function marcarTodas() {
  await notificacionesApi.marcarTodas();
  cargarNotis();
}
async function abrirNoti(n) {
  if (!n.leida_at) await notificacionesApi.marcarLeida(n.id);
  notisOpen.value = false;
  if (n.url) router.push(n.url);
  cargarNotis();
}

// ---- caja abierta ----
const caja = ref(null);
async function cargarCaja() {
  if (!hasPermission("caja:operar") && !hasPermission("caja:ver")) return;
  try {
    const r = await cajaApi.actual();
    caja.value = r.data;
  } catch {
    caja.value = null;
  }
}

// ---- menú de usuario ----
const userRoot = ref(null);
const userOpen = ref(false);

function handleLogout() {
  userOpen.value = false;
  logout();
  router.replace("/login");
}
function irACambiarPassword() {
  userOpen.value = false;
  router.push("/cambiar-password");
}

function onClickFuera(e) {
  if (userOpen.value && userRoot.value && !userRoot.value.contains(e.target)) userOpen.value = false;
  if (notisOpen.value && notiRoot.value && !notiRoot.value.contains(e.target)) notisOpen.value = false;
}

onMounted(() => {
  document.addEventListener("click", onClickFuera);
  cargarNotis();
  cargarCaja();
  // Refresco periódico: la caja y las notificaciones cambian mientras se trabaja.
  timer = setInterval(() => { cargarNotis(); cargarCaja(); }, 60_000);
});
onBeforeUnmount(() => {
  document.removeEventListener("click", onClickFuera);
  if (timer) clearInterval(timer);
});
</script>

<style scoped>
.crumb-wrap { display: inline-flex; align-items: center; gap: 8px; }
.sidebar-toggle { color: var(--ink-3); flex-shrink: 0; }
.sidebar-toggle:hover { color: var(--ink); }

.theme-btn :deep(svg) { transition: color 0.2s ease; }
.theme-swap-enter-active, .theme-swap-leave-active { transition: opacity 0.18s ease, transform 0.18s ease; }
.theme-swap-enter-from { opacity: 0; transform: rotate(-45deg) scale(0.6); }
.theme-swap-leave-to { opacity: 0; transform: rotate(45deg) scale(0.6); }

/* ---- chip de caja abierta ---- */
.caja-chip {
  display: inline-flex; align-items: center; gap: 6px;
  padding: 5px 10px; border-radius: 999px;
  background: var(--emerald-soft); color: var(--emerald-ink);
  border: 1px solid var(--emerald-line);
  font-size: 12px; font-weight: 600; text-decoration: none;
}
.caja-chip:hover { background: var(--emerald-soft-2); }

/* ---- popovers ---- */
.noti-wrap, .user-wrap { position: relative; display: inline-flex; }
.noti-dot {
  position: absolute; top: 2px; right: 2px;
  min-width: 15px; height: 15px; padding: 0 3px;
  border-radius: 999px; background: var(--red); color: #fff;
  font-size: 9px; font-weight: 700; line-height: 15px; text-align: center;
}
.pop-menu {
  position: absolute; top: calc(100% + 8px); right: 0;
  background: var(--bg-elev); border: 1px solid var(--line);
  border-radius: 12px; box-shadow: var(--shadow-pop);
  overflow: hidden; z-index: 200; padding: 6px;
}
.noti-menu { width: 320px; max-height: 420px; overflow-y: auto; }
.user-menu { width: 240px; }

.pop-head {
  display: flex; justify-content: space-between; align-items: center;
  padding: 6px 8px 8px; font-size: 12px; font-weight: 600; color: var(--ink-2);
}
.link-mini {
  background: none; border: none; padding: 0; cursor: pointer;
  color: var(--emerald-deep); font-size: 11px; font-weight: 600;
}
.pop-empty { padding: 18px 10px; text-align: center; color: var(--ink-3); font-size: 12.5px; }

.noti-item {
  display: block; width: 100%; text-align: left;
  padding: 8px 10px; border: none; background: none; border-radius: 8px; cursor: pointer;
}
.noti-item:hover { background: var(--bg-soft); }
.noti-item.unread { background: var(--emerald-soft); }
.noti-item .t { font-size: 12.5px; font-weight: 600; color: var(--ink); }
.noti-item .b { font-size: 11.5px; color: var(--ink-3); margin-top: 2px; }
.noti-item .f { font-size: 10.5px; color: var(--ink-4); margin-top: 3px; }

.user-info { display: flex; align-items: center; gap: 10px; padding: 8px 8px 10px; }
.user-avatar-lg {
  flex: 0 0 auto; width: 38px; height: 38px; border-radius: 999px;
  background: var(--emerald); display: grid; place-items: center;
  color: #fff; font-weight: 600; font-size: 13px;
}
.user-meta { min-width: 0; }
.user-name { font-size: 13px; font-weight: 600; color: var(--ink); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.user-role { font-size: 11.5px; color: var(--ink-3); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.user-sep { height: 1px; background: var(--line); margin: 2px 0 6px; }
.user-action {
  width: 100%; display: flex; align-items: center; gap: 9px;
  padding: 9px 10px; background: none; border: none; border-radius: 8px;
  cursor: pointer; font-size: 13px; color: var(--ink-2); text-align: left;
}
.user-action:hover { background: var(--bg-soft); }
.user-action.danger { color: var(--red-ink); }
.user-action.danger:hover { background: var(--red-soft); }

.pop-enter-active, .pop-leave-active { transition: opacity 0.14s ease, transform 0.14s ease; }
.pop-enter-from, .pop-leave-to { opacity: 0; transform: translateY(-4px) scale(0.98); }
</style>
