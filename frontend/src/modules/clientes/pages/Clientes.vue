<template>
  <div>
    <PageHeader
      eyebrow="Clínica"
      title="Propietarios"
      :subtitle="meta.total ? `${meta.total} propietarios en la cartera` : 'Cartera compartida entre sedes'"
    >
      <template #actions>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="cargando ? 'spin' : ''" /> Actualizar
        </button>
        <button v-if="puedeCrear" class="btn primary" @click="abrirNuevo()">
          <Plus :size="14" /> Nuevo propietario
        </button>
      </template>
    </PageHeader>

    <div class="stat-row">
      <div class="stat">
        <div class="stat-label">Propietarios <span class="icon-tile"><Users :size="14" /></span></div>
        <div class="stat-val">{{ meta.total ?? 0 }}<span class="unit">registrados</span></div>
        <div class="stat-meta">cartera de la cadena</div>
      </div>
      <div class="stat">
        <div class="stat-label">Mascotas vinculadas <span class="icon-tile"><PawPrint :size="14" /></span></div>
        <div class="stat-val">{{ totalMascotas }}<span class="unit">en pantalla</span></div>
        <div class="stat-meta"><span class="trend">{{ promedioMascotas }}</span> por propietario</div>
      </div>
      <div class="stat">
        <div class="stat-label">Con deuda <span class="icon-tile amber"><CreditCard :size="14" /></span></div>
        <div class="stat-val">{{ conDeuda }}<span class="unit">en pantalla</span></div>
        <div class="stat-meta">{{ fmtSoles(deudaTotal) }} pendiente</div>
      </div>
      <div class="stat">
        <div class="stat-label">Con portal activo <span class="icon-tile violet"><Globe :size="14" /></span></div>
        <div class="stat-val">{{ conPortal }}<span class="unit">en pantalla</span></div>
        <div class="stat-meta">acceso a su historial</div>
      </div>
    </div>

    <section class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><Users :size="14" /></span>
          Directorio
          <span class="head-meta">{{ meta.total ?? clientes.length }}</span>
        </h2>
      </header>

      <div class="module-panel-toolbar">
        <div class="fil grow">
          <Search :size="14" />
          <input
            v-model="filtros.buscar"
            type="search"
            placeholder="Nombre, documento, teléfono o nombre de la mascota…"
            @input="debounced"
          />
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
        <span v-if="hayFiltro" class="chip-filter" @click="limpiar">Limpiar <span class="x">×</span></span>
        <div class="toolbar-spacer"></div>
        <span v-if="cargando" class="loading-mini"><Loader2 :size="13" class="spin" /> Cargando…</span>
      </div>

      <div v-if="error" class="module-panel-body module-empty">
        <div class="empty-icon" style="background: var(--red-soft); color: var(--red-ink)">
          <AlertCircle :size="22" />
        </div>
        <h3>Algo salió mal</h3>
        <p>{{ error }}</p>
      </div>

      <div v-else-if="!cargando && !clientes.length" class="module-panel-body module-empty">
        <div class="empty-icon"><Users :size="22" /></div>
        <h3>{{ hayFiltro ? "Sin coincidencias" : "Sin propietarios registrados" }}</h3>
        <p>{{ hayFiltro ? "Ajusta los filtros para ver más resultados." : "Registra el primer propietario de la clínica." }}</p>
      </div>

      <div v-else class="module-panel-body tabla-wrap">
        <table>
          <thead>
            <tr>
              <th>Propietario</th>
              <th>Documento</th>
              <th>Contacto</th>
              <th>Mascotas</th>
              <th>Última visita</th>
              <th class="num">Deuda</th>
              <th>Estado</th>
              <th class="acciones-col"></th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="c in clientes"
              :key="c.id"
              class="clickable"
              @click="$router.push(`/clientes/${c.id}`)"
            >
              <td>
                <div class="entidad-cell">
                  <div class="avatar-sm">{{ iniciales(c.nombre_completo) }}</div>
                  <div class="info">
                    <strong>{{ c.nombre_completo }}</strong>
                    <small v-if="c.correo">{{ c.correo }}</small>
                  </div>
                </div>
              </td>
              <td class="mono">{{ c.tipo_documento }} {{ c.numero_documento }}</td>
              <td class="mono">{{ c.telefono || "—" }}</td>
              <td>
                <div class="mascotas-chips">
                  <span v-for="m in c.mascotas.slice(0, 3)" :key="m.id" class="tag">{{ m.nombre }}</span>
                  <span v-if="c.total_mascotas > 3" class="tag">+{{ c.total_mascotas - 3 }}</span>
                  <span v-if="!c.total_mascotas" class="muted">Sin mascotas</span>
                </div>
              </td>
              <td>
                <span v-if="c.ultima_visita" :title="fmtFechaHora(c.ultima_visita)">
                  {{ fmtRelativo(c.ultima_visita) }}
                </span>
                <span v-else class="muted">Nunca</span>
              </td>
              <td class="num mono">
                <span :class="Number(c.deuda_pendiente) > 0 ? 'deuda' : 'muted'">
                  {{ fmtSoles(c.deuda_pendiente) }}
                </span>
              </td>
              <td>
                <span :class="['estado-pill', c.estado === 'activo' ? 'ok' : 'neutral']">
                  <span class="dot"></span>{{ capitalizar(c.estado) }}
                </span>
                <span v-if="c.portal_acceso" class="estado-pill violet" style="margin-left: 4px" title="Con acceso al portal">
                  <Globe :size="10" />
                </span>
              </td>
              <td class="acciones-col" @click.stop>
                <div class="row-actions">
                  <button class="btn mini" title="Ver ficha" @click="$router.push(`/clientes/${c.id}`)">
                    <FileText :size="13" />
                  </button>
                  <button v-if="puedeEditar" class="btn mini" title="Editar" @click="abrirEditar(c)">
                    <Pencil :size="13" />
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

    <ClienteModal
      v-if="modal"
      :cliente="editando"
      @close="modal = false"
      @guardado="onGuardado"
    />
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from "vue";
import {
  Users, PawPrint, Search, Plus, RefreshCw, Loader2, AlertCircle, Filter,
  FileText, Pencil, CreditCard, Globe,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import ClienteModal from "../components/ClienteModal.vue";
import { clientesApi } from "../api/clientes.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { fmtSoles } from "../../../shared/components/ui/format.js";
import { fmtFechaHora, fmtRelativo, capitalizar, iniciales } from "../../../shared/components/ui/format.js";

const { hasPermission } = useAuth();
const puedeCrear = computed(() => hasPermission("clientes:crear"));
const puedeEditar = computed(() => hasPermission("clientes:editar"));

const clientes = ref([]);
const meta = ref({});
const cargando = ref(false);
const error = ref("");
const modal = ref(false);
const editando = ref(null);
const filtros = reactive({ buscar: "", estado: "", page: 1 });

const hayFiltro = computed(() => !!filtros.buscar || !!filtros.estado);
const totalMascotas = computed(() => clientes.value.reduce((s, c) => s + Number(c.total_mascotas), 0));
const promedioMascotas = computed(() =>
  clientes.value.length ? (totalMascotas.value / clientes.value.length).toFixed(1) : "0",
);
const conDeuda = computed(() => clientes.value.filter((c) => Number(c.deuda_pendiente) > 0).length);
const deudaTotal = computed(() => clientes.value.reduce((s, c) => s + Number(c.deuda_pendiente), 0));
const conPortal = computed(() => clientes.value.filter((c) => c.portal_acceso).length);

let timer = null;
function debounced() {
  clearTimeout(timer);
  timer = setTimeout(recargar, 350);
}
function recargar() { filtros.page = 1; cargar(); }
function irPagina(p) { filtros.page = p; cargar(); }
function limpiar() { filtros.buscar = ""; filtros.estado = ""; recargar(); }

function abrirNuevo() { editando.value = null; modal.value = true; }
function abrirEditar(c) { editando.value = c; modal.value = true; }
function onGuardado() { modal.value = false; cargar(); }

async function cargar() {
  cargando.value = true;
  error.value = "";
  try {
    const r = await clientesApi.listar({
      buscar: filtros.buscar || undefined,
      estado: filtros.estado || undefined,
      page: filtros.page,
      pageSize: 20,
    });
    clientes.value = r.data ?? [];
    meta.value = r.meta ?? {};
  } catch (e) {
    error.value = e.message;
  } finally {
    cargando.value = false;
  }
}

onMounted(cargar);
</script>

<style scoped>
.mascotas-chips { display: flex; flex-wrap: wrap; gap: 4px; }
.deuda { color: var(--red-ink); font-weight: 600; }
.btn.mini { height: 26px; padding: 0 8px; font-size: 11.5px; }
</style>
