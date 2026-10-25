<template>
  <div class="buscador-paciente">
    <div class="fil grow" data-no-dirty>
      <Search :size="14" />
      <input
        :id="inputId"
        v-model="q"
        type="search"
        autocomplete="off"
        placeholder="Busca por propietario, documento, teléfono o nombre de la mascota…"
        @input="buscarDebounced"
      />
      <Loader2 v-if="buscando" :size="14" class="spin" />
    </div>

    <div v-if="resultados.length" class="resultados">
      <div v-for="c in resultados" :key="c.id" class="res-cliente">
        <div class="res-head">
          <strong>{{ c.nombre_completo }}</strong>
          <span class="codigo muted">{{ c.numero_documento }}</span>
        </div>
        <div v-if="!c.mascotas?.length" class="res-vacio">Sin mascotas registradas</div>
        <button v-for="m in c.mascotas" :key="m.id" type="button" class="res-mascota" @click="elegir(c, m)">
          <PawPrint :size="13" /> {{ m.nombre }}
          <span class="tag">{{ m.especie }}</span>
        </button>
        <button
          v-if="puedeCrearMascota"
          type="button" class="res-mascota nueva"
          @click="nuevaMascotaPara(c)"
        >
          <Plus :size="13" /> Otra mascota
        </button>
      </div>
    </div>
    <div v-else-if="q.length >= 2 && !buscando && buscado" class="res-vacio">
      Sin coincidencias para “{{ q }}”.
    </div>

    <button
      v-if="permitirAlta && puedeCrearCliente && puedeCrearMascota"
      type="button" class="btn sm alta-rapida"
      @click="modalCliente = true"
    >
      <UserPlus :size="13" /> Nuevo propietario y mascota
    </button>

    <!-- Alta rápida en recepción: propietario → mascota → queda elegido -->
    <ClienteModal
      v-if="modalCliente"
      :con-mascota="false"
      @close="modalCliente = false"
      @guardado="onCliente"
    />
    <PacienteModal
      v-if="clienteParaMascota"
      :cliente-preseleccionado="clienteParaMascota"
      @close="clienteParaMascota = null"
      @guardado="onMascota"
    />
  </div>
</template>

<script setup>
import { ref, computed } from "vue";
import { Search, Loader2, PawPrint, Plus, UserPlus } from "lucide-vue-next";
import { clientesApi } from "../../clientes/api/clientes.api.js";
import ClienteModal from "../../clientes/components/ClienteModal.vue";
import PacienteModal from "./PacienteModal.vue";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { notify } from "../../../shared/composables/useNotify.js";

/**
 * Buscador de paciente por dueño o mascota, con alta rápida de propietario y
 * mascota sin salir del flujo (llegada a sala, nueva cita). Emite
 * elegir(cliente, mascota) con { id, nombre_completo } y { id, nombre, especie }.
 */
defineProps({
  permitirAlta: { type: Boolean, default: true },
  inputId: { type: String, default: undefined },
});
const emit = defineEmits(["elegir"]);

const { hasPermission } = useAuth();
const puedeCrearCliente = computed(() => hasPermission("clientes:crear"));
const puedeCrearMascota = computed(() => hasPermission("mascotas:crear"));

const q = ref("");
const resultados = ref([]);
const buscando = ref(false);
const buscado = ref(false);
const modalCliente = ref(false);
const clienteParaMascota = ref(null);

let timer = null;
function buscarDebounced() {
  clearTimeout(timer);
  buscado.value = false;
  if (q.value.length < 2) { resultados.value = []; return; }
  timer = setTimeout(async () => {
    buscando.value = true;
    try {
      const r = await clientesApi.buscar(q.value, 8);
      resultados.value = r.data ?? [];
    } catch (e) {
      resultados.value = [];
      notify.toast(`No se pudo buscar: ${e.message}`, "error");
    } finally {
      buscando.value = false;
      buscado.value = true;
    }
  }, 300);
}

function elegir(c, m) {
  resultados.value = [];
  q.value = "";
  emit("elegir", c, m);
}

function nuevaMascotaPara(c) {
  clienteParaMascota.value = { id: c.id, nombre_completo: c.nombre_completo, numero_documento: c.numero_documento };
}

function onCliente(r) {
  modalCliente.value = false;
  if (r?.cliente?.id) clienteParaMascota.value = r.cliente;
}

function onMascota(r) {
  const cliente = clienteParaMascota.value;
  clienteParaMascota.value = null;
  if (!r?.id) return;
  notify.toast("Paciente registrado");
  elegir(cliente, { id: r.id, nombre: r.nombre, especie: r.especie });
}
</script>

<style scoped>
.resultados {
  margin-top: 8px; max-height: 230px; overflow-y: auto;
  border: 1px solid var(--line); border-radius: 10px;
}
.res-cliente { padding: 9px 11px; border-bottom: 1px solid var(--line-soft); }
.res-cliente:last-child { border-bottom: none; }
.res-head { display: flex; justify-content: space-between; gap: 8px; font-size: 12.5px; margin-bottom: 5px; }
.res-mascota {
  display: inline-flex; align-items: center; gap: 6px;
  margin: 2px 4px 2px 0; padding: 4px 9px; min-height: 30px; border-radius: 8px;
  background: var(--bg-soft); border: 1px solid var(--line);
  font-size: 12px; cursor: pointer; color: var(--ink-2);
}
.res-mascota:hover { background: var(--emerald-soft); border-color: var(--emerald-line); color: var(--emerald-ink); }
.res-mascota.nueva { border-style: dashed; background: transparent; }
.res-vacio { font-size: 11.5px; color: var(--ink-4); padding: 6px 2px; }
.alta-rapida { margin-top: 8px; }
@media (pointer: coarse) { .res-mascota { min-height: 40px; } }
</style>
