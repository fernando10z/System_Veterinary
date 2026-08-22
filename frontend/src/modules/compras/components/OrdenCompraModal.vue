<template>
  <div class="modal-back" @click="$emit('close')">
    <div class="modal modal-xwide" @click.stop>
      <div class="m-head"><h3>Nueva orden de compra</h3></div>

      <div class="m-body">
        <div v-if="error" class="callout danger" style="margin-bottom: 14px">
          <AlertCircle :size="15" /> <span>{{ error }}</span>
        </div>

        <div class="form-grid">
          <div class="field">
            <label>Proveedor <span class="req">*</span></label>
            <select v-model="form.proveedor_id">
              <option value="">Seleccionar…</option>
              <option v-for="p in proveedores" :key="p.id" :value="p.id">{{ p.razon_social }}</option>
            </select>
          </div>
          <div class="field">
            <label>Fecha estimada de entrega</label>
            <input v-model="form.fecha_estimada" type="date" />
          </div>
          <div class="field">
            <label>Estado inicial</label>
            <select v-model="form.estado">
              <option value="borrador">Borrador</option>
              <option value="enviada">Enviada al proveedor</option>
            </select>
          </div>
        </div>

        <div class="section-title" style="margin-top: 16px">Ítems</div>
        <div class="tabla-wrap">
          <table>
            <thead>
              <tr>
                <th>Producto</th><th class="num">Cantidad</th><th class="num">Precio</th>
                <th>Lote</th><th>Vence</th><th class="num">Subtotal</th><th class="acciones-col"></th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(it, i) in items" :key="i">
                <td style="min-width: 200px">
                  <select v-model="it.producto_id" @change="autocompletarPrecio(it)">
                    <option value="">Seleccionar…</option>
                    <option v-for="p in productos" :key="p.id" :value="p.id">{{ p.nombre }}</option>
                  </select>
                </td>
                <td class="num"><input v-model.number="it.cantidad" type="number" min="0.01" step="0.01" class="mini-input" /></td>
                <td class="num"><input v-model.number="it.precio_unitario" type="number" min="0" step="0.01" class="mini-input" /></td>
                <td><input v-model.trim="it.numero_lote" type="text" class="mini-input" placeholder="opcional" /></td>
                <td><input v-model="it.fecha_vencimiento" type="date" class="mini-input" /></td>
                <td class="num mono">{{ fmtSoles(subtotal(it)) }}</td>
                <td class="acciones-col">
                  <button class="btn mini" :disabled="items.length === 1" @click="items.splice(i, 1)">
                    <Trash2 :size="13" />
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <button class="btn" style="margin-top: 10px" @click="agregarItem">
          <Plus :size="13" /> Agregar ítem
        </button>

        <div class="totales">
          <div><span>Subtotal</span><span class="mono">{{ fmtSoles(totales.subtotal) }}</span></div>
          <div><span>IGV (18%)</span><span class="mono">{{ fmtSoles(totales.igv) }}</span></div>
          <div class="total"><span>Total</span><span class="mono">{{ fmtSoles(totales.total) }}</span></div>
        </div>
      </div>

      <div class="m-foot modal-actions">
        <button class="btn" @click="$emit('close')">Cancelar</button>
        <button class="btn primary" :disabled="guardando" @click="guardar">
          {{ guardando ? "Creando…" : "Crear orden" }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { reactive, ref, computed } from "vue";
import { AlertCircle, Plus, Trash2 } from "lucide-vue-next";
import { comprasApi } from "../api/compras.api.js";
import { fmtSoles } from "../../../shared/components/ui/format.js";

const props = defineProps({
  proveedores: { type: Array, default: () => [] },
  productos: { type: Array, default: () => [] },
});
const emit = defineEmits(["close", "guardado"]);

const guardando = ref(false);
const error = ref("");

const form = reactive({ proveedor_id: "", fecha_estimada: "", estado: "borrador" });
const items = ref([nuevoItem()]);

function nuevoItem() {
  return { producto_id: "", cantidad: 1, precio_unitario: 0, numero_lote: "", fecha_vencimiento: "" };
}
function agregarItem() { items.value.push(nuevoItem()); }

/** El precio de compra del catálogo es el punto de partida más probable. */
function autocompletarPrecio(it) {
  const p = props.productos.find((x) => x.id === it.producto_id);
  if (p && !it.precio_unitario) it.precio_unitario = Number(p.precio_compra) || 0;
}

function subtotal(it) {
  return (Number(it.cantidad) || 0) * (Number(it.precio_unitario) || 0);
}

const totales = computed(() => {
  const sub = items.value.reduce((s, it) => s + subtotal(it), 0);
  const igv = Math.round(sub * 0.18 * 100) / 100;
  return { subtotal: sub, igv, total: sub + igv };
});

async function guardar() {
  error.value = "";
  if (!form.proveedor_id) { error.value = "Elige el proveedor."; return; }
  const validos = items.value.filter((it) => it.producto_id && it.cantidad > 0);
  if (!validos.length) { error.value = "Agrega al menos un ítem con producto y cantidad."; return; }

  guardando.value = true;
  try {
    await comprasApi.crearOrden({
      proveedor_id: form.proveedor_id,
      fecha_estimada: form.fecha_estimada || undefined,
      estado: form.estado,
      items: validos.map((it) => ({
        producto_id: it.producto_id,
        cantidad: Number(it.cantidad),
        precio_unitario: Number(it.precio_unitario),
        numero_lote: it.numero_lote || undefined,
        fecha_vencimiento: it.fecha_vencimiento || undefined,
      })),
    });
    emit("guardado");
  } catch (e) {
    error.value = e.message;
  } finally {
    guardando.value = false;
  }
}
</script>

<style scoped>
.mini-input {
  width: 100%; height: 28px; padding: 0 7px;
  border: 1px solid var(--line); border-radius: 7px;
  background: var(--bg-elev); font-size: 12.5px; color: var(--ink);
}
.totales {
  margin-top: 16px; margin-left: auto; width: 260px;
  display: flex; flex-direction: column; gap: 6px;
}
.totales > div { display: flex; justify-content: space-between; font-size: 13px; color: var(--ink-2); }
.totales .total {
  border-top: 1px solid var(--line); padding-top: 8px;
  font-size: 15px; font-weight: 700; color: var(--ink);
}
.req { color: var(--red); }
.btn.mini { height: 26px; padding: 0 8px; font-size: 11.5px; }
</style>
