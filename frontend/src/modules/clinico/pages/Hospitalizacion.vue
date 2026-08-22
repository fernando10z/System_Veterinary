<template>
  <div>
    <PageHeader
      eyebrow="Historia clínica"
      title="Hospitalización"
      :subtitle="`${internados.length} pacientes internados`"
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
              <div class="dias mono">{{ h.dias_internado }}</div>
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
              <span v-if="h.ultima_evolucion.temperatura_c" class="tag mono">
                {{ h.ultima_evolucion.temperatura_c }} °C
              </span>
              {{ h.ultima_evolucion.nota }}
            </div>
          </div>
        </div>

        <div v-if="puedeRegistrar && ['ingresado', 'en_observacion'].includes(h.estado)" class="module-panel-foot">
          <button class="btn" @click="abrirEvolucion(h)"><Plus :size="13" /> Registrar evolución</button>
          <button class="btn primary" @click="abrirAlta(h)"><LogOut :size="13" /> Dar de alta</button>
        </div>
      </section>
    </div>

    <!-- Evolución -->
    <div v-if="evoFor" class="modal-back" @click="evoFor = null">
      <div class="modal" @click.stop>
        <div class="m-head"><h3>Evolución — {{ evoFor.mascota }}</h3></div>
        <div class="m-body">
          <div class="form-grid">
            <div class="field">
              <label>Temperatura (°C)</label>
              <input v-model.number="evo.temperatura_c" type="number" step="0.1" min="25" max="45" />
            </div>
            <div class="field">
              <label>FC (lpm)</label>
              <input v-model.number="evo.frecuencia_cardiaca" type="number" min="0" />
            </div>
            <div class="field">
              <label>FR (rpm)</label>
              <input v-model.number="evo.frecuencia_respiratoria" type="number" min="0" />
            </div>
          </div>
          <div class="checks">
            <label class="check-line"><input v-model="evo.come" type="checkbox" /> <span>Come</span></label>
            <label class="check-line"><input v-model="evo.orina" type="checkbox" /> <span>Orina</span></label>
            <label class="check-line"><input v-model="evo.defeca" type="checkbox" /> <span>Defeca</span></label>
          </div>
          <div class="field">
            <label>Nota del turno</label>
            <textarea v-model="evo.nota" rows="3"></textarea>
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
    <div v-if="altaFor" class="modal-back" @click="altaFor = null">
      <div class="modal" @click.stop>
        <div class="m-head"><h3>Alta — {{ altaFor.mascota }}</h3></div>
        <div class="m-body">
          <div class="field">
            <label>Estado de salida</label>
            <select v-model="alta.estado">
              <option value="alta">Alta médica</option>
              <option value="derivado">Derivado a otro centro</option>
              <option value="fallecido">Fallecido</option>
            </select>
          </div>
          <div class="field">
            <label>Indicaciones al propietario</label>
            <textarea v-model="alta.indicaciones_alta" rows="4"></textarea>
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
import { BedDouble, RefreshCw, Plus, LogOut } from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import { clinicoApi } from "../api/clinico.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { fmtFechaHora, capitalizar, iniciales } from "../../../shared/components/ui/format.js";

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
  guardando.value = true;
  try {
    await clinicoApi.registrarEvolucion({ hospitalizacion_id: evoFor.value.id, ...evo });
    evoFor.value = null;
    cargar();
  } finally {
    guardando.value = false;
  }
}

async function guardarAlta() {
  guardando.value = true;
  try {
    await clinicoApi.darAlta(altaFor.value.id, { ...alta });
    altaFor.value = null;
    cargar();
  } finally {
    guardando.value = false;
  }
}

async function cargar() {
  cargando.value = true;
  try {
    const r = await clinicoApi.hospitalizaciones(todas.value);
    internados.value = r.data ?? [];
  } finally {
    cargando.value = false;
  }
}

onMounted(cargar);
</script>

<style scoped>
.hosp-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(360px, 1fr)); gap: 16px; }
.hosp-top { display: flex; align-items: center; gap: 12px; }
.hosp-top .motivo { font-size: 13.5px; font-weight: 600; color: var(--ink); }
.dias { font-size: 22px; font-weight: 700; color: var(--emerald-deep); line-height: 1; }

.ultima-evo {
  margin-top: 12px; padding: 10px 12px; border-radius: 9px;
  background: var(--bg-soft); border: 1px solid var(--line-soft);
}
.ultima-evo .k { font-size: 10.5px; font-weight: 600; color: var(--ink-4); text-transform: uppercase; letter-spacing: 0.05em; }
.ultima-evo .v { font-size: 12.5px; color: var(--ink-2); margin-top: 4px; }

.check-line { display: inline-flex; align-items: center; gap: 7px; font-size: 12.5px; color: var(--ink-2); }
.checks { display: flex; gap: 16px; margin: 10px 0 14px; }
</style>
