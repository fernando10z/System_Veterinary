<template>
  <div>
    <PageHeader
      eyebrow="Operación"
      title="Compras"
      subtitle="Proveedores, órdenes de compra y pagos"
    >
      <template #actions>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="cargando ? 'spin' : ''" /> Actualizar
        </button>
        <button v-if="puedeGestionar && tab === 'proveedores'" class="btn primary" @click="abrirProveedor()">
          <Plus :size="14" /> Nuevo proveedor
        </button>
        <button v-if="puedeGestionar && tab === 'ordenes'" class="btn primary" @click="modalOrden = true">
          <Plus :size="14" /> Nueva orden
        </button>
      </template>
    </PageHeader>

    <div class="stat-row">
      <div class="stat">
        <div class="stat-label">Proveedores <span class="icon-tile"><Truck :size="14" /></span></div>
        <div class="stat-val">{{ proveedores.length }}<span class="unit">activos</span></div>
        <div class="stat-meta">registrados en la empresa</div>
      </div>
      <div class="stat">
        <div class="stat-label">Órdenes abiertas <span class="icon-tile amber"><ClipboardList :size="14" /></span></div>
        <div class="stat-val">{{ abiertas }}<span class="unit">pendientes</span></div>
        <div class="stat-meta">por recibir</div>
      </div>
      <div class="stat">
        <div class="stat-label">Por pagar <span class="icon-tile"><CreditCard :size="14" /></span></div>
        <div class="stat-val">{{ fmtSoles(porPagar) }}</div>
        <div class="stat-meta">saldo con proveedores</div>
      </div>
      <div class="stat">
        <div class="stat-label">Comprado <span class="icon-tile violet"><Receipt :size="14" /></span></div>
        <div class="stat-val">{{ fmtSoles(totalOrdenes) }}</div>
        <div class="stat-meta">en las órdenes listadas</div>
      </div>
    </div>

    <section class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><Truck :size="14" /></span>
          {{ tab === "proveedores" ? "Proveedores" : tab === "ordenes" ? "Órdenes de compra" : "Pagos a proveedores" }}
        </h2>
        <div class="module-panel-head-actions">
          <div class="toggle-group">
            <button :class="tab === 'proveedores' ? 'active' : ''" @click="tab = 'proveedores'">Proveedores</button>
            <button :class="tab === 'ordenes' ? 'active' : ''" @click="tab = 'ordenes'">Órdenes</button>
            <button :class="tab === 'pagos' ? 'active' : ''" @click="tab = 'pagos'">Pagos</button>
          </div>
        </div>
      </header>

      <!-- ---------- Proveedores ---------- -->
      <template v-if="tab === 'proveedores'">
        <div v-if="!proveedores.length" class="module-panel-body module-empty">
          <div class="empty-icon"><Truck :size="22" /></div>
          <h3>Sin proveedores</h3>
          <p>Registra el primer proveedor para poder crear órdenes de compra.</p>
        </div>
        <div v-else class="module-panel-body tabla-wrap">
          <table>
            <thead>
              <tr>
                <th>Proveedor</th><th>Documento</th><th>Contacto</th>
                <th class="num">Órdenes</th><th class="num">Deuda</th><th>Última compra</th>
                <th class="acciones-col"></th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="p in proveedores" :key="p.id">
                <td>
                  <div class="stack">
                    <strong>{{ p.razon_social }}</strong>
                    <small class="muted">{{ p.nombre_comercial || p.categoria || "—" }}</small>
                  </div>
                </td>
                <td class="mono">{{ p.tipo_documento }} {{ p.numero_documento }}</td>
                <td>
                  <div class="stack">
                    <span class="mono">{{ p.telefono || "—" }}</span>
                    <small class="muted">{{ p.correo || "" }}</small>
                  </div>
                </td>
                <td class="num mono">{{ p.total_ordenes }}</td>
                <td class="num mono">
                  <span :class="Number(p.deuda_pendiente) > 0 ? 'deuda' : 'muted'">
                    {{ fmtSoles(p.deuda_pendiente) }}
                  </span>
                </td>
                <td>{{ p.ultima_compra ? fmtDate(p.ultima_compra) : "—" }}</td>
                <td class="acciones-col">
                  <div class="row-actions">
                    <button v-if="puedePagar && Number(p.deuda_pendiente) > 0" class="btn mini" title="Registrar pago" @click="abrirPago(p)">
                      <CreditCard :size="13" />
                    </button>
                    <button v-if="puedeGestionar" class="btn mini" title="Editar" @click="abrirProveedor(p)">
                      <Pencil :size="13" />
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </template>

      <!-- ---------- Órdenes ---------- -->
      <template v-else-if="tab === 'ordenes'">
        <div v-if="!ordenes.length" class="module-panel-body module-empty">
          <div class="empty-icon"><ClipboardList :size="22" /></div>
          <h3>Sin órdenes de compra</h3>
          <p>Crea una orden para reponer stock de medicamentos e insumos.</p>
        </div>
        <div v-else class="module-panel-body tabla-wrap">
          <table>
            <thead>
              <tr>
                <th>Número</th><th>Proveedor</th><th>Emisión</th><th class="num">Ítems</th>
                <th class="num">Total</th><th class="num">Saldo</th><th>Estado</th>
                <th class="acciones-col"></th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="o in ordenes" :key="o.id">
                <td class="mono"><strong>{{ o.numero }}</strong></td>
                <td>{{ o.proveedor }}</td>
                <td class="mono">{{ fmtDate(o.fecha_emision) }}</td>
                <td class="num mono">{{ o.items }}</td>
                <td class="num mono">{{ fmtSoles(o.total) }}</td>
                <td class="num mono">
                  <span :class="Number(o.saldo_pendiente) > 0 ? 'deuda' : 'muted'">
                    {{ fmtSoles(o.saldo_pendiente) }}
                  </span>
                </td>
                <td>
                  <span :class="['estado-pill', toneOrden(o.estado)]">
                    <span class="dot"></span>{{ capitalizar(o.estado) }}
                  </span>
                </td>
                <td class="acciones-col">
                  <div class="row-actions">
                    <button
                      v-if="puedeRecibir && ['enviada', 'en_transito', 'borrador', 'recibida_parcial'].includes(o.estado)"
                      class="btn mini primary"
                      @click="recibir(o)"
                    >
                      Recibir
                    </button>
                    <button v-if="puedePagar && Number(o.saldo_pendiente) > 0" class="btn mini" @click="abrirPagoOrden(o)">
                      Pagar
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </template>

      <!-- ---------- Pagos ---------- -->
      <template v-else>
        <div v-if="!pagos.length" class="module-panel-body module-empty">
          <div class="empty-icon"><CreditCard :size="22" /></div>
          <h3>Sin pagos registrados</h3>
          <p>Aquí quedará el historial de pagos a proveedores.</p>
        </div>
        <div v-else class="module-panel-body tabla-wrap">
          <table>
            <thead>
              <tr><th>Número</th><th>Proveedor</th><th>Orden</th><th>Método</th><th class="num">Monto</th><th>Fecha</th><th>Registró</th></tr>
            </thead>
            <tbody>
              <tr v-for="p in pagos" :key="p.id">
                <td class="mono">{{ p.numero }}</td>
                <td>{{ p.proveedor }}</td>
                <td class="mono">{{ p.orden_compra || "—" }}</td>
                <td>{{ capitalizar(p.metodo) }}</td>
                <td class="num mono">{{ fmtSoles(p.monto) }}</td>
                <td class="mono">{{ fmtFechaHora(p.fecha_pago) }}</td>
                <td class="muted">{{ p.registrado_por || "—" }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </template>
    </section>

    <ProveedorModal
      v-if="modalProveedor"
      :proveedor="editandoProveedor"
      :categorias="categorias"
      @close="modalProveedor = false"
      @guardado="onGuardado"
    />

    <OrdenCompraModal
      v-if="modalOrden"
      :proveedores="proveedores"
      :productos="productos"
      @close="modalOrden = false"
      @guardado="onGuardado"
    />

    <!-- Pago a proveedor -->
    <div v-if="pagoPara" class="modal-back" @click="pagoPara = null">
      <div class="modal" @click.stop>
        <div class="m-head"><h3>Pago a {{ pagoPara.razon_social || pagoPara.proveedor }}</h3></div>
        <div class="m-body">
          <div v-if="errorPago" class="callout danger" style="margin-bottom: 12px">
            <AlertCircle :size="15" /> <span>{{ errorPago }}</span>
          </div>
          <div class="form-grid">
            <div class="field">
              <label>Monto (S/) <span class="req">*</span></label>
              <input v-model.number="pago.monto" type="number" min="0.01" step="0.01" />
            </div>
            <div class="field">
              <label>Método</label>
              <select v-model="pago.metodo">
                <option value="transferencia">Transferencia</option>
                <option value="efectivo">Efectivo</option>
                <option value="deposito">Depósito</option>
                <option value="cheque">Cheque</option>
              </select>
            </div>
            <div class="field" style="grid-column: 1 / -1">
              <label>Referencia</label>
              <input v-model.trim="pago.referencia" type="text" placeholder="N.º de operación" />
            </div>
          </div>
        </div>
        <div class="m-foot modal-actions">
          <button class="btn" @click="pagoPara = null">Cancelar</button>
          <button class="btn primary" :disabled="guardandoPago" @click="registrarPago">
            {{ guardandoPago ? "Registrando…" : "Registrar pago" }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from "vue";
import {
  Truck, ClipboardList, CreditCard, Receipt, Plus, RefreshCw, Pencil, AlertCircle,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import ProveedorModal from "../components/ProveedorModal.vue";
import OrdenCompraModal from "../components/OrdenCompraModal.vue";
import { comprasApi } from "../api/compras.api.js";
import { inventarioApi } from "../../inventario/api/inventario.api.js";
import { catalogosApi } from "../../catalogos/api/catalogos.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { fmtSoles, fmtDate } from "../../../shared/components/ui/format.js";
import { fmtFechaHora, capitalizar } from "../../../shared/components/ui/format.js";
import { notify } from "../../../shared/composables/useNotify.js";

const { hasPermission } = useAuth();
const puedeGestionar = computed(() => hasPermission("compras:gestionar"));
const puedeRecibir = computed(() => hasPermission("compras:recibir"));
const puedePagar = computed(() => hasPermission("compras:pagar"));

const tab = ref("proveedores");
const proveedores = ref([]);
const ordenes = ref([]);
const pagos = ref([]);
const productos = ref([]);
const categorias = ref([]);
const cargando = ref(false);

const modalProveedor = ref(false);
const modalOrden = ref(false);
const editandoProveedor = ref(null);

const pagoPara = ref(null);
const pago = reactive({ monto: 0, metodo: "transferencia", referencia: "", orden_compra_id: null });
const guardandoPago = ref(false);
const errorPago = ref("");

const abiertas = computed(
  () => ordenes.value.filter((o) => !["recibida", "cancelada"].includes(o.estado)).length,
);
const porPagar = computed(() => ordenes.value.reduce((s, o) => s + Number(o.saldo_pendiente), 0));
const totalOrdenes = computed(() => ordenes.value.reduce((s, o) => s + Number(o.total), 0));

function toneOrden(e) {
  return {
    borrador: "neutral", enviada: "info", en_transito: "warn",
    recibida_parcial: "warn", recibida: "ok", cancelada: "danger",
  }[e] || "neutral";
}

function abrirProveedor(p = null) {
  editandoProveedor.value = p;
  modalProveedor.value = true;
}
function abrirPago(p) {
  pagoPara.value = p;
  Object.assign(pago, { monto: Number(p.deuda_pendiente) || 0, metodo: "transferencia", referencia: "", orden_compra_id: null });
  errorPago.value = "";
}
function abrirPagoOrden(o) {
  pagoPara.value = { razon_social: o.proveedor, id: o.proveedor_id };
  Object.assign(pago, { monto: Number(o.saldo_pendiente), metodo: "transferencia", referencia: "", orden_compra_id: o.id });
  errorPago.value = "";
}

async function registrarPago() {
  errorPago.value = "";
  guardandoPago.value = true;
  try {
    await comprasApi.registrarPago({
      proveedor_id: pagoPara.value.id,
      orden_compra_id: pago.orden_compra_id || undefined,
      monto: pago.monto,
      metodo: pago.metodo,
      referencia: pago.referencia || undefined,
    });
    pagoPara.value = null;
    cargar();
  } catch (e) {
    errorPago.value = e.message;
  } finally {
    guardandoPago.value = false;
  }
}

async function recibir(o) {
  const ok = await notify.confirm(
    `¿Recibir la orden ${o.numero}?`,
    "Se registrará la entrada al inventario y se crearán los lotes indicados.",
    { confirmText: "Recibir" },
  );
  if (!ok) return;
  try {
    const r = await comprasApi.recibirOrden(o.id);
    notify.success("Mercadería recibida", `Estado: ${r.data.estado}`);
    cargar();
  } catch (e) {
    notify.error("No se pudo recibir la orden", e.message);
  }
}

function onGuardado() {
  modalProveedor.value = false;
  modalOrden.value = false;
  cargar();
}

async function cargar() {
  cargando.value = true;
  try {
    const [pr, or, pa] = await Promise.all([
      comprasApi.proveedores({ pageSize: 100 }),
      comprasApi.ordenes({ pageSize: 50 }),
      comprasApi.pagos(),
    ]);
    proveedores.value = pr.data ?? [];
    ordenes.value = or.data ?? [];
    pagos.value = pa.data ?? [];
  } finally {
    cargando.value = false;
  }
}

onMounted(async () => {
  const [pd, cat] = await Promise.allSettled([
    inventarioApi.productos({ estado: "activo", pageSize: 100 }),
    catalogosApi.categorias("proveedor"),
  ]);
  if (pd.status === "fulfilled") productos.value = pd.value.data ?? [];
  if (cat.status === "fulfilled") categorias.value = cat.value.data ?? [];
  cargar();
});
</script>

<style scoped>
.deuda { color: var(--red-ink); font-weight: 600; }
.btn.mini { height: 26px; padding: 0 8px; font-size: 11.5px; }
.req { color: var(--red); }
</style>
