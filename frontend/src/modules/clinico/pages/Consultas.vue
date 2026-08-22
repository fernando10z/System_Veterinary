<template>
  <div>
    <PageHeader
      eyebrow="Historia clínica"
      title="Consultas"
      :subtitle="meta.total ? `${meta.total} consultas en el periodo` : 'Registro de atenciones médicas'"
    >
      <template #actions>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="cargando ? 'spin' : ''" /> Actualizar
        </button>
      </template>
    </PageHeader>

    <section class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><Stethoscope :size="14" /></span>
          Atenciones
          <span class="head-meta">{{ meta.total ?? consultas.length }}</span>
        </h2>
      </header>

      <div class="module-panel-toolbar">
        <div class="fil">
          <CalendarRange :size="14" />
          <input v-model="filtros.desde" type="date" @change="recargar" />
        </div>
        <div class="fil">
          <span class="muted">a</span>
          <input v-model="filtros.hasta" type="date" @change="recargar" />
        </div>
        <div class="fil">
          <Stethoscope :size="14" />
          <select v-model="filtros.veterinarioId" @change="recargar">
            <option value="">Todos los veterinarios</option>
            <option v-for="v in veterinarios" :key="v.id" :value="v.id">
              {{ v.nombres }} {{ v.apellido_paterno }}
            </option>
          </select>
        </div>
        <div class="fil">
          <Filter :size="14" />
          <select v-model="filtros.estado" @change="recargar">
            <option value="">Todos los estados</option>
            <option value="borrador">En borrador</option>
            <option value="cerrada">Cerradas</option>
          </select>
        </div>
        <div class="toolbar-spacer"></div>
        <span v-if="cargando" class="loading-mini"><Loader2 :size="13" class="spin" /> Cargando…</span>
      </div>

      <div v-if="!cargando && !consultas.length" class="module-panel-body module-empty">
        <div class="empty-icon"><Stethoscope :size="22" /></div>
        <h3>Sin consultas en el periodo</h3>
        <p>Ajusta el rango de fechas o registra una atención desde la agenda.</p>
      </div>

      <div v-else class="module-panel-body tabla-wrap">
        <table>
          <thead>
            <tr>
              <th>Fecha</th>
              <th>Paciente</th>
              <th>Propietario</th>
              <th>Motivo</th>
              <th>Diagnóstico</th>
              <th>Veterinario</th>
              <th>Estado</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="c in consultas"
              :key="c.id"
              class="clickable"
              @click="$router.push(`/consultas/${c.id}`)"
            >
              <td class="mono">{{ fmtFechaHora(c.fecha) }}</td>
              <td>
                <div class="entidad-cell">
                  <div class="avatar-sm">
                    <img v-if="c.mascota_foto" :src="c.mascota_foto" :alt="c.mascota" />
                    <template v-else>{{ iniciales(c.mascota) }}</template>
                  </div>
                  <div class="info">
                    <strong>{{ c.mascota }}</strong>
                    <small>{{ c.especie }}</small>
                  </div>
                </div>
              </td>
              <td>{{ c.cliente }}</td>
              <td class="truncado">{{ c.motivo }}</td>
              <td class="truncado">{{ c.diagnostico || "—" }}</td>
              <td>{{ c.veterinario || "—" }}</td>
              <td>
                <span :class="['estado-pill', c.estado === 'cerrada' ? 'ok' : 'warn']">
                  <span class="dot"></span>{{ c.estado === "cerrada" ? "Cerrada" : "Borrador" }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div v-if="meta.pages > 1" class="module-panel-foot">
        <span class="muted">Página {{ meta.page }} de {{ meta.pages }}</span>
        <div class="wrap-actions">
          <button class="btn" :disabled="meta.page <= 1" @click="irPagina(meta.page - 1)">Anterior</button>
          <button class="btn" :disabled="meta.page >= meta.pages" @click="irPagina(meta.page + 1)">Siguiente</button>
        </div>
      </div>
    </section>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted } from "vue";
import { Stethoscope, RefreshCw, Loader2, Filter, CalendarRange } from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import { clinicoApi } from "../api/clinico.api.js";
import { usersApi } from "../../users/api/users.api.js";
import { fmtFechaHora, iniciales } from "../../../shared/components/ui/format.js";

const consultas = ref([]);
const veterinarios = ref([]);
const meta = ref({});
const cargando = ref(false);

const hoy = new Date();
const inicioMes = new Date(hoy.getFullYear(), hoy.getMonth(), 1);
const filtros = reactive({
  desde: inicioMes.toISOString().slice(0, 10),
  hasta: hoy.toISOString().slice(0, 10),
  veterinarioId: "",
  estado: "",
  page: 1,
});

function recargar() { filtros.page = 1; cargar(); }
function irPagina(p) { filtros.page = p; cargar(); }

async function cargar() {
  cargando.value = true;
  try {
    // `hasta` es exclusivo en el SP: se suma un día para incluir el día elegido.
    const hastaExcl = new Date(filtros.hasta);
    hastaExcl.setDate(hastaExcl.getDate() + 1);
    const r = await clinicoApi.consultas({
      desde: filtros.desde,
      hasta: hastaExcl.toISOString().slice(0, 10),
      veterinarioId: filtros.veterinarioId || undefined,
      estado: filtros.estado || undefined,
      page: filtros.page,
      pageSize: 25,
    });
    consultas.value = r.data ?? [];
    meta.value = r.meta ?? {};
  } finally {
    cargando.value = false;
  }
}

onMounted(async () => {
  try {
    const v = await usersApi.veterinarios();
    veterinarios.value = v.data ?? [];
  } catch {
    // El filtro por veterinario es accesorio.
  }
  cargar();
});
</script>

<style scoped>
.truncado { max-width: 240px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
</style>
