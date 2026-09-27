<template>
  <div>
    <PageHeader
      eyebrow="Operación"
      title="Peluquería"
      subtitle="Quién está dentro, desde cuándo y qué se le encontró"
    >
      <template #actions>
        <input v-model="fecha" type="date" class="fecha-input" @change="cargar" />
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="{ spin: cargando }" /> Actualizar
        </button>
        <button v-if="puedeOperar" class="btn primary" @click="abrirRecepcion">
          <LogIn :size="14" /> Recibir paciente
        </button>
      </template>
    </PageHeader>

    <div v-if="error" class="callout danger" style="margin-bottom: 14px">
      <AlertCircle :size="15" /> <span>{{ error }}</span>
    </div>

    <div class="kpis">
      <div class="kpi"><span class="k">Recibidos</span><strong class="v">{{ meta.recibidos ?? 0 }}</strong></div>
      <div class="kpi"><span class="k">En proceso</span><strong class="v">{{ meta.en_proceso ?? 0 }}</strong></div>
      <div class="kpi"><span class="k">Terminados</span><strong class="v">{{ meta.terminados ?? 0 }}</strong></div>
      <div class="kpi"><span class="k">Entregados</span><strong class="v">{{ meta.entregados ?? 0 }}</strong></div>
      <div class="kpi"><span class="k">Del día</span><strong class="v">{{ fmtSoles(meta.facturable ?? 0) }}</strong></div>
    </div>

    <section v-if="!ordenes.length" class="module-panel">
      <div class="module-panel-body module-empty">
        <p v-if="cargando">Cargando…</p>
        <p v-else>No hay nadie en peluquería {{ esHoy ? "ahora mismo" : "ese día" }}.</p>
      </div>
    </section>

    <div v-else class="tablero">
      <article v-for="o in ordenes" :key="o.id" :class="['ficha', `e-${o.estado}`]">
        <div class="cuerpo">
          <header>
            <strong class="nombre">{{ o.mascota?.nombre }}</strong>
            <span class="muted">
              {{ o.mascota?.especie }}<template v-if="o.mascota?.raza"> · {{ o.mascota.raza }}</template>
            </span>
            <span :class="['pill', `e-${o.estado}`]">{{ ETIQUETA[o.estado] ?? o.estado }}</span>
            <span v-if="o.retrasado" class="pill tarde"><Clock :size="10" /> Pasada la hora</span>
            <span v-if="o.hallazgos_urgentes" class="pill urgente">
              <AlertTriangle :size="10" /> {{ o.hallazgos_urgentes }} para el veterinario
            </span>
          </header>

          <div class="linea"><User :size="12" /> {{ o.propietario?.nombre }}
            <template v-if="o.propietario?.telefono"> · {{ o.propietario.telefono }}</template>
          </div>
          <div class="linea">
            <Scissors :size="12" />
            {{ (o.servicios ?? []).map((s) => s.servicio).join(", ") || "Sin servicios" }}
            <strong class="total">{{ fmtSoles(o.total) }}</strong>
          </div>
          <div class="linea">
            <LogIn :size="12" /> Entró {{ fmtHora(o.fecha_ingreso) }}
            <template v-if="o.entrega_estimada"> · prometido {{ fmtHora(o.entrega_estimada) }}</template>
            <template v-if="o.fecha_entrega"> · entregado {{ fmtHora(o.fecha_entrega) }}</template>
          </div>

          <!-- El estado en que llegó es lo que protege a la clínica si luego
               hay discusión sobre una herida o un nudo. -->
          <div v-if="o.condicion_pelaje || o.temperamento" class="linea recepcion">
            <ClipboardCheck :size="12" />
            <template v-if="o.condicion_pelaje">Pelaje: {{ capitalizar(o.condicion_pelaje.replace("_", " ")) }}</template>
            <template v-if="o.temperamento"> · {{ capitalizar(o.temperamento.replace("_", " ")) }}</template>
            <template v-if="o.autoriza_rapado"> · autoriza rapado</template>
          </div>
          <p v-if="o.observaciones_ingreso" class="obs">“{{ o.observaciones_ingreso }}”</p>
        </div>

        <div class="acciones">
          <button v-if="puedeOperar && o.estado === 'recibido'" class="btn primary"
                  @click="accion(o, 'iniciar')">
            <Play :size="13" /> Empezar
          </button>
          <button v-if="puedeOperar && ['recibido','en_proceso'].includes(o.estado)"
                  class="btn" @click="abrirHallazgo(o)">
            <Eye :size="13" /> Anotar hallazgo
          </button>
          <button v-if="puedeOperar && ['recibido','en_proceso'].includes(o.estado)"
                  class="btn" @click="abrirTerminar(o)">
            <Check :size="13" /> Terminar
          </button>
          <button v-if="puedeOperar && o.estado === 'terminado'" class="btn primary"
                  @click="abrirEntrega(o)">
            <PackageCheck :size="13" /> Entregar
          </button>
          <button class="btn" @click="verFicha(o)"><FileText :size="13" /> Ficha</button>
        </div>
      </article>
    </div>

    <!-- ───────────────── Recepción ───────────────── -->
    <div v-if="modalRecibir" class="modal-back" @click="modalRecibir = false">
      <div class="modal modal-wide" @click.stop>
        <div class="m-head"><h3>Recibir paciente en peluquería</h3></div>
        <div class="m-body">
          <div class="form-grid">
            <div class="field" style="grid-column: 1 / -1">
              <label>Paciente <span class="req">*</span></label>
              <select v-model="rec.mascota_id">
                <option value="">Elige un paciente…</option>
                <option v-for="m in mascotas" :key="m.id" :value="m.id">
                  {{ m.nombre }}<template v-if="m.propietario"> — {{ m.propietario }}</template>
                </option>
              </select>
            </div>

            <div class="field" style="grid-column: 1 / -1">
              <label>Servicios <span class="req">*</span></label>
              <div class="servicios">
                <label v-for="s in serviciosGrooming" :key="s.id" class="chk">
                  <input v-model="rec.servicios" type="checkbox" :value="s.id" />
                  <span>{{ s.nombre }}</span>
                  <em>{{ fmtSoles(s.precio) }}</em>
                </label>
              </div>
            </div>

            <div class="field">
              <label>Peso (kg)</label>
              <input v-model.number="rec.peso_kg" type="number" step="0.1" min="0" />
            </div>
            <div class="field">
              <label>Entrega prometida</label>
              <input v-model="rec.entrega_estimada" type="datetime-local" />
            </div>
            <div class="field">
              <label>Estado del pelaje</label>
              <select v-model="rec.condicion_pelaje">
                <option value="">Sin definir</option>
                <option v-for="c in CONDICION_PELAJE" :key="c" :value="c">
                  {{ capitalizar(c.replace("_", " ")) }}
                </option>
              </select>
            </div>
            <div class="field">
              <label>Temperamento</label>
              <select v-model="rec.temperamento">
                <option value="">Sin definir</option>
                <option v-for="c in TEMPERAMENTOS" :key="c" :value="c">
                  {{ capitalizar(c.replace("_", " ")) }}
                </option>
              </select>
            </div>

            <div class="field" style="grid-column: 1 / -1">
              <label>Cómo llegó</label>
              <textarea v-model="rec.observaciones_ingreso" rows="2"
                placeholder="Heridas, costras, nudos, cojera… lo que se vea al recibirlo"></textarea>
              <small class="muted">
                Dejar constancia aquí es lo que evita la discusión de después sobre
                si esa herida ya venía.
              </small>
            </div>

            <div class="field" style="grid-column: 1 / -1">
              <label class="check-line">
                <input v-model="rec.autoriza_rapado" type="checkbox" />
                <span>El propietario autoriza rapar si el nudo no se puede desenredar sin dolor</span>
              </label>
            </div>
          </div>
        </div>
        <div class="m-foot modal-actions">
          <button class="btn" @click="modalRecibir = false">Cancelar</button>
          <button class="btn primary" :disabled="!puedeRecibir || guardando" @click="recibir">
            {{ guardando ? "Guardando…" : "Recibir" }}
          </button>
        </div>
      </div>
    </div>

    <!-- ───────────────── Hallazgo ───────────────── -->
    <div v-if="modalHallazgo" class="modal-back" @click="modalHallazgo = false">
      <div class="modal" @click.stop>
        <div class="m-head"><h3>Hallazgo · {{ activa?.mascota?.nombre }}</h3></div>
        <div class="m-body">
          <div class="form-grid">
            <div class="field" style="grid-column: 1 / -1">
              <label>Qué se vio</label>
              <select v-model="hal.hallazgo">
                <option v-for="h in HALLAZGOS" :key="h.v" :value="h.v">{{ h.t }}</option>
              </select>
            </div>
            <div class="field" style="grid-column: 1 / -1">
              <label>Zona</label>
              <input v-model="hal.zona" placeholder="Lomo, axila izquierda, oreja derecha…" />
            </div>
            <div class="field" style="grid-column: 1 / -1">
              <label>Detalle</label>
              <textarea v-model="hal.detalle" rows="2"></textarea>
            </div>
            <div class="field" style="grid-column: 1 / -1">
              <label class="check-line">
                <input v-model="hal.requiere_veterinario" type="checkbox" />
                <span>Que lo vea un veterinario antes de entregar</span>
              </label>
            </div>
          </div>
        </div>
        <div class="m-foot modal-actions">
          <button class="btn" @click="modalHallazgo = false">Cancelar</button>
          <button class="btn primary" :disabled="guardando" @click="guardarHallazgo">Anotar</button>
        </div>
      </div>
    </div>

    <!-- ───────────────── Terminar ───────────────── -->
    <div v-if="modalTerminar" class="modal-back" @click="modalTerminar = false">
      <div class="modal" @click.stop>
        <div class="m-head"><h3>Terminar el trabajo</h3></div>
        <div class="m-body">
          <div class="form-grid">
            <div class="field" style="grid-column: 1 / -1">
              <label>Observaciones de salida</label>
              <textarea v-model="fin.observaciones_salida" rows="3"
                placeholder="Qué se hizo, qué quedó pendiente, qué recomendar al propietario"></textarea>
              <small class="muted">
                Al terminar se generan los cargos y la sesión entra en la historia clínica.
              </small>
            </div>
          </div>
        </div>
        <div class="m-foot modal-actions">
          <button class="btn" @click="modalTerminar = false">Cancelar</button>
          <button class="btn primary" :disabled="guardando" @click="terminar">Terminar y cobrar</button>
        </div>
      </div>
    </div>

    <!-- ───────────────── Entregar ───────────────── -->
    <div v-if="modalEntregar" class="modal-back" @click="modalEntregar = false">
      <div class="modal" @click.stop>
        <div class="m-head"><h3>Entregar el paciente</h3></div>
        <div class="m-body">
          <div class="form-grid">
            <div class="field"><label>Quién lo recoge</label>
              <input v-model="ent.entregado_a" /></div>
            <div class="field"><label>Documento</label>
              <input v-model="ent.documento_receptor" /></div>
          </div>
        </div>
        <div class="m-foot modal-actions">
          <button class="btn" @click="modalEntregar = false">Cancelar</button>
          <button class="btn primary" :disabled="guardando" @click="entregar">Entregar</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from "vue";
import {
  RefreshCw, LogIn, AlertCircle, AlertTriangle, User, Clock, Scissors,
  ClipboardCheck, Play, Eye, Check, PackageCheck, FileText,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import {
  peluqueriaApi, HALLAZGOS, CONDICION_PELAJE, TEMPERAMENTOS,
} from "../api/peluqueria.api.js";
import { mascotasApi } from "../../mascotas/api/mascotas.api.js";
import { catalogosApi } from "../../catalogos/api/catalogos.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { notify } from "../../../shared/composables/useNotify.js";
import { capitalizar, fmtHora, fmtSoles } from "../../../shared/components/ui/format.js";

const { hasPermission } = useAuth();
const puedeOperar = computed(() => hasPermission("peluqueria:operar"));

const ETIQUETA = {
  recibido: "Esperando", en_proceso: "En proceso", terminado: "Listo",
  entregado: "Entregado", cancelado: "Cancelado",
};

const hoy = new Date().toISOString().slice(0, 10);
const fecha = ref(hoy);
const esHoy = computed(() => fecha.value === hoy);
const ordenes = ref([]);
const meta = ref({});
const cargando = ref(false);
const guardando = ref(false);
const error = ref("");

const mascotas = ref([]);
const serviciosGrooming = ref([]);
const activa = ref(null);

const modalRecibir = ref(false);
const modalHallazgo = ref(false);
const modalTerminar = ref(false);
const modalEntregar = ref(false);

const rec = reactive({
  mascota_id: "", servicios: [], peso_kg: null, entrega_estimada: "",
  condicion_pelaje: "", temperamento: "", observaciones_ingreso: "", autoriza_rapado: false,
});
const hal = reactive({ hallazgo: "pulgas", zona: "", detalle: "", requiere_veterinario: false });
const fin = reactive({ observaciones_salida: "" });
const ent = reactive({ entregado_a: "", documento_receptor: "" });

const puedeRecibir = computed(() => rec.mascota_id && rec.servicios.length > 0);

async function cargar() {
  cargando.value = true;
  error.value = "";
  try {
    const r = await peluqueriaApi.listar({ desde: fecha.value, hasta: fecha.value });
    ordenes.value = r.data ?? [];
    meta.value = r.meta ?? {};
  } catch (e) {
    error.value = e.message;
  } finally {
    cargando.value = false;
  }
}

async function abrirRecepcion() {
  Object.assign(rec, {
    mascota_id: "", servicios: [], peso_kg: null, entrega_estimada: "",
    condicion_pelaje: "", temperamento: "", observaciones_ingreso: "", autoriza_rapado: false,
  });
  modalRecibir.value = true;
  if (!mascotas.value.length) {
    try {
      const [m, s] = await Promise.all([
        mascotasApi.listar({ pageSize: 100 }),
        catalogosApi.servicios(),
      ]);
      mascotas.value = m.data ?? [];
      serviciosGrooming.value = (s.data ?? []).filter((x) => x.tipo === "grooming");
    } catch (e) {
      error.value = e.message;
    }
  }
}

async function recibir() {
  guardando.value = true;
  try {
    await peluqueriaApi.recibir({
      mascota_id: rec.mascota_id,
      servicios: rec.servicios.map((id) => ({ servicio_id: id })),
      peso_kg: rec.peso_kg || undefined,
      entrega_estimada: rec.entrega_estimada || undefined,
      condicion_pelaje: rec.condicion_pelaje || undefined,
      temperamento: rec.temperamento || undefined,
      observaciones_ingreso: rec.observaciones_ingreso || undefined,
      autoriza_rapado: rec.autoriza_rapado,
    });
    modalRecibir.value = false;
    notify.success("Paciente recibido");
    await cargar();
  } catch (e) {
    notify.error(e.message);
  } finally {
    guardando.value = false;
  }
}

async function accion(o, cual) {
  try {
    await peluqueriaApi[cual](o.id);
    await cargar();
  } catch (e) {
    notify.error(e.message);
  }
}

function abrirHallazgo(o) {
  activa.value = o;
  Object.assign(hal, { hallazgo: "pulgas", zona: "", detalle: "", requiere_veterinario: false });
  modalHallazgo.value = true;
}
async function guardarHallazgo() {
  guardando.value = true;
  try {
    const r = await peluqueriaApi.hallazgo(activa.value.id, { ...hal });
    modalHallazgo.value = false;
    notify.success(r.data?.aviso_enviado ? "Anotado y avisado al veterinario" : "Hallazgo anotado");
    await cargar();
  } catch (e) {
    notify.error(e.message);
  } finally {
    guardando.value = false;
  }
}

function abrirTerminar(o) {
  activa.value = o;
  fin.observaciones_salida = "";
  modalTerminar.value = true;
}
async function terminar() {
  guardando.value = true;
  try {
    const r = await peluqueriaApi.terminar(activa.value.id, { ...fin });
    modalTerminar.value = false;
    notify.success(`Trabajo cerrado · ${r.data?.cargos ?? 0} cargo(s) por ${fmtSoles(r.data?.total ?? 0)}`);
    await cargar();
  } catch (e) {
    notify.error(e.message);
  } finally {
    guardando.value = false;
  }
}

function abrirEntrega(o) {
  activa.value = o;
  Object.assign(ent, { entregado_a: o.propietario?.nombre ?? "", documento_receptor: "" });
  modalEntregar.value = true;
}
async function entregar() {
  guardando.value = true;
  try {
    await peluqueriaApi.entregar(activa.value.id, { ...ent });
    modalEntregar.value = false;
    notify.success("Entregado");
    await cargar();
  } catch (e) {
    // El único rechazo esperable es el hallazgo urgente sin revisar: se
    // pregunta en vez de dejar al mostrador con el propietario delante.
    if (String(e.message).includes("hallazgo")) {
      const ok = await notify.confirm(
        "Quedan hallazgos sin revisar", e.message,
        { confirmText: "Entregar igualmente", danger: true },
      );
      if (!ok) { guardando.value = false; return; }
      try {
        await peluqueriaApi.entregar(activa.value.id, { ...ent, omitir_aviso: true });
        modalEntregar.value = false;
        notify.success("Entregado, con el aviso registrado");
        await cargar();
      } catch (e2) { notify.error(e2.message); }
    } else {
      notify.error(e.message);
    }
  } finally {
    guardando.value = false;
  }
}

async function verFicha(o) {
  try {
    const r = await peluqueriaApi.obtener(o.id);
    const d = r.data ?? {};
    const hallazgos = (d.hallazgos ?? [])
      .map((h) => `• ${h.hallazgo}${h.zona ? ` (${h.zona})` : ""}${h.detalle ? `: ${h.detalle}` : ""}`)
      .join("\n") || "Sin hallazgos";
    notify.info(`${d.codigo} · ${d.mascota?.nombre}\n\n${hallazgos}`);
  } catch (e) {
    notify.error(e.message);
  }
}

onMounted(cargar);
</script>

<style scoped>
.kpis { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 10px; margin-bottom: 14px }
.kpi { background: var(--bg-elev); border: 1px solid var(--line); border-radius: 10px; padding: 10px 12px }
.kpi .k { display: block; font-size: 11.5px; color: var(--ink-3) }
.kpi .v { font-size: 20px; font-weight: 700 }

.tablero { display: flex; flex-direction: column; gap: 10px }
.ficha {
  display: flex;
  gap: 12px;
  background: var(--bg-elev);
  border: 1px solid var(--line);
  border-left: 3px solid var(--line-strong);
  border-radius: 10px;
  padding: 12px 14px;
}
/* El borde dice en qué punto del recorrido va, sin tener que leer nada. */
.ficha.e-recibido   { border-left-color: #c8a227 }
.ficha.e-en_proceso { border-left-color: #1c5ca3 }
.ficha.e-terminado  { border-left-color: #15803d }
.ficha.e-entregado  { border-left-color: var(--line-strong); opacity: .72 }
.ficha.e-cancelado  { border-left-color: #b91c1c; opacity: .6 }

.cuerpo { flex: 1; min-width: 0 }
.cuerpo header { display: flex; flex-wrap: wrap; gap: 7px; align-items: baseline; margin-bottom: 5px }
.nombre { font-size: 15px }
.linea { display: flex; align-items: center; gap: 5px; font-size: 12.5px; color: var(--ink-2); margin-bottom: 2px }
.linea .total { margin-left: auto; color: var(--ink) }
.linea.recepcion { color: var(--ink-3) }
.obs { font-size: 12px; color: var(--ink-3); font-style: italic; margin: 4px 0 0 }

.pill { font-size: 10.5px; font-weight: 600; padding: 1px 8px; border-radius: 999px;
        border: 1px solid var(--line-strong); color: var(--ink-3); display: inline-flex; gap: 3px; align-items: center }
.pill.e-recibido   { border-color: #e2cc86; color: #8a6d0b; background: #fdf6e0 }
.pill.e-en_proceso { border-color: #a8c8e0; color: #1c5ca3; background: #eef5fd }
.pill.e-terminado  { border-color: #a6d4b4; color: #15803d; background: #eefaf1 }
.pill.tarde        { border-color: #e8c08a; color: #9a5b06; background: #fdf1e2 }
.pill.urgente      { border-color: #e0a8a8; color: #a31c1c; background: #fdeeee }

.acciones { display: flex; flex-direction: column; gap: 6px; justify-content: center }
.acciones .btn { white-space: nowrap }

.servicios { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 6px }
.chk { display: flex; align-items: center; gap: 7px; font-size: 12.5px;
       border: 1px solid var(--line); border-radius: 8px; padding: 6px 9px }
.chk em { margin-left: auto; font-style: normal; color: var(--ink-3) }
.fecha-input { border: 1px solid var(--line); border-radius: 8px; padding: 6px 9px;
               font-size: 12.5px; background: var(--bg-elev); color: var(--ink) }

@media (max-width: 720px) {
  .ficha { flex-wrap: wrap }
  .acciones { flex-direction: row; width: 100%; flex-wrap: wrap }
}
</style>
