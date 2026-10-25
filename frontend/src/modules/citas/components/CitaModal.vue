<template>
  <div class="modal-back" v-dialogo="() => $emit('close')">
    <div class="modal modal-wide" @click.stop>
      <div class="m-head"><h3>Nueva cita</h3></div>

      <div class="m-body">
        <div v-if="error" class="callout danger" style="margin-bottom: 14px">
          <AlertCircle :size="15" /> <span>{{ error }}</span>
        </div>

        <!-- Paso 1: elegir paciente buscando por dueño o mascota -->
        <div class="field">
          <label for="cita-buscar">Paciente <span class="req">*</span></label>
          <div v-if="mascotaSel" class="sel-paciente">
            <div class="avatar-sm">{{ iniciales(mascotaSel.nombre) }}</div>
            <div class="grow">
              <strong>{{ mascotaSel.nombre }}</strong>
              <small>{{ mascotaSel.especie }} · {{ clienteSel?.nombre_completo }}</small>
            </div>
            <button class="btn mini" @click="limpiarPaciente">Cambiar</button>
          </div>

          <BuscadorPaciente v-else input-id="cita-buscar" @elegir="elegir" />
        </div>

        <!-- Paso 2: datos de la cita -->
        <div class="form-grid">
          <div class="field">
            <label for="cita-fecha">Fecha y hora</label>
            <input id="cita-fecha" v-model="form.fecha_hora" type="datetime-local" @change="onFecha" />
          </div>
          <div class="field">
            <label for="cita-vet">Veterinario</label>
            <select id="cita-vet" v-model="form.veterinario_id" @change="cargarSlots">
              <option value="">Sin asignar</option>
              <option v-for="v in veterinarios" :key="v.id" :value="v.id">
                {{ v.nombres }} {{ v.apellido_paterno }}
              </option>
            </select>
          </div>
          <div class="field">
            <label for="cita-serv">Servicio</label>
            <select id="cita-serv" v-model="form.servicio_id" @change="onServicio">
              <option value="">Sin servicio</option>
              <option v-for="s in servicios" :key="s.id" :value="s.id">
                {{ s.nombre }} — {{ fmtSoles(s.precio) }}
              </option>
            </select>
          </div>
          <div class="field">
            <label for="cita-dur">Duración (min)</label>
            <input id="cita-dur" v-model.number="form.duracion_min" type="number" min="5" step="5" />
          </div>
          <div class="field">
            <label for="cita-prio">Prioridad</label>
            <select id="cita-prio" v-model="form.prioridad">
              <option value="normal">Normal</option>
              <option value="preferente">Preferente</option>
              <option value="urgencia">Urgencia</option>
              <option value="emergencia">Emergencia</option>
            </select>
          </div>
          <div class="field">
            <label for="cita-origen">Origen</label>
            <select id="cita-origen" v-model="form.origen">
              <option value="mostrador">Mostrador</option>
              <option value="telefono">Teléfono</option>
              <option value="whatsapp">WhatsApp</option>
              <option value="portal">Portal</option>
            </select>
          </div>
          <div class="field" style="grid-column: 1 / -1">
            <label for="cita-motivo">Motivo</label>
            <textarea id="cita-motivo" v-model="form.motivo" rows="2" placeholder="Motivo de la consulta…"></textarea>
          </div>
        </div>

        <!-- Horarios libres del veterinario elegido -->
        <div v-if="slots.length" class="slots">
          <div class="section-title">Horarios disponibles</div>
          <div class="slots-grid">
            <button
              v-for="s in slots"
              :key="s.inicio"
              :class="['slot', s.disponible ? '' : 'ocupado']"
              :disabled="!s.disponible"
              @click="form.fecha_hora = aLocal(s.inicio)"
            >
              {{ fmtHora(s.inicio) }}
            </button>
          </div>
        </div>
      </div>

      <div class="m-foot modal-actions">
        <button class="btn" @click="$emit('close')">Cancelar</button>
        <button class="btn primary" :disabled="guardando || !mascotaSel" @click="guardar">
          {{ guardando ? "Guardando…" : "Agendar cita" }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted } from "vue";
import { AlertCircle } from "lucide-vue-next";
import BuscadorPaciente from "../../mascotas/components/BuscadorPaciente.vue";
import { citasApi } from "../api/citas.api.js";
import { catalogosApi } from "../../catalogos/api/catalogos.api.js";
import { fmtSoles, fmtHora, iniciales } from "../../../shared/components/ui/format.js";
import { hoyISO, datetimeLocal, datetimeLocalAISO } from "@/shared/utils/fechas.js";
import { notify } from "@/shared/composables/useNotify.js";

const props = defineProps({
  veterinarios: { type: Array, default: () => [] },
  fechaSugerida: { type: String, default: null },
});
const emit = defineEmits(["close", "guardado"]);

const clienteSel = ref(null);
const mascotaSel = ref(null);
const servicios = ref([]);
const slots = ref([]);
const guardando = ref(false);
const error = ref("");

const form = reactive({
  fecha_hora: `${props.fechaSugerida || hoyISO()}T09:00`,
  veterinario_id: "",
  servicio_id: "",
  duracion_min: 30,
  prioridad: "normal",
  origen: "mostrador",
  motivo: "",
});

function elegir(cliente, mascota) {
  clienteSel.value = cliente;
  mascotaSel.value = mascota;
}

/** Cambiar de día recarga los horarios libres del veterinario. */
let diaSlots = "";
function onFecha() {
  const dia = (form.fecha_hora || "").slice(0, 10);
  if (dia && dia !== diaSlots) cargarSlots();
}
function limpiarPaciente() {
  clienteSel.value = null;
  mascotaSel.value = null;
  slots.value = [];
}

function onServicio() {
  const s = servicios.value.find((x) => x.id === form.servicio_id);
  if (s?.duracion_min) form.duracion_min = s.duracion_min;
  cargarSlots();
}

/** El SP devuelve ISO con zona; el input datetime-local necesita hora local sin zona. */
function aLocal(iso) {
  return datetimeLocal(iso);
}

async function cargarSlots() {
  slots.value = [];
  if (!form.veterinario_id || !form.fecha_hora) return;
  diaSlots = form.fecha_hora.slice(0, 10);
  try {
    const r = await citasApi.disponibilidad({
      veterinarioId: form.veterinario_id,
      fecha: form.fecha_hora.slice(0, 10),
      duracion: form.duracion_min,
    });
    slots.value = r.data?.slots ?? [];
  } catch {
    // Si no hay horario configurado para ese día simplemente no se muestran slots.
  }
}

async function guardar() {
  if (guardando.value) return;
  error.value = "";
  if (!mascotaSel.value) {
    error.value = "Elige el paciente de la cita.";
    return;
  }
  const fecha = datetimeLocalAISO(form.fecha_hora);
  if (!fecha) {
    error.value = "Indica la fecha y hora de la cita.";
    return;
  }
  // Una cita en el pasado casi siempre es un error de día o de AM/PM.
  if (new Date(fecha).getTime() < Date.now() - 15 * 60000) {
    const ok = await notify.confirm(
      "La fecha ya pasó",
      "¿Registrar igual la cita en una fecha pasada?",
      { confirmText: "Registrar igual", icon: "warning" },
    );
    if (!ok) return;
  }
  guardando.value = true;
  try {
    await citasApi.crear({
      mascota_id: mascotaSel.value.id,
      // datetime-local no lleva zona: se envía como hora local del navegador.
      fecha_hora: fecha,
      veterinario_id: form.veterinario_id || undefined,
      servicio_id: form.servicio_id || undefined,
      duracion_min: form.duracion_min,
      prioridad: form.prioridad,
      origen: form.origen,
      motivo: form.motivo || undefined,
    });
    emit("guardado");
  } catch (e) {
    error.value = e.message;
  } finally {
    guardando.value = false;
  }
}

onMounted(async () => {
  try {
    const s = await catalogosApi.servicios({ estado: "activo" });
    servicios.value = s.data ?? [];
  } catch {
    // El catálogo es opcional para agendar: la cita puede ir sin servicio.
  }
});
</script>

<style scoped>
.sel-paciente {
  display: flex; align-items: center; gap: 11px;
  padding: 10px 12px; border-radius: 10px;
  background: var(--emerald-soft); border: 1px solid var(--emerald-line);
}
.sel-paciente strong { display: block; font-size: 13.5px; color: var(--ink); }
.sel-paciente small { font-size: 11.5px; color: var(--ink-3); }

.resultados {
  margin-top: 8px; max-height: 230px; overflow-y: auto;
  border: 1px solid var(--line); border-radius: 10px;
}
.res-cliente { padding: 9px 11px; border-bottom: 1px solid var(--line-soft); }
.res-cliente:last-child { border-bottom: none; }
.res-head { display: flex; justify-content: space-between; gap: 8px; font-size: 12.5px; margin-bottom: 5px; }
.res-mascota {
  display: inline-flex; align-items: center; gap: 6px;
  margin: 2px 4px 2px 0; padding: 4px 9px; border-radius: 8px;
  background: var(--bg-soft); border: 1px solid var(--line);
  font-size: 12px; cursor: pointer; color: var(--ink-2);
}
.res-mascota:hover { background: var(--emerald-soft); border-color: var(--emerald-line); color: var(--emerald-ink); }
.res-vacio { font-size: 11.5px; color: var(--ink-4); padding: 6px 2px; }

.slots { margin-top: 16px; }
.slots-grid { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px; }
.slot {
  padding: 5px 10px; border-radius: 8px; font-size: 12px;
  background: var(--emerald-soft); color: var(--emerald-ink);
  border: 1px solid var(--emerald-line); cursor: pointer;
  font-family: var(--font-display); font-variant-numeric: tabular-nums;
}
.slot:hover { background: var(--emerald-soft-2); }
.slot.ocupado {
  background: var(--bg-soft); color: var(--ink-4);
  border-color: var(--line); cursor: not-allowed; text-decoration: line-through;
}
.btn.mini { height: 26px; padding: 0 9px; font-size: 11.5px; }
.req { color: var(--red); }
</style>
