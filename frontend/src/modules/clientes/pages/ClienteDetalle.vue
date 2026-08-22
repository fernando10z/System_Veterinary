<template>
  <div>
    <div v-if="cargando" class="module-panel">
      <div class="module-panel-body module-empty">
        <span class="loading-mini"><Loader2 :size="14" class="spin" /> Cargando ficha…</span>
      </div>
    </div>

    <template v-else-if="c">
      <PageHeader
        :eyebrow="`Propietario · ${c.codigo || 'sin código'}`"
        :title="c.nombre_completo"
        :subtitle="`${c.tipo_documento} ${c.numero_documento}${c.telefono ? ' · ' + c.telefono : ''}`"
      >
        <template #actions>
          <button class="btn" @click="$router.back()"><ArrowLeft :size="14" /> Volver</button>
          <button v-if="puedeEditar" class="btn" @click="modalEditar = true">
            <Pencil :size="14" /> Editar
          </button>
          <button v-if="puedeEditar" class="btn" @click="modalPortal = true">
            <Globe :size="14" /> {{ c.portal_acceso ? "Reiniciar portal" : "Activar portal" }}
          </button>
          <button v-if="puedeCrearMascota" class="btn primary" @click="modalMascota = true">
            <Plus :size="14" /> Nueva mascota
          </button>
        </template>
      </PageHeader>

      <div class="stat-row">
        <div class="stat">
          <div class="stat-label">Mascotas <span class="icon-tile"><PawPrint :size="14" /></span></div>
          <div class="stat-val">{{ (c.mascotas ?? []).length }}<span class="unit">registradas</span></div>
          <div class="stat-meta">{{ activas }} activas</div>
        </div>
        <div class="stat">
          <div class="stat-label">Facturado histórico <span class="icon-tile"><Receipt :size="14" /></span></div>
          <div class="stat-val">{{ fmtSoles(c.facturado_historico) }}</div>
          <div class="stat-meta">acumulado en la empresa</div>
        </div>
        <div class="stat">
          <div class="stat-label">Deuda pendiente <span class="icon-tile amber"><CreditCard :size="14" /></span></div>
          <div class="stat-val">{{ fmtSoles(c.deuda_pendiente) }}</div>
          <div class="stat-meta">
            <span :class="['trend', Number(c.deuda_pendiente) > 0 ? 'flat' : '']">
              {{ Number(c.deuda_pendiente) > 0 ? "requiere cobro" : "al día" }}
            </span>
          </div>
        </div>
        <div class="stat">
          <div class="stat-label">Crédito <span class="icon-tile violet"><Landmark :size="14" /></span></div>
          <div class="stat-val">{{ fmtSoles(c.linea_credito) }}</div>
          <div class="stat-meta">{{ c.dias_credito }} días de plazo</div>
        </div>
      </div>

      <div class="det-grid">
        <div class="col">
          <!-- Mascotas -->
          <section class="module-panel">
            <header class="module-panel-head">
              <h2>
                <span class="head-icon"><PawPrint :size="14" /></span>
                Mascotas
                <span class="head-meta">{{ (c.mascotas ?? []).length }}</span>
              </h2>
            </header>

            <div v-if="!(c.mascotas ?? []).length" class="module-panel-body module-empty">
              <div class="empty-icon"><PawPrint :size="22" /></div>
              <h3>Sin mascotas registradas</h3>
              <p>Registra la primera mascota de este propietario.</p>
              <button v-if="puedeCrearMascota" class="btn primary" style="margin-top: 6px" @click="modalMascota = true">
                <Plus :size="14" /> Nueva mascota
              </button>
            </div>

            <div v-else class="module-panel-body mascotas-grid">
              <router-link
                v-for="m in c.mascotas"
                :key="m.id"
                :to="`/pacientes/${m.id}`"
                class="mascota-card"
              >
                <div class="avatar-sm lg">
                  <img v-if="m.foto_url" :src="m.foto_url" :alt="m.nombre" />
                  <template v-else>{{ iniciales(m.nombre) }}</template>
                </div>
                <div class="grow">
                  <strong>
                    {{ m.nombre }}
                    <AlertTriangle v-if="m.alergias" :size="12" class="alerta-icono" :title="m.alergias" />
                  </strong>
                  <small>{{ m.especie }}{{ m.raza ? ` · ${m.raza}` : "" }}</small>
                  <small class="muted">{{ m.edad?.texto || "edad no registrada" }}</small>
                </div>
                <span :class="['estado-pill', m.estado === 'activo' ? 'ok' : 'neutral']">
                  <span class="dot"></span>{{ capitalizar(m.estado) }}
                </span>
              </router-link>
            </div>
          </section>

          <!-- Últimas citas -->
          <section class="module-panel">
            <header class="module-panel-head">
              <h2><span class="head-icon"><CalendarClock :size="14" /></span> Últimas citas</h2>
            </header>

            <div v-if="!(c.ultimas_citas ?? []).length" class="module-panel-body module-empty">
              <div class="empty-icon"><CalendarClock :size="22" /></div>
              <h3>Sin historial de citas</h3>
              <p>Cuando se agende una atención aparecerá aquí.</p>
            </div>

            <div v-else class="module-panel-body tabla-wrap">
              <table>
                <thead>
                  <tr><th>Fecha</th><th>Mascota</th><th>Servicio</th><th>Motivo</th><th>Estado</th></tr>
                </thead>
                <tbody>
                  <tr v-for="ci in c.ultimas_citas" :key="ci.id">
                    <td class="mono">{{ fmtFechaHora(ci.fecha_hora) }}</td>
                    <td><strong>{{ ci.mascota }}</strong></td>
                    <td>{{ ci.servicio || "—" }}</td>
                    <td class="muted">{{ ci.motivo || "—" }}</td>
                    <td>
                      <span :class="['estado-pill', toneCita(ci.estado)]">
                        <span class="dot"></span>{{ capitalizar(ci.estado) }}
                      </span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        </div>

        <div class="col">
          <!-- Datos de contacto -->
          <section class="module-panel">
            <header class="module-panel-head">
              <h2><span class="head-icon"><User :size="14" /></span> Datos</h2>
            </header>
            <div class="module-panel-body">
              <div class="detalle-grid">
                <div class="detalle-item"><div class="k">Documento</div><div class="v mono">{{ c.tipo_documento }} {{ c.numero_documento }}</div></div>
                <div class="detalle-item"><div class="k">Teléfono</div><div class="v mono">{{ c.telefono || "—" }}</div></div>
                <div class="detalle-item"><div class="k">Alterno</div><div class="v mono">{{ c.telefono_alterno || "—" }}</div></div>
                <div class="detalle-item"><div class="k">Correo</div><div class="v">{{ c.correo || "—" }}</div></div>
                <div class="detalle-item" style="grid-column: 1 / -1"><div class="k">Dirección</div><div class="v">{{ c.direccion || "—" }}</div></div>
                <div class="detalle-item"><div class="k">Portal</div>
                  <div class="v">
                    <span :class="['estado-pill', c.portal_acceso ? 'ok' : 'neutral']">
                      <span class="dot"></span>{{ c.portal_acceso ? "Activo" : "Sin acceso" }}
                    </span>
                  </div>
                </div>
                <div class="detalle-item"><div class="k">Marketing</div><div class="v">{{ c.acepta_marketing ? "Acepta" : "No acepta" }}</div></div>
              </div>
              <div v-if="c.observaciones" style="margin-top: 14px">
                <div class="section-title">Observaciones</div>
                <p class="muted" style="font-size: 12.5px; margin: 6px 0 0">{{ c.observaciones }}</p>
              </div>
            </div>
          </section>

          <!-- Seguimiento -->
          <section class="module-panel">
            <header class="module-panel-head">
              <h2><span class="head-icon"><MessageSquare :size="14" /></span> Seguimiento</h2>
              <div class="module-panel-head-actions">
                <button class="btn" @click="modalComunicacion = true"><Plus :size="13" /> Registrar</button>
              </div>
            </header>

            <div v-if="!comunicaciones.length" class="module-panel-body module-empty">
              <div class="empty-icon"><MessageSquare :size="22" /></div>
              <h3>Sin contactos registrados</h3>
              <p>Deja constancia de llamadas y mensajes al propietario.</p>
            </div>

            <div v-else class="module-panel-body">
              <div class="hc-timeline">
                <div v-for="m in comunicaciones" :key="m.id" class="hc-evento tipo-nota">
                  <div class="hc-fecha">{{ fmtFechaHora(m.fecha) }}</div>
                  <div class="hc-titulo">{{ m.asunto || capitalizar(m.tipo) }}</div>
                  <div class="hc-resumen">{{ m.mensaje }}</div>
                  <div class="hc-meta">
                    <span class="tag">{{ capitalizar(m.tipo) }}</span>
                    <template v-if="m.registrado_por"> · {{ m.registrado_por }}</template>
                  </div>
                </div>
              </div>
            </div>
          </section>
        </div>
      </div>

      <ClienteModal v-if="modalEditar" :cliente="c" @close="modalEditar = false" @guardado="onGuardado" />

      <PacienteModal
        v-if="modalMascota"
        :especies="especies"
        :cliente-preseleccionado="{ id: c.id, nombre_completo: c.nombre_completo, numero_documento: c.numero_documento }"
        @close="modalMascota = false"
        @guardado="onGuardado"
      />

      <!-- Activar / reiniciar portal -->
      <div v-if="modalPortal" class="modal-back" @click="modalPortal = false">
        <div class="modal" @click.stop>
          <div class="m-head"><h3>{{ c.portal_acceso ? "Reiniciar acceso al portal" : "Activar portal" }}</h3></div>
          <div class="m-body">
            <div v-if="errorPortal" class="callout danger" style="margin-bottom: 12px">
              <AlertCircle :size="15" /> <span>{{ errorPortal }}</span>
            </div>
            <p class="muted" style="margin-top: 0">
              El propietario ingresará al portal con su documento
              (<span class="mono">{{ c.numero_documento }}</span>) o su correo y la contraseña
              que definas aquí. Podrá ver sus mascotas, citas, historial y comprobantes.
            </p>
            <div class="field">
              <label>Contraseña del portal</label>
              <input v-model="passwordPortal" type="text" placeholder="Mínimo 8 caracteres" />
            </div>
          </div>
          <div class="m-foot modal-actions">
            <button class="btn" @click="modalPortal = false">Cancelar</button>
            <button class="btn primary" :disabled="guardandoPortal" @click="activarPortal">
              {{ guardandoPortal ? "Guardando…" : "Guardar" }}
            </button>
          </div>
        </div>
      </div>

      <!-- Registrar comunicación -->
      <div v-if="modalComunicacion" class="modal-back" @click="modalComunicacion = false">
        <div class="modal" @click.stop>
          <div class="m-head"><h3>Registrar contacto</h3></div>
          <div class="m-body">
            <div class="form-grid">
              <div class="field">
                <label>Tipo</label>
                <select v-model="com.tipo">
                  <option value="llamada">Llamada</option>
                  <option value="whatsapp">WhatsApp</option>
                  <option value="correo">Correo</option>
                  <option value="sms">SMS</option>
                  <option value="presencial">Presencial</option>
                  <option value="otro">Otro</option>
                </select>
              </div>
              <div class="field">
                <label>Mascota (opcional)</label>
                <select v-model="com.mascota_id">
                  <option value="">Ninguna en particular</option>
                  <option v-for="m in c.mascotas" :key="m.id" :value="m.id">{{ m.nombre }}</option>
                </select>
              </div>
              <div class="field" style="grid-column: 1 / -1">
                <label>Asunto</label>
                <input v-model.trim="com.asunto" type="text" />
              </div>
              <div class="field" style="grid-column: 1 / -1">
                <label>Detalle <span class="req">*</span></label>
                <textarea v-model="com.mensaje" rows="3"></textarea>
              </div>
            </div>
          </div>
          <div class="m-foot modal-actions">
            <button class="btn" @click="modalComunicacion = false">Cancelar</button>
            <button class="btn primary" :disabled="guardandoCom" @click="registrarComunicacion">
              {{ guardandoCom ? "Guardando…" : "Registrar" }}
            </button>
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
  Loader2, ArrowLeft, Pencil, Plus, PawPrint, Receipt, CreditCard, Landmark,
  CalendarClock, User, MessageSquare, Globe, AlertCircle, AlertTriangle,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import ClienteModal from "../components/ClienteModal.vue";
import PacienteModal from "../../mascotas/components/PacienteModal.vue";
import { clientesApi } from "../api/clientes.api.js";
import { catalogosApi } from "../../catalogos/api/catalogos.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { fmtSoles } from "../../../shared/components/ui/format.js";
import { fmtFechaHora, capitalizar, iniciales } from "../../../shared/components/ui/format.js";

const route = useRoute();
const { hasPermission } = useAuth();
const puedeEditar = computed(() => hasPermission("clientes:editar"));
const puedeCrearMascota = computed(() => hasPermission("mascotas:crear"));

const c = ref(null);
const comunicaciones = ref([]);
const especies = ref([]);
const cargando = ref(true);

const modalEditar = ref(false);
const modalMascota = ref(false);
const modalPortal = ref(false);
const modalComunicacion = ref(false);

const passwordPortal = ref("");
const guardandoPortal = ref(false);
const errorPortal = ref("");

const com = reactive({ tipo: "llamada", mascota_id: "", asunto: "", mensaje: "" });
const guardandoCom = ref(false);

const activas = computed(() => (c.value?.mascotas ?? []).filter((m) => m.estado === "activo").length);

function toneCita(estado) {
  return {
    programada: "neutral", confirmada: "info", en_espera: "warn",
    en_atencion: "violet", completada: "ok", cancelada: "danger", no_asistio: "danger",
  }[estado] || "neutral";
}

async function cargar() {
  cargando.value = true;
  try {
    const [ficha, coms] = await Promise.all([
      clientesApi.obtener(route.params.id),
      clientesApi.comunicaciones({ clienteId: route.params.id, limit: 30 }),
    ]);
    c.value = ficha.data;
    comunicaciones.value = coms.data ?? [];
  } finally {
    cargando.value = false;
  }
}

function onGuardado() {
  modalEditar.value = false;
  modalMascota.value = false;
  cargar();
}

async function activarPortal() {
  errorPortal.value = "";
  if (passwordPortal.value.length < 8) {
    errorPortal.value = "La contraseña debe tener al menos 8 caracteres.";
    return;
  }
  guardandoPortal.value = true;
  try {
    await clientesApi.activarPortal(c.value.id, passwordPortal.value);
    modalPortal.value = false;
    passwordPortal.value = "";
    cargar();
  } catch (e) {
    errorPortal.value = e.message;
  } finally {
    guardandoPortal.value = false;
  }
}

async function registrarComunicacion() {
  if (!com.mensaje.trim()) return;
  guardandoCom.value = true;
  try {
    await clientesApi.registrarComunicacion({
      cliente_id: c.value.id,
      mascota_id: com.mascota_id || undefined,
      tipo: com.tipo,
      asunto: com.asunto || undefined,
      mensaje: com.mensaje,
    });
    modalComunicacion.value = false;
    com.asunto = "";
    com.mensaje = "";
    cargar();
  } finally {
    guardandoCom.value = false;
  }
}

onMounted(async () => {
  try {
    const e = await catalogosApi.especies();
    especies.value = e.data ?? [];
  } catch {
    // El catálogo solo hace falta para registrar mascotas.
  }
  cargar();
});

watch(() => route.params.id, cargar);
</script>

<style scoped>
.det-grid { display: grid; grid-template-columns: 1.35fr 1fr; gap: 16px; align-items: start; }
@media (max-width: 1050px) { .det-grid { grid-template-columns: 1fr; } }
.col { display: flex; flex-direction: column; gap: 16px; }

.mascotas-grid {
  display: grid; grid-template-columns: repeat(auto-fill, minmax(230px, 1fr));
  gap: 10px; padding: 14px;
}
.mascota-card {
  display: flex; align-items: center; gap: 11px;
  padding: 11px 12px; border-radius: 11px; text-decoration: none;
  background: var(--bg-elev); border: 1px solid var(--line);
  transition: transform 0.15s ease, box-shadow 0.15s ease;
}
.mascota-card:hover { transform: translateY(-1px); box-shadow: var(--shadow-md); }
.mascota-card strong { display: block; font-size: 13.5px; color: var(--ink); }
.mascota-card small { display: block; font-size: 11.5px; color: var(--ink-3); }
.alerta-icono { color: var(--red); vertical-align: -1px; }
.req { color: var(--red); }
</style>
