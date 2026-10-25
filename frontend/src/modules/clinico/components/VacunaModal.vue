<template>
  <div class="modal-back" v-dialogo="() => $emit('close')">
    <div class="modal" @click.stop>
      <div class="m-head"><h3>Aplicar vacuna</h3></div>

      <div class="m-body">
        <div v-if="error" class="callout danger" style="margin-bottom: 14px">
          <AlertCircle :size="15" /> <span>{{ error }}</span>
        </div>

        <div class="form-grid">
          <!-- Elegir el esquema autocompleta nombre y calcula el refuerzo -->
          <div class="field" style="grid-column: 1 / -1">
            <label for="vacunamoda-esquema-id">Protocolo</label>
            <select id="vacunamoda-esquema-id" v-model="form.esquema_id" @change="onEsquema">
              <option value="">Aplicación libre</option>
              <option v-for="e in esquemas" :key="e.id" :value="e.id">
                {{ e.nombre }}<template v-if="e.obligatoria"> (obligatoria)</template>
              </option>
            </select>
          </div>

          <div class="field" style="grid-column: 1 / -1">
            <label for="vacunamoda-nombre-vacuna">Nombre de la vacuna <span class="req">*</span></label>
            <input id="vacunamoda-nombre-vacuna" v-model.trim="form.nombre_vacuna" type="text" placeholder="Antirrábica" />
          </div>

          <div class="field">
            <label for="vacunamoda-producto-id">Producto del inventario</label>
            <select id="vacunamoda-producto-id" v-model="form.producto_id">
              <option value="">No descontar stock</option>
              <option v-for="p in productos" :key="p.id" :value="p.id">
                {{ p.nombre }} ({{ p.stock_actual }} disp.)
              </option>
            </select>
            <small class="muted">Si eliges producto, se descuenta una dosis.</small>
          </div>
          <div class="field">
            <label for="vacunamoda-laboratorio">Laboratorio</label>
            <input id="vacunamoda-laboratorio" v-model.trim="form.laboratorio" type="text" />
          </div>
          <div class="field">
            <label for="vacunamoda-lote">Lote</label>
            <input id="vacunamoda-lote" v-model.trim="form.lote" type="text" />
          </div>
          <div class="field">
            <label for="vacunamoda-via">Vía</label>
            <select id="vacunamoda-via" v-model="form.via">
              <option value="subcutanea">Subcutánea</option>
              <option value="intramuscular">Intramuscular</option>
              <option value="oral">Oral</option>
              <option value="intravenosa">Intravenosa</option>
            </select>
          </div>
          <div class="field">
            <label for="vacunamoda-fecha-aplicacion">Fecha de aplicación</label>
            <input id="vacunamoda-fecha-aplicacion" v-model="form.fecha_aplicacion" type="date" :max="hoyISO()" @change="calcularRefuerzo" />
          </div>
          <div class="field">
            <label for="vacunamoda-dosis-numero">Dosis n.º</label>
            <input id="vacunamoda-dosis-numero" v-model.number="form.dosis_numero" type="number" min="1" />
          </div>
          <div class="field" style="grid-column: 1 / -1">
            <label for="vacunamoda-proximo-refuerzo">Próximo refuerzo</label>
            <input id="vacunamoda-proximo-refuerzo" v-model="form.proximo_refuerzo" type="date" />
            <small class="muted">Genera un recordatorio automático para contactar al propietario.</small>
          </div>
          <div class="field" style="grid-column: 1 / -1">
            <label for="vacunamoda-observaciones">Observaciones</label>
            <textarea id="vacunamoda-observaciones" v-model="form.observaciones" rows="2"></textarea>
          </div>
        </div>
      </div>

      <div class="m-foot modal-actions">
        <button class="btn" @click="$emit('close')">Cancelar</button>
        <button class="btn primary" :disabled="guardando" @click="guardar">
          {{ guardando ? "Guardando…" : "Registrar aplicación" }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted } from "vue";
import { AlertCircle } from "lucide-vue-next";
import { clinicoApi } from "../api/clinico.api.js";
import { catalogosApi } from "../../catalogos/api/catalogos.api.js";
import { inventarioApi } from "../../inventario/api/inventario.api.js";
import { hoyISO, sumarDias, sumarMeses } from "@/shared/utils/fechas.js";

const props = defineProps({
  mascotaId: { type: String, required: true },
  especieId: { type: String, default: null },
  consultaId: { type: String, default: null },
});
const emit = defineEmits(["close", "guardado"]);

const esquemas = ref([]);
const productos = ref([]);
const guardando = ref(false);
const error = ref("");

const form = reactive({
  esquema_id: "",
  nombre_vacuna: "",
  producto_id: "",
  laboratorio: "",
  lote: "",
  via: "subcutanea",
  fecha_aplicacion: hoyISO(),
  dosis_numero: 1,
  proximo_refuerzo: "",
  observaciones: "",
});

/** El protocolo aporta el nombre y el intervalo hasta el refuerzo. */
function onEsquema() {
  const e = esquemas.value.find((x) => x.id === form.esquema_id);
  if (!e) return;
  form.nombre_vacuna = e.nombre;
  calcularRefuerzo();
}

/** Refuerzo = aplicación + intervalo del protocolo (se recalcula si cambia la fecha). */
function calcularRefuerzo() {
  const e = esquemas.value.find((x) => x.id === form.esquema_id);
  if (!e) return;
  const base = form.fecha_aplicacion || hoyISO();
  if (e.intervalo_dias) form.proximo_refuerzo = sumarDias(base, e.intervalo_dias);
  else form.proximo_refuerzo = sumarMeses(base, e.revacunacion_meses || 12);
}

async function guardar() {
  if (guardando.value) return;
  error.value = "";
  if (!form.nombre_vacuna) { error.value = "Indica el nombre de la vacuna."; return; }
  if (form.fecha_aplicacion > hoyISO()) { error.value = "La fecha de aplicación no puede ser futura."; return; }
  if (form.proximo_refuerzo && form.proximo_refuerzo <= form.fecha_aplicacion) {
    error.value = "El próximo refuerzo debe ser posterior a la aplicación.";
    return;
  }

  guardando.value = true;
  try {
    const payload = { mascota_id: props.mascotaId };
    for (const [k, v] of Object.entries(form)) {
      if (v === "" || v === null) continue;
      payload[k] = v;
    }
    if (props.consultaId) payload.consulta_id = props.consultaId;
    await clinicoApi.aplicarVacuna(payload);
    emit("guardado");
  } catch (e) {
    error.value = e.message;
  } finally {
    guardando.value = false;
  }
}

onMounted(async () => {
  const [es, pr] = await Promise.allSettled([
    catalogosApi.esquemasVacunacion(props.especieId || undefined),
    inventarioApi.productos({ tipo: "vacuna", estado: "activo", pageSize: 50 }),
  ]);
  if (es.status === "fulfilled") esquemas.value = es.value.data ?? [];
  if (pr.status === "fulfilled") productos.value = pr.value.data ?? [];
});
</script>

<style scoped>
.req { color: var(--red); }
</style>
