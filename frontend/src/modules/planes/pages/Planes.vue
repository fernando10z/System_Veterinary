<template>
  <div>
    <PageHeader
      eyebrow="Clínica"
      title="Planes preventivos"
      subtitle="La cuota que convierte una urgencia al año en tres visitas de control"
    >
      <template #actions>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="{ spin: cargando }" /> Actualizar
        </button>
        <button v-if="puedeVender" class="btn" @click="abrirSuscripcion()">
          <UserPlus :size="14" /> Suscribir paciente
        </button>
        <button v-if="puedeGestionar" class="btn primary" @click="abrirPlan()">
          <Plus :size="14" /> Nuevo plan
        </button>
      </template>
    </PageHeader>

    <div v-if="error" class="callout danger" style="margin-bottom: 14px">
      <AlertCircle :size="15" /> <span>{{ error }}</span>
    </div>

    <div class="kpis">
      <div class="kpi-mini"><span class="k">Suscripciones activas</span>
        <strong class="v">{{ metaSus.activas ?? 0 }}</strong></div>
      <div class="kpi-mini"><span class="k">Ingreso recurrente</span>
        <strong class="v">{{ fmtSoles(metaSus.recurrente ?? 0) }}</strong>
        <em class="pie">por periodo de cobro</em></div>
      <div class="kpi-mini" :class="{ alerta: (metaSus.por_vencer ?? 0) > 0 }">
        <span class="k">Vencen en 30 días</span>
        <strong class="v">{{ metaSus.por_vencer ?? 0 }}</strong></div>
      <div class="kpi-mini"><span class="k">Vencidas</span>
        <strong class="v">{{ metaSus.vencidas ?? 0 }}</strong></div>
    </div>

    <Tabs :tabs="tabs" :active="vista" @change="vista = $event" />

    <!-- ══════════ Catálogo de planes ══════════ -->
    <div v-if="vista === 'planes'" class="cards">
      <article v-for="p in planes" :key="p.id" class="plan"
               :style="{ '--acento': p.color || 'var(--line-strong)' }">
        <header>
          <div>
            <strong>{{ p.nombre }}</strong>
            <span v-if="p.estado !== 'activo'" class="pill">Retirado</span>
          </div>
          <div class="precio">{{ fmtSoles(p.precio) }}<em>/{{ CADA[p.periodicidad] }}</em></div>
        </header>

        <p v-if="p.descripcion" class="desc">{{ p.descripcion }}</p>

        <ul class="beneficios">
          <li v-for="b in p.beneficios" :key="b.id">
            <Check :size="12" />
            <span v-if="b.cantidad">{{ b.cantidad }} × </span>{{ b.servicio || b.descripcion }}
            <em v-if="b.tipo !== 'servicio_incluido'">−{{ b.descuento_pct }}%</em>
          </li>
          <li v-if="p.descuento_general_pct > 0" class="general">
            <Percent :size="12" /> {{ p.descuento_general_pct }}% en todo lo demás
          </li>
        </ul>

        <div class="meta">
          <span><Users :size="12" /> {{ p.suscritos }} suscrito(s)</span>
          <span><Wallet :size="12" /> {{ fmtSoles(p.ingreso_recurrente) }}</span>
          <span v-if="p.especie"><PawPrint :size="12" /> {{ p.especie }}</span>
          <span v-if="p.edad_min_meses != null || p.edad_max_meses != null">
            <Calendar :size="12" /> {{ rangoEdad(p) }}
          </span>
        </div>

        <footer v-if="puedeGestionar">
          <button class="btn" @click="abrirPlan(p)"><Pencil :size="13" /> Editar</button>
          <button class="btn" @click="borrarPlan(p)"><Trash2 :size="13" /> Retirar</button>
        </footer>
      </article>

      <p v-if="!planes.length && !cargando" class="vacio">
        Todavía no hay planes. Un plan es lo que hace que el propietario venga
        tres veces al año en vez de una.
      </p>
    </div>

    <!-- ══════════ Suscripciones ══════════ -->
    <section v-else class="module-panel">
      <div class="module-panel-head">
        <div class="filtros">
          <select v-model="filtroEstado" @change="cargarSuscripciones">
            <option value="activa">Activas</option>
            <option value="">Todas</option>
            <option value="vencida">Vencidas</option>
            <option value="cancelada">Canceladas</option>
          </select>
          <label class="check-line">
            <input v-model="soloPorVencer" type="checkbox" @change="cargarSuscripciones" />
            <span>Solo las que vencen en 30 días</span>
          </label>
        </div>
      </div>
      <div class="module-panel-body" style="padding: 0">
        <table class="tabla">
          <thead>
            <tr>
              <th>Paciente</th><th>Propietario</th><th>Plan</th>
              <th>Vigencia</th><th class="num">Cuota</th><th class="num">Ahorrado</th><th></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="s in suscripciones" :key="s.id">
              <td><strong>{{ s.mascota?.nombre }}</strong>
                <span class="muted"> · {{ s.mascota?.especie }}</span></td>
              <td>{{ s.propietario?.nombre }}
                <span class="muted">{{ s.propietario?.telefono }}</span></td>
              <td><span class="chip" :style="{ borderColor: s.color }">{{ s.plan }}</span></td>
              <td>
                {{ fmtDate(s.fecha_inicio) }} → {{ fmtDate(s.fecha_fin) }}
                <span v-if="s.estado === 'activa'"
                      :class="['dias', s.dias_restantes <= 30 ? 'cerca' : '']">
                  {{ s.dias_restantes }} d
                </span>
                <span v-else class="pill">{{ capitalizar(s.estado) }}</span>
              </td>
              <td class="num">{{ fmtSoles(s.precio_pactado) }}</td>
              <td class="num ahorro">{{ fmtSoles(s.ahorrado) }}</td>
              <td class="num">
                <button v-if="puedeVender && s.estado === 'activa'" class="btn"
                        @click="cancelarSuscripcion(s)">Cancelar</button>
              </td>
            </tr>
            <tr v-if="!suscripciones.length">
              <td colspan="7" class="module-empty">
                <p v-if="cargando">Cargando…</p>
                <p v-else>Sin suscripciones con ese filtro.</p>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- ══════════ Modal: plan ══════════ -->
    <div v-if="modalPlan" class="modal-back" @click="modalPlan = null">
      <div class="modal modal-wide" @click.stop>
        <div class="m-head"><h3>{{ modalPlan.id ? "Editar plan" : "Nuevo plan" }}</h3></div>
        <div class="m-body">
          <div class="form-grid">
            <div class="field" style="grid-column: 1 / -1">
              <label>Nombre <span class="req">*</span></label>
              <input v-model="modalPlan.nombre" placeholder="Plan Cachorro" />
            </div>
            <div class="field" style="grid-column: 1 / -1">
              <label>Descripción</label>
              <textarea v-model="modalPlan.descripcion" rows="2"></textarea>
            </div>
            <div class="field"><label>Cuota (S/)</label>
              <input v-model.number="modalPlan.precio" type="number" step="0.01" min="0" /></div>
            <div class="field"><label>Se cobra</label>
              <select v-model="modalPlan.periodicidad">
                <option v-for="p in PERIODICIDADES" :key="p.v" :value="p.v">{{ p.t }}</option>
              </select></div>
            <div class="field"><label>Vigencia (meses)</label>
              <input v-model.number="modalPlan.vigencia_meses" type="number" min="1" max="120" /></div>
            <div class="field"><label>Descuento general (%)</label>
              <input v-model.number="modalPlan.descuento_general_pct" type="number" min="0" max="100" />
              <small class="muted">Sobre todo lo que no esté incluido abajo.</small></div>
            <div class="field"><label>Especie</label>
              <select v-model="modalPlan.especie_id">
                <option value="">Cualquiera</option>
                <option v-for="e in especies" :key="e.id" :value="e.id">{{ e.nombre }}</option>
              </select></div>
            <div class="field"><label>Color</label>
              <input v-model="modalPlan.color" type="color" /></div>
            <div class="field"><label>Edad mínima (meses)</label>
              <input v-model.number="modalPlan.edad_min_meses" type="number" min="0" /></div>
            <div class="field"><label>Edad máxima (meses)</label>
              <input v-model.number="modalPlan.edad_max_meses" type="number" min="0" />
              <small class="muted">Evita vender un plan de cachorro a un perro de diez años.</small></div>

            <div class="field" style="grid-column: 1 / -1">
              <label>Servicios incluidos</label>
              <div class="beneficios-edit">
                <div v-for="s in servicios" :key="s.id" class="ben-fila">
                  <label class="check-line">
                    <input type="checkbox" :checked="incluido(s.id)" @change="alternar(s.id)" />
                    <span>{{ s.nombre }}</span>
                    <em class="muted">{{ fmtSoles(s.precio) }}</em>
                  </label>
                  <input
                    v-if="incluido(s.id)"
                    v-model.number="cupos[s.id]"
                    type="number" min="1" class="cupo" title="Cuántas veces entra en la vigencia"
                  />
                </div>
              </div>
            </div>
          </div>
        </div>
        <div class="m-foot modal-actions">
          <button class="btn" @click="modalPlan = null">Cancelar</button>
          <button class="btn primary" :disabled="!modalPlan.nombre || guardando" @click="guardarPlan">
            {{ guardando ? "Guardando…" : "Guardar" }}
          </button>
        </div>
      </div>
    </div>

    <!-- ══════════ Modal: suscribir ══════════ -->
    <div v-if="modalSus" class="modal-back" @click="modalSus = null">
      <div class="modal" @click.stop>
        <div class="m-head"><h3>Suscribir paciente a un plan</h3></div>
        <div class="m-body">
          <div class="form-grid">
            <div class="field" style="grid-column: 1 / -1">
              <label>Paciente <span class="req">*</span></label>
              <select v-model="modalSus.mascota_id">
                <option value="">Elige un paciente…</option>
                <option v-for="m in mascotas" :key="m.id" :value="m.id">
                  {{ m.nombre }}<template v-if="m.propietario"> — {{ m.propietario }}</template>
                </option>
              </select>
              <small class="muted">
                Se suscribe la mascota, no el propietario: quien se vacuna es el animal.
              </small>
            </div>
            <div class="field" style="grid-column: 1 / -1">
              <label>Plan <span class="req">*</span></label>
              <select v-model="modalSus.plan_id">
                <option value="">Elige un plan…</option>
                <option v-for="p in planesActivos" :key="p.id" :value="p.id">
                  {{ p.nombre }} — {{ fmtSoles(p.precio) }}/{{ CADA[p.periodicidad] }}
                </option>
              </select>
            </div>
            <div class="field"><label>Empieza</label>
              <input v-model="modalSus.fecha_inicio" type="date" /></div>
            <div class="field"><label>Cuota pactada (S/)</label>
              <input v-model.number="modalSus.precio_pactado" type="number" step="0.01" min="0" />
              <small class="muted">Vacío = la del plan. Se congela al contratar.</small></div>
          </div>
        </div>
        <div class="m-foot modal-actions">
          <button class="btn" @click="modalSus = null">Cancelar</button>
          <button class="btn primary"
                  :disabled="!modalSus.mascota_id || !modalSus.plan_id || guardando"
                  @click="suscribir">
            {{ guardando ? "Guardando…" : "Suscribir" }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from "vue";
import {
  RefreshCw, Plus, UserPlus, AlertCircle, Check, Percent, Users, Wallet,
  PawPrint, Calendar, Pencil, Trash2,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import Tabs from "../../../shared/components/ui/Tabs.vue";
import { planesApi, PERIODICIDADES } from "../api/planes.api.js";
import { catalogosApi } from "../../catalogos/api/catalogos.api.js";
import { mascotasApi } from "../../mascotas/api/mascotas.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { notify } from "../../../shared/composables/useNotify.js";
import { capitalizar, fmtDate, fmtSoles } from "../../../shared/components/ui/format.js";

const { hasPermission } = useAuth();
const puedeGestionar = computed(() => hasPermission("planes:gestionar"));
const puedeVender = computed(() => hasPermission("planes:vender"));

const CADA = { mensual: "mes", trimestral: "trimestre", semestral: "semestre", anual: "año" };

const vista = ref("planes");
const planes = ref([]);
const suscripciones = ref([]);
const metaSus = ref({});
const especies = ref([]);
const servicios = ref([]);
const mascotas = ref([]);
const cargando = ref(false);
const guardando = ref(false);
const error = ref("");
const filtroEstado = ref("activa");
const soloPorVencer = ref(false);

const modalPlan = ref(null);
const modalSus = ref(null);
const cupos = reactive({});

const tabs = computed(() => [
  { key: "planes", label: "Planes", count: planes.value.length },
  { key: "suscripciones", label: "Suscripciones", count: metaSus.value.activas ?? 0 },
]);
const planesActivos = computed(() => planes.value.filter((p) => p.estado === "activo"));

function rangoEdad(p) {
  const a = p.edad_min_meses, b = p.edad_max_meses;
  if (a != null && b != null) return `${a}–${b} meses`;
  if (a != null) return `desde ${a} meses`;
  return `hasta ${b} meses`;
}

async function cargar() {
  cargando.value = true;
  error.value = "";
  try {
    planes.value = (await planesApi.listar()).data ?? [];
    await cargarSuscripciones();
  } catch (e) {
    error.value = e.message;
  } finally {
    cargando.value = false;
  }
}

async function cargarSuscripciones() {
  try {
    const params = {};
    if (filtroEstado.value) params.estado = filtroEstado.value;
    if (soloPorVencer.value) params.porVencerDias = 30;
    const r = await planesApi.suscripciones(params);
    suscripciones.value = r.data ?? [];
    metaSus.value = r.meta ?? {};
  } catch (e) {
    error.value = e.message;
  }
}

async function cargarApoyo() {
  if (servicios.value.length) return;
  const [s, e] = await Promise.all([catalogosApi.servicios(), catalogosApi.especies()]);
  servicios.value = s.data ?? [];
  especies.value = e.data ?? [];
}

function incluido(id) { return Object.prototype.hasOwnProperty.call(cupos, id); }
function alternar(id) {
  if (incluido(id)) delete cupos[id];
  else cupos[id] = 1;
}

async function abrirPlan(p = null) {
  await cargarApoyo();
  Object.keys(cupos).forEach((k) => delete cupos[k]);
  if (p) {
    (p.beneficios ?? []).forEach((b) => {
      if (b.servicio_id) cupos[b.servicio_id] = b.cantidad ?? 1;
    });
    modalPlan.value = {
      id: p.id, nombre: p.nombre, descripcion: p.descripcion, precio: Number(p.precio),
      periodicidad: p.periodicidad, vigencia_meses: p.vigencia_meses,
      especie_id: p.especie_id ?? "", edad_min_meses: p.edad_min_meses,
      edad_max_meses: p.edad_max_meses,
      descuento_general_pct: Number(p.descuento_general_pct), color: p.color || "#3b82f6",
    };
  } else {
    modalPlan.value = {
      nombre: "", descripcion: "", precio: 0, periodicidad: "mensual", vigencia_meses: 12,
      especie_id: "", edad_min_meses: null, edad_max_meses: null,
      descuento_general_pct: 0, color: "#3b82f6",
    };
  }
}

async function guardarPlan() {
  guardando.value = true;
  try {
    await planesApi.guardar({
      ...modalPlan.value,
      especie_id: modalPlan.value.especie_id || undefined,
      beneficios: Object.entries(cupos).map(([servicio_id, cantidad]) => ({
        tipo: "servicio_incluido", servicio_id, cantidad: cantidad || 1,
      })),
    });
    modalPlan.value = null;
    notify.success("Plan guardado");
    await cargar();
  } catch (e) {
    notify.error(e.message);
  } finally {
    guardando.value = false;
  }
}

async function borrarPlan(p) {
  const ok = await notify.confirm(
    `¿Retirar «${p.nombre}»?`,
    "Deja de venderse. Quien ya lo contrató conserva su cobertura hasta que venza.",
    { confirmText: "Retirar", danger: true },
  );
  if (!ok) return;
  try {
    await planesApi.eliminar(p.id);
    notify.success("Plan retirado");
    await cargar();
  } catch (e) {
    notify.error(e.message);
  }
}

async function abrirSuscripcion() {
  if (!mascotas.value.length) {
    mascotas.value = (await mascotasApi.listar({ pageSize: 100 })).data ?? [];
  }
  modalSus.value = { mascota_id: "", plan_id: "", fecha_inicio: "", precio_pactado: null };
}

async function suscribir() {
  guardando.value = true;
  try {
    const r = await planesApi.suscribir({
      plan_id: modalSus.value.plan_id,
      mascota_id: modalSus.value.mascota_id,
      fecha_inicio: modalSus.value.fecha_inicio || undefined,
      precio_pactado: modalSus.value.precio_pactado ?? undefined,
    });
    modalSus.value = null;
    notify.success(`Suscrito a ${r.data?.plan}`);
    vista.value = "suscripciones";
    await cargar();
  } catch (e) {
    notify.error(e.message);
  } finally {
    guardando.value = false;
  }
}

async function cancelarSuscripcion(s) {
  const ok = await notify.confirm(
    `¿Cancelar el plan de ${s.mascota?.nombre}?`,
    "Deja de aplicarse en el acto: lo que se atienda a partir de ahora se cobra completo.",
    { confirmText: "Cancelar el plan", danger: true },
  );
  if (!ok) return;
  try {
    await planesApi.cancelar(s.id, "Cancelado desde la pantalla de planes");
    notify.success("Suscripción cancelada");
    await cargar();
  } catch (e) {
    notify.error(e.message);
  }
}

onMounted(cargar);
</script>

<style scoped>
.kpis { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 10px; margin-bottom: 14px }
.kpi-mini { background: var(--bg-elev); border: 1px solid var(--line); border-radius: 10px; padding: 10px 12px }
.kpi-mini.alerta { border-color: #e8c08a }
.kpi-mini .k { display: block; font-size: 11.5px; color: var(--ink-3) }
.kpi-mini .v { font-size: 20px; font-weight: 700 }
.kpi-mini .pie { display: block; font-size: 10.5px; color: var(--ink-4); font-style: normal }

.cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(290px, 1fr)); gap: 12px; margin-top: 14px }
.plan {
  background: var(--bg-elev);
  border: 1px solid var(--line);
  border-top: 3px solid var(--acento);
  border-radius: 10px;
  padding: 14px 16px;
  display: flex;
  flex-direction: column;
  gap: 9px;
}
.plan header { display: flex; justify-content: space-between; align-items: flex-start; gap: 10px }
.plan header strong { font-size: 15px }
.precio { font-size: 17px; font-weight: 700; white-space: nowrap }
.precio em { font-size: 11.5px; font-weight: 400; color: var(--ink-3); font-style: normal }
.desc { font-size: 12.5px; color: var(--ink-2); margin: 0 }

.beneficios { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 3px }
.beneficios li { display: flex; align-items: center; gap: 6px; font-size: 12.5px; color: var(--ink-2) }
.beneficios li em { margin-left: auto; font-style: normal; color: var(--ink-3) }
.beneficios li.general { color: var(--ink-3); border-top: 1px dashed var(--line); padding-top: 4px; margin-top: 2px }

.meta { display: flex; flex-wrap: wrap; gap: 10px; font-size: 11.5px; color: var(--ink-3); margin-top: auto }
.meta span { display: inline-flex; align-items: center; gap: 4px }
.plan footer { display: flex; gap: 6px; border-top: 1px solid var(--line); padding-top: 9px }
.vacio { grid-column: 1 / -1; color: var(--ink-3); font-size: 13px; padding: 18px }

.filtros { display: flex; gap: 12px; align-items: center; flex-wrap: wrap }
.filtros select { border: 1px solid var(--line); border-radius: 8px; padding: 5px 9px;
                  font-size: 12.5px; background: var(--bg-elev); color: var(--ink) }

.tabla { width: 100%; border-collapse: collapse; font-size: 12.5px }
.tabla th { text-align: left; font-weight: 600; color: var(--ink-3); font-size: 11.5px;
            padding: 9px 12px; border-bottom: 1px solid var(--line) }
.tabla td { padding: 9px 12px; border-bottom: 1px solid var(--line) }
.tabla .num { text-align: right }
.tabla .ahorro { color: var(--green-ink, #15803d); font-weight: 600 }
.chip { border: 1px solid var(--line-strong); border-radius: 999px; padding: 1px 9px; font-size: 11.5px }
.dias { margin-left: 6px; font-size: 11px; color: var(--ink-3) }
.dias.cerca { color: #9a5b06; font-weight: 600 }
.pill { font-size: 10.5px; font-weight: 600; padding: 1px 8px; border-radius: 999px;
        border: 1px solid var(--line-strong); color: var(--ink-3) }

.beneficios-edit { display: flex; flex-direction: column; gap: 4px; max-height: 260px; overflow-y: auto;
                   border: 1px solid var(--line); border-radius: 8px; padding: 8px }
.ben-fila { display: flex; align-items: center; gap: 8px }
.ben-fila .check-line { flex: 1 }
.ben-fila .check-line em { margin-left: auto }
.cupo { width: 62px }
</style>
