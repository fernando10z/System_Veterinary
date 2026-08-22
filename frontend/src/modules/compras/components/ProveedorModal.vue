<template>
  <div class="modal-back" @click="$emit('close')">
    <div class="modal modal-wide" @click.stop>
      <div class="m-head"><h3>{{ esEdicion ? "Editar proveedor" : "Nuevo proveedor" }}</h3></div>

      <div class="m-body">
        <div v-if="error" class="callout danger" style="margin-bottom: 14px">
          <AlertCircle :size="15" /> <span>{{ error }}</span>
        </div>

        <div class="form-grid">
          <div class="field">
            <label>Tipo de documento</label>
            <select v-model="form.tipo_documento" :disabled="esEdicion">
              <option value="RUC">RUC</option>
              <option value="DNI">DNI</option>
              <option value="CE">Carné de extranjería</option>
            </select>
          </div>
          <div class="field">
            <label>Número <span class="req">*</span></label>
            <input v-model.trim="form.numero_documento" type="text" :disabled="esEdicion" />
          </div>
          <div class="field" style="grid-column: 1 / -1">
            <label>Razón social <span class="req">*</span></label>
            <input v-model.trim="form.razon_social" type="text" />
          </div>
          <div class="field">
            <label>Nombre comercial</label>
            <input v-model.trim="form.nombre_comercial" type="text" />
          </div>
          <div class="field">
            <label>Categoría</label>
            <select v-model="form.categoria_id">
              <option value="">Sin categoría</option>
              <option v-for="c in categorias" :key="c.id" :value="c.id">{{ c.nombre }}</option>
            </select>
          </div>
          <div class="field">
            <label>Teléfono</label>
            <input v-model.trim="form.telefono" type="tel" />
          </div>
          <div class="field">
            <label>Correo</label>
            <input v-model.trim="form.correo" type="email" />
          </div>
          <div class="field">
            <label>Días de crédito</label>
            <input v-model.number="form.dias_credito" type="number" min="0" />
          </div>
          <div class="field">
            <label>Banco</label>
            <input v-model.trim="form.banco" type="text" />
          </div>
          <div class="field" style="grid-column: 1 / -1">
            <label>Cuenta bancaria</label>
            <input v-model.trim="form.cuenta_bancaria" type="text" />
          </div>
          <div class="field" style="grid-column: 1 / -1">
            <label>Dirección</label>
            <input v-model.trim="form.direccion" type="text" />
          </div>
        </div>
      </div>

      <div class="m-foot modal-actions">
        <button class="btn" @click="$emit('close')">Cancelar</button>
        <button class="btn primary" :disabled="guardando" @click="guardar">
          {{ guardando ? "Guardando…" : "Guardar" }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { reactive, ref, computed } from "vue";
import { AlertCircle } from "lucide-vue-next";
import { comprasApi } from "../api/compras.api.js";

const props = defineProps({
  proveedor: { type: Object, default: null },
  categorias: { type: Array, default: () => [] },
});
const emit = defineEmits(["close", "guardado"]);

const esEdicion = computed(() => !!props.proveedor?.id);
const guardando = ref(false);
const error = ref("");

const form = reactive({
  tipo_documento: props.proveedor?.tipo_documento ?? "RUC",
  numero_documento: props.proveedor?.numero_documento ?? "",
  razon_social: props.proveedor?.razon_social ?? "",
  nombre_comercial: props.proveedor?.nombre_comercial ?? "",
  categoria_id: props.proveedor?.categoria_id ?? "",
  telefono: props.proveedor?.telefono ?? "",
  correo: props.proveedor?.correo ?? "",
  dias_credito: props.proveedor?.dias_credito ?? 0,
  banco: props.proveedor?.banco ?? "",
  cuenta_bancaria: props.proveedor?.cuenta_bancaria ?? "",
  direccion: props.proveedor?.direccion ?? "",
});

async function guardar() {
  error.value = "";
  if (!form.razon_social) { error.value = "Ingresa la razón social."; return; }
  if (!esEdicion.value && !form.numero_documento) { error.value = "Ingresa el documento."; return; }

  guardando.value = true;
  try {
    const p = {};
    for (const [k, v] of Object.entries(form)) {
      if (v === "" || v === null) continue;
      if (esEdicion.value && (k === "tipo_documento" || k === "numero_documento")) continue;
      p[k] = v;
    }
    if (esEdicion.value) p.id = props.proveedor.id;
    await comprasApi.guardarProveedor(p);
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
