<template>
  <div>
    <PageHeader
      eyebrow="Operación"
      title="Inventario"
      :subtitle="meta.total ? `${meta.total} productos en catálogo` : 'Medicamentos, insumos y alimento'"
    >
      <template #actions>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="cargando ? 'spin' : ''" /> Actualizar
        </button>
        <button v-if="puedeMover" class="btn" @click="abrirMovimiento()">
          <ArrowLeftRight :size="14" /> Movimiento
        </button>
        <button v-if="puedeGestionar" class="btn primary" @click="abrirNuevo()">
          <Plus :size="14" /> Nuevo producto
        </button>
      </template>
    </PageHeader>

    <!-- Alertas: lo que exige acción hoy -->
    <div v-if="hayAlertas" class="alertas-row">
      <div v-if="alertas.stock_critico?.length" class="alerta-card danger">
        <PackageX :size="16" />
        <div>
          <div class="n">{{ alertas.stock_critico.length }}</div>
          <div class="l">En stock crítico</div>
        </div>
        <button class="btn mini" @click="verCriticos">Ver</button>
      </div>
      <div v-if="alertas.por_vencer?.length" class="alerta-card warn">
        <CalendarX :size="16" />
        <div>
          <div class="n">{{ alertas.por_vencer.length }}</div>
          <div class="l">Lotes por vencer (90 d)</div>
        </div>
        <button class="btn mini" @click="tab = 'lotes'">Ver</button>
      </div>
      <div v-if="alertas.vencidos?.length" class="alerta-card danger">
        <Ban :size="16" />
        <div>
          <div class="n">{{ alertas.vencidos.length }}</div>
          <div class="l">Lotes vencidos</div>
        </div>
        <button class="btn mini" @click="tab = 'lotes'">Ver</button>
      </div>
    </div>

    <section class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><Package :size="14" /></span>
          {{ tab === "productos" ? "Catálogo" : tab === "lotes" ? "Lotes y vencimientos" : "Kardex" }}
          <span class="head-meta">{{ tab === "productos" ? (meta.total ?? 0) : "" }}</span>
        </h2>
        <div class="module-panel-head-actions">
          <div class="toggle-group">
            <button :class="tab === 'productos' ? 'active' : ''" @click="tab = 'productos'">Productos</button>
            <button :class="tab === 'lotes' ? 'active' : ''" @click="tab = 'lotes'">Lotes</button>
            <button :class="tab === 'kardex' ? 'active' : ''" @click="verKardex">Kardex</button>
          </div>
        </div>
      </header>

      <!-- ---------- Productos ---------- -->
      <template v-if="tab === 'productos'">
        <div class="module-panel-toolbar">
          <div class="fil grow">
            <Search :size="14" />
            <input v-model="filtros.buscar" type="search" placeholder="Nombre, código, principio activo…" @input="debounced" />
          </div>
          <div class="fil">
            <Filter :size="14" />
            <select v-model="filtros.tipo" @change="recargar">
              <option value="">Todos los tipos</option>
              <option value="medicamento">Medicamento</option>
              <option value="insumo">Insumo</option>
              <option value="vacuna">Vacuna</option>
              <option value="alimento">Alimento</option>
              <option value="accesorio">Accesorio</option>
            </select>
          </div>
          <label class="check-line">
            <input v-model="filtros.soloCriticos" type="checkbox" @change="recargar" />
            <span>Solo stock crítico</span>
          </label>
          <div class="toolbar-spacer"></div>
          <span v-if="cargando" class="loading-mini"><Loader2 :size="13" class="spin" /> Cargando…</span>
        </div>

        <div v-if="!cargando && !productos.length" class="module-panel-body module-empty">
          <div class="empty-icon"><Package :size="22" /></div>
          <h3>Sin productos</h3>
          <p>Registra el primer producto del inventario.</p>
        </div>

        <div v-else class="module-panel-body tabla-wrap">
          <table>
            <thead>
              <tr>
                <th>Producto</th>
                <th>Tipo</th>
                <th class="num">Stock</th>
                <th class="num">Mínimo</th>
                <th class="num">Compra</th>
                <th class="num">Venta</th>
                <th class="num">Margen</th>
                <th>Situación</th>
                <th class="acciones-col"></th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="p in productos" :key="p.id">
                <td>
                  <div class="stack">
                    <strong>
                      {{ p.nombre }}
                      <Snowflake v-if="p.refrigerado" :size="11" class="ico-frio" title="Requiere refrigeración" />
                      <FileWarning v-if="p.requiere_receta" :size="11" class="ico-receta" title="Requiere receta" />
                    </strong>
                    <small class="muted mono">{{ p.codigo }}{{ p.presentacion ? ` · ${p.presentacion}` : "" }}</small>
                  </div>
                </td>
                <td><span class="tag">{{ capitalizar(p.tipo) }}</span></td>
                <td class="num mono">{{ p.stock_actual }} {{ p.unidad_medida }}</td>
                <td class="num mono muted">{{ p.stock_minimo }}</td>
                <td class="num mono">{{ fmtSoles(p.precio_compra) }}</td>
                <td class="num mono">{{ fmtSoles(p.precio_venta) }}</td>
                <td class="num mono">{{ p.margen_pct ? `${p.margen_pct}%` : "—" }}</td>
                <td>
                  <span :class="['estado-pill', toneStock(p.situacion_stock)]">
                    <span class="dot"></span>{{ labelStock(p.situacion_stock) }}
                  </span>
                </td>
                <td class="acciones-col">
                  <div class="row-actions">
                    <button v-if="puedeMover" class="btn mini" title="Movimiento" @click="abrirMovimiento(p)">
                      <ArrowLeftRight :size="13" />
                    </button>
                    <button v-if="puedeGestionar" class="btn mini" title="Editar" @click="abrirEditar(p)">
                      <Pencil :size="13" />
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div v-if="meta.pages > 1" class="module-panel-foot">
          <span class="muted">Página {{ meta.page }} de {{ meta.pages }}</span>
          <div class="wrap-actions">
            <button class="btn" :disabled="meta.page <= 1" @click="irPagina(meta.page - 1)">Anterior</button>
            <button class="btn" :disabled="meta.page >= meta.pages" @click="irPagina(meta.page + 1)">Siguiente</button>
          </div>
        </div>
      </template>

      <!-- ---------- Lotes ---------- -->
      <template v-else-if="tab === 'lotes'">
        <div v-if="!lotes.length" class="module-panel-body module-empty">
          <div class="empty-icon"><CheckCircle2 :size="22" /></div>
          <h3>Sin lotes próximos a vencer</h3>
          <p>Ningún lote vence en los próximos 90 días.</p>
        </div>
        <div v-else class="module-panel-body tabla-wrap">
          <table>
            <thead>
              <tr><th>Producto</th><th>Lote</th><th class="num">Cantidad</th><th>Vence</th><th>Situación</th></tr>
            </thead>
            <tbody>
              <tr v-for="l in lotes" :key="l.lote_id">
                <td><strong>{{ l.producto }}</strong></td>
                <td class="mono">{{ l.numero_lote }}</td>
                <td class="num mono">{{ l.cantidad }}</td>
                <td class="mono">{{ fmtDate(l.fecha_vencimiento) }}</td>
                <td>
                  <span :class="['estado-pill', (l.dias_restantes ?? -1) < 0 ? 'danger' : 'warn']">
                    {{ (l.dias_restantes ?? -1) < 0 ? "Vencido" : `${l.dias_restantes} días` }}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </template>

      <!-- ---------- Kardex ---------- -->
      <template v-else>
        <div v-if="!movimientos.length" class="module-panel-body module-empty">
          <div class="empty-icon"><ArrowLeftRight :size="22" /></div>
          <h3>Sin movimientos</h3>
          <p>Las entradas y salidas del inventario aparecerán aquí.</p>
        </div>
        <div v-else class="module-panel-body tabla-wrap">
          <table>
            <thead>
              <tr>
                <th>Fecha</th><th>Producto</th><th>Tipo</th><th>Motivo</th>
                <th class="num">Cantidad</th><th class="num">Saldo</th><th>Registró</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="m in movimientos" :key="m.id">
                <td class="mono">{{ fmtFechaHora(m.fecha) }}</td>
                <td><strong>{{ m.producto }}</strong><br /><small class="muted mono">{{ m.producto_codigo }}</small></td>
                <td>
                  <span :class="['estado-pill', esEntrada(m.tipo) ? 'ok' : 'danger']">
                    <span class="dot"></span>{{ capitalizar(m.tipo) }}
                  </span>
                </td>
                <td class="muted">{{ capitalizar(m.motivo) }}</td>
                <td class="num mono">{{ esEntrada(m.tipo) ? "+" : "−" }}{{ m.cantidad }}</td>
                <td class="num mono">{{ m.saldo_despues ?? "—" }}</td>
                <td class="muted">{{ m.usuario || "—" }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </template>
    </section>

    <ProductoModal
      v-if="modalProducto"
      :producto="editando"
      :categorias="categorias"
      @close="modalProducto = false"
      @guardado="onGuardado"
    />

    <MovimientoModal
      v-if="modalMovimiento"
      :producto="productoMovimiento"
      :productos="productos"
      :almacenes="almacenes"
      @close="modalMovimiento = false"
      @guardado="onGuardado"
    />
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from "vue";
import {
  Package, PackageX, CalendarX, Ban, Search, Plus, RefreshCw, Loader2, Filter,
  Pencil, ArrowLeftRight, CheckCircle2, Snowflake, FileWarning,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import ProductoModal from "../components/ProductoModal.vue";
import MovimientoModal from "../components/MovimientoModal.vue";
import { inventarioApi } from "../api/inventario.api.js";
import { catalogosApi } from "../../catalogos/api/catalogos.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { fmtSoles, fmtDate } from "../../../shared/components/ui/format.js";
import { fmtFechaHora, capitalizar } from "../../../shared/components/ui/format.js";

const { hasPermission } = useAuth();
const puedeGestionar = computed(() => hasPermission("inventario:gestionar"));
const puedeMover = computed(() => hasPermission("inventario:mover"));

const tab = ref("productos");
const productos = ref([]);
const movimientos = ref([]);
const almacenes = ref([]);
const categorias = ref([]);
const alertas = ref({});
const meta = ref({});
const cargando = ref(false);

const modalProducto = ref(false);
const modalMovimiento = ref(false);
const editando = ref(null);
const productoMovimiento = ref(null);

const filtros = reactive({ buscar: "", tipo: "", soloCriticos: false, page: 1 });

const hayAlertas = computed(
  () => (alertas.value.stock_critico?.length || alertas.value.por_vencer?.length || alertas.value.vencidos?.length) > 0,
);
/** Vencidos primero: son los que hay que retirar del almacén. */
const lotes = computed(() => [...(alertas.value.vencidos ?? []), ...(alertas.value.por_vencer ?? [])]);

function esEntrada(t) { return ["entrada", "ajuste_positivo"].includes(t); }
function toneStock(s) {
  return { agotado: "danger", critico: "warn", exceso: "info", normal: "ok" }[s] || "neutral";
}
function labelStock(s) {
  return { agotado: "Agotado", critico: "Crítico", exceso: "Exceso", normal: "Normal" }[s] || s;
}

let timer = null;
function debounced() { clearTimeout(timer); timer = setTimeout(recargar, 350); }
function recargar() { filtros.page = 1; cargar(); }
function irPagina(p) { filtros.page = p; cargar(); }

function verCriticos() {
  tab.value = "productos";
  filtros.soloCriticos = true;
  recargar();
}

async function verKardex() {
  tab.value = "kardex";
  const r = await inventarioApi.movimientos({ pageSize: 60 });
  movimientos.value = r.data ?? [];
}

function abrirNuevo() { editando.value = null; modalProducto.value = true; }
function abrirEditar(p) { editando.value = p; modalProducto.value = true; }
function abrirMovimiento(p = null) {
  productoMovimiento.value = p;
  modalMovimiento.value = true;
}
function onGuardado() {
  modalProducto.value = false;
  modalMovimiento.value = false;
  cargar();
}

async function cargar() {
  cargando.value = true;
  try {
    const [prod, al] = await Promise.all([
      inventarioApi.productos({
        buscar: filtros.buscar || undefined,
        tipo: filtros.tipo || undefined,
        soloCriticos: filtros.soloCriticos || undefined,
        page: filtros.page,
        pageSize: 25,
      }),
      inventarioApi.alertas(),
    ]);
    productos.value = prod.data ?? [];
    meta.value = prod.meta ?? {};
    alertas.value = al.data ?? {};
    if (tab.value === "kardex") await verKardex();
  } finally {
    cargando.value = false;
  }
}

onMounted(async () => {
  const [alm, cat] = await Promise.allSettled([
    inventarioApi.almacenes(),
    catalogosApi.categorias("producto"),
  ]);
  if (alm.status === "fulfilled") almacenes.value = alm.value.data ?? [];
  if (cat.status === "fulfilled") categorias.value = cat.value.data ?? [];
  cargar();
});
</script>

<style scoped>
.alertas-row { display: grid; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); gap: 12px; margin-bottom: 18px; }
.alerta-card {
  display: flex; align-items: center; gap: 11px;
  padding: 12px 14px; border-radius: 12px;
  background: var(--bg-elev); border: 1px solid var(--line);
}
.alerta-card .n { font-size: 18px; font-weight: 700; color: var(--ink); line-height: 1.1; }
.alerta-card .l { font-size: 11.5px; color: var(--ink-3); }
.alerta-card .btn { margin-left: auto; }
.alerta-card.danger { border-left: 3px solid var(--red); color: var(--red-ink); }
.alerta-card.warn { border-left: 3px solid var(--amber); color: var(--amber-ink); }

.check-line { display: inline-flex; align-items: center; gap: 7px; font-size: 12.5px; color: var(--ink-2); white-space: nowrap; }
.ico-frio { color: var(--blue); vertical-align: -1px; }
.ico-receta { color: var(--amber); vertical-align: -1px; }
.btn.mini { height: 26px; padding: 0 8px; font-size: 11.5px; }
</style>
