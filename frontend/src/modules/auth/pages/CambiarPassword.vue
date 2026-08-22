<template>
  <div>
    <PageHeader
      eyebrow="Mi cuenta"
      title="Cambiar contraseña"
      subtitle="Elige una contraseña que no uses en otros servicios"
    />

    <section class="module-panel" style="max-width: 520px">
      <header class="module-panel-head">
        <h2><span class="head-icon"><KeyRound :size="14" /></span> Seguridad</h2>
      </header>

      <div class="module-panel-body" style="padding: 18px">
        <div v-if="error" class="callout danger" style="margin-bottom: 14px">
          <AlertCircle :size="15" /> <span>{{ error }}</span>
        </div>
        <div v-if="ok" class="callout" style="margin-bottom: 14px">
          <CheckCircle2 :size="15" /> <span>Contraseña actualizada.</span>
        </div>

        <form class="form-grid" style="grid-template-columns: 1fr" @submit.prevent="guardar">
          <div class="field">
            <label>Contraseña actual</label>
            <input v-model="actual" type="password" autocomplete="current-password" />
          </div>
          <div class="field">
            <label>Contraseña nueva</label>
            <input v-model="nueva" type="password" autocomplete="new-password" />
            <small class="muted">Mínimo 8 caracteres.</small>
          </div>
          <div class="field">
            <label>Repetir contraseña nueva</label>
            <input v-model="repetir" type="password" autocomplete="new-password" />
          </div>
          <div>
            <button class="btn primary" :disabled="guardando">
              {{ guardando ? "Guardando…" : "Actualizar contraseña" }}
            </button>
          </div>
        </form>
      </div>
    </section>
  </div>
</template>

<script setup>
import { ref } from "vue";
import { KeyRound, AlertCircle, CheckCircle2 } from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import { authApi } from "../api/auth.api.js";

const actual = ref("");
const nueva = ref("");
const repetir = ref("");
const guardando = ref(false);
const error = ref("");
const ok = ref(false);

async function guardar() {
  error.value = "";
  ok.value = false;

  if (nueva.value.length < 8) {
    error.value = "La contraseña nueva debe tener al menos 8 caracteres.";
    return;
  }
  if (nueva.value !== repetir.value) {
    error.value = "Las contraseñas nuevas no coinciden.";
    return;
  }

  guardando.value = true;
  try {
    await authApi.cambiarPassword(actual.value, nueva.value);
    ok.value = true;
    actual.value = nueva.value = repetir.value = "";
  } catch (e) {
    error.value = e.message;
  } finally {
    guardando.value = false;
  }
}
</script>
