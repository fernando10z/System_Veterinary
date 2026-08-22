<template>
  <div class="portal-shell">
    <header class="portal-topbar">
      <div class="pt-brand">
        <div class="pt-logo"><PawPrint :size="17" /></div>
        <div>
          <div class="pt-nombre">Portal del propietario</div>
          <div class="pt-sub">{{ cliente?.nombres }} {{ cliente?.apellido_paterno }}</div>
        </div>
      </div>
      <button class="btn" @click="salir"><LogOut :size="14" /> Salir</button>
    </header>

    <main class="portal-page">
      <div v-if="cargando" class="module-panel">
        <div class="module-panel-body module-empty">
          <span class="loading-mini"><Loader2 :size="14" class="spin" /> Cargando…</span>
        </div>
      </div>

      <template v-else>
        <!-- Mis mascotas -->
        <section class="module-panel">
          <header class="module-panel-head">
            <h2>
              <span class="head-icon"><PawPrint :size="14" /></span>
              Mis mascotas
              <span class="head-meta">{{ mascotas.length }}</span>
            </h2>
          </header>

          <div v-if="!mascotas.length" class="module-panel-body module-empty">
            <div class="empty-icon"><PawPrint :size="22" /></div>
            <h3>Sin mascotas registradas</h3>
            <p>Consulta en recepción para vincular tus mascotas a tu cuenta.</p>
          </div>

          <div v-else class="module-panel-body mascotas">
            <button
              v-for="m in mascotas"
              :key="m.id"
              :class="['mascota', mascotaSel?.id === m.id ? 'activa' : '']"
              @click="verHistorial(m)"
            >
              <div class="avatar-sm lg">
                <img v-if="m.foto_url" :src="m.foto_url" :alt="m.nombre" />
                <template v-else>{{ iniciales(m.nombre) }}</template>
              </div>
              <div class="grow">
                <strong>{{ m.nombre }}</strong>
                <small>{{ m.especie }}{{ m.raza ? ` · ${m.raza}` : "" }}</small>
                <small class="muted">{{ m.edad?.texto || "" }}</small>
              </div>
              <div class="stack text-right">
                <span v-if="m.vacunas_vencidas > 0" class="estado-pill danger">
                  {{ m.vacunas_vencidas }} vacuna(s) vencida(s)
                </span>
                <span v-else-if="m.proxima_vacuna" class="estado-pill info">
                  Refuerzo {{ fmtDate(m.proxima_vacuna) }}
                </span>
                <span v-if="m.proxima_cita" class="estado-pill ok">
                  Cita {{ fmtFechaHora(m.proxima_cita.fecha_hora) }}
                </span>
              </div>
            </button>
          </div>
        </section>

        <!-- Historial de la mascota elegida -->
        <section v-if="mascotaSel" class="module-panel">
          <header class="module-panel-head">
            <h2>
              <span class="head-icon"><ClipboardList :size="14" /></span>
              Historial de {{ mascotaSel.nombre }}
            </h2>
            <div class="module-panel-head-actions">
              <button class="btn" @click="mascotaSel = null">Cerrar</button>
            </div>
          </header>

          <div class="module-panel-body">
            <div v-if="(historial.tratamientos_activos ?? []).length" class="callout" style="margin-bottom: 16px">
              <Pill :size="15" />
              <span>
                Tratamiento en curso:
                {{ historial.tratamientos_activos.map((t) => `${t.medicamento} (${t.dosis})`).join(", ") }}
              </span>
            </div>

            <div class="section-title">Vacunas</div>
            <div v-if="!(historial.vacunas ?? []).length" class="muted" style="font-size: 12.5px; margin: 8px 0 16px">
              Sin vacunas registradas.
            </div>
            <div v-else class="tabla-wrap" style="margin: 8px 0 20px">
              <table>
                <thead><tr><th>Vacuna</th><th>Aplicación</th><th>Próximo refuerzo</th></tr></thead>
                <tbody>
                  <tr v-for="(v, i) in historial.vacunas" :key="i">
                    <td><strong>{{ v.nombre_vacuna }}</strong></td>
                    <td class="mono">{{ fmtDate(v.fecha_aplicacion) }}</td>
                    <td>
                      <span v-if="!v.proximo_refuerzo" class="muted">—</span>
                      <span v-else :class="['estado-pill', v.vencida ? 'danger' : 'ok']">
                        {{ fmtDate(v.proximo_refuerzo) }}
                      </span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div class="section-title">Atenciones</div>
            <div v-if="!(historial.eventos ?? []).length" class="muted" style="font-size: 12.5px; margin-top: 8px">
              Sin atenciones registradas.
            </div>
            <div v-else class="hc-timeline" style="margin-top: 12px">
              <div v-for="(e, i) in historial.eventos" :key="i" :class="['hc-evento', `tipo-${e.tipo_evento}`]">
                <div class="hc-fecha">{{ fmtFechaHora(e.fecha) }}</div>
                <div class="hc-titulo">{{ e.titulo }}</div>
                <div v-if="e.resumen" class="hc-resumen">{{ e.resumen }}</div>
                <div class="hc-meta">
                  <template v-if="e.veterinario">{{ e.veterinario }}</template>
                  <template v-if="e.sede"> · {{ e.sede }}</template>
                </div>
              </div>
            </div>
          </div>
        </section>

        <!-- Mis citas -->
        <section class="module-panel">
          <header class="module-panel-head">
            <h2>
              <span class="head-icon"><CalendarClock :size="14" /></span>
              Mis citas
              <span class="head-meta">{{ citas.length }}</span>
            </h2>
          </header>

          <div v-if="!citas.length" class="module-panel-body module-empty">
            <div class="empty-icon"><CalendarClock :size="22" /></div>
            <h3>Sin citas registradas</h3>
            <p>Comunícate con la clínica para agendar una atención.</p>
          </div>

          <div v-else class="module-panel-body tabla-wrap">
            <table>
              <thead><tr><th>Fecha</th><th>Mascota</th><th>Servicio</th><th>Veterinario</th><th>Sede</th><th>Estado</th></tr></thead>
              <tbody>
                <tr v-for="c in citas" :key="c.id">
                  <td class="mono">{{ fmtFechaHora(c.fecha_hora) }}</td>
                  <td><strong>{{ c.mascota }}</strong></td>
                  <td>{{ c.servicio || c.motivo || "—" }}</td>
                  <td class="muted">{{ c.veterinario || "Por asignar" }}</td>
                  <td class="muted">{{ c.sede }}</td>
                  <td>
                    <span :class="['estado-pill', toneCita(c.estado)]">
                      <span class="dot"></span>{{ capitalizar(c.estado) }}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <!-- Mis comprobantes -->
        <section class="module-panel">
          <header class="module-panel-head">
            <h2>
              <span class="head-icon"><Receipt :size="14" /></span>
              Mis comprobantes
              <span class="head-meta">{{ comprobantes.length }}</span>
            </h2>
          </header>

          <div v-if="!comprobantes.length" class="module-panel-body module-empty">
            <div class="empty-icon"><Receipt :size="22" /></div>
            <h3>Sin comprobantes</h3>
            <p>Aquí verás las boletas y facturas de las atenciones.</p>
          </div>

          <div v-else class="module-panel-body tabla-wrap">
            <table>
              <thead><tr><th>Comprobante</th><th>Fecha</th><th>Mascota</th><th class="num">Total</th><th class="num">Saldo</th><th>Estado</th></tr></thead>
              <tbody>
                <tr v-for="c in comprobantes" :key="c.id">
                  <td class="mono"><strong>{{ c.numero_completo }}</strong></td>
                  <td class="mono">{{ fmtDate(c.fecha_emision) }}</td>
                  <td>{{ c.mascota || "—" }}</td>
                  <td class="num mono">{{ fmtSoles(c.total) }}</td>
                  <td class="num mono">{{ fmtSoles(c.saldo_pendiente) }}</td>
                  <td>
                    <span :class="['estado-pill', c.estado_pago === 'pagado' ? 'ok' : 'warn']">
                      <span class="dot"></span>{{ capitalizar(c.estado_pago) }}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </template>
    </main>
  </div>
</template>

<script setup>
import { ref, onMounted } from "vue";
import { useRouter } from "vue-router";
import {
  PawPrint, LogOut, Loader2, ClipboardList, CalendarClock, Receipt, Pill,
} from "lucide-vue-next";
import { portalApi } from "../api/portal.api.js";
import { fmtSoles, fmtDate } from "../../../shared/components/ui/format.js";
import { fmtFechaHora, capitalizar, iniciales } from "../../../shared/components/ui/format.js";

const router = useRouter();
const cliente = ref(portalApi.cliente());
const mascotas = ref([]);
const citas = ref([]);
const comprobantes = ref([]);
const mascotaSel = ref(null);
const historial = ref({});
const cargando = ref(true);

function toneCita(e) {
  return {
    programada: "neutral", confirmada: "info", en_espera: "warn",
    en_atencion: "violet", completada: "ok", cancelada: "danger", no_asistio: "danger",
  }[e] || "neutral";
}

async function verHistorial(m) {
  if (mascotaSel.value?.id === m.id) { mascotaSel.value = null; return; }
  mascotaSel.value = m;
  const r = await portalApi.historial(m.id);
  historial.value = r.data ?? {};
}

function salir() {
  portalApi.logout();
  router.replace("/portal/login");
}

onMounted(async () => {
  try {
    const [ms, ct, cp] = await Promise.all([
      portalApi.misMascotas(),
      portalApi.misCitas(),
      portalApi.misComprobantes(),
    ]);
    mascotas.value = ms.data ?? [];
    citas.value = ct.data ?? [];
    comprobantes.value = cp.data ?? [];
  } finally {
    cargando.value = false;
  }
});
</script>

<style scoped>
.portal-shell { min-height: 100vh; background: var(--bg); }
.portal-topbar {
  display: flex; align-items: center; justify-content: space-between;
  padding: 12px 24px; background: var(--bg-elev);
  border-bottom: 1px solid var(--line);
}
.pt-brand { display: flex; align-items: center; gap: 11px; }
.pt-logo {
  width: 34px; height: 34px; border-radius: 9px;
  background: var(--emerald); color: #fff; display: grid; place-items: center;
}
.pt-nombre { font-size: 13.5px; font-weight: 600; color: var(--ink); }
.pt-sub { font-size: 11.5px; color: var(--ink-3); }

.portal-page {
  max-width: 1040px; margin: 0 auto; padding: 24px;
  display: flex; flex-direction: column; gap: 16px;
}

.mascotas { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 10px; padding: 14px; }
.mascota {
  display: flex; align-items: center; gap: 11px;
  padding: 12px; border-radius: 11px; cursor: pointer; text-align: left;
  background: var(--bg-elev); border: 1px solid var(--line);
}
.mascota:hover { box-shadow: var(--shadow-md); }
.mascota.activa { border-color: var(--emerald); background: var(--emerald-soft); }
.mascota strong { display: block; font-size: 13.5px; color: var(--ink); }
.mascota small { display: block; font-size: 11.5px; color: var(--ink-3); }
</style>
