<template>
  <div>
    <PageHeader
      :eyebrow="saludo"
      :title="`Hola, ${primerNombre}`"
      :subtitle="subtitulo"
    >
      <template #actions>
        <div class="fil">
          <CalendarRange :size="14" />
          <select v-model="periodo" @change="cargar">
            <option value="hoy">Hoy</option>
            <option value="semana">Últimos 7 días</option>
            <option value="mes">Este mes</option>
            <option value="trimestre">Últimos 90 días</option>
          </select>
        </div>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="cargando ? 'spin' : ''" /> Actualizar
        </button>
      </template>
    </PageHeader>

    <!-- ---------- Indicadores ---------- -->
    <div class="stat-row">
      <div class="stat">
        <div class="stat-label">
          Citas de hoy
          <span class="icon-tile"><CalendarClock :size="14" /></span>
        </div>
        <div class="stat-val">{{ d.hoy?.citas ?? 0 }}<span class="unit">agendadas</span></div>
        <div class="stat-meta">
          <span class="trend">{{ d.hoy?.completadas ?? 0 }} atendidas</span>
          {{ d.hoy?.pendientes ?? 0 }} por atender
        </div>
      </div>

      <div class="stat">
        <div class="stat-label">
          Facturado
          <span class="icon-tile"><Receipt :size="14" /></span>
        </div>
        <div class="stat-val">{{ fmtSoles(d.ingresos?.facturado ?? 0) }}</div>
        <div class="stat-meta">
          <span :class="['trend', variacion >= 0 ? '' : 'flat']">
            {{ variacion >= 0 ? "+" : "" }}{{ variacion }}%
          </span>
          vs. periodo anterior
        </div>
      </div>

      <div class="stat">
        <div class="stat-label">
          Cobrado
          <span class="icon-tile"><Wallet :size="14" /></span>
        </div>
        <div class="stat-val">{{ fmtSoles(d.ingresos?.cobrado ?? 0) }}</div>
        <div class="stat-meta">
          <span class="trend flat">{{ fmtSoles(d.ingresos?.pendiente ?? 0) }}</span>
          por cobrar
        </div>
      </div>

      <div class="stat">
        <div class="stat-label">
          Ticket promedio
          <span class="icon-tile violet"><TrendingUp :size="14" /></span>
        </div>
        <div class="stat-val">{{ fmtSoles(d.ingresos?.ticket_promedio ?? 0) }}</div>
        <div class="stat-meta">
          <span class="trend flat">{{ d.ingresos?.documentos ?? 0 }}</span>
          comprobantes
        </div>
      </div>
    </div>

    <!-- ---------- Alertas que exigen acción ---------- -->
    <div v-if="alertasActivas.length" class="alertas-row">
      <router-link
        v-for="a in alertasActivas"
        :key="a.label"
        :to="a.to"
        :class="['alerta-card', a.tone]"
      >
        <component :is="a.icon" :size="16" />
        <div>
          <div class="n">{{ a.valor }}</div>
          <div class="l">{{ a.label }}</div>
        </div>
        <ChevronRight :size="15" class="chev" />
      </router-link>
    </div>

    <div class="dash-cols">
      <!-- ---------- Agenda de hoy ---------- -->
      <section class="module-panel">
        <header class="module-panel-head">
          <h2>
            <span class="head-icon"><CalendarClock :size="14" /></span>
            Agenda de hoy
            <span class="head-meta">{{ citasHoy.length }} citas</span>
          </h2>
          <div class="module-panel-head-actions">
            <router-link to="/agenda" class="btn">Ver agenda completa</router-link>
          </div>
        </header>

        <div v-if="cargando" class="module-panel-body module-empty">
          <span class="loading-mini"><Loader2 :size="14" class="spin" /> Cargando…</span>
        </div>

        <div v-else-if="!citasHoy.length" class="module-panel-body module-empty">
          <div class="empty-icon"><CalendarCheck :size="22" /></div>
          <h3>Sin citas para hoy</h3>
          <p>Cuando recepción agende una atención, aparecerá aquí.</p>
        </div>

        <div v-else class="module-panel-body agenda-hoy">
          <button
            v-for="c in citasHoy"
            :key="c.id"
            :class="['cita-card', c.prioridad]"
            @click="$router.push('/agenda')"
          >
            <div class="hora">{{ fmtHora(c.fecha_hora) }}</div>
            <div class="paciente">{{ c.mascota }} · {{ c.especie }}</div>
            <div class="meta">{{ c.cliente }}</div>
            <div class="pie">
              <span :class="['estado-pill', toneCita(c.estado)]">
                <span class="dot"></span>{{ capitalizar(c.estado) }}
              </span>
              <span class="tag">{{ c.veterinario || "Sin asignar" }}</span>
            </div>
          </button>
        </div>
      </section>

      <!-- ---------- Recordatorios ---------- -->
      <section class="module-panel">
        <header class="module-panel-head">
          <h2>
            <span class="head-icon"><BellRing :size="14" /></span>
            Por contactar
            <span class="head-meta">{{ recordatorios.length }}</span>
          </h2>
        </header>

        <div v-if="!recordatorios.length" class="module-panel-body module-empty">
          <div class="empty-icon"><CheckCircle2 :size="22" /></div>
          <h3>Todo al día</h3>
          <p>No hay refuerzos ni controles pendientes esta semana.</p>
        </div>

        <div v-else class="module-panel-body recordatorios">
          <div v-for="r in recordatorios" :key="r.id" class="recordatorio">
            <div :class="['avatar-sm', toneRecordatorio(r.tipo)]">
              <component :is="iconoRecordatorio(r.tipo)" :size="15" />
            </div>
            <div class="grow">
              <div class="t">{{ r.titulo }}</div>
              <div class="s">
                {{ r.mascota }} · {{ r.cliente }}
                <span v-if="r.cliente_telefono" class="mono"> · {{ r.cliente_telefono }}</span>
              </div>
            </div>
            <div class="stack text-right">
              <span :class="['estado-pill', r.dias_restantes < 0 ? 'danger' : 'warn']">
                {{ r.dias_restantes < 0 ? "vencido" : fmtRelativo(r.fecha_objetivo) }}
              </span>
              <button class="btn mini" @click="completar(r)">Hecho</button>
            </div>
          </div>
        </div>
      </section>
    </div>

    <div class="dash-cols">
      <!-- ---------- Actividad clínica ---------- -->
      <section class="module-panel">
        <header class="module-panel-head">
          <h2><span class="head-icon"><Stethoscope :size="14" /></span> Actividad clínica</h2>
        </header>
        <div class="module-panel-body clinico-grid">
          <div class="clinico-item">
            <div class="n">{{ d.clinico?.consultas ?? 0 }}</div>
            <div class="l">Consultas</div>
          </div>
          <div class="clinico-item">
            <div class="n">{{ d.clinico?.cirugias ?? 0 }}</div>
            <div class="l">Cirugías</div>
          </div>
          <div class="clinico-item">
            <div class="n">{{ d.clinico?.vacunas ?? 0 }}</div>
            <div class="l">Vacunas</div>
          </div>
          <div class="clinico-item">
            <div class="n">{{ d.clinico?.hospitalizados ?? 0 }}</div>
            <div class="l">Hospitalizados</div>
          </div>
        </div>

        <div class="module-panel-body" style="border-top: 1px solid var(--line-soft)">
          <div class="section-title">Pacientes por especie</div>
          <div class="especies">
            <div v-for="e in d.por_especie ?? []" :key="e.especie" class="especie-row">
              <span class="nom">{{ e.especie }}</span>
              <div class="barra">
                <div class="fill" :style="{ width: pctEspecie(e) + '%' }"></div>
              </div>
              <span class="n mono">{{ e.pacientes }}</span>
            </div>
          </div>
        </div>
      </section>

      <!-- ---------- Top servicios ---------- -->
      <section class="module-panel">
        <header class="module-panel-head">
          <h2><span class="head-icon"><BarChart3 :size="14" /></span> Servicios más facturados</h2>
        </header>

        <div v-if="!(d.top_servicios ?? []).length" class="module-panel-body module-empty">
          <div class="empty-icon"><BarChart3 :size="22" /></div>
          <h3>Sin datos en el periodo</h3>
          <p>Cuando se presten servicios aparecerán aquí ordenados por ingreso.</p>
        </div>

        <div v-else class="module-panel-body tabla-wrap">
          <table>
            <thead>
              <tr>
                <th>Servicio</th>
                <th class="num">Veces</th>
                <th class="num">Ingresos</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="s in d.top_servicios" :key="s.nombre">
                <td>
                  <div class="stack">
                    <strong>{{ s.nombre }}</strong>
                    <span class="tag">{{ capitalizar(s.tipo) }}</span>
                  </div>
                </td>
                <td class="num mono">{{ s.veces }}</td>
                <td class="num mono">{{ fmtSoles(s.ingresos) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from "vue";
import {
  CalendarClock, CalendarCheck, CalendarRange, Receipt, Wallet, TrendingUp,
  RefreshCw, Loader2, BellRing, CheckCircle2, Stethoscope, BarChart3,
  ChevronRight, PackageX, CalendarX, Syringe, AlarmClock, Scissors,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import { dashboardApi } from "../api/dashboard.api.js";
import { citasApi } from "../../citas/api/citas.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { fmtSoles } from "../../../shared/components/ui/format.js";
import { fmtHora, fmtRelativo, capitalizar } from "../../../shared/components/ui/format.js";

const { user } = useAuth();
const d = ref({});
const citasHoy = ref([]);
const recordatorios = ref([]);
const cargando = ref(false);
const periodo = ref("mes");

const primerNombre = computed(() => (user.value?.nombre || "").split(" ")[0] || "");
const saludo = computed(() => {
  const h = new Date().getHours();
  if (h < 12) return "Buenos días";
  if (h < 19) return "Buenas tardes";
  return "Buenas noches";
});
const subtitulo = computed(() => {
  const n = d.value.hoy?.pendientes ?? 0;
  if (!n) return "No quedan citas pendientes para hoy";
  return `Quedan ${n} ${n === 1 ? "cita pendiente" : "citas pendientes"} para hoy`;
});

/** Variación porcentual del facturado contra el periodo anterior de igual duración. */
const variacion = computed(() => {
  const act = Number(d.value.ingresos?.facturado ?? 0);
  const ant = Number(d.value.ingresos_periodo_anterior ?? 0);
  if (!ant) return act > 0 ? 100 : 0;
  return Math.round(((act - ant) / ant) * 100);
});

/** Solo se muestran las alertas con valor: una tarjeta en cero es ruido. */
const alertasActivas = computed(() => {
  const a = d.value.alertas ?? {};
  return [
    { label: "Productos en stock crítico", valor: a.stock_critico, icon: PackageX, tone: "danger", to: "/inventario" },
    { label: "Lotes por vencer (90 d)", valor: a.por_vencer, icon: CalendarX, tone: "warn", to: "/inventario" },
    { label: "Refuerzos de vacuna próximos", valor: a.refuerzos_pendientes, icon: Syringe, tone: "info", to: "/vacunacion" },
    { label: "Permisos por aprobar", valor: a.permisos_pendientes, icon: AlarmClock, tone: "warn", to: "/equipo" },
  ].filter((x) => Number(x.valor) > 0);
});

function pctEspecie(e) {
  const total = (d.value.por_especie ?? []).reduce((s, x) => s + Number(x.pacientes), 0);
  return total ? Math.round((Number(e.pacientes) / total) * 100) : 0;
}

function toneCita(estado) {
  return {
    programada: "neutral", confirmada: "info", en_espera: "warn",
    en_atencion: "violet", completada: "ok", cancelada: "danger", no_asistio: "danger",
  }[estado] || "neutral";
}
function toneRecordatorio(tipo) {
  return { vacuna: "blue", desparasitacion: "amber", control: "", cita: "violet" }[tipo] ?? "";
}
function iconoRecordatorio(tipo) {
  return { vacuna: Syringe, desparasitacion: Syringe, control: Stethoscope, cita: CalendarClock }[tipo] ?? BellRing;
}

/** Rango del selector: el backend calcula solo el comparativo del periodo anterior. */
function rango() {
  const hoy = new Date();
  const iso = (x) => x.toISOString().slice(0, 10);
  if (periodo.value === "hoy") return { desde: iso(hoy), hasta: iso(hoy) };
  if (periodo.value === "semana") {
    const d7 = new Date(hoy); d7.setDate(d7.getDate() - 6);
    return { desde: iso(d7), hasta: iso(hoy) };
  }
  if (periodo.value === "trimestre") {
    const d90 = new Date(hoy); d90.setDate(d90.getDate() - 89);
    return { desde: iso(d90), hasta: iso(hoy) };
  }
  return { desde: iso(new Date(hoy.getFullYear(), hoy.getMonth(), 1)), hasta: iso(hoy) };
}

async function cargar() {
  cargando.value = true;
  try {
    const hoyISO = new Date().toISOString().slice(0, 10);
    const manana = new Date(); manana.setDate(manana.getDate() + 1);
    const [resumen, agenda, recs] = await Promise.all([
      dashboardApi.resumen(rango()),
      citasApi.listar({ desde: hoyISO, hasta: manana.toISOString().slice(0, 10), pageSize: 12 }),
      dashboardApi.recordatorios(7),
    ]);
    d.value = resumen.data ?? {};
    citasHoy.value = agenda.data ?? [];
    recordatorios.value = recs.data ?? [];
  } finally {
    cargando.value = false;
  }
}

async function completar(r) {
  await dashboardApi.completarRecordatorio(r.id);
  recordatorios.value = recordatorios.value.filter((x) => x.id !== r.id);
}

onMounted(cargar);
</script>

<style scoped>
/* ---- alertas ---- */
.alertas-row {
  display: grid; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr));
  gap: 12px; margin-bottom: 18px;
}
.alerta-card {
  display: flex; align-items: center; gap: 11px;
  padding: 12px 14px; border-radius: 12px; text-decoration: none;
  background: var(--bg-elev); border: 1px solid var(--line);
  transition: transform 0.15s ease, box-shadow 0.15s ease;
}
.alerta-card:hover { transform: translateY(-1px); box-shadow: var(--shadow-md); }
.alerta-card .n { font-size: 18px; font-weight: 700; color: var(--ink); line-height: 1.1; }
.alerta-card .l { font-size: 11.5px; color: var(--ink-3); }
.alerta-card .chev { margin-left: auto; color: var(--ink-4); }
.alerta-card.danger { border-left: 3px solid var(--red);   color: var(--red-ink); }
.alerta-card.warn   { border-left: 3px solid var(--amber); color: var(--amber-ink); }
.alerta-card.info   { border-left: 3px solid var(--blue);  color: var(--blue-ink); }

/* ---- columnas ---- */
.dash-cols {
  display: grid; grid-template-columns: 1.4fr 1fr;
  gap: 16px; margin-bottom: 16px; align-items: start;
}
@media (max-width: 1100px) { .dash-cols { grid-template-columns: 1fr; } }

.agenda-hoy {
  display: grid; grid-template-columns: repeat(auto-fill, minmax(210px, 1fr));
  gap: 10px; padding: 14px;
}
.agenda-hoy .cita-card { text-align: left; font: inherit; }

.recordatorios { display: flex; flex-direction: column; gap: 2px; padding: 8px; }
.recordatorio {
  display: flex; align-items: center; gap: 11px;
  padding: 9px 10px; border-radius: 9px;
}
.recordatorio:hover { background: var(--bg-soft); }
.recordatorio .t { font-size: 13px; font-weight: 600; color: var(--ink); }
.recordatorio .s { font-size: 11.5px; color: var(--ink-3); }

.clinico-grid {
  display: grid; grid-template-columns: repeat(4, 1fr);
  gap: 1px; background: var(--line-soft); padding: 0;
}
.clinico-item { background: var(--bg-elev); padding: 16px 14px; text-align: center; }
.clinico-item .n { font-size: 22px; font-weight: 700; color: var(--ink); letter-spacing: -0.02em; }
.clinico-item .l { font-size: 11px; color: var(--ink-3); margin-top: 2px; }

.especies { display: flex; flex-direction: column; gap: 9px; margin-top: 10px; }
.especie-row { display: grid; grid-template-columns: 90px 1fr 34px; align-items: center; gap: 10px; }
.especie-row .nom { font-size: 12.5px; color: var(--ink-2); }
.especie-row .barra { height: 7px; border-radius: 999px; background: var(--bg-soft); overflow: hidden; }
.especie-row .fill { height: 100%; border-radius: 999px; background: var(--emerald); }
.especie-row .n { font-size: 12px; color: var(--ink-3); text-align: right; }

.btn.mini { height: 24px; padding: 0 8px; font-size: 11px; }
</style>
