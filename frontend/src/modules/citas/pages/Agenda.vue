<template>
  <div>
    <PageHeader
      eyebrow="Clínica"
      title="Agenda"
      :subtitle="`${resumen.total ?? 0} citas · ${resumen.pendientes ?? 0} por atender`"
    >
      <template #actions>
        <div class="fil">
          <ChevronLeft :size="14" class="nav-dia" @click="moverDia(-1)" />
          <input v-model="fecha" type="date" @change="cargar" />
          <ChevronRight :size="14" class="nav-dia" @click="moverDia(1)" />
        </div>
        <button class="btn" @click="irHoy">Hoy</button>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="cargando ? 'spin' : ''" /> Actualizar
        </button>
        <button v-if="puedeCrear" class="btn primary" @click="abrirNueva()">
          <Plus :size="14" /> Nueva cita
        </button>
      </template>
    </PageHeader>

    <!-- Resumen del día -->
    <div class="stat-row">
      <div class="stat">
        <div class="stat-label">Total del día <span class="icon-tile"><CalendarClock :size="14" /></span></div>
        <div class="stat-val">{{ resumen.total ?? 0 }}<span class="unit">citas</span></div>
        <div class="stat-meta"><span class="trend">{{ resumen.completadas ?? 0 }} atendidas</span> registradas</div>
      </div>
      <div class="stat">
        <div class="stat-label">En sala <span class="icon-tile amber"><Users :size="14" /></span></div>
        <div class="stat-val">{{ resumen.en_espera ?? 0 }}<span class="unit">esperando</span></div>
        <div class="stat-meta"><span class="trend flat">{{ resumen.en_atencion ?? 0 }}</span> en atención</div>
      </div>
      <div class="stat">
        <div class="stat-label">Urgencias <span class="icon-tile"><Siren :size="14" /></span></div>
        <div class="stat-val">{{ resumen.urgencias ?? 0 }}<span class="unit">del día</span></div>
        <div class="stat-meta">requieren prioridad</div>
      </div>
      <div class="stat">
        <div class="stat-label">Inasistencias <span class="icon-tile violet"><CalendarX :size="14" /></span></div>
        <div class="stat-val">{{ (resumen.no_asistio ?? 0) + (resumen.canceladas ?? 0) }}<span class="unit">del día</span></div>
        <div class="stat-meta"><span class="trend flat">{{ resumen.canceladas ?? 0 }}</span> canceladas</div>
      </div>
    </div>

    <section class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><CalendarClock :size="14" /></span>
          {{ fechaLegible }}
          <span class="head-meta">{{ citas.length }} en pantalla</span>
        </h2>
        <div class="module-panel-head-actions">
          <div class="toggle-group">
            <button :class="vista === 'tablero' ? 'active' : ''" @click="vista = 'tablero'">
              <LayoutGrid :size="13" /> Tablero
            </button>
            <button :class="vista === 'lista' ? 'active' : ''" @click="vista = 'lista'">
              <List :size="13" /> Lista
            </button>
          </div>
        </div>
      </header>

      <div class="module-panel-toolbar">
        <div class="fil grow">
          <Search :size="14" />
          <input v-model="filtros.buscar" type="search" placeholder="Buscar por paciente o propietario…" @input="debounced" />
        </div>
        <div class="fil">
          <Stethoscope :size="14" />
          <select v-model="filtros.veterinarioId" @change="cargar">
            <option value="">Todos los veterinarios</option>
            <option v-for="v in veterinarios" :key="v.id" :value="v.id">
              {{ v.nombres }} {{ v.apellido_paterno }}
            </option>
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

      <div v-else-if="!cargando && !citas.length" class="module-panel-body module-empty">
        <div class="empty-icon"><CalendarCheck :size="22" /></div>
        <h3>Sin citas este día</h3>
        <p>Agenda la primera atención para {{ fechaLegible.toLowerCase() }}.</p>
        <button v-if="puedeCrear" class="btn primary" style="margin-top: 6px" @click="abrirNueva()">
          <Plus :size="14" /> Nueva cita
        </button>
      </div>

      <!-- Tablero por estado: refleja el recorrido real del paciente -->
      <div v-else-if="vista === 'tablero'" class="module-panel-body tablero">
        <div v-for="col in columnas" :key="col.estado" class="agenda-col">
          <div class="agenda-col-head">
            <span>{{ col.label }}</span>
            <span class="n">{{ porEstado(col.estado).length }}</span>
          </div>
          <div
            v-for="c in porEstado(col.estado)"
            :key="c.id"
            :class="['cita-card', c.prioridad]"
            @click="abrirDetalle(c)"
          >
            <div class="hora">{{ fmtHora(c.fecha_hora) }} · {{ c.duracion_min }}′</div>
            <div class="paciente">{{ c.mascota }}</div>
            <div class="meta">{{ c.especie }}{{ c.raza ? ` · ${c.raza}` : "" }}</div>
            <div class="meta">{{ c.cliente }}</div>
            <div v-if="c.alergias" class="meta alergia">
              <AlertTriangle :size="11" /> {{ c.alergias }}
            </div>
            <div class="pie">
              <span class="tag">{{ c.servicio || "Sin servicio" }}</span>
              <span v-if="c.veterinario" class="vet-dot" :style="{ background: c.color_agenda || 'var(--emerald)' }" :title="c.veterinario"></span>
            </div>
          </div>
        </div>
      </div>

      <!-- Lista compacta -->
      <div v-else class="module-panel-body tabla-wrap">
        <table>
          <thead>
            <tr>
              <th>Hora</th>
              <th>Paciente</th>
              <th>Propietario</th>
              <th>Servicio</th>
              <th>Veterinario</th>
              <th>Estado</th>
              <th class="acciones-col"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="c in citas" :key="c.id" class="clickable" @click="abrirDetalle(c)">
              <td class="mono">{{ fmtHora(c.fecha_hora) }}</td>
              <td>
                <div class="entidad-cell">
                  <div class="avatar-sm">
                    <img v-if="c.mascota_foto" :src="c.mascota_foto" :alt="c.mascota" />
                    <template v-else>{{ iniciales(c.mascota) }}</template>
                  </div>
                  <div class="info">
                    <strong>{{ c.mascota }}</strong>
                    <small>{{ c.especie }}{{ c.raza ? ` · ${c.raza}` : "" }}</small>
                  </div>
                </div>
              </td>
              <td>
                <div class="stack">
                  <span>{{ c.cliente }}</span>
                  <small class="muted mono">{{ c.cliente_telefono || "—" }}</small>
                </div>
              </td>
              <td>{{ c.servicio || "—" }}</td>
              <td>{{ c.veterinario || "Sin asignar" }}</td>
              <td>
                <span :class="['estado-pill', toneCita(c.estado)]">
                  <span class="dot"></span>{{ capitalizar(c.estado) }}
                </span>
              </td>
              <td class="acciones-col" @click.stop>
                <div class="row-actions">
                  <button
                    v-if="siguientePaso(c.estado)"
                    class="btn mini primary"
                    :title="siguientePaso(c.estado).label"
                    @click="avanzar(c)"
                  >
                    {{ siguientePaso(c.estado).label }}
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- ---------- Modal: nueva cita ---------- -->
    <CitaModal
      v-if="modalNueva"
      :veterinarios="veterinarios"
      :fecha-sugerida="fecha"
      @close="modalNueva = false"
      @guardado="onGuardada"
    />

    <!-- ---------- Modal: detalle de la cita ---------- -->
    <CitaDetalleModal
      v-if="citaSel"
      :cita-id="citaSel.id"
      @close="citaSel = null"
      @cambiado="cargar"
    />
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from "vue";
import {
  CalendarClock, CalendarCheck, CalendarX, RefreshCw, Plus, Search, Loader2,
  AlertCircle, AlertTriangle, Users, Siren, Stethoscope, LayoutGrid, List,
  ChevronLeft, ChevronRight,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import CitaModal from "../components/CitaModal.vue";
import CitaDetalleModal from "../components/CitaDetalleModal.vue";
import { citasApi } from "../api/citas.api.js";
import { usersApi } from "../../users/api/users.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { fmtHora, capitalizar, iniciales } from "../../../shared/components/ui/format.js";
import { notify } from "../../../shared/composables/useNotify.js";

const { hasPermission } = useAuth();
const puedeCrear = computed(() => hasPermission("citas:crear"));

const hoyISO = () => new Date().toISOString().slice(0, 10);
const fecha = ref(hoyISO());
const vista = ref("tablero");
const citas = ref([]);
const resumen = ref({});
const veterinarios = ref([]);
const cargando = ref(false);
const error = ref("");
const modalNueva = ref(false);
const citaSel = ref(null);
const filtros = reactive({ buscar: "", veterinarioId: "" });

const columnas = [
  { estado: "programada",  label: "Programadas" },
  { estado: "confirmada",  label: "Confirmadas" },
  { estado: "en_espera",   label: "En sala" },
  { estado: "en_atencion", label: "En atención" },
  { estado: "completada",  label: "Atendidas" },
];

const fechaLegible = computed(() => {
  const [y, m, dd] = fecha.value.split("-").map(Number);
  return new Date(y, m - 1, dd).toLocaleDateString("es-PE", {
    weekday: "long", day: "numeric", month: "long",
  }).replace(/^./, (c) => c.toUpperCase());
});

const hayFiltro = computed(() => !!filtros.buscar || !!filtros.veterinarioId);

function porEstado(estado) {
  return citas.value.filter((c) => c.estado === estado);
}

function toneCita(estado) {
  return {
    programada: "neutral", confirmada: "info", en_espera: "warn",
    en_atencion: "violet", completada: "ok", cancelada: "danger", no_asistio: "danger",
  }[estado] || "neutral";
}

/** El siguiente paso natural del recorrido, para el botón de acción rápida. */
function siguientePaso(estado) {
  return {
    programada: { estado: "confirmada", label: "Confirmar" },
    confirmada: { estado: "en_espera", label: "Llegó" },
    en_espera: { estado: "en_atencion", label: "Pasar" },
    en_atencion: { estado: "completada", label: "Terminar" },
  }[estado] || null;
}

async function avanzar(c) {
  const paso = siguientePaso(c.estado);
  if (!paso) return;
  try {
    await citasApi.cambiarEstado(c.id, paso.estado);
    await cargar();
  } catch (e) {
    notify.error("No se pudo actualizar la cita", e.message);
  }
}

function moverDia(delta) {
  const [y, m, d] = fecha.value.split("-").map(Number);
  const nd = new Date(y, m - 1, d + delta);
  fecha.value = nd.toISOString().slice(0, 10);
  cargar();
}
function irHoy() {
  fecha.value = hoyISO();
  cargar();
}
function limpiar() {
  filtros.buscar = "";
  filtros.veterinarioId = "";
  cargar();
}

let timer = null;
function debounced() {
  clearTimeout(timer);
  timer = setTimeout(cargar, 350);
}

function abrirNueva() { modalNueva.value = true; }
function abrirDetalle(c) { citaSel.value = c; }
function onGuardada() {
  modalNueva.value = false;
  cargar();
}

async function cargar() {
  cargando.value = true;
  error.value = "";
  try {
    const [y, m, d] = fecha.value.split("-").map(Number);
    const siguiente = new Date(y, m - 1, d + 1).toISOString().slice(0, 10);
    const [lista, dia] = await Promise.all([
      citasApi.listar({
        desde: fecha.value,
        hasta: siguiente,
        buscar: filtros.buscar || undefined,
        veterinarioId: filtros.veterinarioId || undefined,
        pageSize: 200,
      }),
      citasApi.agendaDia(fecha.value),
    ]);
    citas.value = lista.data ?? [];
    resumen.value = dia.data?.resumen ?? {};
    resumen.value.pendientes =
      (resumen.value.programadas ?? 0) + (resumen.value.confirmadas ?? 0);
  } catch (e) {
    error.value = e.message;
  } finally {
    cargando.value = false;
  }
}

onMounted(async () => {
  try {
    const v = await usersApi.veterinarios();
    veterinarios.value = v.data ?? [];
  } catch {
    // Sin la lista de veterinarios la agenda sigue funcionando; solo se pierde el filtro.
  }
  cargar();
});
</script>

<style scoped>
.nav-dia { cursor: pointer; color: var(--ink-3); }
.nav-dia:hover { color: var(--ink); }

.tablero {
  display: grid; grid-template-columns: repeat(5, minmax(190px, 1fr));
  gap: 14px; padding: 14px; overflow-x: auto;
}
@media (max-width: 1200px) { .tablero { grid-template-columns: repeat(3, minmax(190px, 1fr)); } }
@media (max-width: 760px) { .tablero { grid-template-columns: 1fr; } }

.cita-card .alergia { color: var(--red-ink); display: inline-flex; align-items: center; gap: 4px; }
.vet-dot { width: 9px; height: 9px; border-radius: 999px; flex-shrink: 0; }
.btn.mini { height: 26px; padding: 0 9px; font-size: 11.5px; }
</style>
