<template>
  <div>
    <PageHeader
      eyebrow="Clínica"
      title="Pacientes"
      :subtitle="meta.total ? `${meta.total} pacientes registrados` : 'Fichas clínicas de la cadena'"
    >
      <template #actions>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="cargando ? 'spin' : ''" /> Actualizar
        </button>
        <button v-if="puedeCrear" class="btn primary" @click="abrirNuevo()">
          <Plus :size="14" /> Nuevo paciente
        </button>
      </template>
    </PageHeader>

    <div class="stat-row">
      <div class="stat">
        <div class="stat-label">Pacientes <span class="icon-tile"><PawPrint :size="14" /></span></div>
        <div class="stat-val">{{ meta.total ?? 0 }}<span class="unit">fichas</span></div>
        <div class="stat-meta">en toda la cadena</div>
      </div>
      <div class="stat">
        <div class="stat-label">Con vacuna vencida <span class="icon-tile amber"><Syringe :size="14" /></span></div>
        <div class="stat-val">{{ vacunaVencida }}<span class="unit">en pantalla</span></div>
        <div class="stat-meta">requieren refuerzo</div>
      </div>
      <div class="stat">
        <div class="stat-label">Sin visita reciente <span class="icon-tile violet"><CalendarX :size="14" /></span></div>
        <div class="stat-val">{{ sinVisita }}<span class="unit">+6 meses</span></div>
        <div class="stat-meta">oportunidad de contacto</div>
      </div>
      <div class="stat">
        <div class="stat-label">Con alerta clínica <span class="icon-tile"><AlertTriangle :size="14" /></span></div>
        <div class="stat-val">{{ conAlergia }}<span class="unit">en pantalla</span></div>
        <div class="stat-meta">alergias o crónicos</div>
      </div>
    </div>

    <section class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><PawPrint :size="14" /></span>
          Fichas clínicas
          <span class="head-meta">{{ meta.total ?? pacientes.length }}</span>
        </h2>
      </header>

      <div class="module-panel-toolbar">
        <div class="fil grow">
          <Search :size="14" />
          <input
            v-model="filtros.buscar"
            type="search"
            placeholder="Nombre, código HC, microchip o propietario…"
            @input="debounced"
          />
        </div>
        <div class="fil">
          <PawPrint :size="14" />
          <select v-model="filtros.especieId" @change="recargar">
            <option value="">Todas las especies</option>
            <option v-for="e in especies" :key="e.id" :value="e.id">{{ e.nombre }}</option>
          </select>
        </div>
        <div class="fil">
          <Filter :size="14" />
          <select v-model="filtros.estado" @change="recargar">
            <option value="">Todos los estados</option>
            <option value="activo">Activo</option>
            <option value="inactivo">Inactivo</option>
            <option value="fallecido">Fallecido</option>
            <option value="extraviado">Extraviado</option>
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

      <div v-else-if="!cargando && !pacientes.length" class="module-panel-body module-empty">
        <div class="empty-icon"><PawPrint :size="22" /></div>
        <h3>{{ hayFiltro ? "Sin coincidencias" : "Sin pacientes registrados" }}</h3>
        <p>{{ hayFiltro ? "Ajusta los filtros para ver más resultados." : "Registra el primer paciente de la clínica." }}</p>
        <button v-if="puedeCrear && !hayFiltro" class="btn primary" style="margin-top: 6px" @click="abrirNuevo()">
          <Plus :size="14" /> Nuevo paciente
        </button>
      </div>

      <div v-else class="module-panel-body tabla-wrap">
        <table>
          <thead>
            <tr>
              <th>Paciente</th>
              <th>Propietario</th>
              <th>Edad</th>
              <th class="num">Peso</th>
              <th>Última visita</th>
              <th>Próxima vacuna</th>
              <th>Estado</th>
              <th class="acciones-col"></th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="p in pacientes"
              :key="p.id"
              class="clickable"
              @click="$router.push(`/pacientes/${p.id}`)"
            >
              <td>
                <div class="entidad-cell">
                  <div class="avatar-sm">
                    <img v-if="p.foto_url" :src="p.foto_url" :alt="p.nombre" />
                    <template v-else>{{ iniciales(p.nombre) }}</template>
                  </div>
                  <div class="info">
                    <strong>
                      {{ p.nombre }}
                      <AlertTriangle
                        v-if="p.alergias || p.condiciones_cronicas"
                        :size="12"
                        class="alerta-icono"
                        :title="p.alergias || p.condiciones_cronicas"
                      />
                    </strong>
                    <small>{{ p.especie }}{{ p.raza ? ` · ${p.raza}` : "" }} · {{ sexoLabel(p.sexo) }}</small>
                  </div>
                </div>
              </td>
              <td>
                <div class="stack">
                  <span>{{ p.propietario }}</span>
                  <small class="muted mono">{{ p.propietario_telefono || "—" }}</small>
                </div>
              </td>
              <td>{{ p.edad?.texto || "—" }}</td>
              <td class="num mono">{{ p.peso_kg ? `${p.peso_kg} kg` : "—" }}</td>
              <td>
                <span v-if="p.ultima_visita" :title="fmtFechaHora(p.ultima_visita)">
                  {{ fmtRelativo(p.ultima_visita) }}
                </span>
                <span v-else class="muted">Nunca</span>
              </td>
              <td>
                <span v-if="!p.proxima_vacuna" class="muted">—</span>
                <span
                  v-else
                  :class="['estado-pill', vencida(p.proxima_vacuna) ? 'danger' : 'info']"
                >
                  {{ fmtDate(p.proxima_vacuna) }}
                </span>
              </td>
              <td>
                <span :class="['estado-pill', toneEstado(p.estado)]">
                  <span class="dot"></span>{{ capitalizar(p.estado) }}
                </span>
              </td>
              <td class="acciones-col" @click.stop>
                <div class="row-actions">
                  <button class="btn mini" title="Ver ficha" @click="$router.push(`/pacientes/${p.id}`)">
                    <FileText :size="13" />
                  </button>
                  <button v-if="puedeEditar" class="btn mini" title="Editar" @click="abrirEditar(p)">
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

    <PacienteModal
      v-if="modal"
      :paciente="editando"
      :especies="especies"
      @close="modal = false"
      @guardado="onGuardado"
    />
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from "vue";
import {
  PawPrint, Search, Plus, RefreshCw, Loader2, AlertCircle, AlertTriangle,
  Filter, FileText, Pencil, Syringe, CalendarX,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import PacienteModal from "../components/PacienteModal.vue";
import { mascotasApi } from "../api/mascotas.api.js";
import { catalogosApi } from "../../catalogos/api/catalogos.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { fmtDate } from "../../../shared/components/ui/format.js";
import { fmtFechaHora, fmtRelativo, capitalizar, iniciales } from "../../../shared/components/ui/format.js";

const { hasPermission } = useAuth();
const puedeCrear = computed(() => hasPermission("mascotas:crear"));
const puedeEditar = computed(() => hasPermission("mascotas:editar"));

const pacientes = ref([]);
const especies = ref([]);
const meta = ref({});
const cargando = ref(false);
const error = ref("");
const modal = ref(false);
const editando = ref(null);
const filtros = reactive({ buscar: "", especieId: "", estado: "activo", page: 1 });

const hayFiltro = computed(() => !!filtros.buscar || !!filtros.especieId || filtros.estado !== "activo");

const vacunaVencida = computed(
  () => pacientes.value.filter((p) => p.proxima_vacuna && vencida(p.proxima_vacuna)).length,
);
const conAlergia = computed(
  () => pacientes.value.filter((p) => p.alergias || p.condiciones_cronicas).length,
);
const sinVisita = computed(() => {
  const limite = new Date();
  limite.setMonth(limite.getMonth() - 6);
  return pacientes.value.filter((p) => !p.ultima_visita || new Date(p.ultima_visita) < limite).length;
});

function vencida(f) { return new Date(f) < new Date(); }
function sexoLabel(s) { return { macho: "Macho", hembra: "Hembra" }[s] || "Sexo no registrado"; }
function toneEstado(e) {
  return { activo: "ok", inactivo: "neutral", fallecido: "neutral", extraviado: "danger" }[e] || "neutral";
}

let timer = null;
function debounced() {
  clearTimeout(timer);
  timer = setTimeout(recargar, 350);
}
function recargar() {
  filtros.page = 1;
  cargar();
}
function irPagina(p) {
  filtros.page = p;
  cargar();
}
function limpiar() {
  filtros.buscar = "";
  filtros.especieId = "";
  filtros.estado = "activo";
  recargar();
}

function abrirNuevo() {
  editando.value = null;
  modal.value = true;
}
function abrirEditar(p) {
  editando.value = p;
  modal.value = true;
}
function onGuardado() {
  modal.value = false;
  cargar();
}

async function cargar() {
  cargando.value = true;
  error.value = "";
  try {
    const r = await mascotasApi.listar({
      buscar: filtros.buscar || undefined,
      especieId: filtros.especieId || undefined,
      estado: filtros.estado || undefined,
      page: filtros.page,
      pageSize: 20,
    });
    pacientes.value = r.data ?? [];
    meta.value = r.meta ?? {};
  } catch (e) {
    error.value = e.message;
  } finally {
    cargando.value = false;
  }
}

onMounted(async () => {
  try {
    const e = await catalogosApi.especies();
    especies.value = e.data ?? [];
  } catch {
    // El filtro por especie es accesorio: la lista funciona sin él.
  }
  cargar();
});
</script>

<style scoped>
.alerta-icono { color: var(--red); vertical-align: -1px; margin-left: 3px; }
.btn.mini { height: 26px; padding: 0 8px; font-size: 11.5px; }
</style>
