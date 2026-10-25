<template>
  <div>
    <PageHeader
      eyebrow="Historia clínica"
      title="Hospitalización"
      :subtitle="`${internados.length} ${internados.length === 1 ? 'paciente internado' : 'pacientes internados'}`"
    >
      <template #actions>
        <label class="check-line">
          <input v-model="todas" type="checkbox" @change="cargar" />
          <span>Incluir dadas de alta</span>
        </label>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="cargando ? 'spin' : ''" /> Actualizar
        </button>
      </template>
    </PageHeader>

    <div v-if="!cargando && !internados.length" class="module-panel">
      <div class="module-panel-body module-empty">
        <div class="empty-icon"><BedDouble :size="22" /></div>
        <h3>Sin pacientes hospitalizados</h3>
        <p>Los ingresos se registran desde la ficha del paciente o la consulta.</p>
      </div>
    </div>

    <div v-else class="hosp-grid">
      <section v-for="h in internados" :key="h.id" class="module-panel hosp-card">
        <header class="module-panel-head">
          <h2>
            <span class="head-icon"><BedDouble :size="14" /></span>
            {{ h.mascota }}
            <span class="head-meta">{{ h.jaula || "sin jaula" }}</span>
          </h2>
          <div class="module-panel-head-actions">
            <span :class="['estado-pill', tone(h.estado)]">
              <span class="dot"></span>{{ capitalizar(h.estado) }}
            </span>
          </div>
        </header>

        <div class="module-panel-body">
          <div class="hosp-top">
            <div class="avatar-sm lg">
              <img v-if="h.mascota_foto" :src="h.mascota_foto" :alt="h.mascota" />
              <template v-else>{{ iniciales(h.mascota) }}</template>
            </div>
            <div class="grow">
              <div class="motivo">{{ h.motivo }}</div>
              <div class="muted">{{ h.especie }} · {{ h.cliente }} · {{ h.cliente_telefono }}</div>
            </div>
            <div class="text-right">
              <div class="dias cifra">{{ h.dias_internado }}</div>
              <div class="muted" style="font-size: 11px">
                {{ h.dias_internado === 1 ? "día" : "días" }}
              </div>
            </div>
          </div>

          <div v-if="h.diagnostico" class="detalle-item" style="margin-top: 12px">
            <div class="k">Diagnóstico</div>
            <div class="v">{{ h.diagnostico }}</div>
          </div>

          <div v-if="h.ultima_evolucion" class="ultima-evo">
            <div class="k">Última evolución · {{ fmtFechaHora(h.ultima_evolucion.fecha_hora) }}</div>
            <div class="v">
              <span v-if="h.ultima_evolucion.temperatura_c" class="tag cifra">
                {{ h.ultima_evolucion.temperatura_c }} °C
              </span>
              {{ h.ultima_evolucion.nota }}
            </div>
          </div>
        </div>

        <div class="module-panel-foot">
          <!-- Se imprime también durante el internamiento: es el parte que
               pide el propietario cuando viene a preguntar. -->
          <button class="btn" @click="abrirDocumento('alta', h.id, { auto: true })">
            <FileText :size="13" /> Informe
          </button>
          <template v-if="puedeRegistrar && ['ingresado', 'en_observacion'].includes(h.estado)">
            <button class="btn" @click="abrirEvolucion(h)"><Plus :size="13" /> Registrar evolución</button>
            <button class="btn primary" @click="abrirAlta(h)"><LogOut :size="13" /> Dar de alta</button>
          </template>
        </div>
      </section>
    </div>

    <!-- Evolución -->
    <div v-if="evoFor" class="modal-back" v-dialogo="() => (evoFor = null)">
      <div class="modal" @click.stop>
        <div class="m-head"><h3>Evolución — {{ evoFor.mascota }}</h3></div>
        <div class="m-body">
          <div class="form-grid">
            <div class="field">
              <label for="hospitaliz-temperatura-c">Temperatura (°C)</label>
              <input id="hospitaliz-temperatura-c" v-model.number="evo.temperatura_c" type="number" step="0.1" min="25" max="45" />
            </div>
            <div class="field">
              <label for="hospitaliz-frecuencia-cardiaca">FC (lpm)</label>
              <input id="hospitaliz-frecuencia-cardiaca" v-model.number="evo.frecuencia_cardiaca" type="number" min="0" />
            </div>
            <div class="field">
              <label for="hospitaliz-frecuencia-respiratoria">FR (rpm)</label>
              <input id="hospitaliz-frecuencia-respiratoria" v-model.number="evo.frecuencia_respiratoria" type="number" min="0" />
            </div>
          </div>
          <div class="checks">
            <label class="check-line"><input v-model="evo.come" type="checkbox" /> <span>Come</span></label>
            <label class="check-line"><input v-model="evo.orina" type="checkbox" /> <span>Orina</span></label>
            <label class="check-line"><input v-model="evo.defeca" type="checkbox" /> <span>Defeca</span></label>
          </div>
          <div class="field">
            <label for="hospitaliz-nota">Nota del turno</label>
            <textarea id="hospitaliz-nota" v-model="evo.nota" rows="3"></textarea>
          </div>
        </div>
        <div class="m-foot modal-actions">
          <button class="btn" @click="evoFor = null">Cancelar</button>
          <button class="btn primary" :disabled="guardando" @click="guardarEvolucion">
            {{ guardando ? "Guardando…" : "Registrar" }}
          </button>
        </div>
      </div>
    </div>

    <!-- Alta -->
    <div v-if="altaFor" class="modal-back" v-dialogo="() => (altaFor = null)">
      <div class="modal" @click.stop>
        <div class="m-head"><h3>Alta — {{ altaFor.mascota }}</h3></div>
        <div class="m-body">
          <div class="field">
            <label for="hospitaliz-estado">Estado de salida</label>
            <select id="hospitaliz-estado" v-model="alta.estado">
              <option value="alta">Alta médica</option>
              <option value="derivado">Derivado a otro centro</option>
              <option value="fallecido">Fallecido</option>
            </select>
          </div>
          <div class="field">
            <label for="hospitaliz-indicaciones-alta">Indicaciones al propietario</label>
            <textarea id="hospitaliz-indicaciones-alta" v-model="alta.indicaciones_alta" rows="4"></textarea>
          </div>
        </div>
        <div class="m-foot modal-actions">
          <button class="btn" @click="altaFor = null">Cancelar</button>
          <button class="btn primary" :disabled="guardando" @click="guardarAlta">
            {{ guardando ? "Guardando…" : "Confirmar alta" }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from "vue";
import { BedDouble, RefreshCw, Plus, LogOut, FileText,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import { clinicoApi } from "../api/clinico.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { fmtFechaHora, capitalizar, iniciales } from "../../../shared/components/ui/format.js";
import { abrirDocumento } from "../../../shared/print/abrir-documento.js";
import { notify } from "@/shared/composables/useNotify.js";

const { hasPermission } = useAuth();
const puedeRegistrar = computed(() => hasPermission("clinico:registrar"));

const internados = ref([]);
const cargando = ref(false);
const todas = ref(false);
const guardando = ref(false);

const evoFor = ref(null);
const altaFor = ref(null);
const evo = reactive({
  temperatura_c: null, frecuencia_cardiaca: null, frecuencia_respiratoria: null,
  come: false, orina: false, defeca: false, nota: "",
});
const alta = reactive({ estado: "alta", indicaciones_alta: "" });

function tone(e) {
  return { ingresado: "warn", en_observacion: "info", alta: "ok", fallecido: "neutral", derivado: "neutral" }[e] || "neutral";
}

function abrirEvolucion(h) {
  evoFor.value = h;
  Object.assign(evo, {
    temperatura_c: null, frecuencia_cardiaca: null, frecuencia_respiratoria: null,
    come: false, orina: false, defeca: false, nota: "",
  });
}
function abrirAlta(h) {
  altaFor.value = h;
  Object.assign(alta, { estado: "alta", indicaciones_alta: "" });
}

async function guardarEvolucion() {
  if (guardando.value) return;
  // Un número borrado llega como "" y la API lo rechaza: solo viaja lo cargado.
  const p = { hospitalizacion_id: evoFor.value.id };
  for (const [k, v] of Object.entries(evo)) {
    if (v === "" || v === null || v === undefined) continue;
    p[k] = typeof v === "string" ? v.trim() : v;
  }
  const hayDatos = ["temperatura_c", "frecuencia_cardiaca", "frecuencia_respiratoria", "nota"].some((k) => p[k] !== undefined && p[k] !== "")
    || evo.come || evo.orina || evo.defeca;
  if (!hayDatos) {
    notify.warn("Evolución vacía", "Registra al menos una constante o una nota del turno.");
    return;
  }
  guardando.value = true;
  try {
    await clinicoApi.registrarEvolucion(p);
    evoFor.value = null;
    cargar();
  } catch (e) {
    notify.error("No se pudo registrar la evolución", e.message);
  } finally {
    guardando.value = false;
  }
}

async function guardarAlta() {
  if (guardando.value) return;
  if (alta.estado === "fallecido" && !(await notify.confirm(
    `Registrar el fallecimiento de ${altaFor.value.mascota}`,
    "Cierra la hospitalización con estado fallecido. No se puede deshacer desde aquí.",
    { confirmText: "Registrar", danger: true, icon: "warning" },
  ))) return;
  guardando.value = true;
  try {
    await clinicoApi.darAlta(altaFor.value.id, { ...alta });
    altaFor.value = null;
    cargar();
  } catch (e) {
    notify.error("No se pudo dar el alta", e.message);
  } finally {
    guardando.value = false;
  }
}

async function cargar() {
  cargando.value = true;
  try {
    const r = await clinicoApi.hospitalizaciones(todas.value);
    internados.value = r.data ?? [];
  } catch (e) {
    notify.toast(`No se pudieron cargar los internados: ${e.message}`, "error");
  } finally {
    cargando.value = false;
  }
}

onMounted(cargar);
</script>

<style scoped>
/* auto-fit, no auto-fill: con un solo internado la ficha ocupa el ancho en vez
   de dejar dos columnas muertas al lado. A partir de tres se comporta igual.
   420px de mínimo: por debajo, el diagnóstico se parte en demasiadas líneas. */
.hosp-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(420px, 1fr)); gap: var(--gap-paneles); }
.hosp-top { display: flex; align-items: center; gap: 12px; }
.hosp-top .text-right { flex-shrink: 0; }

/* El pie de panel reparte a los extremos porque casi siempre lleva "Página X de
   Y" a la izquierda. Aquí son dos acciones: con la ficha a ancho completo
   quedarían a un palmo una de otra, así que se agrupan a la derecha. */
.hosp-card .module-panel-foot { justify-content: flex-end; }
.hosp-top .motivo { font-size: 13.5px; font-weight: 600; color: var(--ink); }
.dias { font-family: var(--font-display); font-variant-numeric: tabular-nums; font-size: 22px; font-weight: 700; color: var(--emerald-deep); line-height: 1; }

.ultima-evo {
  margin-top: 12px; padding: 10px 12px; border-radius: 9px;
  background: var(--bg-soft); border: 1px solid var(--line-soft);
}
.ultima-evo .k { font-size: 10.5px; font-weight: 600; color: var(--ink-4); text-transform: uppercase; letter-spacing: 0.05em; }
.ultima-evo .v { font-size: 12.5px; color: var(--ink-2); margin-top: 4px; }

.check-line { display: inline-flex; align-items: center; gap: 7px; font-size: 12.5px; color: var(--ink-2); }
.checks { display: flex; gap: 16px; margin: 10px 0 14px; }
</style>
