<template>
  <div class="modal-back" v-dialogo="() => $emit('close')">
    <div class="modal modal-wide" @click.stop>
      <div class="m-head"><h3>{{ esEdicion ? "Editar paciente" : "Nuevo paciente" }}</h3></div>

      <div class="m-body">
        <div v-if="error" class="callout danger" style="margin-bottom: 14px">
          <AlertCircle :size="15" /> <span>{{ error }}</span>
        </div>

        <!-- El propietario solo se elige al crear: mover un paciente de dueño
             es una operación distinta y no debe pasar por este formulario. -->
        <div v-if="!esEdicion" class="field">
          <label for="pac-buscar-prop">Propietario <span class="req">*</span></label>
          <div v-if="clienteSel" class="sel-cliente">
            <div class="avatar-sm">{{ iniciales(clienteSel.nombre_completo) }}</div>
            <div class="grow">
              <strong>{{ clienteSel.nombre_completo }}</strong>
              <small class="codigo">{{ clienteSel.numero_documento }}</small>
            </div>
            <button class="btn mini" @click="clienteSel = null">Cambiar</button>
          </div>
          <template v-else>
            <div class="fil grow" data-no-dirty>
              <Search :size="14" />
              <input
                id="pac-buscar-prop" v-model="q" type="search"
                placeholder="Buscar propietario por nombre, documento o teléfono…" @input="buscarDebounced"
              />
              <Loader2 v-if="buscando" :size="14" class="spin" />
            </div>
            <small v-if="q.length >= 2 && !buscando && buscado && !resultados.length" class="muted">
              Sin coincidencias. Registra primero al propietario desde Propietarios.
            </small>
            <div v-if="resultados.length" class="resultados">
              <button v-for="c in resultados" :key="c.id" class="res-item" @click="clienteSel = c; resultados = []; q = ''">
                <strong>{{ c.nombre_completo }}</strong>
                <span class="codigo muted">{{ c.numero_documento }}</span>
              </button>
            </div>
          </template>
        </div>

        <div class="form-grid">
          <div class="field">
            <label for="pac-nombre">Nombre <span class="req">*</span></label>
            <input id="pac-nombre" v-model.trim="form.nombre" type="text" placeholder="Luna" />
          </div>
          <div class="field">
            <label for="pac-especie">Especie <span class="req">*</span></label>
            <select id="pac-especie" v-model="form.especie_id" @change="form.raza_id = ''">
              <option value="">Seleccionar…</option>
              <option v-for="e in especies" :key="e.id" :value="e.id">{{ e.nombre }}</option>
            </select>
          </div>
          <div class="field">
            <label for="pac-raza">Raza</label>
            <div class="raza-row">
              <select id="pac-raza" v-model="form.raza_id" :disabled="!form.especie_id">
                <option value="">Sin especificar</option>
                <option v-for="r in razasDeEspecie" :key="r.id" :value="r.id">
                  {{ r.nombre }}{{ r.propia ? " ·" : "" }}
                </option>
              </select>
              <button
                type="button"
                class="btn"
                :disabled="!form.especie_id"
                title="Agregar una raza que no está en el catálogo"
                aria-label="Agregar una raza que no está en el catálogo"
                @click="agregarRaza"
              >
                <Plus :size="13" />
              </button>
            </div>
            <small class="muted">
              ¿No está en la lista? Agrégala: queda en el catálogo de tu empresa.
            </small>
          </div>
          <div class="field">
            <label for="pac-sexo">Sexo</label>
            <select id="pac-sexo" v-model="form.sexo">
              <option value="desconocido">No registrado</option>
              <option value="macho">Macho</option>
              <option value="hembra">Hembra</option>
            </select>
          </div>
          <div class="field">
            <label for="pac-nac">Fecha de nacimiento</label>
            <input id="pac-nac" v-model="form.fecha_nacimiento" type="date" :max="hoyISO()" />
            <small class="muted">Si no se conoce, usa la edad aproximada.</small>
          </div>
          <div class="field">
            <label for="pac-edad">Edad aproximada (meses)</label>
            <input id="pac-edad" v-model.number="form.edad_aproximada_meses" type="number" min="0" />
          </div>
          <div class="field">
            <label for="pac-peso">Peso (kg)</label>
            <input id="pac-peso" v-model.number="form.peso_kg" type="number" min="0" step="0.1" />
          </div>
          <div class="field">
            <label for="pac-color">Color</label>
            <input id="pac-color" v-model.trim="form.color" type="text" placeholder="Dorado" />
          </div>
          <div class="field">
            <label for="pac-chip">Microchip</label>
            <input id="pac-chip" v-model.trim="form.microchip" type="text" placeholder="985141000000000" />
          </div>
          <div class="field">
            <label for="pac-ester">Esterilizado</label>
            <select id="pac-ester" v-model="form.esterilizado">
              <option :value="false">No</option>
              <option :value="true">Sí</option>
            </select>
          </div>
          <div class="field" style="grid-column: 1 / -1">
            <label for="pac-alergias">Alergias</label>
            <input id="pac-alergias" v-model.trim="form.alergias" type="text" placeholder="Ninguna conocida" />
            <small class="muted">Se muestra como alerta roja en cada atención.</small>
          </div>
          <div class="field" style="grid-column: 1 / -1">
            <label for="pac-cronicas">Condiciones crónicas</label>
            <input id="pac-cronicas" v-model.trim="form.condiciones_cronicas" type="text" placeholder="Cardiopatía, epilepsia…" />
          </div>
          <div class="field" style="grid-column: 1 / -1">
            <label for="pac-senias">Señas particulares</label>
            <textarea id="pac-senias" v-model="form.senias_particulares" rows="2"></textarea>
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
import { AlertCircle, Search, Plus, Loader2 } from "lucide-vue-next";
import { mascotasApi } from "../api/mascotas.api.js";
import { clientesApi } from "../../clientes/api/clientes.api.js";
import { catalogosApi } from "../../catalogos/api/catalogos.api.js";
import { notify } from "../../../shared/composables/useNotify.js";
import { iniciales } from "../../../shared/components/ui/format.js";
import { hoyISO } from "../../../shared/utils/fechas.js";

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
const buscando = ref(false);
const buscado = ref(false);
const guardando = ref(false);
const error = ref("");

const form = reactive({
  nombre: props.paciente?.nombre ?? "",
  especie_id: props.paciente?.especie_id ?? "",
  raza_id: props.paciente?.raza_id ?? "",
  sexo: props.paciente?.sexo ?? "desconocido",
  color: props.paciente?.color ?? "",
  fecha_nacimiento: props.paciente?.fecha_nacimiento ? String(props.paciente.fecha_nacimiento).slice(0, 10) : "",
  edad_aproximada_meses: props.paciente?.edad_aproximada_meses ?? null,
  peso_kg: props.paciente?.peso_kg ?? null,
  microchip: props.paciente?.microchip ?? "",
  esterilizado: props.paciente?.esterilizado ?? false,
  alergias: props.paciente?.alergias ?? "",
  condiciones_cronicas: props.paciente?.condiciones_cronicas ?? "",
  senias_particulares: props.paciente?.senias_particulares ?? "",
});

/**
 * El catálogo del padre puede quedar desfasado si acabamos de crear una raza,
 * así que se mantiene una copia local que se refresca al agregar.
 */
const catalogo = ref(props.especies);
const razasDeEspecie = computed(
  () => catalogo.value.find((e) => e.id === form.especie_id)?.razas ?? [],
);

/** Crea la raza en el catálogo de la empresa y la deja seleccionada. */
async function agregarRaza() {
  const nombre = await notify.prompt("Nueva raza", {
    text: "Se agregará al catálogo de tu empresa para esta especie.",
    placeholder: "Ej. Bulldog Inglés",
  });
  if (!nombre?.trim()) return;
  try {
    const r = await catalogosApi.guardarRaza({
      especie_id: form.especie_id,
      nombre: nombre.trim(),
    });
    const fresco = await catalogosApi.especies();
    catalogo.value = fresco.data ?? [];
    form.raza_id = r.data.id;
  } catch (e) {
    notify.error("No se pudo agregar la raza", e.message);
  }
}

let timer = null;
function buscarDebounced() {
  clearTimeout(timer);
  buscado.value = false;
  if (q.value.length < 2) { resultados.value = []; return; }
  timer = setTimeout(async () => {
    buscando.value = true;
    try {
      const r = await clientesApi.buscar(q.value, 8);
      resultados.value = r.data ?? [];
    } catch (e) {
      resultados.value = [];
      notify.toast(`No se pudo buscar: ${e.message}`, "error");
    } finally {
      buscando.value = false;
      buscado.value = true;
    }
  }, 300);
}

const original = { ...form };
// Texto que el SP vacía si llega "" (COALESCE(nuevo, actual)). Borrar una
// alergia mal registrada tiene que ser posible. Números, fechas, raza y
// microchip pasan por NULLIF: un vacío se ignora y queda el valor anterior.
const TEXTO_BORRABLE = new Set(["color", "senias_particulares", "alergias", "condiciones_cronicas"]);

/** Al crear, solo lo que tiene valor; al editar, solo lo que cambió. */
function payload() {
  const p = {};
  for (const [k, v] of Object.entries(form)) {
    const vacio = v === "" || v === null || v === undefined;
    if (!esEdicion.value) {
      if (!vacio) p[k] = v;
      continue;
    }
    if (v === original[k]) continue;
    if (vacio) {
      if (TEXTO_BORRABLE.has(k)) p[k] = "";
      continue;
    }
    p[k] = v;
  }
  p.esterilizado = form.esterilizado;
  return p;
}

async function guardar() {
  if (guardando.value) return;
  error.value = "";
  if (!form.nombre) { error.value = "El paciente necesita un nombre."; return; }
  if (!form.especie_id) { error.value = "Elige la especie del paciente."; return; }
  if (!esEdicion.value && !clienteSel.value) { error.value = "Elige el propietario."; return; }

  guardando.value = true;
  try {
    if (esEdicion.value) {
      await mascotasApi.actualizar(props.paciente.id, payload());
      emit("guardado", { nuevo: false, id: props.paciente.id });
    } else {
      const r = await mascotasApi.crear({ ...payload(), cliente_id: clienteSel.value.id });
      const especie = catalogo.value.find((e) => e.id === form.especie_id)?.nombre ?? "";
      emit("guardado", {
        nuevo: true, id: r.data?.id, nombre: form.nombre, especie, cliente: clienteSel.value,
      });
    }
  } catch (e) {
    error.value = e.message;
  } finally {
    guardando.value = false;
  }
}

onMounted(async () => {
  // Si el padre no pasó el catálogo (o llega vacío), se pide aquí: sin razas el
  // formulario no se puede completar.
  if (!catalogo.value.length) {
    try {
      const r = await catalogosApi.especies();
      catalogo.value = r.data ?? [];
    } catch {
      // Sin catálogo se puede registrar igual: la raza es opcional.
    }
  }
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
.raza-row { display: flex; gap: 6px; }
.raza-row select { flex: 1; min-width: 0; }
.req { color: var(--red); }
.btn.mini { height: 26px; padding: 0 9px; font-size: 11.5px; }
</style>
