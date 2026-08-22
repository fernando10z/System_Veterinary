<template>
  <div class="modal-back" @click="$emit('close')">
    <div class="modal modal-wide" @click.stop>
      <div class="m-head"><h3>{{ esEdicion ? "Editar producto" : "Nuevo producto" }}</h3></div>

      <div class="m-body">
        <div v-if="error" class="callout danger" style="margin-bottom: 14px">
          <AlertCircle :size="15" /> <span>{{ error }}</span>
        </div>

        <div class="form-grid">
          <div class="field" style="grid-column: 1 / -1">
            <label>Nombre <span class="req">*</span></label>
            <input v-model.trim="form.nombre" type="text" placeholder="Amoxicilina 500 mg" />
          </div>
          <div class="field">
            <label>Tipo</label>
            <select v-model="form.tipo">
              <option value="medicamento">Medicamento</option>
              <option value="insumo">Insumo</option>
              <option value="vacuna">Vacuna</option>
              <option value="alimento">Alimento</option>
              <option value="accesorio">Accesorio</option>
              <option value="otro">Otro</option>
            </select>
          </div>
          <div class="field">
            <label>Categoría</label>
            <select v-model="form.categoria_id">
              <option value="">Sin categoría</option>
              <option v-for="c in categorias" :key="c.id" :value="c.id">{{ c.nombre }}</option>
            </select>
          </div>
          <div class="field">
            <label>Presentación</label>
            <input v-model.trim="form.presentacion" type="text" placeholder="Caja x 20 tabletas" />
          </div>
          <div class="field">
            <label>Unidad de medida</label>
            <input v-model.trim="form.unidad_medida" type="text" placeholder="UND" />
          </div>
          <div class="field">
            <label>Principio activo</label>
            <input v-model.trim="form.principio_activo" type="text" />
          </div>
          <div class="field">
            <label>Laboratorio</label>
            <input v-model.trim="form.laboratorio" type="text" />
          </div>
          <div class="field">
            <label>Precio de compra (S/)</label>
            <input v-model.number="form.precio_compra" type="number" min="0" step="0.01" />
          </div>
          <div class="field">
            <label>Precio de venta (S/) <span class="req">*</span></label>
            <input v-model.number="form.precio_venta" type="number" min="0" step="0.01" />
            <small v-if="margen !== null" class="muted">Margen: {{ margen }}%</small>
          </div>
          <div class="field">
            <label>Stock mínimo</label>
            <input v-model.number="form.stock_minimo" type="number" min="0" />
            <small class="muted">Dispara la alerta de stock crítico.</small>
          </div>
          <div class="field">
            <label>Stock máximo</label>
            <input v-model.number="form.stock_maximo" type="number" min="0" />
          </div>
          <div v-if="!esEdicion" class="field">
            <label>Stock inicial</label>
            <input v-model.number="form.stock_inicial" type="number" min="0" />
            <small class="muted">Se registra como entrada en el kardex.</small>
          </div>
          <div class="field" style="grid-column: 1 / -1">
            <label>Descripción</label>
            <textarea v-model="form.descripcion" rows="2"></textarea>
          </div>
        </div>

        <div class="checks">
          <label class="check-line"><input v-model="form.requiere_receta" type="checkbox" /> <span>Requiere receta</span></label>
          <label class="check-line"><input v-model="form.controlado" type="checkbox" /> <span>Controlado</span></label>
          <label class="check-line"><input v-model="form.refrigerado" type="checkbox" /> <span>Refrigerado</span></label>
          <label class="check-line"><input v-model="form.maneja_lotes" type="checkbox" /> <span>Maneja lotes</span></label>
          <label class="check-line"><input v-model="form.afecto_igv" type="checkbox" /> <span>Afecto a IGV</span></label>
        </div>
      </div>

      <div class="m-foot modal-actions">
        <button class="btn" @click="$emit('close')">Cancelar</button>
        <button class="btn primary" :disabled="guardando" @click="guardar">
          {{ guardando ? "Guardando…" : esEdicion ? "Guardar cambios" : "Registrar producto" }}
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
  categorias: { type: Array, default: () => [] },
});
const emit = defineEmits(["close", "guardado"]);

const esEdicion = computed(() => !!props.producto?.id);
const guardando = ref(false);
const error = ref("");

const form = reactive({
  nombre: props.producto?.nombre ?? "",
  tipo: props.producto?.tipo ?? "insumo",
  categoria_id: props.producto?.categoria_id ?? "",
  presentacion: props.producto?.presentacion ?? "",
  unidad_medida: props.producto?.unidad_medida ?? "UND",
  principio_activo: props.producto?.principio_activo ?? "",
  laboratorio: props.producto?.laboratorio ?? "",
  precio_compra: Number(props.producto?.precio_compra ?? 0),
  precio_venta: Number(props.producto?.precio_venta ?? 0),
  stock_minimo: Number(props.producto?.stock_minimo ?? 0),
  stock_maximo: props.producto?.stock_maximo ?? null,
  stock_inicial: 0,
  descripcion: props.producto?.descripcion ?? "",
  requiere_receta: props.producto?.requiere_receta ?? false,
  controlado: props.producto?.controlado ?? false,
  refrigerado: props.producto?.refrigerado ?? false,
  maneja_lotes: props.producto?.maneja_lotes ?? false,
  afecto_igv: props.producto?.afecto_igv ?? true,
});

const margen = computed(() => {
  const c = Number(form.precio_compra);
  const v = Number(form.precio_venta);
  if (!c || !v) return null;
  return Math.round(((v - c) / c) * 100);
});

async function guardar() {
  error.value = "";
  if (!form.nombre) { error.value = "El producto necesita un nombre."; return; }
  if (!form.precio_venta) { error.value = "Indica el precio de venta."; return; }

  guardando.value = true;
  try {
    const p = { ...form };
    if (esEdicion.value) {
      p.id = props.producto.id;
      delete p.stock_inicial;
    }
    for (const k of Object.keys(p)) {
      if (p[k] === "" || p[k] === null) delete p[k];
    }
    // Los booleanos deben viajar aunque sean false.
    for (const b of ["requiere_receta", "controlado", "refrigerado", "maneja_lotes", "afecto_igv"]) {
      p[b] = form[b];
    }
    await inventarioApi.guardarProducto(p);
    emit("guardado");
  } catch (e) {
    error.value = e.message;
  } finally {
    guardando.value = false;
  }
}
</script>

<style scoped>
.checks { display: flex; flex-wrap: wrap; gap: 14px; margin-top: 14px; }
.check-line { display: inline-flex; align-items: center; gap: 7px; font-size: 12.5px; color: var(--ink-2); }
.req { color: var(--red); }
</style>
