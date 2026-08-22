<template>
  <div class="modal-back" @click="$emit('close')">
    <div class="modal modal-wide" @click.stop>
      <div class="m-head"><h3>{{ esEdicion ? "Editar paciente" : "Nuevo paciente" }}</h3></div>

      <div class="m-body">
        <div v-if="error" class="callout danger" style="margin-bottom: 14px">
          <AlertCircle :size="15" /> <span>{{ error }}</span>
        </div>

        <!-- El propietario solo se elige al crear: mover un paciente de dueño
             es una operación distinta y no debe pasar por este formulario. -->
        <div v-if="!esEdicion" class="field">
          <label>Propietario</label>
          <div v-if="clienteSel" class="sel-cliente">
            <div class="avatar-sm">{{ iniciales(clienteSel.nombre_completo) }}</div>
            <div class="grow">
              <strong>{{ clienteSel.nombre_completo }}</strong>
              <small class="mono">{{ clienteSel.numero_documento }}</small>
            </div>
            <button class="btn mini" @click="clienteSel = null">Cambiar</button>
          </div>
          <template v-else>
            <div class="fil grow">
              <Search :size="14" />
              <input v-model="q" type="search" placeholder="Buscar propietario por nombre, documento o teléfono…" @input="buscarDebounced" />
            </div>
            <div v-if="resultados.length" class="resultados">
              <button v-for="c in resultados" :key="c.id" class="res-item" @click="clienteSel = c">
                <strong>{{ c.nombre_completo }}</strong>
                <span class="mono muted">{{ c.numero_documento }}</span>
              </button>
            </div>
          </template>
        </div>

        <div class="form-grid">
          <div class="field">
            <label>Nombre <span class="req">*</span></label>
            <input v-model.trim="form.nombre" type="text" placeholder="Luna" />
          </div>
          <div class="field">
            <label>Especie <span class="req">*</span></label>
            <select v-model="form.especie_id" @change="form.raza_id = ''">
              <option value="">Seleccionar…</option>
              <option v-for="e in especies" :key="e.id" :value="e.id">{{ e.nombre }}</option>
            </select>
          </div>
          <div class="field">
            <label>Raza</label>
            <select v-model="form.raza_id">
              <option value="">Sin especificar / mestizo</option>
              <option v-for="r in razasDeEspecie" :key="r.id" :value="r.id">{{ r.nombre }}</option>
            </select>
          </div>
          <div class="field">
            <label>Sexo</label>
            <select v-model="form.sexo">
              <option value="desconocido">No registrado</option>
              <option value="macho">Macho</option>
              <option value="hembra">Hembra</option>
            </select>
          </div>
          <div class="field">
            <label>Fecha de nacimiento</label>
            <input v-model="form.fecha_nacimiento" type="date" />
            <small class="muted">Si no se conoce, usa la edad aproximada.</small>
          </div>
          <div class="field">
            <label>Edad aproximada (meses)</label>
            <input v-model.number="form.edad_aproximada_meses" type="number" min="0" />
          </div>
          <div class="field">
            <label>Peso (kg)</label>
            <input v-model.number="form.peso_kg" type="number" min="0" step="0.1" />
          </div>
          <div class="field">
            <label>Color</label>
            <input v-model.trim="form.color" type="text" placeholder="Dorado" />
          </div>
          <div class="field">
            <label>Microchip</label>
            <input v-model.trim="form.microchip" type="text" placeholder="985141000000000" />
          </div>
          <div class="field">
            <label>Esterilizado</label>
            <select v-model="form.esterilizado">
              <option :value="false">No</option>
              <option :value="true">Sí</option>
            </select>
          </div>
          <div class="field" style="grid-column: 1 / -1">
            <label>Alergias</label>
            <input v-model.trim="form.alergias" type="text" placeholder="Ninguna conocida" />
            <small class="muted">Se muestra como alerta roja en cada atención.</small>
          </div>
          <div class="field" style="grid-column: 1 / -1">
            <label>Condiciones crónicas</label>
            <input v-model.trim="form.condiciones_cronicas" type="text" placeholder="Cardiopatía, epilepsia…" />
          </div>
          <div class="field" style="grid-column: 1 / -1">
            <label>Señas particulares</label>
            <textarea v-model="form.senias_particulares" rows="2"></textarea>
          </div>
        </div>
      </div>

      <div class="m-foot modal-actions">
        <button class="btn" @click="$emit('close')">Cancelar</button>
        <button class="btn primary" :disabled="guardando" @click="guardar">
          {{ guardando ? "Guardando…" : esEdicion ? "Guardar cambios" : "Registrar paciente" }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from "vue";
import { AlertCircle, Search } from "lucide-vue-next";
import { mascotasApi } from "../api/mascotas.api.js";
import { clientesApi } from "../../clientes/api/clientes.api.js";
import { iniciales } from "../../../shared/components/ui/format.js";

const props = defineProps({
  paciente: { type: Object, default: null },
  especies: { type: Array, default: () => [] },
  clientePreseleccionado: { type: Object, default: null },
});
const emit = defineEmits(["close", "guardado"]);

const esEdicion = computed(() => !!props.paciente?.id);
const clienteSel = ref(props.clientePreseleccionado);
const q = ref("");
const resultados = ref([]);
const guardando = ref(false);
const error = ref("");

const form = reactive({
  nombre: props.paciente?.nombre ?? "",
  especie_id: props.paciente?.especie_id ?? "",
  raza_id: props.paciente?.raza_id ?? "",
  sexo: props.paciente?.sexo ?? "desconocido",
  color: props.paciente?.color ?? "",
  fecha_nacimiento: props.paciente?.fecha_nacimiento ?? "",
  edad_aproximada_meses: props.paciente?.edad_aproximada_meses ?? null,
  peso_kg: props.paciente?.peso_kg ?? null,
  microchip: props.paciente?.microchip ?? "",
  esterilizado: props.paciente?.esterilizado ?? false,
  alergias: props.paciente?.alergias ?? "",
  condiciones_cronicas: props.paciente?.condiciones_cronicas ?? "",
  senias_particulares: props.paciente?.senias_particulares ?? "",
});

const razasDeEspecie = computed(
  () => props.especies.find((e) => e.id === form.especie_id)?.razas ?? [],
);

let timer = null;
function buscarDebounced() {
  clearTimeout(timer);
  if (q.value.length < 2) { resultados.value = []; return; }
  timer = setTimeout(async () => {
    const r = await clientesApi.buscar(q.value, 8);
    resultados.value = r.data ?? [];
  }, 300);
}

/** Solo se envían los campos con valor: el SP conserva lo demás con COALESCE. */
function payload() {
  const p = {};
  for (const [k, v] of Object.entries(form)) {
    if (v === "" || v === null || v === undefined) continue;
    p[k] = v;
  }
  p.esterilizado = form.esterilizado;
  return p;
}

async function guardar() {
  error.value = "";
  if (!form.nombre) { error.value = "El paciente necesita un nombre."; return; }
  if (!form.especie_id) { error.value = "Elige la especie del paciente."; return; }
  if (!esEdicion.value && !clienteSel.value) { error.value = "Elige el propietario."; return; }

  guardando.value = true;
  try {
    if (esEdicion.value) {
      await mascotasApi.actualizar(props.paciente.id, payload());
    } else {
      await mascotasApi.crear({ ...payload(), cliente_id: clienteSel.value.id });
    }
    emit("guardado");
  } catch (e) {
    error.value = e.message;
  } finally {
    guardando.value = false;
  }
}

onMounted(() => {
  // Al editar, la especie viene con las razas ya cargadas desde el catálogo.
});
</script>

<style scoped>
.sel-cliente {
  display: flex; align-items: center; gap: 11px;
  padding: 10px 12px; border-radius: 10px;
  background: var(--emerald-soft); border: 1px solid var(--emerald-line);
}
.sel-cliente strong { display: block; font-size: 13.5px; color: var(--ink); }
.sel-cliente small { font-size: 11.5px; color: var(--ink-3); }
.resultados {
  margin-top: 8px; max-height: 200px; overflow-y: auto;
  border: 1px solid var(--line); border-radius: 10px;
}
.res-item {
  display: flex; justify-content: space-between; gap: 10px; width: 100%;
  padding: 9px 11px; border: none; background: none; cursor: pointer;
  text-align: left; font-size: 12.5px; border-bottom: 1px solid var(--line-soft);
}
.res-item:last-child { border-bottom: none; }
.res-item:hover { background: var(--bg-soft); }
.req { color: var(--red); }
.btn.mini { height: 26px; padding: 0 9px; font-size: 11.5px; }
</style>
