<template>
  <div>
    <PageHeader
      eyebrow="Agenda"
      title="Sala de espera"
      subtitle="Quién está ahora en la clínica, por gravedad"
    >
      <template #actions>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="{ spin: cargando }" /> Actualizar
        </button>
        <router-link class="btn" to="/agenda"><Calendar :size="14" /> Agenda</router-link>
        <button v-if="puedeCrear" class="btn primary" @click="modalLlegada = true">
          <LogIn :size="14" /> Registrar llegada
        </button>
      </template>
    </PageHeader>

    <div v-if="error" class="callout danger" style="margin-bottom: 14px">
      <AlertCircle :size="15" /> <span>{{ error }}</span>
    </div>

    <!-- Lo que el mostrador mira de reojo cada rato -->
    <div class="kpis">
      <div class="kpi">
        <span class="k">En espera</span>
        <strong class="v">{{ meta.en_espera ?? 0 }}</strong>
      </div>
      <div class="kpi">
        <span class="k">En atención</span>
        <strong class="v">{{ meta.en_atencion ?? 0 }}</strong>
      </div>
      <div class="kpi" :class="{ alerta: (meta.urgentes ?? 0) > 0 }">
        <span class="k">Urgencias</span>
        <strong class="v">{{ meta.urgentes ?? 0 }}</strong>
      </div>
      <div class="kpi" :class="{ alerta: (meta.espera_max_min ?? 0) >= 30 }">
        <span class="k">Espera más larga</span>
        <strong class="v">{{ meta.espera_max_min ?? 0 }} min</strong>
      </div>
      <div class="kpi">
        <span class="k">Agendados hoy sin llegar</span>
        <strong class="v">{{ meta.agendados_hoy ?? 0 }}</strong>
      </div>
    </div>

    <section v-if="!cola.length" class="module-panel">
      <div class="module-panel-body module-empty">
        <p v-if="cargando">Cargando…</p>
        <p v-else>No hay nadie esperando. La sala está vacía.</p>
      </div>
    </section>

    <div v-else class="cola">
      <article v-for="(c, i) in cola" :key="c.id" :class="['ficha', `p-${c.prioridad}`]">
        <div class="turno">{{ c.estado === "en_atencion" ? "—" : i + 1 - enAtencionAntes(i) }}</div>

        <div class="cuerpo">
          <header>
            <strong class="nombre">{{ c.mascota }}</strong>
            <span class="muted">{{ c.especie }}<template v-if="c.edad?.texto"> · {{ c.edad.texto }}</template></span>
            <span :class="['pill', `p-${c.prioridad}`]">{{ capitalizar(c.prioridad) }}</span>
            <span v-if="c.estado === 'en_atencion'" class="pill atencion">En atención</span>
          </header>

          <div class="linea">
            <User :size="12" /> {{ c.cliente }}
            <template v-if="c.cliente_telefono"> · {{ c.cliente_telefono }}</template>
          </div>
          <div class="linea">
            <MessageSquare :size="12" /> {{ c.motivo || "Sin motivo indicado" }}
            <template v-if="c.servicio"> · {{ c.servicio }}</template>
          </div>
          <div class="linea">
            <Clock :size="12" />
            <span :class="{ 'espera-larga': c.espera_min >= 30 }">
              {{ c.espera_min }} min esperando
            </span>
            <template v-if="c.veterinario"> · {{ c.veterinario }}</template>
            <template v-else> · <em>sin veterinario asignado</em></template>
          </div>

          <div v-if="c.alergias || c.condiciones_cronicas" class="alerta-clinica compacta">
            <AlertTriangle :size="13" />
            <span>
              <template v-if="c.alergias"><b>Alergias:</b> {{ c.alergias }}</template>
              <template v-if="c.alergias && c.condiciones_cronicas"> · </template>
              <template v-if="c.condiciones_cronicas"><b>Crónico:</b> {{ c.condiciones_cronicas }}</template>
            </span>
          </div>
        </div>

        <div class="acciones">
          <router-link class="btn mini" :to="`/pacientes/${c.mascota_id}`">Ficha</router-link>

          <template v-if="puedeAtender">
            <button
              v-if="c.estado === 'en_espera'"
              class="btn mini primary"
              @click="pasar(c)"
            >
              Pasar a consulta
            </button>
            <router-link
              v-else-if="c.consulta_id"
              class="btn mini primary"
              :to="`/consultas/${c.consulta_id}`"
            >
              Abrir consulta
            </router-link>
            <button v-else class="btn mini primary" @click="pasar(c)">Abrir consulta</button>
          </template>

          <button v-if="puedeEditar && c.estado === 'en_espera'" class="btn mini" @click="noAsistio(c)">
            No espera
          </button>
        </div>
      </article>
    </div>

    <!-- ---------- Registrar llegada ---------- -->
    <div v-if="modalLlegada" class="modal-back" @click="modalLlegada = false">
      <div class="modal" @click.stop>
        <div class="m-head"><h3>Registrar llegada</h3></div>
        <div class="m-body">
          <div class="field">
            <label>¿Tenía cita?</label>
            <select v-model="llegada.cita_id">
              <option value="">No — atención sin cita</option>
              <option v-for="c in citasHoy" :key="c.id" :value="c.id">
                {{ fmtHora(c.fecha_hora) }} · {{ c.mascota }} · {{ c.cliente }}
              </option>
            </select>
          </div>

          <template v-if="!llegada.cita_id">
            <div class="field">
              <label>Paciente <span class="req">*</span></label>
              <select v-model="llegada.mascota_id">
                <option value="">Seleccionar…</option>
                <option v-for="m in mascotas" :key="m.id" :value="m.id">
                  {{ m.nombre }} — {{ m.propietario }}
                </option>
              </select>
              <small class="muted">
                ¿No está en la lista? Regístralo primero en Pacientes.
              </small>
            </div>
            <div class="field">
              <label>Motivo</label>
              <input v-model.trim="llegada.motivo" type="text" placeholder="Qué le pasa" />
            </div>
            <div class="field">
              <label>Veterinario</label>
              <select v-model="llegada.veterinario_id">
                <option value="">Asignar después</option>
                <option v-for="v in veterinarios" :key="v.id" :value="v.id">
                  {{ fmtNombreCorto(v) }}
                </option>
              </select>
            </div>
          </template>

          <div class="field">
            <label>Triaje</label>
            <select v-model="llegada.prioridad">
              <option value="normal">Normal — puede esperar</option>
              <option value="preferente">Preferente — gestante, cachorro, geronte</option>
              <option value="urgencia">Urgencia — atender pronto</option>
              <option value="emergencia">Emergencia — pasa primero</option>
            </select>
            <small class="muted">
              Sólo puede agravar la prioridad con la que venía la cita, nunca bajarla.
            </small>
          </div>
        </div>
        <div class="m-foot modal-actions">
          <button class="btn" @click="modalLlegada = false">Cancelar</button>
          <button class="btn primary" :disabled="!puedeGuardar || guardando" @click="guardarLlegada">
            {{ guardando ? "Registrando…" : "Registrar llegada" }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted, onUnmounted } from "vue";
import { useRouter } from "vue-router";
import {
  RefreshCw, Calendar, LogIn, AlertCircle, AlertTriangle, User, Clock, MessageSquare,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import { citasApi } from "../api/citas.api.js";
import { mascotasApi } from "../../mascotas/api/mascotas.api.js";
import { usersApi } from "../../users/api/users.api.js";
import { clinicoApi } from "../../clinico/api/clinico.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { notify } from "../../../shared/composables/useNotify.js";
import { capitalizar, fmtHora, fmtNombreCorto } from "../../../shared/components/ui/format.js";

const router = useRouter();
const { hasPermission } = useAuth();
const puedeCrear = computed(() => hasPermission("citas:crear"));
const puedeEditar = computed(() => hasPermission("citas:editar"));
const puedeAtender = computed(() => hasPermission("clinico:registrar"));

const cola = ref([]);
const meta = ref({});
const cargando = ref(false);
const guardando = ref(false);
const error = ref("");

const modalLlegada = ref(false);
const llegada = reactive({ cita_id: "", mascota_id: "", motivo: "", veterinario_id: "", prioridad: "normal" });
const mascotas = ref([]);
const veterinarios = ref([]);
const citasHoy = ref([]);

const puedeGuardar = computed(() => llegada.cita_id || llegada.mascota_id);

/**
 * Los que ya están en consulta no ocupan turno en la fila: el número que ve el
 * propietario es cuántos tiene delante esperando, no cuántos hay en total.
 */
function enAtencionAntes(i) {
  return cola.value.slice(0, i).filter((c) => c.estado === "en_atencion").length;
}

async function cargar() {
  cargando.value = true;
  error.value = "";
  try {
    const r = await citasApi.salaEspera();
    cola.value = r.data ?? [];
    meta.value = r.meta ?? {};
  } catch (e) {
    error.value = e.message;
  } finally {
    cargando.value = false;
  }
}

async function cargarApoyo() {
  // `hasta` es exclusivo en el SP y `estado` acepta un solo valor, así que se
  // pide el día completo sin filtrar estado y se descarta acá lo que ya pasó
  // por la sala.
  const hoy = new Date();
  const desde = new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate());
  const hasta = new Date(desde.getTime() + 86400000);
  const iso = (d) => d.toISOString();

  const [m, v, c] = await Promise.all([
    mascotasApi.listar({ pageSize: 200 }).catch(() => ({ data: [] })),
    usersApi.veterinarios().catch(() => ({ data: [] })),
    citasApi.listar({ desde: iso(desde), hasta: iso(hasta), pageSize: 100 })
      .catch(() => ({ data: [] })),
  ]);
  mascotas.value = m.data ?? [];
  veterinarios.value = v.data ?? [];
  citasHoy.value = (c.data ?? []).filter((x) =>
    ["programada", "confirmada"].includes(x.estado),
  );
}

async function guardarLlegada() {
  guardando.value = true;
  try {
    const p = { prioridad: llegada.prioridad };
    if (llegada.cita_id) p.cita_id = llegada.cita_id;
    else {
      p.mascota_id = llegada.mascota_id;
      if (llegada.motivo) p.motivo = llegada.motivo;
      if (llegada.veterinario_id) p.veterinario_id = llegada.veterinario_id;
    }
    await citasApi.registrarLlegada(p);
    notify.success("Llegada registrada");
    modalLlegada.value = false;
    Object.assign(llegada, { cita_id: "", mascota_id: "", motivo: "", veterinario_id: "", prioridad: "normal" });
    await Promise.all([cargar(), cargarApoyo()]);
  } catch (e) {
    notify.error("No se pudo registrar la llegada", e.message);
  } finally {
    guardando.value = false;
  }
}

/** Pasar a consulta: marca en atención y abre (o crea) la consulta. */
async function pasar(c) {
  try {
    await citasApi.cambiarEstado(c.id, "en_atencion");
    if (c.consulta_id) {
      router.push(`/consultas/${c.consulta_id}`);
      return;
    }
    const { data } = await clinicoApi.crearConsulta({
      mascota_id: c.mascota_id,
      cita_id: c.id,
      veterinario_id: c.veterinario_id || undefined,
      motivo: c.motivo || "Atención",
    });
    router.push(`/consultas/${data.id}`);
  } catch (e) {
    notify.error("No se pudo pasar a consulta", e.message);
    await cargar();
  }
}

async function noAsistio(c) {
  const motivo = await notify.prompt(`${c.mascota} se retiró`, {
    text: "Queda registrado en el historial de la cita.",
    defaultValue: "Se retiró sin ser atendido",
  });
  if (!motivo) return;
  try {
    await citasApi.cambiarEstado(c.id, "no_asistio", motivo);
    await cargar();
  } catch (e) {
    notify.error("No se pudo actualizar", e.message);
  }
}

// La sala cambia sola: alguien llega, alguien entra. Refrescar a mano cada vez
// sería lo primero que molesta de esta pantalla.
let timer = null;
onMounted(async () => {
  await Promise.all([cargar(), cargarApoyo()]);
  timer = setInterval(cargar, 30000);
});
onUnmounted(() => clearInterval(timer));
</script>

<style scoped>
.kpis {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  gap: 10px;
  margin-bottom: 16px;
}
.kpi {
  background: var(--bg-elev);
  border: 1px solid var(--line);
  border-radius: 11px;
  padding: 11px 13px;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.kpi .k { font-size: 11.5px; color: var(--ink-3) }
.kpi .v { font-size: 21px; font-weight: 700; color: var(--ink) }
.kpi.alerta { border-color: var(--red-line, #e6bcbc) }
.kpi.alerta .v { color: var(--red-ink, #a33) }

.cola { display: flex; flex-direction: column; gap: 10px }

.ficha {
  display: flex;
  gap: 13px;
  align-items: stretch;
  background: var(--bg-elev);
  border: 1px solid var(--line);
  border-left-width: 4px;
  border-radius: 11px;
  padding: 12px 14px;
}
/* El color del borde izquierdo es el triaje: se lee sin leer. */
.ficha.p-normal     { border-left-color: var(--line-strong) }
.ficha.p-preferente { border-left-color: #c8a227 }
.ficha.p-urgencia   { border-left-color: #d97706 }
.ficha.p-emergencia { border-left-color: #b91c1c }

.turno {
  flex: 0 0 38px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 19px;
  font-weight: 700;
  color: var(--ink-3);
}
.cuerpo { flex: 1; min-width: 0 }
.cuerpo header { display: flex; flex-wrap: wrap; gap: 7px; align-items: baseline; margin-bottom: 5px }
.nombre { font-size: 15px }
.linea {
  display: flex;
  align-items: center;
  gap: 5px;
  font-size: 12.5px;
  color: var(--ink-2);
  margin-bottom: 2px;
}
.espera-larga { color: var(--red-ink, #a33); font-weight: 600 }

.pill {
  font-size: 10.5px;
  font-weight: 600;
  padding: 1px 8px;
  border-radius: 999px;
  border: 1px solid var(--line-strong);
  color: var(--ink-3);
}
.pill.p-preferente { border-color: #e2cc86; color: #8a6d0b; background: #fdf6e0 }
.pill.p-urgencia   { border-color: #e8c08a; color: #9a5b06; background: #fdf1e2 }
.pill.p-emergencia { border-color: #e0a8a8; color: #a31c1c; background: #fdeeee }
.pill.atencion     { border-color: #a8c8e0; color: #1c5ca3; background: #eef5fd }

.alerta-clinica.compacta {
  display: flex;
  gap: 6px;
  align-items: flex-start;
  font-size: 11.5px;
  margin-top: 5px;
  padding: 5px 8px;
}

.acciones { display: flex; flex-direction: column; gap: 6px; justify-content: center }
.acciones .btn { white-space: nowrap }

@media (max-width: 720px) {
  .ficha { flex-wrap: wrap }
  .acciones { flex-direction: row; width: 100%; flex-wrap: wrap }
}
</style>
