<template>
  <div>
    <PageHeader
      eyebrow="Configuración"
      title="Sede"
      :subtitle="empresa?.razon_social || 'Datos de la clínica'"
    >
      <template #actions>
        <div v-if="esSuperAdmin && sedes.length > 1" class="fil">
          <Building2 :size="14" />
          <select v-model="sedeId" @change="cargarSede">
            <option v-for="s in sedes" :key="s.id" :value="s.id">
              {{ s.nombre_comercial || s.razon_social }}
            </option>
          </select>
        </div>
        <button v-if="esSuperAdmin" class="btn" @click="modalNueva = true">
          <Plus :size="14" /> Nueva sede
        </button>
        <button class="btn primary" :disabled="guardando" @click="guardar">
          <Save :size="14" /> {{ guardando ? "Guardando…" : "Guardar cambios" }}
        </button>
      </template>
    </PageHeader>

    <div v-if="error" class="callout danger" style="margin-bottom: 14px">
      <AlertCircle :size="15" /> <span>{{ error }}</span>
    </div>
    <div v-if="mensaje" class="callout" style="margin-bottom: 14px">
      <CheckCircle2 :size="15" /> <span>{{ mensaje }}</span>
    </div>

    <div v-if="cargando" class="module-panel">
      <div class="module-panel-body module-empty">
        <span class="loading-mini"><Loader2 :size="14" class="spin" /> Cargando…</span>
      </div>
    </div>

    <div v-else-if="empresa" class="sede-grid">
      <section class="module-panel">
        <header class="module-panel-head">
          <h2><span class="head-icon"><Building2 :size="14" /></span> Datos de la clínica</h2>
        </header>
        <div class="module-panel-body">
          <div class="form-grid">
            <div class="field">
              <label>RUC</label>
              <input v-model.trim="f.ruc" type="text" disabled />
              <small class="muted">El RUC identifica a la sede y no se edita aquí.</small>
            </div>
            <div class="field">
              <label>Razón social</label>
              <input v-model.trim="f.razon_social" type="text" />
            </div>
            <div class="field">
              <label>Nombre comercial</label>
              <input v-model.trim="f.nombre_comercial" type="text" />
            </div>
            <div class="field">
              <label>Teléfono</label>
              <input v-model.trim="f.telefono" type="tel" />
            </div>
            <div class="field">
              <label>Correo</label>
              <input v-model.trim="f.correo" type="email" />
            </div>
            <div class="field">
              <label>Ubigeo</label>
              <input v-model.trim="f.ubigeo" type="text" maxlength="6" />
            </div>
            <div class="field" style="grid-column: 1 / -1">
              <label>Dirección fiscal</label>
              <input v-model.trim="f.direccion_fiscal" type="text" />
            </div>
            <div class="field" style="grid-column: 1 / -1">
              <label>Logo (URL)</label>
              <input v-model.trim="f.logo_url" type="text" placeholder="https://…" />
            </div>
          </div>
        </div>
      </section>

      <section class="module-panel">
        <header class="module-panel-head">
          <h2><span class="head-icon"><Receipt :size="14" /></span> Facturación</h2>
        </header>
        <div class="module-panel-body">
          <div class="form-grid">
            <div class="field">
              <label>Serie de factura</label>
              <input v-model.trim="f.serie_factura_default" type="text" placeholder="F001" />
            </div>
            <div class="field">
              <label>Serie de boleta</label>
              <input v-model.trim="f.serie_boleta_default" type="text" placeholder="B001" />
            </div>
            <div class="field">
              <label>Serie de nota de venta</label>
              <input v-model.trim="f.serie_nota_venta_default" type="text" placeholder="NV01" />
            </div>
            <div class="field">
              <label>Tasa de IGV</label>
              <input v-model.number="f.igv_tasa" type="number" step="0.0001" min="0" max="1" />
              <small class="muted">0.18 equivale al 18%.</small>
            </div>
          </div>

          <div class="section-title" style="margin-top: 18px">Proveedor de facturación electrónica</div>
          <div class="form-grid">
            <div class="field" style="grid-column: 1 / -1">
              <label>Endpoint del PSE/OSE</label>
              <input v-model.trim="f.pse_endpoint" type="text" placeholder="https://api.proveedor.com" />
            </div>
            <div class="field">
              <label>Usuario</label>
              <input v-model.trim="f.pse_usuario" type="text" />
            </div>
          </div>
          <small class="muted">
            La contraseña del PSE se guarda cifrada y no se muestra: se reemplaza desde el
            backend al configurar la integración.
          </small>
        </div>
      </section>

      <section class="module-panel">
        <header class="module-panel-head">
          <h2><span class="head-icon"><CalendarClock :size="14" /></span> Operación</h2>
        </header>
        <div class="module-panel-body">
          <div class="form-grid">
            <div class="field">
              <label>Consultorios simultáneos</label>
              <input v-model.number="f.aforo_consultorios" type="number" min="1" />
            </div>
            <div class="field">
              <label>Duración por defecto de cita (min)</label>
              <input v-model.number="f.duracion_cita_min" type="number" min="5" step="5" />
              <small class="muted">Define el tamaño de los huecos de la agenda.</small>
            </div>
            <div class="field">
              <label>Estado de la sede</label>
              <select v-model="f.estado" :disabled="!esSuperAdmin">
                <option value="activa">Activa</option>
                <option value="suspendida">Suspendida</option>
                <option value="cerrada">Cerrada</option>
              </select>
            </div>
          </div>
        </div>
      </section>

      <section v-if="esSuperAdmin" class="module-panel">
        <header class="module-panel-head">
          <h2>
            <span class="head-icon"><Network :size="14" /></span>
            Sedes de la cadena
            <span class="head-meta">{{ sedes.length }}</span>
          </h2>
        </header>
        <div class="module-panel-body tabla-wrap">
          <table>
            <thead>
              <tr><th>Sede</th><th>RUC</th><th class="num">Personal</th><th class="num">Citas hoy</th><th>Estado</th></tr>
            </thead>
            <tbody>
              <tr v-for="s in sedes" :key="s.id" class="clickable" @click="sedeId = s.id; cargarSede()">
                <td>
                  <div class="stack">
                    <strong>{{ s.nombre_comercial || s.razon_social }}</strong>
                    <small class="muted">{{ s.direccion_fiscal }}</small>
                  </div>
                </td>
                <td class="mono">{{ s.ruc }}</td>
                <td class="num mono">{{ s.total_personal }}</td>
                <td class="num mono">{{ s.citas_hoy }}</td>
                <td>
                  <span :class="['estado-pill', s.estado === 'activa' ? 'ok' : 'neutral']">
                    <span class="dot"></span>{{ capitalizar(s.estado) }}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>

    <!-- Nueva sede -->
    <div v-if="modalNueva" class="modal-back" @click="modalNueva = false">
      <div class="modal modal-wide" @click.stop>
        <div class="m-head"><h3>Nueva sede</h3></div>
        <div class="m-body">
          <div v-if="errorNueva" class="callout danger" style="margin-bottom: 12px">
            <AlertCircle :size="15" /> <span>{{ errorNueva }}</span>
          </div>
          <p class="muted" style="margin-top: 0">
            Al crear la sede se aprovisionan automáticamente su almacén principal
            y un primer consultorio, para que pueda operar desde el día uno.
          </p>
          <div class="form-grid">
            <div class="field">
              <label>RUC <span class="req">*</span></label>
              <input v-model.trim="nueva.ruc" type="text" maxlength="11" />
            </div>
            <div class="field">
              <label>Razón social <span class="req">*</span></label>
              <input v-model.trim="nueva.razon_social" type="text" />
            </div>
            <div class="field">
              <label>Nombre comercial</label>
              <input v-model.trim="nueva.nombre_comercial" type="text" />
            </div>
            <div class="field">
              <label>Teléfono</label>
              <input v-model.trim="nueva.telefono" type="tel" />
            </div>
            <div class="field" style="grid-column: 1 / -1">
              <label>Dirección</label>
              <input v-model.trim="nueva.direccion_fiscal" type="text" />
            </div>
          </div>
        </div>
        <div class="m-foot modal-actions">
          <button class="btn" @click="modalNueva = false">Cancelar</button>
          <button class="btn primary" :disabled="guardando" @click="crearSede">
            {{ guardando ? "Creando…" : "Crear sede" }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from "vue";
import {
  Building2, Receipt, CalendarClock, Network, Save, Plus, Loader2,
  AlertCircle, CheckCircle2,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import { empresasApi } from "../api/empresas.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { capitalizar } from "../../../shared/components/ui/format.js";

const { isSuperAdmin } = useAuth();
const esSuperAdmin = computed(() => isSuperAdmin.value);

const empresa = ref(null);
const sedes = ref([]);
const sedeId = ref("");
const cargando = ref(true);
const guardando = ref(false);
const error = ref("");
const mensaje = ref("");

const modalNueva = ref(false);
const errorNueva = ref("");
const nueva = reactive({ ruc: "", razon_social: "", nombre_comercial: "", telefono: "", direccion_fiscal: "" });

const f = reactive({
  ruc: "", razon_social: "", nombre_comercial: "", direccion_fiscal: "", ubigeo: "",
  telefono: "", correo: "", logo_url: "",
  serie_factura_default: "", serie_boleta_default: "", serie_nota_venta_default: "",
  igv_tasa: 0.18, aforo_consultorios: 1, duracion_cita_min: 30,
  pse_endpoint: "", pse_usuario: "", estado: "activa",
});

function hidratar(e) {
  empresa.value = e;
  for (const k of Object.keys(f)) {
    if (e[k] !== undefined && e[k] !== null) f[k] = e[k];
  }
  f.igv_tasa = Number(e.igv_tasa ?? 0.18);
}

async function cargarSede() {
  cargando.value = true;
  try {
    const r = sedeId.value ? await empresasApi.obtener(sedeId.value) : await empresasApi.actual();
    hidratar(r.data);
    sedeId.value = r.data.id;
  } catch (e) {
    error.value = e.message;
  } finally {
    cargando.value = false;
  }
}

async function guardar() {
  error.value = "";
  mensaje.value = "";
  guardando.value = true;
  try {
    const p = {};
    for (const [k, v] of Object.entries(f)) {
      if (k === "ruc" || v === "" || v === null) continue;
      p[k] = v;
    }
    await empresasApi.actualizar(empresa.value.id, p);
    mensaje.value = "Datos de la sede actualizados.";
    await cargarSede();
  } catch (e) {
    error.value = e.message;
  } finally {
    guardando.value = false;
  }
}

async function crearSede() {
  errorNueva.value = "";
  if (!nueva.ruc || !nueva.razon_social) {
    errorNueva.value = "RUC y razón social son obligatorios.";
    return;
  }
  guardando.value = true;
  try {
    const p = {};
    for (const [k, v] of Object.entries(nueva)) if (v) p[k] = v;
    await empresasApi.crear(p);
    modalNueva.value = false;
    Object.assign(nueva, { ruc: "", razon_social: "", nombre_comercial: "", telefono: "", direccion_fiscal: "" });
    await cargarTodo();
  } catch (e) {
    errorNueva.value = e.message;
  } finally {
    guardando.value = false;
  }
}

async function cargarTodo() {
  try {
    const l = await empresasApi.listar();
    sedes.value = l.data ?? [];
  } catch {
    // Un usuario de sede única no necesita el listado completo.
  }
  await cargarSede();
}

onMounted(cargarTodo);
</script>

<style scoped>
.sede-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; align-items: start; }
@media (max-width: 1000px) { .sede-grid { grid-template-columns: 1fr; } }
.req { color: var(--red); }
</style>
