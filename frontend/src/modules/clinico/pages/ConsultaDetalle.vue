<template>
  <div>
    <div v-if="cargando" class="module-panel">
      <div class="module-panel-body module-empty">
        <span class="loading-mini"><Loader2 :size="14" class="spin" /> Cargando consulta…</span>
      </div>
    </div>

    <template v-else-if="c">
      <PageHeader
        :eyebrow="`Consulta · ${c.codigo || ''}`"
        :title="c.mascota"
        :subtitle="`${c.especie}${c.raza ? ' · ' + c.raza : ''} · ${c.edad?.texto || ''} · ${c.cliente}`"
      >
        <template #actions>
          <button class="btn" @click="$router.back()"><ArrowLeft :size="14" /> Volver</button>
          <router-link class="btn" :to="`/pacientes/${c.mascota_id}`">
            <PawPrint :size="14" /> Ficha del paciente
          </router-link>
          <button v-if="editable" class="btn" :disabled="guardando" @click="guardar">
            <Save :size="14" /> {{ guardando ? "Guardando…" : "Guardar" }}
          </button>
          <button v-if="editable" class="btn primary" :disabled="cerrando" @click="cerrar">
            <CheckCircle2 :size="14" /> {{ cerrando ? "Cerrando…" : "Cerrar consulta" }}
          </button>
        </template>
      </PageHeader>

      <div v-if="error" class="callout danger" style="margin-bottom: 14px">
        <AlertCircle :size="15" /> <span>{{ error }}</span>
      </div>
      <div v-if="mensaje" class="callout" style="margin-bottom: 14px">
        <CheckCircle2 :size="15" /> <span>{{ mensaje }}</span>
      </div>

      <div v-if="c.alergias || c.condiciones_cronicas" class="alerta-clinica" style="margin-bottom: 16px">
        <AlertTriangle :size="17" />
        <div>
          <strong>Alertas clínicas</strong>
          <div v-if="c.alergias"><b>Alergias:</b> {{ c.alergias }}</div>
          <div v-if="c.condiciones_cronicas"><b>Crónico:</b> {{ c.condiciones_cronicas }}</div>
        </div>
      </div>

      <div v-if="!editable" class="callout" style="margin-bottom: 16px">
        <Lock :size="15" />
        <span>
          Esta consulta está cerrada y firmada por {{ c.veterinario }}
          <template v-if="c.colegiatura">({{ c.colegiatura }})</template>.
          Para agregar información, registra una nota médica o una nueva consulta.
        </span>
      </div>

      <div class="cons-grid">
        <div class="col">
          <!-- SOAP: subjetivo -->
          <section class="module-panel">
            <header class="module-panel-head">
              <h2><span class="head-icon"><MessageSquare :size="14" /></span> Motivo y anamnesis</h2>
            </header>
            <div class="module-panel-body">
              <div class="field">
                <label>Motivo de la consulta</label>
                <textarea v-model="f.motivo" rows="2" :disabled="!editable"></textarea>
              </div>
              <div class="field">
                <label>Anamnesis</label>
                <textarea
                  v-model="f.anamnesis"
                  rows="3"
                  :disabled="!editable"
                  placeholder="Lo que relata el propietario: desde cuándo, qué cambió, qué se intentó…"
                ></textarea>
              </div>
            </div>
          </section>

          <!-- SOAP: objetivo -->
          <section class="module-panel">
            <header class="module-panel-head">
              <h2><span class="head-icon"><Activity :size="14" /></span> Constantes y examen físico</h2>
            </header>
            <div class="module-panel-body">
              <div class="constantes">
                <div class="field">
                  <label>Peso (kg)</label>
                  <input v-model.number="f.peso_kg" type="number" step="0.1" min="0" :disabled="!editable" />
                </div>
                <div class="field">
                  <label>Temperatura (°C)</label>
                  <input v-model.number="f.temperatura_c" type="number" step="0.1" min="25" max="45" :disabled="!editable" />
                  <small v-if="tempAlerta" class="alerta-txt">{{ tempAlerta }}</small>
                </div>
                <div class="field">
                  <label>FC (lpm)</label>
                  <input v-model.number="f.frecuencia_cardiaca" type="number" min="0" :disabled="!editable" />
                </div>
                <div class="field">
                  <label>FR (rpm)</label>
                  <input v-model.number="f.frecuencia_respiratoria" type="number" min="0" :disabled="!editable" />
                </div>
                <div class="field">
                  <label>Mucosas</label>
                  <input v-model.trim="f.mucosas" type="text" placeholder="rosadas" :disabled="!editable" />
                </div>
                <div class="field">
                  <label>TLLC (s)</label>
                  <input v-model.number="f.tllc_seg" type="number" step="0.1" min="0" :disabled="!editable" />
                </div>
                <div class="field">
                  <label>Condición corporal (1-9)</label>
                  <input v-model.number="f.condicion_corporal" type="number" min="1" max="9" :disabled="!editable" />
                </div>
              </div>
              <div class="field" style="margin-top: 12px">
                <label>Examen físico</label>
                <textarea v-model="f.examen_fisico" rows="3" :disabled="!editable"></textarea>
              </div>
            </div>
          </section>

          <!-- SOAP: análisis y plan -->
          <section class="module-panel">
            <header class="module-panel-head">
              <h2><span class="head-icon"><ClipboardCheck :size="14" /></span> Diagnóstico y plan</h2>
            </header>
            <div class="module-panel-body">
              <div class="field">
                <label>Diagnóstico <span class="req">*</span></label>
                <textarea v-model="f.diagnostico" rows="2" :disabled="!editable"></textarea>
                <small class="muted">Obligatorio para poder cerrar la consulta.</small>
              </div>
              <div class="field">
                <label>Diagnóstico diferencial</label>
                <textarea v-model="f.diagnostico_diferencial" rows="2" :disabled="!editable"></textarea>
              </div>
              <div class="form-grid">
                <div class="field">
                  <label>Pronóstico</label>
                  <select v-model="f.pronostico" :disabled="!editable">
                    <option value="">Sin definir</option>
                    <option value="favorable">Favorable</option>
                    <option value="reservado">Reservado</option>
                    <option value="desfavorable">Desfavorable</option>
                  </select>
                </div>
                <div class="field">
                  <label>Próxima visita</label>
                  <input v-model="f.proxima_visita" type="date" :disabled="!editable" />
                  <small class="muted">Genera un recordatorio de control.</small>
                </div>
              </div>
              <div class="field">
                <label>Plan terapéutico</label>
                <textarea v-model="f.plan_terapeutico" rows="3" :disabled="!editable"></textarea>
              </div>
              <div class="field">
                <label>Prescripción</label>
                <textarea v-model="f.prescripcion" rows="3" :disabled="!editable"></textarea>
              </div>
              <div class="field">
                <label>Indicaciones para casa</label>
                <textarea v-model="f.indicaciones_casa" rows="2" :disabled="!editable"></textarea>
              </div>
            </div>
          </section>
        </div>

        <div class="col">
          <!-- Servicios prestados -->
          <section class="module-panel">
            <header class="module-panel-head">
              <h2>
                <span class="head-icon"><Receipt :size="14" /></span>
                Servicios
                <span class="head-meta">{{ (c.servicios ?? []).length }}</span>
              </h2>
              <div class="module-panel-head-actions">
                <button v-if="editable" class="btn" @click="modalServicio = true"><Plus :size="13" /> Agregar</button>
              </div>
            </header>
            <div v-if="!(c.servicios ?? []).length" class="module-panel-body module-empty compacto">
              <p>Sin servicios registrados en esta consulta.</p>
            </div>
            <div v-else class="module-panel-body tabla-wrap">
              <table>
                <thead><tr><th>Servicio</th><th class="num">Cant.</th><th class="num">Total</th></tr></thead>
                <tbody>
                  <tr v-for="s in c.servicios" :key="s.id">
                    <td>{{ s.servicio }}</td>
                    <td class="num mono">{{ s.cantidad }}</td>
                    <td class="num mono">{{ fmtSoles(s.total) }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <!-- Insumos consumidos -->
          <section class="module-panel">
            <header class="module-panel-head">
              <h2>
                <span class="head-icon"><Package :size="14" /></span>
                Insumos
                <span class="head-meta">{{ (c.insumos ?? []).length }}</span>
              </h2>
              <div class="module-panel-head-actions">
                <button v-if="editable" class="btn" @click="modalInsumo = true"><Plus :size="13" /> Consumir</button>
              </div>
            </header>
            <div v-if="!(c.insumos ?? []).length" class="module-panel-body module-empty compacto">
              <p>Sin insumos consumidos.</p>
            </div>
            <div v-else class="module-panel-body tabla-wrap">
              <table>
                <thead><tr><th>Producto</th><th class="num">Cant.</th><th class="num">Precio</th></tr></thead>
                <tbody>
                  <tr v-for="i in c.insumos" :key="i.id">
                    <td>{{ i.producto }}</td>
                    <td class="num mono">{{ i.cantidad }}</td>
                    <td class="num mono">{{ fmtSoles(i.precio_unitario) }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <!-- Tratamientos indicados -->
          <section class="module-panel">
            <header class="module-panel-head">
              <h2>
                <span class="head-icon"><Pill :size="14" /></span>
                Tratamientos
                <span class="head-meta">{{ (c.tratamientos ?? []).length }}</span>
              </h2>
              <div class="module-panel-head-actions">
                <button v-if="editable" class="btn" @click="modalTratamiento = true"><Plus :size="13" /> Indicar</button>
              </div>
            </header>
            <div v-if="!(c.tratamientos ?? []).length" class="module-panel-body module-empty compacto">
              <p>Sin tratamientos indicados.</p>
            </div>
            <div v-else class="module-panel-body tabla-wrap">
              <table>
                <thead><tr><th>Medicamento</th><th>Dosis</th><th>Pauta</th></tr></thead>
                <tbody>
                  <tr v-for="t in c.tratamientos" :key="t.id">
                    <td><strong>{{ t.medicamento }}</strong></td>
                    <td>{{ t.dosis }}</td>
                    <td class="muted">
                      {{ capitalizar(t.via) }}<template v-if="t.frecuencia_horas"> · c/{{ t.frecuencia_horas }} h</template>
                      <template v-if="t.duracion_dias"> · {{ t.duracion_dias }} d</template>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <!-- Vacunas y exámenes -->
          <section class="module-panel">
            <header class="module-panel-head">
              <h2><span class="head-icon"><Syringe :size="14" /></span> Otros registros</h2>
            </header>
            <div class="module-panel-body wrap-actions">
              <button v-if="editable" class="btn" @click="modalVacuna = true"><Syringe :size="13" /> Aplicar vacuna</button>
              <button v-if="editable" class="btn" @click="modalExamen = true"><FlaskConical :size="13" /> Registrar examen</button>
            </div>
            <div v-if="(c.examenes ?? []).length" class="module-panel-body tabla-wrap" style="border-top: 1px solid var(--line-soft)">
              <table>
                <thead><tr><th>Examen</th><th>Resultado</th></tr></thead>
                <tbody>
                  <tr v-for="e in c.examenes" :key="e.id">
                    <td><strong>{{ e.nombre }}</strong><br /><small class="muted">{{ capitalizar(e.tipo) }}</small></td>
                    <td class="muted">{{ e.resultado || "Pendiente" }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </div>

      <!-- ---------- Modales ---------- -->
      <VacunaModal
        v-if="modalVacuna"
        :mascota-id="c.mascota_id"
        :consulta-id="c.id"
        @close="modalVacuna = false"
        @guardado="onSub"
      />

      <div v-if="modalServicio" class="modal-back" @click="modalServicio = false">
        <div class="modal" @click.stop>
          <div class="m-head"><h3>Agregar servicio</h3></div>
          <div class="m-body">
            <div class="field">
              <label>Servicio</label>
              <select v-model="sub.servicio_id">
                <option value="">Seleccionar…</option>
                <option v-for="s in servicios" :key="s.id" :value="s.id">
                  {{ s.nombre }} — {{ fmtSoles(s.precio) }}
                </option>
              </select>
            </div>
            <div class="field">
              <label>Cantidad</label>
              <input v-model.number="sub.cantidad" type="number" min="1" step="1" />
            </div>
          </div>
          <div class="m-foot modal-actions">
            <button class="btn" @click="modalServicio = false">Cancelar</button>
            <button class="btn primary" :disabled="!sub.servicio_id" @click="agregarServicio">Agregar</button>
          </div>
        </div>
      </div>

      <div v-if="modalInsumo" class="modal-back" @click="modalInsumo = false">
        <div class="modal" @click.stop>
          <div class="m-head"><h3>Consumir insumo</h3></div>
          <div class="m-body">
            <p class="muted" style="margin-top: 0">
              El consumo descuenta stock del almacén y queda pendiente de facturar.
            </p>
            <div class="field">
              <label>Producto</label>
              <select v-model="sub.producto_id">
                <option value="">Seleccionar…</option>
                <option v-for="p in productos" :key="p.id" :value="p.id">
                  {{ p.nombre }} ({{ p.stock_actual }} {{ p.unidad_medida }})
                </option>
              </select>
            </div>
            <div class="field">
              <label>Cantidad</label>
              <input v-model.number="sub.cantidadInsumo" type="number" min="0.01" step="0.01" />
            </div>
          </div>
          <div class="m-foot modal-actions">
            <button class="btn" @click="modalInsumo = false">Cancelar</button>
            <button class="btn primary" :disabled="!sub.producto_id" @click="consumirInsumo">Consumir</button>
          </div>
        </div>
      </div>

      <div v-if="modalTratamiento" class="modal-back" @click="modalTratamiento = false">
        <div class="modal modal-wide" @click.stop>
          <div class="m-head"><h3>Indicar tratamiento</h3></div>
          <div class="m-body">
            <div class="form-grid">
              <div class="field" style="grid-column: 1 / -1">
                <label>Medicamento <span class="req">*</span></label>
                <input v-model.trim="trat.medicamento" type="text" placeholder="Amoxicilina 500 mg" />
              </div>
              <div class="field">
                <label>Dosis <span class="req">*</span></label>
                <input v-model.trim="trat.dosis" type="text" placeholder="1/2 tableta" />
              </div>
              <div class="field">
                <label>Vía</label>
                <select v-model="trat.via">
                  <option value="oral">Oral</option>
                  <option value="subcutanea">Subcutánea</option>
                  <option value="intramuscular">Intramuscular</option>
                  <option value="intravenosa">Intravenosa</option>
                  <option value="topica">Tópica</option>
                  <option value="oftalmica">Oftálmica</option>
                  <option value="otica">Ótica</option>
                </select>
              </div>
              <div class="field">
                <label>Cada (horas)</label>
                <input v-model.number="trat.frecuencia_horas" type="number" min="1" />
              </div>
              <div class="field">
                <label>Duración (días)</label>
                <input v-model.number="trat.duracion_dias" type="number" min="1" />
              </div>
              <div class="field" style="grid-column: 1 / -1">
                <label>Indicaciones</label>
                <textarea v-model="trat.indicaciones" rows="2"></textarea>
              </div>
            </div>
          </div>
          <div class="m-foot modal-actions">
            <button class="btn" @click="modalTratamiento = false">Cancelar</button>
            <button class="btn primary" :disabled="!trat.medicamento || !trat.dosis" @click="agregarTratamiento">
              Indicar
            </button>
          </div>
        </div>
      </div>

      <div v-if="modalExamen" class="modal-back" @click="modalExamen = false">
        <div class="modal" @click.stop>
          <div class="m-head"><h3>Registrar examen</h3></div>
          <div class="m-body">
            <div class="field">
              <label>Tipo <span class="req">*</span></label>
              <select v-model="exam.tipo">
                <option value="hemograma">Hemograma</option>
                <option value="bioquimica">Bioquímica</option>
                <option value="urianalisis">Urianálisis</option>
                <option value="radiografia">Radiografía</option>
                <option value="ecografia">Ecografía</option>
                <option value="citologia">Citología</option>
                <option value="otro">Otro</option>
              </select>
            </div>
            <div class="field">
              <label>Nombre <span class="req">*</span></label>
              <input v-model.trim="exam.nombre" type="text" placeholder="Hemograma completo" />
            </div>
            <div class="field">
              <label>Resultado</label>
              <textarea v-model="exam.resultado" rows="3"></textarea>
            </div>
            <div class="field">
              <label>Interpretación</label>
              <textarea v-model="exam.interpretacion" rows="2"></textarea>
            </div>
          </div>
          <div class="m-foot modal-actions">
            <button class="btn" @click="modalExamen = false">Cancelar</button>
            <button class="btn primary" :disabled="!exam.nombre" @click="agregarExamen">Registrar</button>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted, watch } from "vue";
import { useRoute } from "vue-router";
import {
  Loader2, ArrowLeft, Save, CheckCircle2, AlertCircle, AlertTriangle, Lock,
  MessageSquare, Activity, ClipboardCheck, Receipt, Package, Pill, Syringe,
  FlaskConical, Plus, PawPrint,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import VacunaModal from "../components/VacunaModal.vue";
import { clinicoApi } from "../api/clinico.api.js";
import { catalogosApi } from "../../catalogos/api/catalogos.api.js";
import { inventarioApi } from "../../inventario/api/inventario.api.js";
import { fmtSoles, capitalizar } from "../../../shared/components/ui/format.js";

const route = useRoute();
const c = ref(null);
const servicios = ref([]);
const productos = ref([]);
const cargando = ref(true);
const guardando = ref(false);
const cerrando = ref(false);
const error = ref("");
const mensaje = ref("");

const modalVacuna = ref(false);
const modalServicio = ref(false);
const modalInsumo = ref(false);
const modalTratamiento = ref(false);
const modalExamen = ref(false);

const sub = reactive({ servicio_id: "", cantidad: 1, producto_id: "", cantidadInsumo: 1 });
const trat = reactive({ medicamento: "", dosis: "", via: "oral", frecuencia_horas: null, duracion_dias: null, indicaciones: "" });
const exam = reactive({ tipo: "hemograma", nombre: "", resultado: "", interpretacion: "" });

const f = reactive({
  motivo: "", anamnesis: "", peso_kg: null, temperatura_c: null,
  frecuencia_cardiaca: null, frecuencia_respiratoria: null, mucosas: "",
  tllc_seg: null, condicion_corporal: null, examen_fisico: "",
  diagnostico: "", diagnostico_diferencial: "", pronostico: "",
  plan_terapeutico: "", prescripcion: "", indicaciones_casa: "", proxima_visita: "",
});

const editable = computed(() => c.value?.estado === "borrador");

/** Rango fisiológico aproximado de perro y gato: aviso, no bloqueo. */
const tempAlerta = computed(() => {
  const t = Number(f.temperatura_c);
  if (!t) return "";
  if (t < 37.5) return "Por debajo del rango normal (37,5–39,2 °C)";
  if (t > 39.2) return "Por encima del rango normal (37,5–39,2 °C)";
  return "";
});

function hidratar(data) {
  c.value = data;
  for (const k of Object.keys(f)) {
    f[k] = data[k] ?? (typeof f[k] === "number" ? null : "");
  }
  if (data.proxima_visita) f.proxima_visita = String(data.proxima_visita).slice(0, 10);
}

async function cargar() {
  cargando.value = true;
  try {
    const r = await clinicoApi.consulta(route.params.id);
    hidratar(r.data);
  } catch (e) {
    error.value = e.message;
  } finally {
    cargando.value = false;
  }
}

function payload() {
  const p = {};
  for (const [k, v] of Object.entries(f)) {
    if (v === "" || v === null || v === undefined) continue;
    p[k] = v;
  }
  return p;
}

async function guardar() {
  error.value = "";
  mensaje.value = "";
  guardando.value = true;
  try {
    await clinicoApi.actualizarConsulta(route.params.id, payload());
    mensaje.value = "Consulta guardada.";
    await cargar();
  } catch (e) {
    error.value = e.message;
  } finally {
    guardando.value = false;
  }
}

async function cerrar() {
  error.value = "";
  if (!f.diagnostico?.trim()) {
    error.value = "No se puede cerrar la consulta sin diagnóstico.";
    return;
  }
  cerrando.value = true;
  try {
    // Se guarda primero: cerrar congela el documento clínico.
    await clinicoApi.actualizarConsulta(route.params.id, payload());
    await clinicoApi.cerrarConsulta(route.params.id);
    mensaje.value = "Consulta cerrada y cita completada.";
    await cargar();
  } catch (e) {
    error.value = e.message;
  } finally {
    cerrando.value = false;
  }
}

async function onSub() {
  modalVacuna.value = false;
  await cargar();
}

async function agregarServicio() {
  try {
    await clinicoApi.crearOrdenServicio({
      mascota_id: c.value.mascota_id,
      servicio_id: sub.servicio_id,
      consulta_id: c.value.id,
      cantidad: sub.cantidad,
    });
    modalServicio.value = false;
    sub.servicio_id = "";
    sub.cantidad = 1;
    await cargar();
  } catch (e) {
    error.value = e.message;
    modalServicio.value = false;
  }
}

async function consumirInsumo() {
  try {
    await clinicoApi.consumirInsumo({
      producto_id: sub.producto_id,
      cantidad: sub.cantidadInsumo,
      mascota_id: c.value.mascota_id,
      consulta_id: c.value.id,
    });
    modalInsumo.value = false;
    sub.producto_id = "";
    sub.cantidadInsumo = 1;
    await Promise.all([cargar(), cargarProductos()]);
  } catch (e) {
    error.value = e.message;
    modalInsumo.value = false;
  }
}

async function agregarTratamiento() {
  try {
    await clinicoApi.registrarTratamiento({
      mascota_id: c.value.mascota_id,
      consulta_id: c.value.id,
      medicamento: trat.medicamento,
      dosis: trat.dosis,
      via: trat.via,
      frecuencia_horas: trat.frecuencia_horas || undefined,
      duracion_dias: trat.duracion_dias || undefined,
      indicaciones: trat.indicaciones || undefined,
    });
    modalTratamiento.value = false;
    Object.assign(trat, { medicamento: "", dosis: "", via: "oral", frecuencia_horas: null, duracion_dias: null, indicaciones: "" });
    await cargar();
  } catch (e) {
    error.value = e.message;
    modalTratamiento.value = false;
  }
}

async function agregarExamen() {
  try {
    await clinicoApi.registrarExamen({
      mascota_id: c.value.mascota_id,
      consulta_id: c.value.id,
      tipo: exam.tipo,
      nombre: exam.nombre,
      resultado: exam.resultado || undefined,
      interpretacion: exam.interpretacion || undefined,
    });
    modalExamen.value = false;
    Object.assign(exam, { tipo: "hemograma", nombre: "", resultado: "", interpretacion: "" });
    await cargar();
  } catch (e) {
    error.value = e.message;
    modalExamen.value = false;
  }
}

async function cargarProductos() {
  const p = await inventarioApi.productos({ estado: "activo", pageSize: 100 });
  productos.value = p.data ?? [];
}

onMounted(async () => {
  await cargar();
  try {
    const [s] = await Promise.all([catalogosApi.servicios({ estado: "activo" }), cargarProductos()]);
    servicios.value = s.data ?? [];
  } catch {
    // Los catálogos solo hacen falta para agregar líneas; la consulta se ve igual.
  }
});

watch(() => route.params.id, cargar);
</script>

<style scoped>
.cons-grid { display: grid; grid-template-columns: 1.35fr 1fr; gap: 16px; align-items: start; }
@media (max-width: 1050px) { .cons-grid { grid-template-columns: 1fr; } }
.col { display: flex; flex-direction: column; gap: 16px; }

.constantes {
  display: grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr)); gap: 12px;
}
.alerta-txt { color: var(--amber-ink); font-size: 11px; }
.module-empty.compacto { padding: 22px 16px; }
.module-empty.compacto p { margin: 0; font-size: 12.5px; color: var(--ink-3); }
.req { color: var(--red); }
</style>
