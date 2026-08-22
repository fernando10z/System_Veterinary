<template>
  <div>
    <PageHeader
      eyebrow="Medicina preventiva"
      title="Vacunación"
      subtitle="Refuerzos pendientes y protocolos de la empresa"
    >
      <template #actions>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="cargando ? 'spin' : ''" /> Actualizar
        </button>
      </template>
    </PageHeader>

    <div class="stat-row">
      <div class="stat">
        <div class="stat-label">Refuerzos vencidos <span class="icon-tile"><AlertTriangle :size="14" /></span></div>
        <div class="stat-val">{{ vencidos.length }}<span class="unit">pacientes</span></div>
        <div class="stat-meta">requieren contacto inmediato</div>
      </div>
      <div class="stat">
        <div class="stat-label">Próximos 30 días <span class="icon-tile amber"><CalendarClock :size="14" /></span></div>
        <div class="stat-val">{{ proximos.length }}<span class="unit">refuerzos</span></div>
        <div class="stat-meta">planificar contacto</div>
      </div>
      <div class="stat">
        <div class="stat-label">Protocolos <span class="icon-tile"><Syringe :size="14" /></span></div>
        <div class="stat-val">{{ esquemas.length }}<span class="unit">activos</span></div>
        <div class="stat-meta">{{ obligatorios }} obligatorios</div>
      </div>
      <div class="stat">
        <div class="stat-label">Stock de vacunas <span class="icon-tile violet"><Package :size="14" /></span></div>
        <div class="stat-val">{{ stockVacunas }}<span class="unit">dosis</span></div>
        <div class="stat-meta">{{ vacunasCriticas }} en stock crítico</div>
      </div>
    </div>

    <section class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><BellRing :size="14" /></span>
          Cola de refuerzos
          <span class="head-meta">{{ recordatorios.length }}</span>
        </h2>
        <div class="module-panel-head-actions">
          <div class="fil">
            <CalendarRange :size="13" />
            <select v-model.number="dias" @change="cargar">
              <option :value="7">Próximos 7 días</option>
              <option :value="30">Próximos 30 días</option>
              <option :value="90">Próximos 90 días</option>
            </select>
          </div>
        </div>
      </header>

      <div v-if="!recordatorios.length" class="module-panel-body module-empty">
        <div class="empty-icon"><CheckCircle2 :size="22" /></div>
        <h3>Sin refuerzos pendientes</h3>
        <p>Ningún paciente tiene vacunas por vencer en el rango elegido.</p>
      </div>

      <div v-else class="module-panel-body tabla-wrap">
        <table>
          <thead>
            <tr>
              <th>Paciente</th>
              <th>Propietario</th>
              <th>Contacto</th>
              <th>Refuerzo</th>
              <th>Vence</th>
              <th class="acciones-col"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in recordatorios" :key="r.id">
              <td>
                <router-link :to="`/pacientes/${r.mascota_id}`" class="entidad-cell">
                  <div class="avatar-sm">
                    <img v-if="r.mascota_foto" :src="r.mascota_foto" :alt="r.mascota" />
                    <template v-else>{{ iniciales(r.mascota || "?") }}</template>
                  </div>
                  <div class="info"><strong>{{ r.mascota }}</strong></div>
                </router-link>
              </td>
              <td>{{ r.cliente }}</td>
              <td class="mono">{{ r.cliente_telefono || r.cliente_correo || "—" }}</td>
              <td>{{ r.titulo }}</td>
              <td>
                <span :class="['estado-pill', r.dias_restantes < 0 ? 'danger' : 'warn']">
                  {{ fmtDate(r.fecha_objetivo) }} · {{ fmtRelativo(r.fecha_objetivo) }}
                </span>
              </td>
              <td class="acciones-col">
                <button class="btn mini" @click="marcarContactado(r)">Contactado</button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <section class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><Syringe :size="14" /></span>
          Protocolos de vacunación
          <span class="head-meta">{{ esquemas.length }}</span>
        </h2>
      </header>

      <div v-if="!esquemas.length" class="module-panel-body module-empty">
        <div class="empty-icon"><Syringe :size="22" /></div>
        <h3>Sin protocolos configurados</h3>
        <p>Define los esquemas por especie en Configuración → Catálogos.</p>
      </div>

      <div v-else class="module-panel-body tabla-wrap">
        <table>
          <thead>
            <tr>
              <th>Protocolo</th>
              <th>Especie</th>
              <th class="num">Inicio</th>
              <th class="num">Dosis</th>
              <th class="num">Intervalo</th>
              <th class="num">Revacunación</th>
              <th>Obligatoria</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="e in esquemas" :key="e.id">
              <td><strong>{{ e.nombre }}</strong></td>
              <td>{{ e.especie }}</td>
              <td class="num mono">{{ e.edad_inicio_semanas ? `${e.edad_inicio_semanas} sem` : "—" }}</td>
              <td class="num mono">{{ e.dosis_totales }}</td>
              <td class="num mono">{{ e.intervalo_dias ? `${e.intervalo_dias} d` : "—" }}</td>
              <td class="num mono">{{ e.revacunacion_meses ? `${e.revacunacion_meses} m` : "—" }}</td>
              <td>
                <span :class="['estado-pill', e.obligatoria ? 'danger' : 'neutral']">
                  <span class="dot"></span>{{ e.obligatoria ? "Obligatoria" : "Opcional" }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from "vue";
import {
  Syringe, RefreshCw, BellRing, CheckCircle2, AlertTriangle,
  CalendarClock, CalendarRange, Package,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import { dashboardApi } from "../../dashboard/api/dashboard.api.js";
import { catalogosApi } from "../../catalogos/api/catalogos.api.js";
import { inventarioApi } from "../../inventario/api/inventario.api.js";
import { fmtDate } from "../../../shared/components/ui/format.js";
import { fmtRelativo, iniciales } from "../../../shared/components/ui/format.js";

const recordatorios = ref([]);
const esquemas = ref([]);
const vacunas = ref([]);
const cargando = ref(false);
const dias = ref(30);

const vencidos = computed(() => recordatorios.value.filter((r) => r.dias_restantes < 0));
const proximos = computed(() => recordatorios.value.filter((r) => r.dias_restantes >= 0));
const obligatorios = computed(() => esquemas.value.filter((e) => e.obligatoria).length);
const stockVacunas = computed(() => vacunas.value.reduce((s, v) => s + Number(v.stock_actual), 0));
const vacunasCriticas = computed(
  () => vacunas.value.filter((v) => Number(v.stock_actual) <= Number(v.stock_minimo)).length,
);

async function marcarContactado(r) {
  await dashboardApi.completarRecordatorio(r.id);
  recordatorios.value = recordatorios.value.filter((x) => x.id !== r.id);
}

async function cargar() {
  cargando.value = true;
  try {
    const [rec, esq, vac] = await Promise.all([
      dashboardApi.recordatorios(dias.value),
      catalogosApi.esquemasVacunacion(),
      inventarioApi.productos({ tipo: "vacuna", pageSize: 100 }),
    ]);
    recordatorios.value = (rec.data ?? []).filter((r) => r.tipo === "vacuna");
    esquemas.value = esq.data ?? [];
    vacunas.value = vac.data ?? [];
  } finally {
    cargando.value = false;
  }
}

onMounted(cargar);
</script>

<style scoped>
.entidad-cell { text-decoration: none; }
.btn.mini { height: 26px; padding: 0 9px; font-size: 11.5px; }
</style>
