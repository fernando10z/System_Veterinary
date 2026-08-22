<template>
  <div>
    <PageHeader
      eyebrow="Configuración"
      title="Auditoría"
      :subtitle="meta.total ? `${meta.total} eventos registrados` : 'Bitácora de acciones del sistema'"
    >
      <template #actions>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="cargando ? 'spin' : ''" /> Actualizar
        </button>
      </template>
    </PageHeader>

    <section class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><History :size="14" /></span>
          Bitácora
          <span class="head-meta">{{ meta.total ?? eventos.length }}</span>
        </h2>
      </header>

      <div class="module-panel-toolbar">
        <div class="fil">
          <CalendarRange :size="14" />
          <input v-model="filtros.desde" type="date" @change="recargar" />
        </div>
        <div class="fil">
          <span class="muted">a</span>
          <input v-model="filtros.hasta" type="date" @change="recargar" />
        </div>
        <div class="fil">
          <Database :size="14" />
          <select v-model="filtros.entidad" @change="recargar">
            <option value="">Todas las entidades</option>
            <option v-for="e in ENTIDADES" :key="e" :value="e">{{ capitalizar(e) }}</option>
          </select>
        </div>
        <div class="fil">
          <Zap :size="14" />
          <select v-model="filtros.accion" @change="recargar">
            <option value="">Todas las acciones</option>
            <option v-for="a in ACCIONES" :key="a" :value="a">{{ capitalizar(a) }}</option>
          </select>
        </div>
        <div class="toolbar-spacer"></div>
        <span v-if="cargando" class="loading-mini"><Loader2 :size="13" class="spin" /> Cargando…</span>
      </div>

      <div v-if="!cargando && !eventos.length" class="module-panel-body module-empty">
        <div class="empty-icon"><History :size="22" /></div>
        <h3>Sin eventos en el periodo</h3>
        <p>Ajusta los filtros para ver más registros.</p>
      </div>

      <div v-else class="module-panel-body tabla-wrap">
        <table>
          <thead>
            <tr><th>Fecha</th><th>Usuario</th><th>Acción</th><th>Entidad</th><th>Sede</th><th>Cambios</th></tr>
          </thead>
          <tbody>
            <tr v-for="e in eventos" :key="e.id">
              <td class="mono">{{ fmtFechaHora(e.created_at) }}</td>
              <td>
                <div class="stack">
                  <strong>{{ e.usuario || "Sistema" }}</strong>
                  <small class="muted">{{ e.usuario_email || "" }}</small>
                </div>
              </td>
              <td><span :class="['estado-pill', toneAccion(e.accion)]">{{ capitalizar(e.accion) }}</span></td>
              <td>
                <span class="tag">{{ capitalizar(e.entidad) }}</span>
              </td>
              <td class="muted">{{ e.sede || "—" }}</td>
              <td>
                <button v-if="tieneDiff(e)" class="btn mini" @click="verDiff(e)">
                  <Eye :size="12" /> {{ Object.keys(e.diff).length }} campos
                </button>
                <span v-else class="muted">—</span>
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
    </section>

    <!-- Detalle del cambio -->
    <div v-if="diffSel" class="modal-back" @click="diffSel = null">
      <div class="modal modal-wide" @click.stop>
        <div class="m-head">
          <h3>{{ capitalizar(diffSel.accion) }} · {{ capitalizar(diffSel.entidad) }}</h3>
        </div>
        <div class="m-body">
          <div class="detalle-grid" style="margin-bottom: 14px">
            <div class="detalle-item"><div class="k">Usuario</div><div class="v">{{ diffSel.usuario || "Sistema" }}</div></div>
            <div class="detalle-item"><div class="k">Fecha</div><div class="v mono">{{ fmtFechaHora(diffSel.created_at) }}</div></div>
            <div class="detalle-item"><div class="k">Registro</div><div class="v mono">{{ diffSel.entidad_id || "—" }}</div></div>
          </div>

          <div class="tabla-wrap">
            <table>
              <thead><tr><th>Campo</th><th>Antes</th><th>Después</th></tr></thead>
              <tbody>
                <tr v-for="(v, k) in diffSel.diff" :key="k">
                  <td><strong>{{ k }}</strong></td>
                  <td class="muted">{{ formatValor(v?.antes) }}</td>
                  <td>{{ formatValor(v?.despues) }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        <div class="m-foot modal-actions">
          <button class="btn" @click="diffSel = null">Cerrar</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted } from "vue";
import { History, RefreshCw, Loader2, CalendarRange, Database, Zap, Eye } from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import { auditoriaApi } from "../api/auditoria.api.js";
import { fmtFechaHora, capitalizar } from "../../../shared/components/ui/format.js";

const ENTIDADES = [
  "users", "clientes", "mascotas", "citas", "consultas", "servicios", "productos",
  "comprobantes", "pagos", "cajas", "proveedores", "ordenes_compra", "empresas", "roles",
];
const ACCIONES = [
  "crear", "actualizar", "eliminar", "login", "emitir", "anular", "cerrar",
  "abrir", "recibir", "registrar_pago", "cambiar_estado", "cambiar_rol",
];

const eventos = ref([]);
const meta = ref({});
const cargando = ref(false);
const diffSel = ref(null);

const hoy = new Date();
const hace7 = new Date(hoy);
hace7.setDate(hace7.getDate() - 7);
const filtros = reactive({
  desde: hace7.toISOString().slice(0, 10),
  hasta: hoy.toISOString().slice(0, 10),
  entidad: "",
  accion: "",
  page: 1,
});

function toneAccion(a) {
  if (["eliminar", "anular"].includes(a)) return "danger";
  if (["crear", "emitir", "registrar_pago"].includes(a)) return "ok";
  if (a === "login") return "neutral";
  return "info";
}

/** El diff `_creado`/`_eliminado` no aporta en la tabla comparativa. */
function tieneDiff(e) {
  const d = e.diff;
  if (!d || typeof d !== "object") return false;
  const claves = Object.keys(d);
  return claves.length > 0 && !claves.every((k) => k.startsWith("_"));
}

function verDiff(e) { diffSel.value = e; }

function formatValor(v) {
  if (v === null || v === undefined) return "—";
  if (typeof v === "object") return JSON.stringify(v);
  return String(v);
}

function recargar() { filtros.page = 1; cargar(); }
function irPagina(p) { filtros.page = p; cargar(); }

async function cargar() {
  cargando.value = true;
  try {
    const hastaExcl = new Date(filtros.hasta);
    hastaExcl.setDate(hastaExcl.getDate() + 1);
    const r = await auditoriaApi.listar({
      desde: filtros.desde,
      hasta: hastaExcl.toISOString().slice(0, 10),
      entidad: filtros.entidad || undefined,
      accion: filtros.accion || undefined,
      page: filtros.page,
      pageSize: 50,
    });
    eventos.value = r.data ?? [];
    meta.value = r.meta ?? {};
  } finally {
    cargando.value = false;
  }
}

onMounted(cargar);
</script>

<style scoped>
.btn.mini { height: 24px; padding: 0 8px; font-size: 11px; }
</style>
