<template>
  <div class="modal-back" @click="$emit('close')">
    <div class="modal" @click.stop>
      <div class="m-head"><h3>Nueva consulta</h3></div>

      <div class="m-body">
        <div v-if="error" class="callout danger" style="margin-bottom: 14px">
          <AlertCircle :size="15" /> <span>{{ error }}</span>
        </div>

        <p class="muted" style="margin-top: 0">
          Se abre la consulta en borrador. Podrás registrar constantes, diagnóstico
          y tratamiento en la pantalla de atención, y cerrarla al terminar.
        </p>

        <div class="field">
          <label>Motivo de la consulta <span class="req">*</span></label>
          <textarea v-model="motivo" rows="3" placeholder="Decaimiento y falta de apetito desde ayer…"></textarea>
        </div>

        <div class="field">
          <label>Veterinario</label>
          <select v-model="veterinarioId">
            <option value="">Yo mismo</option>
            <option v-for="v in veterinarios" :key="v.id" :value="v.id">
              {{ v.nombres }} {{ v.apellido_paterno }}
            </option>
          </select>
        </div>
      </div>

      <div class="m-foot modal-actions">
        <button class="btn" @click="$emit('close')">Cancelar</button>
        <button class="btn primary" :disabled="guardando" @click="crear">
          {{ guardando ? "Abriendo…" : "Abrir consulta" }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from "vue";
import { AlertCircle } from "lucide-vue-next";
import { clinicoApi } from "../api/clinico.api.js";
import { usersApi } from "../../users/api/users.api.js";

const props = defineProps({
  mascotaId: { type: String, required: true },
  citaId: { type: String, default: null },
});
const emit = defineEmits(["close", "creada"]);

const motivo = ref("");
const veterinarioId = ref("");
const veterinarios = ref([]);
const guardando = ref(false);
const error = ref("");

async function crear() {
  error.value = "";
  if (!motivo.value.trim()) { error.value = "Indica el motivo de la consulta."; return; }

  guardando.value = true;
  try {
    const r = await clinicoApi.crearConsulta({
      mascota_id: props.mascotaId,
      cita_id: props.citaId || undefined,
      veterinario_id: veterinarioId.value || undefined,
      motivo: motivo.value.trim(),
    });
    emit("creada", r.data.id);
  } catch (e) {
    error.value = e.message;
  } finally {
    guardando.value = false;
  }
}

onMounted(async () => {
  try {
    const v = await usersApi.veterinarios();
    veterinarios.value = v.data ?? [];
  } catch {
    // Sin la lista, la consulta se firma con el usuario en sesión.
  }
});
</script>

<style scoped>
.req { color: var(--red); }
</style>
