<template>
  <div>
    <PageHeader
      eyebrow="Configuración"
      title="Roles y permisos"
      :subtitle="`${roles.length} roles · ${totalPermisos} permisos disponibles`"
    >
      <template #actions>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="cargando ? 'spin' : ''" /> Actualizar
        </button>
        <button class="btn primary" @click="modalNuevo = true"><Plus :size="14" /> Nuevo rol</button>
      </template>
    </PageHeader>

    <div class="roles-grid">
      <!-- Lista de roles -->
      <section class="module-panel">
        <header class="module-panel-head">
          <h2><span class="head-icon"><ShieldCheck :size="14" /></span> Roles</h2>
        </header>
        <div class="module-panel-body roles-lista">
          <button
            v-for="r in roles"
            :key="r.id"
            :class="['rol-item', sel?.id === r.id ? 'activo' : '']"
            @click="seleccionar(r)"
          >
            <div class="grow">
              <strong>{{ r.nombre }}</strong>
              <small class="mono muted">{{ r.codigo }}</small>
            </div>
            <div class="stack text-right">
              <span class="tag">{{ labelScope(r.scope) }}</span>
              <small class="muted">{{ r.usuarios }} usuarios</small>
            </div>
          </button>
        </div>
      </section>

      <!-- Matriz de permisos -->
      <section class="module-panel">
        <header class="module-panel-head">
          <h2>
            <span class="head-icon"><KeySquare :size="14" /></span>
            {{ sel ? `Permisos de ${sel.nombre}` : "Permisos" }}
            <span v-if="sel" class="head-meta">{{ seleccionados.size }} activos</span>
          </h2>
          <div v-if="sel" class="module-panel-head-actions">
            <button class="btn" @click="marcarTodos(false)">Ninguno</button>
            <button class="btn" @click="marcarTodos(true)">Todos</button>
            <button class="btn primary" :disabled="guardando || esSuperAdmin" @click="guardar">
              {{ guardando ? "Guardando…" : "Guardar permisos" }}
            </button>
          </div>
        </header>

        <div v-if="!sel" class="module-panel-body module-empty">
          <div class="empty-icon"><KeySquare :size="22" /></div>
          <h3>Elige un rol</h3>
          <p>Selecciona un rol de la izquierda para ver y editar sus permisos.</p>
        </div>

        <div v-else-if="esSuperAdmin" class="module-panel-body module-empty">
          <div class="empty-icon" style="background: var(--violet-soft); color: var(--violet)">
            <ShieldCheck :size="22" />
          </div>
          <h3>Acceso total</h3>
          <p>
            El super administrador pasa todas las validaciones de permiso por diseño.
            No hay nada que configurar aquí.
          </p>
        </div>

        <div v-else class="module-panel-body permisos">
          <div v-for="mod in permisos" :key="mod.modulo" class="modulo">
            <div class="modulo-head">
              <label class="check-line">
                <input
                  type="checkbox"
                  :checked="todosDelModulo(mod)"
                  :indeterminate.prop="algunoDelModulo(mod) && !todosDelModulo(mod)"
                  @change="alternarModulo(mod, $event.target.checked)"
                />
                <strong>{{ capitalizar(mod.modulo) }}</strong>
              </label>
              <span class="muted">{{ activosDelModulo(mod) }}/{{ mod.permisos.length }}</span>
            </div>
            <div class="modulo-permisos">
              <label v-for="p in mod.permisos" :key="p.codigo" class="check-line">
                <input
                  type="checkbox"
                  :checked="seleccionados.has(p.codigo)"
                  @change="alternar(p.codigo, $event.target.checked)"
                />
                <span>
                  {{ p.descripcion || p.accion }}
                  <small class="mono muted">{{ p.codigo }}</small>
                </span>
              </label>
            </div>
          </div>
        </div>
      </section>
    </div>

    <!-- Nuevo rol -->
    <div v-if="modalNuevo" class="modal-back" @click="modalNuevo = false">
      <div class="modal" @click.stop>
        <div class="m-head"><h3>Nuevo rol</h3></div>
        <div class="m-body">
          <div v-if="error" class="callout danger" style="margin-bottom: 12px">
            <AlertCircle :size="15" /> <span>{{ error }}</span>
          </div>
          <div class="field">
            <label>Nombre <span class="req">*</span></label>
            <input v-model.trim="nuevo.nombre" type="text" placeholder="Auxiliar de clínica" />
          </div>
          <div class="field">
            <label>Código <span class="req">*</span></label>
            <input v-model.trim="nuevo.codigo" type="text" placeholder="auxiliar_clinica" />
          </div>
          <div class="field">
            <label>Alcance</label>
            <select v-model="nuevo.scope">
              <option value="empresa">Una empresa</option>
              <option value="global_restricted">Todas las empresas (solo lectura/operación)</option>
              <option value="global">Todas las empresas (super admin)</option>
            </select>
            <small class="muted">
              Los roles globales no se anclan a una empresa: sus usuarios ven todas.
            </small>
          </div>
          <div class="field">
            <label>Descripción</label>
            <textarea v-model="nuevo.descripcion" rows="2"></textarea>
          </div>
        </div>
        <div class="m-foot modal-actions">
          <button class="btn" @click="modalNuevo = false">Cancelar</button>
          <button class="btn primary" :disabled="guardando" @click="crearRol">
            {{ guardando ? "Creando…" : "Crear rol" }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from "vue";
import { ShieldCheck, KeySquare, Plus, RefreshCw, AlertCircle } from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import { rolesApi } from "../api/roles.api.js";
import { capitalizar } from "../../../shared/components/ui/format.js";
import { notify } from "../../../shared/composables/useNotify.js";

const roles = ref([]);
const permisos = ref([]);
const sel = ref(null);
const seleccionados = ref(new Set());
const cargando = ref(false);
const guardando = ref(false);
const modalNuevo = ref(false);
const error = ref("");

const nuevo = reactive({ nombre: "", codigo: "", scope: "empresa", descripcion: "" });

const totalPermisos = computed(() =>
  permisos.value.reduce((s, m) => s + m.permisos.length, 0),
);
const esSuperAdmin = computed(() => sel.value?.codigo === "super_admin");

function labelScope(s) {
  return { global: "Global", global_restricted: "Global (lectura)", empresa: "Empresa" }[s] || s;
}

function seleccionar(r) {
  sel.value = r;
  seleccionados.value = new Set(r.permisos ?? []);
}

function alternar(codigo, activo) {
  const s = new Set(seleccionados.value);
  if (activo) s.add(codigo);
  else s.delete(codigo);
  seleccionados.value = s;
}

function activosDelModulo(mod) {
  return mod.permisos.filter((p) => seleccionados.value.has(p.codigo)).length;
}
function todosDelModulo(mod) {
  return activosDelModulo(mod) === mod.permisos.length;
}
function algunoDelModulo(mod) {
  return activosDelModulo(mod) > 0;
}
function alternarModulo(mod, activo) {
  const s = new Set(seleccionados.value);
  for (const p of mod.permisos) {
    if (activo) s.add(p.codigo);
    else s.delete(p.codigo);
  }
  seleccionados.value = s;
}
function marcarTodos(activo) {
  if (!activo) { seleccionados.value = new Set(); return; }
  const s = new Set();
  for (const m of permisos.value) for (const p of m.permisos) s.add(p.codigo);
  seleccionados.value = s;
}

async function guardar() {
  guardando.value = true;
  try {
    await rolesApi.setPermisos(sel.value.id, [...seleccionados.value]);
    notify.success("Permisos actualizados");
    await cargar();
    const actualizado = roles.value.find((r) => r.id === sel.value.id);
    if (actualizado) seleccionar(actualizado);
  } catch (e) {
    notify.error("No se pudieron guardar los permisos", e.message);
  } finally {
    guardando.value = false;
  }
}

async function crearRol() {
  error.value = "";
  if (!nuevo.nombre || !nuevo.codigo) { error.value = "Nombre y código son obligatorios."; return; }
  guardando.value = true;
  try {
    await rolesApi.crear({ ...nuevo });
    modalNuevo.value = false;
    Object.assign(nuevo, { nombre: "", codigo: "", scope: "empresa", descripcion: "" });
    cargar();
  } catch (e) {
    error.value = e.message;
  } finally {
    guardando.value = false;
  }
}

async function cargar() {
  cargando.value = true;
  try {
    const [r, p] = await Promise.all([rolesApi.listar(), rolesApi.permisos()]);
    roles.value = r.data ?? [];
    permisos.value = p.data ?? [];
    if (sel.value) {
      const act = roles.value.find((x) => x.id === sel.value.id);
      if (act) seleccionar(act);
    }
  } finally {
    cargando.value = false;
  }
}

onMounted(cargar);
</script>

<style scoped>
.roles-grid { display: grid; grid-template-columns: 320px 1fr; gap: 16px; align-items: start; }
@media (max-width: 900px) { .roles-grid { grid-template-columns: 1fr; } }

.roles-lista { display: flex; flex-direction: column; gap: 2px; padding: 8px; }
.rol-item {
  display: flex; align-items: center; gap: 10px;
  width: 100%; padding: 10px 11px; border-radius: 9px;
  border: 1px solid transparent; background: none; cursor: pointer; text-align: left;
}
.rol-item:hover { background: var(--bg-soft); }
.rol-item.activo { background: var(--emerald-soft); border-color: var(--emerald-line); }
.rol-item strong { display: block; font-size: 13px; color: var(--ink); }
.rol-item small { display: block; font-size: 11px; }

.permisos { display: flex; flex-direction: column; gap: 16px; }
.modulo { border: 1px solid var(--line); border-radius: 11px; overflow: hidden; }
.modulo-head {
  display: flex; justify-content: space-between; align-items: center;
  padding: 9px 12px; background: var(--bg-soft); border-bottom: 1px solid var(--line-soft);
  font-size: 12.5px;
}
.modulo-permisos {
  display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
  gap: 8px 16px; padding: 12px;
}
.check-line { display: inline-flex; align-items: flex-start; gap: 8px; font-size: 12.5px; color: var(--ink-2); cursor: pointer; }
.check-line small { display: block; font-size: 10.5px; }
.req { color: var(--red); }
</style>
