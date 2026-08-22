<template>
  <div>
    <PageHeader
      eyebrow="Administración"
      title="Equipo"
      :subtitle="`${equipo.length} personas · ${veterinarios} veterinarios`"
    >
      <template #actions>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="cargando ? 'spin' : ''" /> Actualizar
        </button>
        <button class="btn primary" @click="marcar">
          <Fingerprint :size="14" /> Marcar asistencia
        </button>
      </template>
    </PageHeader>

    <div class="stat-row">
      <div class="stat">
        <div class="stat-label">Consultas del mes <span class="icon-tile"><Stethoscope :size="14" /></span></div>
        <div class="stat-val">{{ totalConsultas }}<span class="unit">atendidas</span></div>
        <div class="stat-meta">por todo el equipo</div>
      </div>
      <div class="stat">
        <div class="stat-label">Horas trabajadas <span class="icon-tile"><Clock :size="14" /></span></div>
        <div class="stat-val">{{ totalHoras }}<span class="unit">horas</span></div>
        <div class="stat-meta">en el periodo</div>
      </div>
      <div class="stat">
        <div class="stat-label">Tardanzas <span class="icon-tile amber"><AlarmClock :size="14" /></span></div>
        <div class="stat-val">{{ totalTardanzas }}<span class="unit">registros</span></div>
        <div class="stat-meta">requieren seguimiento</div>
      </div>
      <div class="stat">
        <div class="stat-label">Permisos pendientes <span class="icon-tile violet"><FileClock :size="14" /></span></div>
        <div class="stat-val">{{ pendientes.length }}<span class="unit">por aprobar</span></div>
        <div class="stat-meta">solicitudes abiertas</div>
      </div>
    </div>

    <!-- Solicitudes que esperan decisión -->
    <section v-if="pendientes.length" class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><FileClock :size="14" /></span>
          Permisos por aprobar
          <span class="head-meta">{{ pendientes.length }}</span>
        </h2>
      </header>
      <div class="module-panel-body tabla-wrap">
        <table>
          <thead>
            <tr><th>Solicitante</th><th>Tipo</th><th>Desde</th><th>Hasta</th><th class="num">Días</th><th>Motivo</th><th class="acciones-col"></th></tr>
          </thead>
          <tbody>
            <tr v-for="p in pendientes" :key="p.id">
              <td><strong>{{ p.solicitante }}</strong></td>
              <td><span class="tag">{{ capitalizar(p.tipo) }}</span></td>
              <td class="mono">{{ fmtDate(p.fecha_inicio) }}</td>
              <td class="mono">{{ fmtDate(p.fecha_fin) }}</td>
              <td class="num mono">{{ p.dias }}</td>
              <td class="muted">{{ p.motivo || "—" }}</td>
              <td class="acciones-col">
                <div class="row-actions">
                  <button v-if="puedeAprobar" class="btn mini primary" @click="resolver(p, 'aprobado')">Aprobar</button>
                  <button v-if="puedeAprobar" class="btn mini" @click="resolver(p, 'rechazado')">Rechazar</button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <section class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><Users :size="14" /></span>
          Personal de la empresa
          <span class="head-meta">{{ equipo.length }}</span>
        </h2>
        <div class="module-panel-head-actions">
          <div class="fil">
            <CalendarRange :size="13" />
            <input v-model="desde" type="date" @change="cargar" />
          </div>
          <div class="fil">
            <span class="muted">a</span>
            <input v-model="hasta" type="date" @change="cargar" />
          </div>
        </div>
      </header>

      <div v-if="!cargando && !equipo.length" class="module-panel-body module-empty">
        <div class="empty-icon"><Users :size="22" /></div>
        <h3>Sin personal registrado</h3>
        <p>Los usuarios de la empresa aparecerán aquí con su carga de trabajo.</p>
      </div>

      <div v-else class="module-panel-body equipo-grid">
        <div v-for="p in equipo" :key="p.user_id" class="persona">
          <div class="persona-head">
            <div class="avatar-sm lg" :style="p.color_agenda ? { background: p.color_agenda, color: '#fff' } : {}">
              <img v-if="p.foto_url" :src="p.foto_url" :alt="p.profesional" />
              <template v-else>{{ iniciales(p.profesional) }}</template>
            </div>
            <div class="grow">
              <strong>{{ p.profesional }}</strong>
              <small>
                {{ p.rol || "Sin rol" }}
                <template v-if="p.especializacion"> · {{ p.especializacion }}</template>
              </small>
              <small v-if="p.colegiatura" class="mono muted">{{ p.colegiatura }}</small>
            </div>
            <span :class="['estado-pill', p.estado === 'activo' ? 'ok' : 'neutral']">
              <span class="dot"></span>{{ capitalizar(p.estado) }}
            </span>
          </div>

          <div class="persona-metricas">
            <div><div class="n">{{ p.citas_atendidas }}</div><div class="l">Citas</div></div>
            <div><div class="n">{{ p.consultas }}</div><div class="l">Consultas</div></div>
            <div><div class="n">{{ p.cirugias }}</div><div class="l">Cirugías</div></div>
            <div><div class="n">{{ Number(p.horas_trabajadas).toFixed(0) }}</div><div class="l">Horas</div></div>
          </div>

          <div class="persona-pie">
            <span v-if="p.contrato" class="tag">
              {{ capitalizar(p.contrato.tipo) }}{{ p.contrato.cargo ? ` · ${p.contrato.cargo}` : "" }}
            </span>
            <span v-if="Number(p.tardanzas) > 0" class="estado-pill warn">
              {{ p.tardanzas }} {{ Number(p.tardanzas) === 1 ? "tardanza" : "tardanzas" }}
            </span>
            <span v-if="p.evaluacion_promedio" class="estado-pill info">
              <Star :size="10" /> {{ p.evaluacion_promedio }}
            </span>
          </div>
        </div>
      </div>
    </section>

    <section class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><CalendarCheck :size="14" /></span>
          Asistencia
          <span class="head-meta">{{ resumenAsistencia.dias ?? 0 }} registros</span>
        </h2>
        <div class="module-panel-head-actions">
          <span class="tag">{{ resumenAsistencia.puntuales ?? 0 }} puntuales</span>
          <span class="tag">{{ resumenAsistencia.tardanzas ?? 0 }} tardanzas</span>
          <span class="tag">{{ Number(resumenAsistencia.horas_totales ?? 0).toFixed(1) }} h</span>
        </div>
      </header>

      <div v-if="!asistencia.length" class="module-panel-body module-empty">
        <div class="empty-icon"><CalendarCheck :size="22" /></div>
        <h3>Sin registros de asistencia</h3>
        <p>Las marcas de entrada y salida aparecerán aquí.</p>
      </div>

      <div v-else class="module-panel-body tabla-wrap">
        <table>
          <thead>
            <tr><th>Fecha</th><th>Persona</th><th>Entrada</th><th>Salida</th><th class="num">Horas</th><th>Estado</th></tr>
          </thead>
          <tbody>
            <tr v-for="a in asistencia" :key="a.id">
              <td class="mono">{{ fmtDate(a.fecha) }}</td>
              <td>{{ a.profesional }}</td>
              <td class="mono">{{ a.hora_entrada || "—" }}</td>
              <td class="mono">{{ a.hora_salida || "—" }}</td>
              <td class="num mono">{{ a.horas_trabajadas ?? "—" }}</td>
              <td>
                <span :class="['estado-pill', toneAsistencia(a.estado)]">
                  <span class="dot"></span>{{ capitalizar(a.estado) }}
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
  Users, Clock, AlarmClock, FileClock, Stethoscope, RefreshCw, Fingerprint,
  CalendarRange, CalendarCheck, Star,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import { rrhhApi } from "../api/rrhh.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { fmtDate, capitalizar, iniciales } from "../../../shared/components/ui/format.js";
import { notify } from "../../../shared/composables/useNotify.js";

const { hasPermission } = useAuth();
const puedeAprobar = computed(() => hasPermission("rrhh:aprobar"));

const equipo = ref([]);
const asistencia = ref([]);
const resumenAsistencia = ref({});
const pendientes = ref([]);
const cargando = ref(false);

const hoy = new Date();
const inicioMes = new Date(hoy.getFullYear(), hoy.getMonth(), 1);
const desde = ref(inicioMes.toISOString().slice(0, 10));
const hasta = ref(hoy.toISOString().slice(0, 10));

const veterinarios = computed(() => equipo.value.filter((p) => p.es_veterinario).length);
const totalConsultas = computed(() => equipo.value.reduce((s, p) => s + Number(p.consultas), 0));
const totalHoras = computed(() =>
  equipo.value.reduce((s, p) => s + Number(p.horas_trabajadas), 0).toFixed(0),
);
const totalTardanzas = computed(() => equipo.value.reduce((s, p) => s + Number(p.tardanzas), 0));

function toneAsistencia(e) {
  return { puntual: "ok", tardanza: "warn", falta: "danger", justificada: "info" }[e] || "neutral";
}

async function marcar() {
  try {
    const r = await rrhhApi.marcarAsistencia();
    const d = r.data;
    notify.success(
      d.accion === "entrada" ? "Entrada registrada" : "Salida registrada",
      `${d.hora}${d.estado ? ` · ${d.estado}` : ""}`,
    );
    cargar();
  } catch (e) {
    notify.error("No se pudo marcar", e.message);
  }
}

async function resolver(p, estado) {
  const comentario = estado === "rechazado"
    ? await notify.prompt("Motivo del rechazo", { placeholder: "Explica la decisión" })
    : "";
  if (estado === "rechazado" && !comentario) return;
  try {
    await rrhhApi.resolverPermiso(p.id, { estado, comentario: comentario || undefined });
    notify.success(estado === "aprobado" ? "Permiso aprobado" : "Permiso rechazado");
    cargar();
  } catch (e) {
    notify.error("No se pudo resolver", e.message);
  }
}

async function cargar() {
  cargando.value = true;
  try {
    const [eq, asis, per] = await Promise.all([
      rrhhApi.equipo({ desde: desde.value, hasta: hasta.value }),
      rrhhApi.asistencia({ desde: desde.value, hasta: hasta.value }),
      rrhhApi.permisos({ estado: "pendiente" }),
    ]);
    equipo.value = eq.data ?? [];
    asistencia.value = asis.data ?? [];
    resumenAsistencia.value = asis.meta ?? {};
    pendientes.value = per.data ?? [];
  } finally {
    cargando.value = false;
  }
}

onMounted(cargar);
</script>

<style scoped>
.equipo-grid {
  display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 12px; padding: 14px;
}
.persona {
  border: 1px solid var(--line); border-radius: 12px;
  padding: 13px; background: var(--bg-elev);
}
.persona-head { display: flex; align-items: center; gap: 11px; }
.persona-head strong { display: block; font-size: 13.5px; color: var(--ink); }
.persona-head small { display: block; font-size: 11.5px; color: var(--ink-3); }

.persona-metricas {
  display: grid; grid-template-columns: repeat(4, 1fr);
  gap: 1px; margin: 12px 0 10px;
  background: var(--line-soft); border-radius: 9px; overflow: hidden;
}
.persona-metricas > div { background: var(--bg-soft); padding: 9px 4px; text-align: center; }
.persona-metricas .n { font-size: 16px; font-weight: 700; color: var(--ink); }
.persona-metricas .l { font-size: 10px; color: var(--ink-3); }

.persona-pie { display: flex; flex-wrap: wrap; gap: 5px; }
.btn.mini { height: 26px; padding: 0 9px; font-size: 11.5px; }
</style>
