<template>
  <div>
    <PageHeader
      eyebrow="Configuración"
      title="Usuarios"
      :subtitle="meta.total ? `${meta.total} cuentas del sistema` : 'Personal con acceso al ERP'"
    >
      <template #actions>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="cargando ? 'spin' : ''" /> Actualizar
        </button>
        <button v-if="puedeCrear" class="btn primary" @click="abrirNuevo()">
          <UserPlus :size="14" /> Nuevo usuario
        </button>
      </template>
    </PageHeader>

    <div class="stat-row">
      <div class="stat">
        <div class="stat-label">Cuentas <span class="icon-tile"><Users :size="14" /></span></div>
        <div class="stat-val">{{ meta.total ?? 0 }}<span class="unit">usuarios</span></div>
        <div class="stat-meta"><span class="trend">{{ activos }} activos</span> en pantalla</div>
      </div>
      <div class="stat">
        <div class="stat-label">Veterinarios <span class="icon-tile"><Stethoscope :size="14" /></span></div>
        <div class="stat-val">{{ vets }}<span class="unit">colegiados</span></div>
        <div class="stat-meta">pueden firmar historia clínica</div>
      </div>
      <div class="stat">
        <div class="stat-label">Inactivos <span class="icon-tile amber"><UserX :size="14" /></span></div>
        <div class="stat-val">{{ inactivos }}<span class="unit">sin acceso</span></div>
        <div class="stat-meta">requieren revisión</div>
      </div>
      <div class="stat">
        <div class="stat-label">Roles <span class="icon-tile violet"><ShieldCheck :size="14" /></span></div>
        <div class="stat-val">{{ roles.length }}<span class="unit">definidos</span></div>
        <div class="stat-meta">perfiles de acceso</div>
      </div>
    </div>

    <section class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><Users :size="14" /></span>
          Cuentas y accesos
          <span class="head-meta">{{ meta.total ?? usuarios.length }}</span>
        </h2>
      </header>

      <div class="module-panel-toolbar">
        <div class="fil grow">
          <Search :size="14" />
          <input v-model="filtros.buscar" type="search" placeholder="Nombre, correo o documento…" @input="debounced" />
        </div>
        <div class="fil">
          <Filter :size="14" />
          <select v-model="filtros.estado" @change="recargar">
            <option value="">Todos los estados</option>
            <option value="activo">Activo</option>
            <option value="inactivo">Inactivo</option>
            <option value="bloqueado">Bloqueado</option>
          </select>
        </div>
        <div class="fil">
          <ShieldCheck :size="14" />
          <select v-model="filtros.rolId" @change="recargar">
            <option value="">Todos los roles</option>
            <option v-for="r in roles" :key="r.id" :value="r.id">{{ r.nombre }}</option>
          </select>
        </div>
        <div class="toolbar-spacer"></div>
        <span v-if="cargando" class="loading-mini"><Loader2 :size="13" class="spin" /> Cargando…</span>
      </div>

      <div v-if="!cargando && !usuarios.length" class="module-panel-body module-empty">
        <div class="empty-icon"><Users :size="22" /></div>
        <h3>Sin usuarios</h3>
        <p>Crea la primera cuenta de acceso al sistema.</p>
      </div>

      <div v-else class="module-panel-body tabla-wrap">
        <table>
          <thead>
            <tr>
              <th>Usuario</th><th>Correo</th><th>Rol</th><th>Sede</th>
              <th>Último acceso</th><th>Estado</th><th class="acciones-col"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="u in usuarios" :key="u.id">
              <td>
                <div class="entidad-cell">
                  <div class="avatar-sm" :style="u.color_agenda ? { background: u.color_agenda, color: '#fff' } : {}">
                    {{ iniciales(`${u.nombres} ${u.apellido_paterno}`) }}
                  </div>
                  <div class="info">
                    <strong>
                      {{ u.nombres }} {{ u.apellido_paterno }}
                      <Stethoscope v-if="u.es_veterinario" :size="11" class="ico-vet" title="Veterinario colegiado" />
                    </strong>
                    <small class="mono">{{ u.tipo_documento }} {{ u.numero_documento }}</small>
                  </div>
                </div>
              </td>
              <td>
                <div class="stack">
                  <span>{{ u.email }}</span>
                  <small class="muted mono">{{ u.telefono || "—" }}</small>
                </div>
              </td>
              <td>
                <span class="tag">{{ u.rol_nombre || "Sin rol" }}</span>
                <span v-if="u.is_super_admin" class="estado-pill violet" style="margin-left: 4px">
                  <ShieldCheck :size="10" /> super
                </span>
              </td>
              <td class="muted">{{ u.empresa_nombre || "Todas las sedes" }}</td>
              <td class="muted mono">{{ u.ultimo_login_at ? fmtFechaHora(u.ultimo_login_at) : "Nunca" }}</td>
              <td>
                <span :class="['estado-pill', toneEstado(u.estado)]">
                  <span class="dot"></span>{{ capitalizar(u.estado) }}
                </span>
              </td>
              <td class="acciones-col">
                <div class="row-actions">
                  <button v-if="puedeEditar" class="btn mini" title="Editar" @click="abrirEditar(u)">
                    <Pencil :size="13" />
                  </button>
                  <button v-if="puedeEditar" class="btn mini" title="Reiniciar contraseña" @click="resetPassword(u)">
                    <KeyRound :size="13" />
                  </button>
                  <button
                    v-if="puedeEditar"
                    class="btn mini"
                    :title="u.estado === 'activo' ? 'Desactivar' : 'Activar'"
                    @click="alternarEstado(u)"
                  >
                    <component :is="u.estado === 'activo' ? UserX : UserCheck" :size="13" />
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div v-if="meta.pages > 1" class="module-panel-foot">
        <span class="muted">Página {{ meta.page }} de {{ meta.pages }}</span>
        <div class="wrap-actions">
          <button class="btn" :disabled="meta.page <= 1" @click="irPagina(meta.page - 1)">Anterior</button>
          <button class="btn" :disabled="meta.page >= meta.pages" @click="irPagina(meta.page + 1)">Siguiente</button>
        </div>
      </div>
    </section>

    <UsuarioModal
      v-if="modal"
      :usuario="editando"
      :roles="roles"
      :especializaciones="especializaciones"
      :empresas="empresas"
      @close="modal = false"
      @guardado="onGuardado"
    />
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from "vue";
import {
  Users, UserPlus, UserX, UserCheck, Search, RefreshCw, Loader2, Filter,
  Pencil, KeyRound, ShieldCheck, Stethoscope,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import UsuarioModal from "../components/UsuarioModal.vue";
import { usersApi } from "../api/users.api.js";
import { rolesApi } from "../../roles/api/roles.api.js";
import { catalogosApi } from "../../catalogos/api/catalogos.api.js";
import { empresasApi } from "../../configuracion/api/empresas.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { fmtFechaHora, capitalizar, iniciales } from "../../../shared/components/ui/format.js";
import { notify } from "../../../shared/composables/useNotify.js";

const { hasPermission } = useAuth();
const puedeCrear = computed(() => hasPermission("usuarios:crear"));
const puedeEditar = computed(() => hasPermission("usuarios:editar"));

const usuarios = ref([]);
const roles = ref([]);
const especializaciones = ref([]);
const empresas = ref([]);
const meta = ref({});
const cargando = ref(false);
const modal = ref(false);
const editando = ref(null);
const filtros = reactive({ buscar: "", estado: "", rolId: "", page: 1 });

const activos = computed(() => usuarios.value.filter((u) => u.estado === "activo").length);
const inactivos = computed(() => usuarios.value.filter((u) => u.estado !== "activo").length);
const vets = computed(() => usuarios.value.filter((u) => u.es_veterinario).length);

function toneEstado(e) {
  return { activo: "ok", inactivo: "neutral", bloqueado: "danger", solicitud: "warn" }[e] || "neutral";
}

let timer = null;
function debounced() { clearTimeout(timer); timer = setTimeout(recargar, 350); }
function recargar() { filtros.page = 1; cargar(); }
function irPagina(p) { filtros.page = p; cargar(); }

function abrirNuevo() { editando.value = null; modal.value = true; }
function abrirEditar(u) { editando.value = u; modal.value = true; }
function onGuardado() { modal.value = false; cargar(); }

async function alternarEstado(u) {
  const nuevo = u.estado === "activo" ? "inactivo" : "activo";
  const ok = await notify.confirm(
    nuevo === "inactivo" ? `¿Desactivar a ${u.nombres}?` : `¿Activar a ${u.nombres}?`,
    nuevo === "inactivo" ? "Se cerrarán sus sesiones activas." : "Podrá volver a ingresar al sistema.",
  );
  if (!ok) return;
  try {
    await usersApi.cambiarEstado(u.id, nuevo);
    cargar();
  } catch (e) {
    notify.error("No se pudo cambiar el estado", e.message);
  }
}

async function resetPassword(u) {
  const temp = await notify.prompt(`Nueva contraseña para ${u.nombres}`, {
    text: "El usuario deberá cambiarla al ingresar.",
    placeholder: "Mínimo 8 caracteres",
  });
  if (!temp) return;
  try {
    await usersApi.resetPassword(u.id, temp);
    notify.success("Contraseña reiniciada", "Comunícasela al usuario por un canal seguro.");
  } catch (e) {
    notify.error("No se pudo reiniciar", e.message);
  }
}

async function cargar() {
  cargando.value = true;
  try {
    const r = await usersApi.listar({
      buscar: filtros.buscar || undefined,
      estado: filtros.estado || undefined,
      rolId: filtros.rolId || undefined,
      page: filtros.page,
      pageSize: 20,
    });
    usuarios.value = r.data ?? [];
    meta.value = r.meta ?? {};
  } finally {
    cargando.value = false;
  }
}

onMounted(async () => {
  const [rl, es, em] = await Promise.allSettled([
    rolesApi.listar(),
    catalogosApi.especializaciones(),
    empresasApi.listar(),
  ]);
  if (rl.status === "fulfilled") roles.value = rl.value.data ?? [];
  if (es.status === "fulfilled") especializaciones.value = es.value.data ?? [];
  if (em.status === "fulfilled") empresas.value = em.value.data ?? [];
  cargar();
});
</script>

<style scoped>
.ico-vet { color: var(--emerald); vertical-align: -1px; margin-left: 3px; }
.btn.mini { height: 26px; padding: 0 8px; font-size: 11.5px; }
</style>
