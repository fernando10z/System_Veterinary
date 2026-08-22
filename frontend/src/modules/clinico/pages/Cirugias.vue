<template>
  <div>
    <PageHeader
      eyebrow="Historia clínica"
      title="Cirugías"
      :subtitle="`${programadas} programadas · ${realizadas} realizadas`"
    >
      <template #actions>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="cargando ? 'spin' : ''" /> Actualizar
        </button>
      </template>
    </PageHeader>

    <section class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><Scissors :size="14" /></span>
          Quirófano
          <span class="head-meta">{{ cirugias.length }}</span>
        </h2>
      </header>

      <div class="module-panel-toolbar">
        <div class="fil">
          <Filter :size="14" />
          <select v-model="estado" @change="cargar">
            <option value="">Todas</option>
            <option value="programada">Programadas</option>
            <option value="en_quirofano">En quirófano</option>
            <option value="realizada">Realizadas</option>
            <option value="cancelada">Canceladas</option>
          </select>
        </div>
        <div class="toolbar-spacer"></div>
        <span v-if="cargando" class="loading-mini"><Loader2 :size="13" class="spin" /> Cargando…</span>
      </div>

      <div v-if="!cargando && !cirugias.length" class="module-panel-body module-empty">
        <div class="empty-icon"><Scissors :size="22" /></div>
        <h3>Sin cirugías registradas</h3>
        <p>Las cirugías se programan desde la ficha del paciente o la agenda.</p>
      </div>

      <div v-else class="module-panel-body tabla-wrap">
        <table>
          <thead>
            <tr>
              <th>Procedimiento</th>
              <th>Paciente</th>
              <th>Fecha</th>
              <th>Cirujano</th>
              <th>Consentimiento</th>
              <th>Estado</th>
              <th class="acciones-col"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="c in cirugias" :key="c.id">
              <td>
                <div class="stack">
                  <strong>{{ c.nombre }}</strong>
                  <small class="muted mono">{{ c.codigo }}</small>
                </div>
              </td>
              <td>
                <div class="entidad-cell">
                  <div class="avatar-sm">
                    <img v-if="c.mascota_foto" :src="c.mascota_foto" :alt="c.mascota" />
                    <template v-else>{{ iniciales(c.mascota) }}</template>
                  </div>
                  <div class="info">
                    <strong>{{ c.mascota }}</strong>
                    <small>{{ c.especie }} · {{ c.cliente }}</small>
                  </div>
                </div>
              </td>
              <td class="mono">{{ fmtFechaHora(c.fecha) }}</td>
              <td>{{ c.cirujano || "—" }}</td>
              <td>
                <span :class="['estado-pill', c.consentimiento_firmado ? 'ok' : 'danger']">
                  <span class="dot"></span>{{ c.consentimiento_firmado ? "Firmado" : "Pendiente" }}
                </span>
              </td>
              <td>
                <span :class="['estado-pill', tone(c.estado)]">
                  <span class="dot"></span>{{ capitalizar(c.estado) }}
                </span>
              </td>
              <td class="acciones-col">
                <button
                  v-if="puedeRegistrar && c.estado !== 'realizada' && c.estado !== 'cancelada'"
                  class="btn mini primary"
                  @click="abrirResultado(c)"
                >
                  Registrar resultado
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- Registrar el resultado quirúrgico -->
    <div v-if="sel" class="modal-back" @click="sel = null">
      <div class="modal modal-wide" @click.stop>
        <div class="m-head"><h3>{{ sel.nombre }} — {{ sel.mascota }}</h3></div>
        <div class="m-body">
          <div v-if="error" class="callout danger" style="margin-bottom: 12px">
            <AlertCircle :size="15" /> <span>{{ error }}</span>
          </div>

          <label class="check-line">
            <input v-model="res.consentimiento_firmado" type="checkbox" />
            <span>Consentimiento informado firmado por el propietario</span>
          </label>
          <small class="muted" style="display: block; margin-bottom: 12px">
            Sin el consentimiento firmado la cirugía no se puede cerrar.
          </small>

          <div class="form-grid">
            <div class="field">
              <label>Inicio</label>
              <input v-model="res.fecha_inicio" type="datetime-local" />
            </div>
            <div class="field">
              <label>Fin</label>
              <input v-model="res.fecha_fin" type="datetime-local" />
            </div>
            <div class="field">
              <label>Anestesia</label>
              <input v-model.trim="res.anestesia_tipo" type="text" placeholder="Inhalatoria (isoflurano)" />
            </div>
            <div class="field">
              <label>Dosis anestésica</label>
              <input v-model.trim="res.anestesia_dosis" type="text" />
            </div>
            <div class="field" style="grid-column: 1 / -1">
              <label>Hallazgos</label>
              <textarea v-model="res.hallazgos" rows="2"></textarea>
            </div>
            <div class="field" style="grid-column: 1 / -1">
              <label>Complicaciones</label>
              <textarea v-model="res.complicaciones" rows="2"></textarea>
            </div>
            <div class="field" style="grid-column: 1 / -1">
              <label>Resultado</label>
              <textarea v-model="res.resultado" rows="2"></textarea>
            </div>
            <div class="field" style="grid-column: 1 / -1">
              <label>Cuidados post-operatorios</label>
              <textarea v-model="res.cuidados_post" rows="3"></textarea>
            </div>
          </div>
        </div>
        <div class="m-foot modal-actions">
          <button class="btn" @click="sel = null">Cancelar</button>
          <button class="btn primary" :disabled="guardando" @click="guardarResultado">
            {{ guardando ? "Guardando…" : "Registrar como realizada" }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from "vue";
import { Scissors, RefreshCw, Loader2, Filter, AlertCircle } from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import { clinicoApi } from "../api/clinico.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { fmtFechaHora, capitalizar, iniciales } from "../../../shared/components/ui/format.js";

const { hasPermission } = useAuth();
const puedeRegistrar = computed(() => hasPermission("clinico:registrar"));

const cirugias = ref([]);
const cargando = ref(false);
const estado = ref("");
const sel = ref(null);
const guardando = ref(false);
const error = ref("");

const res = reactive({
  consentimiento_firmado: false,
  fecha_inicio: "", fecha_fin: "",
  anestesia_tipo: "", anestesia_dosis: "",
  hallazgos: "", complicaciones: "", resultado: "", cuidados_post: "",
});

const programadas = computed(() => cirugias.value.filter((c) => c.estado === "programada").length);
const realizadas = computed(() => cirugias.value.filter((c) => c.estado === "realizada").length);

function tone(e) {
  return { programada: "info", en_quirofano: "warn", realizada: "ok", cancelada: "danger" }[e] || "neutral";
}

function abrirResultado(c) {
  sel.value = c;
  error.value = "";
  const ahora = new Date();
  const local = (d) => new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
  Object.assign(res, {
    consentimiento_firmado: !!c.consentimiento_firmado,
    fecha_inicio: c.fecha_inicio ? local(new Date(c.fecha_inicio)) : local(ahora),
    fecha_fin: c.fecha_fin ? local(new Date(c.fecha_fin)) : local(ahora),
    anestesia_tipo: c.anestesia_tipo ?? "",
    anestesia_dosis: "",
    hallazgos: c.hallazgos ?? "",
    complicaciones: c.complicaciones ?? "",
    resultado: c.resultado ?? "",
    cuidados_post: "",
  });
}

async function guardarResultado() {
  error.value = "";
  guardando.value = true;
  try {
    const p = { consentimiento_firmado: res.consentimiento_firmado, estado: "realizada" };
    for (const [k, v] of Object.entries(res)) {
      if (k === "consentimiento_firmado" || v === "" || v === null) continue;
      p[k] = k.startsWith("fecha_") ? new Date(v).toISOString() : v;
    }
    await clinicoApi.resultadoCirugia(sel.value.id, p);
    sel.value = null;
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
    const r = await clinicoApi.cirugias({ estado: estado.value || undefined });
    cirugias.value = r.data ?? [];
  } finally {
    cargando.value = false;
  }
}

onMounted(cargar);
</script>

<style scoped>
.check-line { display: flex; align-items: center; gap: 8px; font-size: 13px; color: var(--ink-2); }
.btn.mini { height: 26px; padding: 0 9px; font-size: 11.5px; }
</style>
