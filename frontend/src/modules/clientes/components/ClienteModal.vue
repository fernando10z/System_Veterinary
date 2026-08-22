<template>
  <div class="modal-back" @click="$emit('close')">
    <div class="modal modal-wide" @click.stop>
      <div class="m-head"><h3>{{ esEdicion ? "Editar propietario" : "Nuevo propietario" }}</h3></div>

      <div class="m-body">
        <div v-if="error" class="callout danger" style="margin-bottom: 14px">
          <AlertCircle :size="15" /> <span>{{ error }}</span>
        </div>

        <div class="form-grid">
          <div class="field">
            <label>Tipo de documento</label>
            <select v-model="form.tipo_documento" :disabled="esEdicion">
              <option value="DNI">DNI</option>
              <option value="CE">Carné de extranjería</option>
              <option value="RUC">RUC</option>
              <option value="PASAPORTE">Pasaporte</option>
            </select>
          </div>
          <div class="field">
            <label>Número <span class="req">*</span></label>
            <input v-model.trim="form.numero_documento" type="text" :disabled="esEdicion" />
          </div>
          <div class="field">
            <label>Nombres <span class="req">*</span></label>
            <input v-model.trim="form.nombres" type="text" />
          </div>
          <div class="field">
            <label>Apellido paterno</label>
            <input v-model.trim="form.apellido_paterno" type="text" />
          </div>
          <div class="field">
            <label>Apellido materno</label>
            <input v-model.trim="form.apellido_materno" type="text" />
          </div>
          <div v-if="form.tipo_documento === 'RUC'" class="field">
            <label>Razón social</label>
            <input v-model.trim="form.razon_social" type="text" />
          </div>
          <div class="field">
            <label>Teléfono</label>
            <input v-model.trim="form.telefono" type="tel" placeholder="9XXXXXXXX" />
          </div>
          <div class="field">
            <label>Teléfono alterno</label>
            <input v-model.trim="form.telefono_alterno" type="tel" />
          </div>
          <div class="field">
            <label>Correo</label>
            <input v-model.trim="form.correo" type="email" />
          </div>
          <div class="field">
            <label>Fecha de nacimiento</label>
            <input v-model="form.fecha_nacimiento" type="date" />
          </div>
          <div class="field" style="grid-column: 1 / -1">
            <label>Dirección</label>
            <input v-model.trim="form.direccion" type="text" />
          </div>
          <div class="field">
            <label>Línea de crédito (S/)</label>
            <input v-model.number="form.linea_credito" type="number" min="0" step="10" />
          </div>
          <div class="field">
            <label>Días de crédito</label>
            <input v-model.number="form.dias_credito" type="number" min="0" />
            <small class="muted">Define el vencimiento de sus comprobantes.</small>
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
          {{ guardando ? "Guardando…" : esEdicion ? "Guardar cambios" : "Registrar propietario" }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { reactive, ref, computed } from "vue";
import { AlertCircle } from "lucide-vue-next";
import { clientesApi } from "../api/clientes.api.js";

const props = defineProps({ cliente: { type: Object, default: null } });
const emit = defineEmits(["close", "guardado"]);

const esEdicion = computed(() => !!props.cliente?.id);
const guardando = ref(false);
const error = ref("");

const form = reactive({
  tipo_documento: props.cliente?.tipo_documento ?? "DNI",
  numero_documento: props.cliente?.numero_documento ?? "",
  nombres: props.cliente?.nombres ?? "",
  apellido_paterno: props.cliente?.apellido_paterno ?? "",
  apellido_materno: props.cliente?.apellido_materno ?? "",
  razon_social: props.cliente?.razon_social ?? "",
  telefono: props.cliente?.telefono ?? "",
  telefono_alterno: props.cliente?.telefono_alterno ?? "",
  correo: props.cliente?.correo ?? "",
  direccion: props.cliente?.direccion ?? "",
  fecha_nacimiento: props.cliente?.fecha_nacimiento ?? "",
  linea_credito: props.cliente?.linea_credito ?? 0,
  dias_credito: props.cliente?.dias_credito ?? 0,
  observaciones: props.cliente?.observaciones ?? "",
});

function payload() {
  const p = {};
  for (const [k, v] of Object.entries(form)) {
    if (v === "" || v === null || v === undefined) continue;
    // Al editar, el documento no viaja: es la identidad del registro.
    if (esEdicion.value && (k === "tipo_documento" || k === "numero_documento")) continue;
    p[k] = v;
  }
  return p;
}

async function guardar() {
  error.value = "";
  if (!form.nombres) { error.value = "Ingresa el nombre del propietario."; return; }
  if (!esEdicion.value && !form.numero_documento) {
    error.value = "Ingresa el número de documento.";
    return;
  }

  guardando.value = true;
  try {
    if (esEdicion.value) await clientesApi.actualizar(props.cliente.id, payload());
    else await clientesApi.crear(payload());
    emit("guardado");
  } catch (e) {
    error.value = e.message;
  } finally {
    guardando.value = false;
  }
}
</script>

<style scoped>
.req { color: var(--red); }
</style>
