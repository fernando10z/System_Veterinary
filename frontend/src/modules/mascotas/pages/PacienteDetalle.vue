<template>
  <div>
    <div v-if="cargando" class="module-panel">
      <div class="module-panel-body module-empty">
        <span class="loading-mini"><Loader2 :size="14" class="spin" /> Cargando ficha…</span>
      </div>
    </div>

    <template v-else-if="p">
      <PageHeader
        :eyebrow="`Paciente · ${p.codigo || 'sin código'}`"
        :title="p.nombre"
        :subtitle="`${p.especie}${p.raza ? ' · ' + p.raza : ''} · ${p.edad?.texto || 'edad desconocida'}`"
      >
        <template #actions>
          <button class="btn" @click="$router.back()"><ArrowLeft :size="14" /> Volver</button>
          <button v-if="puedeEditar" class="btn" @click="modalEditar = true">
            <Pencil :size="14" /> Editar ficha
          </button>
          <button v-if="puedeRegistrar" class="btn primary" @click="modalConsulta = true">
            <Stethoscope :size="14" /> Nueva consulta
          </button>
        </template>
      </PageHeader>

      <!-- Alertas clínicas: lo primero que debe ver el veterinario -->
      <div v-if="p.alergias || p.condiciones_cronicas" class="alerta-clinica" style="margin-bottom: 16px">
        <AlertTriangle :size="17" />
        <div>
          <strong>Alertas clínicas</strong>
          <div v-if="p.alergias"><b>Alergias:</b> {{ p.alergias }}</div>
          <div v-if="p.condiciones_cronicas"><b>Condiciones crónicas:</b> {{ p.condiciones_cronicas }}</div>
        </div>
      </div>

      <div v-if="p.hospitalizacion_actual" class="callout" style="margin-bottom: 16px">
        <BedDouble :size="15" />
        <span>
          Hospitalizado desde {{ fmtFechaHora(p.hospitalizacion_actual.fecha_ingreso) }}
          <template v-if="p.hospitalizacion_actual.jaula"> · jaula {{ p.hospitalizacion_actual.jaula }}</template>
          — {{ p.hospitalizacion_actual.motivo }}
        </span>
        <router-link to="/hospitalizacion" class="btn mini">Ver</router-link>
      </div>

      <div class="ficha-grid">
        <!-- ---------- Columna izquierda: identidad ---------- -->
        <div class="col-izq">
          <section class="module-panel">
            <div class="module-panel-body ficha-id">
              <div class="avatar-sm xl">
                <img v-if="p.foto_url" :src="p.foto_url" :alt="p.nombre" />
                <template v-else>{{ iniciales(p.nombre) }}</template>
              </div>
              <div class="ficha-nombre">{{ p.nombre }}</div>
              <div class="ficha-sub">{{ p.especie }}{{ p.raza ? ` · ${p.raza}` : "" }}</div>
              <span :class="['estado-pill', toneEstado(p.estado)]" style="margin-top: 8px">
                <span class="dot"></span>{{ capitalizar(p.estado) }}
              </span>

              <div class="ficha-datos">
                <div><span class="k">Sexo</span><span class="v">{{ sexoLabel(p.sexo) }}</span></div>
                <div><span class="k">Edad</span><span class="v">{{ p.edad?.texto || "—" }}</span></div>
                <div><span class="k">Peso</span><span class="v">{{ p.peso_kg ? `${p.peso_kg} kg` : "—" }}</span></div>
                <div><span class="k">Color</span><span class="v">{{ p.color || "—" }}</span></div>
                <div><span class="k">Esterilizado</span><span class="v">{{ p.esterilizado ? "Sí" : "No" }}</span></div>
                <div><span class="k">Microchip</span><span class="v mono">{{ p.microchip || "—" }}</span></div>
              </div>
            </div>
          </section>

          <section class="module-panel">
            <header class="module-panel-head">
              <h2><span class="head-icon"><User :size="14" /></span> Propietario</h2>
            </header>
            <div class="module-panel-body">
              <router-link :to="`/clientes/${p.propietario.id}`" class="prop-link">
                <div class="avatar-sm">{{ iniciales(p.propietario.nombre_completo) }}</div>
                <div>
                  <strong>{{ p.propietario.nombre_completo }}</strong>
                  <small class="mono">{{ p.propietario.numero_documento }}</small>
                </div>
              </router-link>
              <div class="detalle-grid" style="margin-top: 12px">
                <div class="detalle-item">
                  <div class="k">Teléfono</div>
                  <div class="v mono">{{ p.propietario.telefono || "—" }}</div>
                </div>
                <div class="detalle-item">
                  <div class="k">Correo</div>
                  <div class="v">{{ p.propietario.correo || "—" }}</div>
                </div>
              </div>
            </div>
          </section>

          <!-- Curva de peso: dice más que cualquier número aislado -->
          <section v-if="(p.curva_peso ?? []).length > 1" class="module-panel">
            <header class="module-panel-head">
              <h2><span class="head-icon"><TrendingUp :size="14" /></span> Evolución del peso</h2>
            </header>
            <div class="module-panel-body">
              <svg class="sparkline" viewBox="0 0 240 70" preserveAspectRatio="none">
                <polyline :points="puntosPeso" fill="none" stroke="var(--emerald)" stroke-width="2" />
              </svg>
              <div class="peso-pies">
                <span>{{ fmtDate(p.curva_peso[0].fecha) }}</span>
                <span class="mono">{{ pesoMin }}–{{ pesoMax }} kg</span>
                <span>{{ fmtDate(p.curva_peso[p.curva_peso.length - 1].fecha) }}</span>
              </div>
            </div>
          </section>
        </div>

        <!-- ---------- Columna derecha: historia clínica ---------- -->
        <div class="col-der">
          <section class="module-panel">
            <header class="module-panel-head">
              <h2>
                <span class="head-icon"><ClipboardList :size="14" /></span>
                Historia clínica
                <span class="head-meta">{{ historia.length }} eventos</span>
              </h2>
              <div class="module-panel-head-actions">
                <div class="fil">
                  <Filter :size="13" />
                  <select v-model="tipoEvento" @change="cargarHistoria">
                    <option value="">Todos</option>
                    <option value="consulta">Consultas</option>
                    <option value="vacuna">Vacunas</option>
                    <option value="tratamiento">Tratamientos</option>
                    <option value="cirugia">Cirugías</option>
                    <option value="hospitalizacion">Hospitalizaciones</option>
                    <option value="examen">Exámenes</option>
                    <option value="nota">Notas</option>
                  </select>
                </div>
              </div>
            </header>

            <div v-if="!historia.length" class="module-panel-body module-empty">
              <div class="empty-icon"><ClipboardList :size="22" /></div>
              <h3>Sin eventos clínicos</h3>
              <p>La historia se irá construyendo con cada atención.</p>
            </div>

            <div v-else class="module-panel-body">
              <div class="hc-timeline">
                <div
                  v-for="e in historia"
                  :key="e.id"
                  :class="['hc-evento', `tipo-${e.tipo_evento}`]"
                >
                  <div class="hc-fecha">{{ fmtFechaHora(e.fecha) }}</div>
                  <div class="hc-titulo">{{ e.titulo }}</div>
                  <div v-if="e.resumen" class="hc-resumen">{{ e.resumen }}</div>
                  <div class="hc-meta">
                    <span class="tag">{{ capitalizar(e.tipo_evento) }}</span>
                    <template v-if="e.veterinario"> · {{ e.veterinario }}</template>
                    <template v-if="e.colegiatura"> ({{ e.colegiatura }})</template>
                    <template v-if="e.sede"> · {{ e.sede }}</template>
                  </div>
                </div>
              </div>
            </div>
          </section>

          <!-- Carné de vacunación -->
          <section class="module-panel">
            <header class="module-panel-head">
              <h2>
                <span class="head-icon"><Syringe :size="14" /></span>
                Carné de vacunación
                <span class="head-meta">{{ (p.vacunas ?? []).length }}</span>
              </h2>
              <div class="module-panel-head-actions">
                <button v-if="puedeRegistrar" class="btn" @click="modalVacuna = true">
                  <Plus :size="13" /> Aplicar vacuna
                </button>
              </div>
            </header>

            <div v-if="!(p.vacunas ?? []).length" class="module-panel-body module-empty">
              <div class="empty-icon"><Syringe :size="22" /></div>
              <h3>Sin vacunas registradas</h3>
              <p>Registra la primera aplicación para iniciar el carné.</p>
            </div>

            <div v-else class="module-panel-body tabla-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Vacuna</th>
                    <th>Aplicación</th>
                    <th>Dosis</th>
                    <th>Próximo refuerzo</th>
                    <th>Lote</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="v in p.vacunas" :key="v.id">
                    <td><strong>{{ v.nombre_vacuna }}</strong></td>
                    <td>{{ fmtDate(v.fecha_aplicacion) }}</td>
                    <td class="mono">{{ v.dosis_numero }}</td>
                    <td>
                      <span v-if="!v.proximo_refuerzo" class="muted">—</span>
                      <span v-else :class="['estado-pill', v.vencida ? 'danger' : 'ok']">
                        {{ fmtDate(v.proximo_refuerzo) }}
                      </span>
                    </td>
                    <td class="mono muted">{{ v.lote || "—" }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <!-- Tratamientos activos -->
          <section v-if="(p.tratamientos_activos ?? []).length" class="module-panel">
            <header class="module-panel-head">
              <h2><span class="head-icon"><Pill :size="14" /></span> Tratamientos activos</h2>
            </header>
            <div class="module-panel-body tabla-wrap">
              <table>
                <thead>
                  <tr><th>Medicamento</th><th>Dosis</th><th>Vía</th><th>Frecuencia</th><th>Hasta</th></tr>
                </thead>
                <tbody>
                  <tr v-for="t in p.tratamientos_activos" :key="t.id">
                    <td><strong>{{ t.medicamento }}</strong></td>
                    <td>{{ t.dosis }}</td>
                    <td>{{ capitalizar(t.via) }}</td>
                    <td>{{ t.frecuencia_horas ? `c/${t.frecuencia_horas} h` : "—" }}</td>
                    <td>{{ t.fecha_fin ? fmtDate(t.fecha_fin) : "—" }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </div>

      <PacienteModal
        v-if="modalEditar"
        :paciente="p"
        :especies="especies"
        @close="modalEditar = false"
        @guardado="onGuardado"
      />

      <VacunaModal
        v-if="modalVacuna"
        :mascota-id="p.id"
        :especie-id="p.especie_id"
        @close="modalVacuna = false"
        @guardado="onGuardado"
      />

      <ConsultaModal
        v-if="modalConsulta"
        :mascota-id="p.id"
        @close="modalConsulta = false"
        @creada="irAConsulta"
      />
    </template>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import {
  Loader2, ArrowLeft, Pencil, Stethoscope, AlertTriangle, User, TrendingUp,
  ClipboardList, Syringe, Pill, Plus, Filter, BedDouble,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import PacienteModal from "../components/PacienteModal.vue";
import VacunaModal from "../../clinico/components/VacunaModal.vue";
import ConsultaModal from "../../clinico/components/ConsultaModal.vue";
import { mascotasApi } from "../api/mascotas.api.js";
import { catalogosApi } from "../../catalogos/api/catalogos.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { fmtDate } from "../../../shared/components/ui/format.js";
import { fmtFechaHora, capitalizar, iniciales } from "../../../shared/components/ui/format.js";

const route = useRoute();
const router = useRouter();
const { hasPermission } = useAuth();
const puedeEditar = computed(() => hasPermission("mascotas:editar"));
const puedeRegistrar = computed(() => hasPermission("clinico:registrar"));

const p = ref(null);
const historia = ref([]);
const especies = ref([]);
const cargando = ref(true);
const tipoEvento = ref("");
const modalEditar = ref(false);
const modalVacuna = ref(false);
const modalConsulta = ref(false);

function sexoLabel(s) { return { macho: "Macho", hembra: "Hembra" }[s] || "No registrado"; }
function toneEstado(e) {
  return { activo: "ok", inactivo: "neutral", fallecido: "neutral", extraviado: "danger" }[e] || "neutral";
}

const pesos = computed(() => (p.value?.curva_peso ?? []).map((x) => Number(x.peso_kg)));
const pesoMin = computed(() => (pesos.value.length ? Math.min(...pesos.value) : 0));
const pesoMax = computed(() => (pesos.value.length ? Math.max(...pesos.value) : 0));

/** Sparkline normalizado al rango de pesos del paciente. */
const puntosPeso = computed(() => {
  const v = pesos.value;
  if (v.length < 2) return "";
  const min = pesoMin.value;
  const rango = pesoMax.value - min || 1;
  return v
    .map((y, i) => {
      const x = (i / (v.length - 1)) * 240;
      const yy = 62 - ((y - min) / rango) * 54;
      return `${x.toFixed(1)},${yy.toFixed(1)}`;
    })
    .join(" ");
});

async function cargarHistoria() {
  const h = await mascotasApi.historia(route.params.id, {
    tipo: tipoEvento.value || undefined,
    limit: 100,
  });
  historia.value = h.data ?? [];
}

async function cargar() {
  cargando.value = true;
  try {
    const [ficha] = await Promise.all([mascotasApi.obtener(route.params.id), cargarHistoria()]);
    p.value = ficha.data;
  } finally {
    cargando.value = false;
  }
}

function onGuardado() {
  modalEditar.value = false;
  modalVacuna.value = false;
  cargar();
}
function irAConsulta(id) {
  modalConsulta.value = false;
  router.push(`/consultas/${id}`);
}

onMounted(async () => {
  try {
    const e = await catalogosApi.especies();
    especies.value = e.data ?? [];
  } catch {
    // El catálogo solo hace falta para editar; la ficha se muestra igual.
  }
  cargar();
});

watch(() => route.params.id, cargar);
</script>

<style scoped>
.ficha-grid { display: grid; grid-template-columns: 320px 1fr; gap: 16px; align-items: start; }
@media (max-width: 1000px) { .ficha-grid { grid-template-columns: 1fr; } }
.col-izq, .col-der { display: flex; flex-direction: column; gap: 16px; }

.ficha-id { display: flex; flex-direction: column; align-items: center; text-align: center; padding: 22px 18px; }
.ficha-nombre { font-size: 19px; font-weight: 700; color: var(--ink); margin-top: 12px; letter-spacing: -0.02em; }
.ficha-sub { font-size: 12.5px; color: var(--ink-3); }

.ficha-datos {
  width: 100%; margin-top: 18px; display: flex; flex-direction: column; gap: 8px;
  border-top: 1px solid var(--line-soft); padding-top: 14px;
}
.ficha-datos > div { display: flex; justify-content: space-between; gap: 10px; font-size: 12.5px; }
.ficha-datos .k { color: var(--ink-3); }
.ficha-datos .v { color: var(--ink); font-weight: 500; }

.prop-link { display: flex; align-items: center; gap: 10px; text-decoration: none; }
.prop-link strong { display: block; font-size: 13.5px; color: var(--ink); }
.prop-link small { font-size: 11.5px; color: var(--ink-3); }
.prop-link:hover strong { color: var(--emerald-deep); }

.sparkline { width: 100%; height: 70px; display: block; }
.peso-pies {
  display: flex; justify-content: space-between;
  font-size: 11px; color: var(--ink-4); margin-top: 4px;
}
.btn.mini { height: 26px; padding: 0 9px; font-size: 11.5px; }
</style>
