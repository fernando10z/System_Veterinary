<template>
  <div class="modal-back" @click="$emit('close')">
    <div class="modal" @click.stop>
      <div class="m-head"><h3>Aplicar vacuna</h3></div>

      <div class="m-body">
        <div v-if="error" class="callout danger" style="margin-bottom: 14px">
          <AlertCircle :size="15" /> <span>{{ error }}</span>
        </div>

        <div class="form-grid">
          <!-- Elegir el esquema autocompleta nombre y calcula el refuerzo -->
          <div class="field" style="grid-column: 1 / -1">
            <label>Protocolo</label>
            <select v-model="form.esquema_id" @change="onEsquema">
              <option value="">Aplicación libre</option>
              <option v-for="e in esquemas" :key="e.id" :value="e.id">
                {{ e.nombre }}<template v-if="e.obligatoria"> (obligatoria)</template>
              </option>
            </select>
          </div>

          <div class="field" style="grid-column: 1 / -1">
            <label>Nombre de la vacuna <span class="req">*</span></label>
            <input v-model.trim="form.nombre_vacuna" type="text" placeholder="Antirrábica" />
          </div>

          <div class="field">
            <label>Producto del inventario</label>
            <select v-model="form.producto_id">
              <option value="">No descontar stock</option>
              <option v-for="p in productos" :key="p.id" :value="p.id">
                {{ p.nombre }} ({{ p.stock_actual }} disp.)
              </option>
            </select>
            <small class="muted">Si eliges producto, se descuenta una dosis.</small>
          </div>
          <div class="field">
            <label>Laboratorio</label>
            <input v-model.trim="form.laboratorio" type="text" />
          </div>
          <div class="field">
            <label>Lote</label>
            <input v-model.trim="form.lote" type="text" />
          </div>
          <div class="field">
            <label>Vía</label>
            <select v-model="form.via">
              <option value="subcutanea">Subcutánea</option>
              <option value="intramuscular">Intramuscular</option>
              <option value="oral">Oral</option>
              <option value="intravenosa">Intravenosa</option>
            </select>
          </div>
          <div class="field">
            <label>Fecha de aplicación</label>
            <input v-model="form.fecha_aplicacion" type="date" />
          </div>
          <div class="field">
            <label>Dosis n.º</label>
            <input v-model.number="form.dosis_numero" type="number" min="1" />
          </div>
          <div class="field" style="grid-column: 1 / -1">
            <label>Próximo refuerzo</label>
            <input v-model="form.proximo_refuerzo" type="date" />
            <small class="muted">Genera un recordatorio automático para contactar al propietario.</small>
          </div>
          <div class="field" style="grid-column: 1 / -1">
            <label>Observaciones</label>
            <textarea v-model="form.observaciones" rows="2"></textarea>
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
  fecha_aplicacion: new Date().toISOString().slice(0, 10),
  dosis_numero: 1,
  proximo_refuerzo: "",
  observaciones: "",
});

/** El protocolo aporta el nombre y el intervalo hasta el refuerzo. */
function onEsquema() {
  const e = esquemas.value.find((x) => x.id === form.esquema_id);
  if (!e) return;
  form.nombre_vacuna = e.nombre;
  const dias = e.intervalo_dias || (e.revacunacion_meses ? e.revacunacion_meses * 30 : 365);
  const base = new Date(form.fecha_aplicacion);
  base.setDate(base.getDate() + dias);
  form.proximo_refuerzo = base.toISOString().slice(0, 10);
}

async function guardar() {
  error.value = "";
  if (!form.nombre_vacuna) { error.value = "Indica el nombre de la vacuna."; return; }

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
