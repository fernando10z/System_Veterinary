<template>
  <div class="modal-back" v-dialogo="() => $emit('close')">
    <div class="modal modal-wide" @click.stop>
      <div class="m-head"><h3>{{ esEdicion ? "Editar propietario" : "Nuevo propietario" }}</h3></div>

      <div class="m-body">
        <div v-if="error" class="callout danger" style="margin-bottom: 14px">
          <AlertCircle :size="15" /> <span>{{ error }}</span>
        </div>

        <div class="form-grid">
          <div class="field">
            <label for="cli-tipo-doc">Tipo de documento</label>
            <select id="cli-tipo-doc" v-model="form.tipo_documento" :disabled="esEdicion" @change="validarCampo('numero_documento')">
              <option value="DNI">DNI</option>
              <option value="CE">Carné de extranjería</option>
              <option value="RUC">RUC</option>
              <option value="PASAPORTE">Pasaporte</option>
            </select>
          </div>
          <div class="field">
            <label for="cli-num-doc">Número <span class="req">*</span></label>
            <input
              id="cli-num-doc" v-model.trim="form.numero_documento" type="text" :disabled="esEdicion"
              :maxlength="maxDocumento(form.tipo_documento)"
              :inputmode="['DNI', 'RUC'].includes(form.tipo_documento) ? 'numeric' : 'text'"
              autocomplete="off" :class="{ invalid: errores.numero_documento }"
              @blur="validarCampo('numero_documento')"
            />
            <small v-if="errores.numero_documento" class="field-error">{{ errores.numero_documento }}</small>
          </div>
          <div class="field">
            <label for="cli-nombres">Nombres <span class="req">*</span></label>
            <input
              id="cli-nombres" v-model.trim="form.nombres" type="text" maxlength="150"
              :class="{ invalid: errores.nombres }" @blur="validarCampo('nombres')"
            />
            <small v-if="errores.nombres" class="field-error">{{ errores.nombres }}</small>
          </div>
          <div class="field">
            <label for="cli-ap-pat">Apellido paterno</label>
            <input id="cli-ap-pat" v-model.trim="form.apellido_paterno" type="text" maxlength="100" />
          </div>
          <div class="field">
            <label for="cli-ap-mat">Apellido materno</label>
            <input id="cli-ap-mat" v-model.trim="form.apellido_materno" type="text" maxlength="100" />
          </div>
          <div v-if="form.tipo_documento === 'RUC'" class="field">
            <label for="cli-razon">Razón social</label>
            <input id="cli-razon" v-model.trim="form.razon_social" type="text" maxlength="255" />
          </div>
          <div class="field">
            <label for="cli-tel">Celular</label>
            <input
              id="cli-tel" v-model.trim="form.telefono" type="tel" inputmode="tel" maxlength="30"
              placeholder="9XXXXXXXX" :class="{ invalid: errores.telefono }" @blur="validarCampo('telefono')"
            />
            <small v-if="errores.telefono" class="field-error">{{ errores.telefono }}</small>
          </div>
          <div class="field">
            <label for="cli-tel2">Teléfono alterno</label>
            <input
              id="cli-tel2" v-model.trim="form.telefono_alterno" type="tel" inputmode="tel" maxlength="30"
              :class="{ invalid: errores.telefono_alterno }" @blur="validarCampo('telefono_alterno')"
            />
            <small v-if="errores.telefono_alterno" class="field-error">{{ errores.telefono_alterno }}</small>
          </div>
          <div class="field">
            <label for="cli-correo">Correo</label>
            <input
              id="cli-correo" v-model.trim="form.correo" type="email" inputmode="email" autocomplete="off"
              :class="{ invalid: errores.correo }" @blur="validarCampo('correo')"
            />
            <small v-if="errores.correo" class="field-error">{{ errores.correo }}</small>
          </div>
          <div class="field">
            <label for="cli-nac">Fecha de nacimiento</label>
            <input id="cli-nac" v-model="form.fecha_nacimiento" type="date" :max="hoyISO()" />
          </div>
          <div class="field" style="grid-column: 1 / -1">
            <label for="cli-dir">Dirección</label>
            <input id="cli-dir" v-model.trim="form.direccion" type="text" />
          </div>
          <div class="field">
            <label for="cli-credito">Línea de crédito (S/)</label>
            <input id="cli-credito" v-model.number="form.linea_credito" type="number" min="0" step="10" inputmode="decimal" />
          </div>
          <div class="field">
            <label for="cli-dias">Días de crédito</label>
            <input id="cli-dias" v-model.number="form.dias_credito" type="number" min="0" inputmode="numeric" />
            <small class="muted">Define el vencimiento de sus comprobantes.</small>
          </div>
          <div class="field" style="grid-column: 1 / -1">
            <label for="cli-obs">Observaciones</label>
            <textarea id="cli-obs" v-model="form.observaciones" rows="2"></textarea>
          </div>
        </div>
      </div>

      <div class="m-foot modal-actions">
        <button class="btn" @click="$emit('close')">Cancelar</button>
        <button :class="['btn', !esEdicion && conMascota ? '' : 'primary']" :disabled="guardando" @click="guardar(false)">
          {{ guardando ? "Guardando…" : esEdicion ? "Guardar cambios" : "Registrar propietario" }}
        </button>
        <button v-if="!esEdicion && conMascota" class="btn primary" :disabled="guardando" @click="guardar(true)">
          <PawPrint :size="14" /> Registrar y agregar mascota
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { reactive, ref, computed } from "vue";
import { AlertCircle, PawPrint } from "lucide-vue-next";
import { clientesApi } from "../api/clientes.api.js";
import {
  validarDocumento, maxDocumento, validarCelular, validarTelefono, validarCorreo,
} from "../../../shared/utils/validaciones.js";
import { hoyISO } from "../../../shared/utils/fechas.js";

const props = defineProps({
  cliente: { type: Object, default: null },
  /** Muestra "Registrar y agregar mascota" (alta de propietario en recepción). */
  conMascota: { type: Boolean, default: true },
});
/** guardado(payload): { id, nuevo, agregarMascota } */
const emit = defineEmits(["close", "guardado"]);

const esEdicion = computed(() => !!props.cliente?.id);
const guardando = ref(false);
const error = ref("");
const errores = reactive({ numero_documento: "", nombres: "", telefono: "", telefono_alterno: "", correo: "" });

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
  fecha_nacimiento: props.cliente?.fecha_nacimiento ? String(props.cliente.fecha_nacimiento).slice(0, 10) : "",
  linea_credito: props.cliente?.linea_credito ?? 0,
  dias_credito: props.cliente?.dias_credito ?? 0,
  observaciones: props.cliente?.observaciones ?? "",
});
const original = { ...form };

// Campos de texto que el SP vacía si llegan como "" (COALESCE(nuevo, actual)).
// fecha_nacimiento y correo pasan por NULLIF: un vacío se ignora y queda el valor anterior.
const TEXTO_BORRABLE = new Set([
  "apellido_paterno", "apellido_materno", "razon_social", "telefono",
  "telefono_alterno", "direccion", "observaciones",
]);

function validarCampo(k) {
  const v = form[k];
  if (k === "numero_documento") errores[k] = esEdicion.value ? "" : validarDocumento(form.tipo_documento, v);
  else if (k === "nombres") errores[k] = v ? "" : "Ingresa el nombre del propietario.";
  else if (k === "telefono") errores[k] = validarCelular(v);
  else if (k === "telefono_alterno") errores[k] = validarTelefono(v);
  else if (k === "correo") errores[k] = validarCorreo(v);
  return !errores[k];
}

function payload() {
  const p = {};
  for (const [k, v] of Object.entries(form)) {
    // Al editar, el documento no viaja: es la identidad del registro.
    if (esEdicion.value && (k === "tipo_documento" || k === "numero_documento")) continue;
    const vacio = v === "" || v === null || v === undefined;
    if (!esEdicion.value) {
      if (!vacio) p[k] = v;
      continue;
    }
    // Edición: solo lo que cambió. Un texto borrado viaja como "" para vaciarlo.
    if (v === original[k]) continue;
    if (vacio) {
      if (TEXTO_BORRABLE.has(k)) p[k] = "";
      continue;
    }
    p[k] = v;
  }
  if (p.linea_credito !== undefined) p.linea_credito = Number(p.linea_credito) || 0;
  if (p.dias_credito !== undefined) p.dias_credito = Number(p.dias_credito) || 0;
  return p;
}

async function guardar(agregarMascota = false) {
  if (guardando.value) return;
  error.value = "";
  const ok = ["numero_documento", "nombres", "telefono", "telefono_alterno", "correo"]
    .map(validarCampo).every(Boolean);
  if (!ok) { error.value = "Revisa los campos marcados."; return; }

  guardando.value = true;
  try {
    if (esEdicion.value) {
      const p = payload();
      if (Object.keys(p).length) await clientesApi.actualizar(props.cliente.id, p);
      emit("guardado", { id: props.cliente.id, nuevo: false, agregarMascota: false });
    } else {
      const r = await clientesApi.crear(payload());
      emit("guardado", {
        id: r.data?.id, nuevo: true, agregarMascota,
        cliente: {
          id: r.data?.id,
          nombre_completo: [form.nombres, form.apellido_paterno, form.apellido_materno].filter(Boolean).join(" "),
          numero_documento: form.numero_documento,
        },
      });
    }
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
