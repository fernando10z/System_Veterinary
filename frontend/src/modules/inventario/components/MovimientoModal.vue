<template>
  <div class="modal-back" @click="$emit('close')">
    <div class="modal" @click.stop>
      <div class="m-head"><h3>Movimiento de inventario</h3></div>

      <div class="m-body">
        <div v-if="error" class="callout danger" style="margin-bottom: 14px">
          <AlertCircle :size="15" /> <span>{{ error }}</span>
        </div>

        <div class="field">
          <label>Producto <span class="req">*</span></label>
          <select v-model="form.producto_id">
            <option value="">Seleccionar…</option>
            <option v-for="p in productos" :key="p.id" :value="p.id">
              {{ p.nombre }} ({{ p.stock_actual }} {{ p.unidad_medida }})
            </option>
          </select>
        </div>

        <div class="form-grid">
          <div class="field">
            <label>Tipo</label>
            <select v-model="form.tipo" @change="sincronizarMotivo">
              <option value="entrada">Entrada</option>
              <option value="salida">Salida</option>
              <option value="ajuste_positivo">Ajuste (+)</option>
              <option value="ajuste_negativo">Ajuste (−)</option>
              <option value="merma">Merma</option>
              <option value="vencimiento">Baja por vencimiento</option>
            </select>
          </div>
          <div class="field">
            <label>Motivo</label>
            <select v-model="form.motivo">
              <option value="compra">Compra</option>
              <option value="venta">Venta</option>
              <option value="uso_clinico">Uso clínico</option>
              <option value="ajuste_inventario">Ajuste de inventario</option>
              <option value="devolucion">Devolución</option>
              <option value="donacion">Donación</option>
              <option value="vencido">Vencido</option>
              <option value="traslado">Traslado</option>
            </select>
          </div>
          <div class="field">
            <label>Cantidad <span class="req">*</span></label>
            <input v-model.number="form.cantidad" type="number" min="0.01" step="0.01" />
          </div>
          <div class="field">
            <label>Costo unitario (S/)</label>
            <input v-model.number="form.costo_unitario" type="number" min="0" step="0.01" />
          </div>
          <div v-if="almacenes.length > 1" class="field" style="grid-column: 1 / -1">
            <label>Almacén</label>
            <select v-model="form.almacen_id">
              <option value="">Principal</option>
              <option v-for="a in almacenes" :key="a.id" :value="a.id">{{ a.nombre }}</option>
            </select>
          </div>
          <div class="field" style="grid-column: 1 / -1">
            <label>Observaciones</label>
            <textarea v-model="form.observaciones" rows="2"></textarea>
          </div>
        </div>

        <p v-if="stockResultante !== null" class="resultado">
          Stock resultante: <strong class="mono">{{ stockResultante }}</strong>
        </p>
      </div>

      <div class="m-foot modal-actions">
        <button class="btn" @click="$emit('close')">Cancelar</button>
        <button class="btn primary" :disabled="guardando" @click="guardar">
          {{ guardando ? "Registrando…" : "Registrar movimiento" }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { reactive, ref, computed } from "vue";
import { AlertCircle } from "lucide-vue-next";
import { inventarioApi } from "../api/inventario.api.js";

const props = defineProps({
  producto: { type: Object, default: null },
  productos: { type: Array, default: () => [] },
  almacenes: { type: Array, default: () => [] },
});
const emit = defineEmits(["close", "guardado"]);

const guardando = ref(false);
const error = ref("");

const form = reactive({
  producto_id: props.producto?.id ?? "",
  tipo: "entrada",
  motivo: "compra",
  cantidad: 1,
  costo_unitario: null,
  almacen_id: "",
  observaciones: "",
});

const seleccionado = computed(() => props.productos.find((p) => p.id === form.producto_id));

/** Anticipa el saldo para que el usuario vea si va a dejar el stock en negativo. */
const stockResultante = computed(() => {
  if (!seleccionado.value || !form.cantidad) return null;
  const actual = Number(seleccionado.value.stock_actual);
  const suma = ["entrada", "ajuste_positivo"].includes(form.tipo);
  return suma ? actual + Number(form.cantidad) : actual - Number(form.cantidad);
});

/** El motivo por defecto coherente con el tipo evita combinaciones sin sentido. */
function sincronizarMotivo() {
  form.motivo = {
    entrada: "compra",
    salida: "uso_clinico",
    ajuste_positivo: "ajuste_inventario",
    ajuste_negativo: "ajuste_inventario",
    merma: "vencido",
    vencimiento: "vencido",
  }[form.tipo] ?? "ajuste_inventario";
}

async function guardar() {
  error.value = "";
  if (!form.producto_id) { error.value = "Elige el producto."; return; }
  if (!form.cantidad || form.cantidad <= 0) { error.value = "La cantidad debe ser mayor a cero."; return; }
  if (stockResultante.value !== null && stockResultante.value < 0) {
    error.value = "El movimiento dejaría el stock en negativo.";
    return;
  }

  guardando.value = true;
  try {
    const p = { ...form };
    for (const k of Object.keys(p)) {
      if (p[k] === "" || p[k] === null) delete p[k];
    }
    await inventarioApi.registrarMovimiento(p);
    emit("guardado");
  } catch (e) {
    error.value = e.message;
  } finally {
    guardando.value = false;
  }
}
</script>

<style scoped>
.resultado { margin-top: 12px; font-size: 12.5px; color: var(--ink-2); }
.req { color: var(--red); }
</style>
