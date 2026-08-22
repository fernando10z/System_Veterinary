<template>
  <div class="modal-back" @click="$emit('close')">
    <div class="modal modal-wide" @click.stop>
      <div class="m-head">
        <h3>{{ cita?.mascota || "Cita" }} <span class="mono muted">{{ cita?.codigo }}</span></h3>
      </div>

      <div v-if="cargando" class="m-body">
        <span class="loading-mini"><Loader2 :size="14" class="spin" /> Cargando…</span>
      </div>

      <div v-else-if="cita" class="m-body">
        <div v-if="error" class="callout danger" style="margin-bottom: 14px">
          <AlertCircle :size="15" /> <span>{{ error }}</span>
        </div>

        <!-- Alertas clínicas primero: es lo que no se puede pasar por alto -->
        <div v-if="cita.alergias || cita.condiciones_cronicas" class="alerta-clinica" style="margin-bottom: 14px">
          <AlertTriangle :size="16" />
          <div>
            <strong>Atención</strong>
            <div v-if="cita.alergias">Alergias: {{ cita.alergias }}</div>
            <div v-if="cita.condiciones_cronicas">Crónico: {{ cita.condiciones_cronicas }}</div>
          </div>
        </div>

        <div class="detalle-grid">
          <div class="detalle-item">
            <div class="k">Fecha y hora</div>
            <div class="v">{{ fmtFechaHora(cita.fecha_hora) }} · {{ cita.duracion_min }}′</div>
          </div>
          <div class="detalle-item">
            <div class="k">Estado</div>
            <div class="v">
              <span :class="['estado-pill', tone(cita.estado)]">
                <span class="dot"></span>{{ capitalizar(cita.estado) }}
              </span>
            </div>
          </div>
          <div class="detalle-item">
            <div class="k">Paciente</div>
            <div class="v">
              <router-link :to="`/pacientes/${cita.mascota_id}`" @click="$emit('close')">
                {{ cita.mascota }}
              </router-link>
              <span class="muted"> · {{ cita.especie }}{{ cita.raza ? ` · ${cita.raza}` : "" }}</span>
            </div>
          </div>
          <div class="detalle-item">
            <div class="k">Edad / peso</div>
            <div class="v">{{ cita.edad?.texto || "—" }} · {{ cita.peso_kg ? cita.peso_kg + " kg" : "—" }}</div>
          </div>
          <div class="detalle-item">
            <div class="k">Propietario</div>
            <div class="v">{{ cita.cliente }}</div>
          </div>
          <div class="detalle-item">
            <div class="k">Contacto</div>
            <div class="v mono">{{ cita.cliente_telefono || "—" }}</div>
          </div>
          <div class="detalle-item">
            <div class="k">Veterinario</div>
            <div class="v">{{ cita.veterinario || "Sin asignar" }}</div>
          </div>
          <div class="detalle-item">
            <div class="k">Servicio</div>
            <div class="v">{{ cita.servicio || "—" }}</div>
          </div>
          <div class="detalle-item" style="grid-column: 1 / -1">
            <div class="k">Motivo</div>
            <div class="v">{{ cita.motivo || "—" }}</div>
          </div>
        </div>

        <!-- Recorrido de la cita -->
        <div v-if="cita.historial?.length" class="section-title" style="margin-top: 18px">Historial</div>
        <div v-if="cita.historial?.length" class="hc-timeline" style="margin-top: 8px">
          <div v-for="(h, i) in cita.historial" :key="i" class="hc-evento">
            <div class="hc-fecha">{{ fmtFechaHora(h.created_at) }}</div>
            <div class="hc-titulo">{{ capitalizar(h.accion) }}</div>
            <div v-if="h.motivo" class="hc-resumen">{{ h.motivo }}</div>
            <div v-if="h.usuario" class="hc-meta">{{ h.usuario }}</div>
          </div>
        </div>
      </div>

      <div class="m-foot modal-actions">
        <button class="btn" @click="$emit('close')">Cerrar</button>

        <button
          v-if="cita && !['completada', 'cancelada'].includes(cita.estado)"
          class="btn danger"
          @click="cancelar"
        >
          Cancelar cita
        </button>

        <router-link
          v-if="cita?.consulta_id"
          class="btn"
          :to="`/consultas/${cita.consulta_id}`"
          @click="$emit('close')"
        >
          Ver consulta
        </router-link>

        <button
          v-else-if="cita && puedeAtender && ['en_espera', 'en_atencion', 'confirmada'].includes(cita.estado)"
          class="btn primary"
          @click="atender"
        >
          <Stethoscope :size="14" /> Atender
        </button>

        <button
          v-if="cita && siguiente"
          class="btn primary"
          @click="avanzar"
        >
          {{ siguiente.label }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from "vue";
import { useRouter } from "vue-router";
import { Loader2, AlertCircle, AlertTriangle, Stethoscope } from "lucide-vue-next";
import { citasApi } from "../api/citas.api.js";
import { clinicoApi } from "../../clinico/api/clinico.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { fmtFechaHora, capitalizar } from "../../../shared/components/ui/format.js";
import { notify } from "../../../shared/composables/useNotify.js";

const props = defineProps({ citaId: { type: String, required: true } });
const emit = defineEmits(["close", "cambiado"]);

const router = useRouter();
const { hasPermission } = useAuth();
const puedeAtender = computed(() => hasPermission("clinico:registrar"));

const cita = ref(null);
const cargando = ref(true);
const error = ref("");

const siguiente = computed(() => {
  const map = {
    programada: { estado: "confirmada", label: "Confirmar" },
    confirmada: { estado: "en_espera", label: "Marcar llegada" },
    en_espera: { estado: "en_atencion", label: "Pasar a consultorio" },
  };
  return cita.value ? map[cita.value.estado] : null;
});

function tone(estado) {
  return {
    programada: "neutral", confirmada: "info", en_espera: "warn",
    en_atencion: "violet", completada: "ok", cancelada: "danger", no_asistio: "danger",
  }[estado] || "neutral";
}

async function cargar() {
  cargando.value = true;
  try {
    const r = await citasApi.obtener(props.citaId);
    cita.value = r.data;
  } catch (e) {
    error.value = e.message;
  } finally {
    cargando.value = false;
  }
}

async function avanzar() {
  try {
    await citasApi.cambiarEstado(props.citaId, siguiente.value.estado);
    await cargar();
    emit("cambiado");
  } catch (e) {
    error.value = e.message;
  }
}

async function cancelar() {
  const motivo = await notify.prompt("¿Por qué se cancela la cita?", {
    placeholder: "Motivo de la cancelación",
  });
  if (!motivo) return;
  try {
    await citasApi.cambiarEstado(props.citaId, "cancelada", motivo);
    emit("cambiado");
    emit("close");
  } catch (e) {
    error.value = e.message;
  }
}

/** Abre la consulta ligada a la cita; si no existe, la crea en borrador. */
async function atender() {
  try {
    if (cita.value.estado !== "en_atencion") {
      await citasApi.cambiarEstado(props.citaId, "en_atencion");
    }
    const r = await clinicoApi.crearConsulta({
      mascota_id: cita.value.mascota_id,
      cita_id: props.citaId,
      motivo: cita.value.motivo || "Atención en consultorio",
    });
    emit("cambiado");
    emit("close");
    router.push(`/consultas/${r.data.id}`);
  } catch (e) {
    error.value = e.message;
  }
}

onMounted(cargar);
</script>
