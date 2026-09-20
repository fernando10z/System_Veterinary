<template>
  <div>
    <PageHeader
      eyebrow="Configuración"
      title="Empresa"
      :subtitle="empresa?.razon_social || 'Datos del negocio'"
    >
      <template #actions>
        <div v-if="esSuperAdmin && empresas.length > 1" class="fil">
          <Building2 :size="14" />
          <select v-model="empresaId" @change="cargarEmpresa">
            <option v-for="s in empresas" :key="s.id" :value="s.id">
              {{ s.nombre_comercial || s.razon_social }}
            </option>
          </select>
        </div>
        <button v-if="esSuperAdmin" class="btn" @click="modalNueva = true">
          <Plus :size="14" /> Nueva empresa
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

    <div v-else-if="empresa" class="empresa-grid">
      <section class="module-panel">
        <header class="module-panel-head">
          <h2><span class="head-icon"><Building2 :size="14" /></span> Datos de la clínica</h2>
        </header>
        <div class="module-panel-body">
          <div class="form-grid">
            <div class="field">
              <label>RUC</label>
              <input v-model.trim="f.ruc" type="text" disabled />
              <small class="muted">El RUC identifica a la empresa y no se edita aquí.</small>
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
            <div class="field">
              <label>Distrito</label>
              <input v-model.trim="f.distrito" type="text" maxlength="30" placeholder="MIRAFLORES" />
            </div>
            <div class="field">
              <label>Provincia</label>
              <input v-model.trim="f.provincia" type="text" maxlength="30" placeholder="LIMA" />
            </div>
            <div class="field">
              <label>Departamento</label>
              <input v-model.trim="f.departamento" type="text" maxlength="30" placeholder="LIMA" />
            </div>
            <div class="field">
              <label>Urbanización</label>
              <input v-model.trim="f.urbanizacion" type="text" maxlength="120" />
            </div>
            <div class="field" style="grid-column: 1 / -1">
              <small class="muted">
                Distrito, provincia y departamento van al comprobante electrónico. SUNAT los
                limita a 30 caracteres: más largo y rechaza el documento.
              </small>
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
              <label>Serie de nota de crédito</label>
              <input v-model.trim="f.serie_nota_credito_default" type="text" placeholder="BC01" />
            </div>
            <div class="field">
              <label>Tasa de IGV</label>
              <input v-model.number="f.igv_tasa" type="number" step="0.0001" min="0" max="1" />
              <small class="muted">0.18 equivale al 18%.</small>
            </div>
          </div>

          <div class="section-title" style="margin-top: 18px">Facturación electrónica (SUNAT)</div>

          <label class="check" style="margin-bottom: 12px">
            <input v-model="f.emite_electronico" type="checkbox" />
            <span>
              Esta empresa emite electrónicamente desde el ERP
              <small class="muted" style="display: block">
                Si está apagado, la clínica numera y cobra aquí pero emite su talonario por
                fuera: ningún comprobante suyo se envía a SUNAT.
              </small>
            </span>
          </label>

          <div class="form-grid">
            <div class="field">
              <label>Proveedor</label>
              <select v-model="f.pse_proveedor">
                <option value="the_factory_hka">The Factory HKA</option>
              </select>
            </div>
            <div class="field">
              <label>RUC emisor</label>
              <input v-model.trim="f.pse_ruc" type="text" maxlength="11" :placeholder="f.ruc" />
              <small class="muted">Sólo si difiere del RUC de la empresa (homologación).</small>
            </div>
            <div class="field" style="grid-column: 1 / -1">
              <label>Endpoint del PSE/OSE</label>
              <input
                v-model.trim="f.pse_endpoint"
                type="text"
                placeholder="https://demo-api.thefactoryhka.com.pe/ServiceClients.svc"
              />
            </div>
            <div class="field">
              <label>Usuario</label>
              <input v-model.trim="f.pse_usuario" type="text" autocomplete="off" />
            </div>
            <div class="field">
              <label>Contraseña</label>
              <input
                v-model="f.pse_password"
                type="password"
                autocomplete="new-password"
                placeholder="Déjalo vacío para no cambiarla"
              />
              <small class="muted">Se guarda cifrada y nunca se vuelve a mostrar.</small>
            </div>
          </div>
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
              <label>Estado de la empresa</label>
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
            Empresas de la instalación
            <span class="head-meta">{{ empresas.length }}</span>
          </h2>
        </header>
        <div class="module-panel-body tabla-wrap">
          <table>
            <thead>
              <tr><th>Empresa</th><th>RUC</th><th class="num">Personal</th><th class="num">Citas hoy</th><th>Estado</th></tr>
            </thead>
            <tbody>
              <tr v-for="s in empresas" :key="s.id" class="clickable" @click="empresaId = s.id; cargarEmpresa()">
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

    <!-- Nueva empresa -->
    <div v-if="modalNueva" class="modal-back" @click="modalNueva = false">
      <div class="modal modal-wide" @click.stop>
        <div class="m-head"><h3>Nueva empresa</h3></div>
        <div class="m-body">
          <div v-if="errorNueva" class="callout danger" style="margin-bottom: 12px">
            <AlertCircle :size="15" /> <span>{{ errorNueva }}</span>
          </div>
          <p class="muted" style="margin-top: 0">
            Al crear la empresa se aprovisionan su almacén principal y un primer
            consultorio. No hereda nada de las demás: su catálogo de servicios,
            productos, horario y usuarios se cargan aparte.
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
          <button class="btn primary" :disabled="guardando" @click="crearEmpresa">
            {{ guardando ? "Creando…" : "Crear empresa" }}
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
const empresas = ref([]);
const empresaId = ref("");
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
  distrito: "", provincia: "", departamento: "", urbanizacion: "",
  serie_factura_default: "", serie_boleta_default: "", serie_nota_venta_default: "",
  serie_nota_credito_default: "",
  igv_tasa: 0.18, aforo_consultorios: 1, duracion_cita_min: 30,
  emite_electronico: false, pse_proveedor: "the_factory_hka", pse_ruc: "",
  pse_endpoint: "", pse_usuario: "", pse_password: "", estado: "activa",
});

function hidratar(e) {
  empresa.value = e;
  for (const k of Object.keys(f)) {
    if (e[k] !== undefined && e[k] !== null) f[k] = e[k];
  }
  f.igv_tasa = Number(e.igv_tasa ?? 0.18);
  f.emite_electronico = Boolean(e.emite_electronico);
  // La clave nunca vuelve del servidor: el campo arranca vacío y sólo se manda
  // si el usuario escribe una nueva.
  f.pse_password = "";
}

async function cargarEmpresa() {
  cargando.value = true;
  try {
    const r = empresaId.value ? await empresasApi.obtener(empresaId.value) : await empresasApi.actual();
    hidratar(r.data);
    empresaId.value = r.data.id;
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
    // Apagar la emisión electrónica es un valor, no un campo vacío: el filtro
    // de arriba descarta el string vacío, no el false.
    p.emite_electronico = f.emite_electronico;
    await empresasApi.actualizar(empresa.value.id, p);
    mensaje.value = "Datos de la empresa actualizados.";
    await cargarEmpresa();
  } catch (e) {
    error.value = e.message;
  } finally {
    guardando.value = false;
  }
}

async function crearEmpresa() {
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
    empresas.value = l.data ?? [];
  } catch {
    // Un usuario de una sola empresa no necesita el listado completo.
  }
  await cargarEmpresa();
}

onMounted(cargarTodo);
</script>

<style scoped>
.empresa-grid { display: grid; grid-template-columns: 1fr 1fr; gap: var(--gap-paneles); align-items: start; }
@media (max-width: 1000px) { .empresa-grid { grid-template-columns: 1fr; } }
.req { color: var(--red); }
</style>
