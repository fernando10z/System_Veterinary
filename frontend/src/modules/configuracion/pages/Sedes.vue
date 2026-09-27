<template>
  <div>
    <PageHeader
      eyebrow="Configuración"
      title="Sedes"
      subtitle="Los locales de la clínica: agenda, stock y caja propios; una sola cartera de pacientes"
    >
      <template #actions>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="{ spin: cargando }" /> Actualizar
        </button>
        <button v-if="puedeConfigurar" class="btn primary" @click="abrir()">
          <Plus :size="14" /> Nueva sede
        </button>
      </template>
    </PageHeader>

    <div v-if="error" class="callout danger" style="margin-bottom: 14px">
      <AlertCircle :size="15" /> <span>{{ error }}</span>
    </div>

    <div class="callout" style="margin-bottom: 14px">
      <Info :size="15" />
      <span>
        Los propietarios, la historia clínica, el catálogo y el personal son de la
        empresa y los comparten todos los locales. Lo que ocupa espacio —agenda,
        consultorios, stock, caja y horario— es de cada sede.
      </span>
    </div>

    <div class="cards">
      <article v-for="s in sedes" :key="s.id" class="sede" :class="{ inactiva: s.estado !== 'activo' }">
        <header>
          <div>
            <strong>{{ s.nombre }}</strong>
            <span class="codigo">{{ s.codigo }}</span>
          </div>
          <span v-if="s.es_principal" class="pill principal">Principal</span>
          <span v-else-if="s.estado !== 'activo'" class="pill">Inactiva</span>
        </header>

        <div v-if="s.direccion" class="linea"><MapPin :size="12" /> {{ s.direccion }}</div>
        <div v-if="s.distrito" class="linea muted">
          {{ [s.distrito, s.provincia, s.departamento].filter(Boolean).join(", ") }}
        </div>
        <div v-if="s.telefono" class="linea"><Phone :size="12" /> {{ s.telefono }}</div>
        <div v-if="s.serie_boleta || s.serie_factura" class="linea">
          <Receipt :size="12" /> Series: {{ [s.serie_boleta, s.serie_factura].filter(Boolean).join(" · ") }}
        </div>

        <div class="meta">
          <span><Users :size="12" /> {{ s.personal }} en plantilla</span>
          <span><DoorOpen :size="12" /> {{ s.consultorios }} consultorio(s)</span>
          <span><CalendarClock :size="12" /> {{ s.citas_hoy }} cita(s) hoy</span>
        </div>

        <footer v-if="puedeConfigurar">
          <button class="btn" @click="abrir(s)"><Pencil :size="13" /> Editar</button>
          <button v-if="!s.es_principal" class="btn" @click="borrar(s)">
            <Trash2 :size="13" /> Dar de baja
          </button>
        </footer>
      </article>

      <p v-if="!sedes.length && !cargando" class="vacio">
        No hay sedes registradas.
      </p>
    </div>

    <div v-if="modal" class="modal-back" @click="modal = null">
      <div class="modal modal-wide" @click.stop>
        <div class="m-head"><h3>{{ modal.id ? "Editar sede" : "Nueva sede" }}</h3></div>
        <div class="m-body">
          <div class="form-grid">
            <div class="field" style="grid-column: 1 / -1">
              <label>Nombre <span class="req">*</span></label>
              <input v-model="modal.nombre" placeholder="Sede Surco" />
            </div>
            <div class="field" style="grid-column: 1 / -1">
              <label>Dirección</label>
              <input v-model="modal.direccion" />
            </div>
            <div class="field"><label>Distrito</label><input v-model="modal.distrito" /></div>
            <div class="field"><label>Provincia</label><input v-model="modal.provincia" /></div>
            <div class="field"><label>Departamento</label><input v-model="modal.departamento" /></div>
            <div class="field"><label>Ubigeo</label><input v-model="modal.ubigeo" maxlength="6" /></div>
            <div class="field"><label>Teléfono</label><input v-model="modal.telefono" /></div>
            <div class="field"><label>Correo</label><input v-model="modal.correo" type="email" /></div>
            <div class="field">
              <label>Serie de boleta</label>
              <input v-model="modal.serie_boleta" maxlength="4" placeholder="B002" />
              <small class="muted">Serie propia del local: dos mostradores con la misma serie se pisan.</small>
            </div>
            <div class="field">
              <label>Serie de factura</label>
              <input v-model="modal.serie_factura" maxlength="4" placeholder="F002" />
            </div>
            <div class="field" style="grid-column: 1 / -1">
              <label class="check-line">
                <input v-model="modal.es_principal" type="checkbox" />
                <span>Es la sede principal (hereda lo que no diga sede)</span>
              </label>
            </div>
          </div>
        </div>
        <div class="m-foot modal-actions">
          <button class="btn" @click="modal = null">Cancelar</button>
          <button class="btn primary" :disabled="!modal.nombre || guardando" @click="guardar">
            {{ guardando ? "Guardando…" : "Guardar" }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from "vue";
import {
  RefreshCw, Plus, AlertCircle, Info, MapPin, Phone, Receipt, Users,
  DoorOpen, CalendarClock, Pencil, Trash2,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import { sedesApi } from "../api/sedes.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { notify } from "../../../shared/composables/useNotify.js";

const { hasPermission } = useAuth();
const puedeConfigurar = computed(() => hasPermission("empresa:configurar"));

const sedes = ref([]);
const cargando = ref(false);
const guardando = ref(false);
const error = ref("");
const modal = ref(null);

async function cargar() {
  cargando.value = true;
  error.value = "";
  try {
    sedes.value = (await sedesApi.listar()).data ?? [];
  } catch (e) {
    error.value = e.message;
  } finally {
    cargando.value = false;
  }
}

function abrir(s = null) {
  modal.value = s
    ? { ...s }
    : {
        nombre: "", direccion: "", distrito: "", provincia: "", departamento: "",
        ubigeo: "", telefono: "", correo: "", serie_boleta: "", serie_factura: "",
        es_principal: false,
      };
}

async function guardar() {
  guardando.value = true;
  try {
    const payload = { ...modal.value };
    // El backend valida el correo: mandarlo vacío haría fallar el alta de una
    // sede que simplemente no tiene correo propio.
    Object.keys(payload).forEach((k) => {
      if (payload[k] === "" || payload[k] === null) delete payload[k];
    });
    await sedesApi.guardar(payload);
    modal.value = null;
    notify.success("Sede guardada");
    await cargar();
  } catch (e) {
    notify.error(e.message);
  } finally {
    guardando.value = false;
  }
}

async function borrar(s) {
  const ok = await notify.confirm(
    `¿Dar de baja «${s.nombre}»?`,
    "No se puede si tiene caja abierta o citas futuras.",
    { confirmText: "Dar de baja", danger: true },
  );
  if (!ok) return;
  try {
    await sedesApi.eliminar(s.id);
    notify.success("Sede dada de baja");
    await cargar();
  } catch (e) {
    notify.error(e.message);
  }
}

onMounted(cargar);
</script>

<style scoped>
.cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 12px }
.sede {
  background: var(--bg-elev);
  border: 1px solid var(--line);
  border-radius: 10px;
  padding: 14px 16px;
  display: flex;
  flex-direction: column;
  gap: 5px;
}
.sede.inactiva { opacity: .6 }
.sede header { display: flex; justify-content: space-between; align-items: flex-start; gap: 8px; margin-bottom: 3px }
.sede header strong { font-size: 15px }
.codigo { display: block; font-size: 11px; color: var(--ink-4); letter-spacing: .03em }
.linea { display: flex; align-items: center; gap: 6px; font-size: 12.5px; color: var(--ink-2) }
.linea.muted { color: var(--ink-3); font-size: 11.5px; padding-left: 18px }
.meta { display: flex; flex-wrap: wrap; gap: 10px; font-size: 11.5px; color: var(--ink-3); margin-top: 8px }
.meta span { display: inline-flex; align-items: center; gap: 4px }
.sede footer { display: flex; gap: 6px; border-top: 1px solid var(--line); padding-top: 9px; margin-top: 8px }
.pill { font-size: 10.5px; font-weight: 600; padding: 1px 8px; border-radius: 999px;
        border: 1px solid var(--line-strong); color: var(--ink-3); white-space: nowrap }
.pill.principal { border-color: #a6d4b4; color: #15803d; background: #eefaf1 }
.vacio { grid-column: 1 / -1; color: var(--ink-3); font-size: 13px; padding: 18px }
</style>
