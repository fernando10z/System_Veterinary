<template>
  <div class="modal-back" @click="$emit('close')">
    <div class="modal modal-wide" @click.stop>
      <div class="m-head"><h3>Nueva cita</h3></div>

      <div class="m-body">
        <div v-if="error" class="callout danger" style="margin-bottom: 14px">
          <AlertCircle :size="15" /> <span>{{ error }}</span>
        </div>

        <!-- Paso 1: elegir paciente buscando por dueño o mascota -->
        <div class="field">
          <label>Paciente</label>
          <div v-if="mascotaSel" class="sel-paciente">
            <div class="avatar-sm">{{ iniciales(mascotaSel.nombre) }}</div>
            <div class="grow">
              <strong>{{ mascotaSel.nombre }}</strong>
              <small>{{ mascotaSel.especie }} · {{ clienteSel?.nombre_completo }}</small>
            </div>
            <button class="btn mini" @click="limpiarPaciente">Cambiar</button>
          </div>

          <template v-else>
            <div class="fil grow">
              <Search :size="14" />
              <input
                v-model="q"
                type="search"
                placeholder="Busca por propietario, documento, teléfono o nombre de la mascota…"
                @input="buscarDebounced"
              />
            </div>

            <div v-if="resultados.length" class="resultados">
              <div v-for="c in resultados" :key="c.id" class="res-cliente">
                <div class="res-head">
                  <strong>{{ c.nombre_completo }}</strong>
                  <span class="mono muted">{{ c.numero_documento }}</span>
                </div>
                <div v-if="!c.mascotas.length" class="res-vacio">Sin mascotas registradas</div>
                <button
                  v-for="m in c.mascotas"
                  :key="m.id"
                  class="res-mascota"
                  @click="elegir(c, m)"
                >
                  <PawPrint :size="13" /> {{ m.nombre }}
                  <span class="tag">{{ m.especie }}</span>
                </button>
              </div>
            </div>
            <div v-else-if="q.length >= 2 && !buscando" class="res-vacio">
              Sin coincidencias para “{{ q }}”.
            </div>
          </template>
        </div>

        <!-- Paso 2: datos de la cita -->
        <div class="form-grid">
          <div class="field">
            <label>Fecha y hora</label>
            <input v-model="form.fecha_hora" type="datetime-local" />
          </div>
          <div class="field">
            <label>Veterinario</label>
            <select v-model="form.veterinario_id" @change="cargarSlots">
              <option value="">Sin asignar</option>
              <option v-for="v in veterinarios" :key="v.id" :value="v.id">
                {{ v.nombres }} {{ v.apellido_paterno }}
              </option>
            </select>
          </div>
          <div class="field">
            <label>Servicio</label>
            <select v-model="form.servicio_id" @change="onServicio">
              <option value="">Sin servicio</option>
              <option v-for="s in servicios" :key="s.id" :value="s.id">
                {{ s.nombre }} — {{ fmtSoles(s.precio) }}
              </option>
            </select>
          </div>
          <div class="field">
            <label>Duración (min)</label>
            <input v-model.number="form.duracion_min" type="number" min="5" step="5" />
          </div>
          <div class="field">
            <label>Prioridad</label>
            <select v-model="form.prioridad">
              <option value="normal">Normal</option>
              <option value="preferente">Preferente</option>
              <option value="urgencia">Urgencia</option>
              <option value="emergencia">Emergencia</option>
            </select>
          </div>
          <div class="field">
            <label>Origen</label>
            <select v-model="form.origen">
              <option value="mostrador">Mostrador</option>
              <option value="telefono">Teléfono</option>
              <option value="whatsapp">WhatsApp</option>
              <option value="portal">Portal</option>
            </select>
          </div>
          <div class="field" style="grid-column: 1 / -1">
            <label>Motivo</label>
            <textarea v-model="form.motivo" rows="2" placeholder="Motivo de la consulta…"></textarea>
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
import { Search, AlertCircle, PawPrint } from "lucide-vue-next";
import { citasApi } from "../api/citas.api.js";
import { clientesApi } from "../../clientes/api/clientes.api.js";
import { catalogosApi } from "../../catalogos/api/catalogos.api.js";
import { fmtSoles, fmtHora, iniciales } from "../../../shared/components/ui/format.js";

const props = defineProps({
  veterinarios: { type: Array, default: () => [] },
  fechaSugerida: { type: String, default: null },
});
const emit = defineEmits(["close", "guardado"]);

const q = ref("");
const resultados = ref([]);
const buscando = ref(false);
const clienteSel = ref(null);
const mascotaSel = ref(null);
const servicios = ref([]);
const slots = ref([]);
const guardando = ref(false);
const error = ref("");

const form = reactive({
  fecha_hora: `${props.fechaSugerida || new Date().toISOString().slice(0, 10)}T09:00`,
  veterinario_id: "",
  servicio_id: "",
  duracion_min: 30,
  prioridad: "normal",
  origen: "mostrador",
  motivo: "",
});

let timer = null;
function buscarDebounced() {
  clearTimeout(timer);
  if (q.value.length < 2) {
    resultados.value = [];
    return;
  }
  timer = setTimeout(async () => {
    buscando.value = true;
    try {
      const r = await clientesApi.buscar(q.value, 8);
      resultados.value = r.data ?? [];
    } finally {
      buscando.value = false;
    }
  }, 300);
}

function elegir(cliente, mascota) {
  clienteSel.value = cliente;
  mascotaSel.value = mascota;
  resultados.value = [];
  q.value = "";
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
  const d = new Date(iso);
  const off = d.getTimezoneOffset();
  return new Date(d.getTime() - off * 60000).toISOString().slice(0, 16);
}

async function cargarSlots() {
  slots.value = [];
  if (!form.veterinario_id || !form.fecha_hora) return;
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
  error.value = "";
  if (!mascotaSel.value) {
    error.value = "Elige el paciente de la cita.";
    return;
  }
  guardando.value = true;
  try {
    await citasApi.crear({
      mascota_id: mascotaSel.value.id,
      // datetime-local no lleva zona: se envía como hora local del navegador.
      fecha_hora: new Date(form.fecha_hora).toISOString(),
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
  font-family: var(--font-mono);
}
.slot:hover { background: var(--emerald-soft-2); }
.slot.ocupado {
  background: var(--bg-soft); color: var(--ink-4);
  border-color: var(--line); cursor: not-allowed; text-decoration: line-through;
}
.btn.mini { height: 26px; padding: 0 9px; font-size: 11.5px; }
</style>
