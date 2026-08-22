<template>
  <div class="portal-login">
    <div class="pl-card">
      <div class="pl-logo"><PawPrint :size="26" /></div>
      <h1>Portal del propietario</h1>
      <p class="pl-sub">
        Consulta las citas, vacunas e historial de tus mascotas.
      </p>

      <div v-if="error" class="lf-error" role="alert">
        <AlertCircle :size="14" /> <span>{{ error }}</span>
      </div>

      <form class="lf" novalidate @submit.prevent="entrar">
        <div class="lf-field">
          <label for="doc">Documento o correo</label>
          <div class="input-wrap">
            <IdCard :size="16" />
            <input id="doc" v-model.trim="documento" type="text" placeholder="44556677" :disabled="cargando" />
          </div>
        </div>

        <div class="lf-field">
          <label for="pass">Contraseña</label>
          <div class="input-wrap">
            <Lock :size="16" />
            <input
              id="pass"
              v-model="password"
              :type="ver ? 'text' : 'password'"
              placeholder="••••••••"
              :disabled="cargando"
            />
            <button type="button" class="eye" tabindex="-1" @click="ver = !ver">
              <EyeOff v-if="ver" :size="16" /><Eye v-else :size="16" />
            </button>
          </div>
        </div>

        <button type="submit" class="lf-submit" :disabled="cargando">
          <template v-if="cargando"><span class="spinner" /> Ingresando…</template>
          <template v-else>Entrar <ArrowRight :size="14" /></template>
        </button>
      </form>

      <p class="pl-ayuda">
        ¿No tienes acceso? Pídelo en recepción de la clínica.
      </p>
      <router-link to="/login" class="pl-staff">Soy personal de la clínica</router-link>
    </div>
  </div>
</template>

<script setup>
import { ref } from "vue";
import { useRouter } from "vue-router";
import { PawPrint, IdCard, Lock, Eye, EyeOff, ArrowRight, AlertCircle } from "lucide-vue-next";
import { portalApi } from "../api/portal.api.js";

const router = useRouter();
const documento = ref("");
const password = ref("");
const ver = ref(false);
const cargando = ref(false);
const error = ref("");

async function entrar() {
  error.value = "";
  if (!documento.value || !password.value) {
    error.value = "Completa tu documento y contraseña.";
    return;
  }
  cargando.value = true;
  try {
    await portalApi.login(documento.value, password.value);
    router.replace("/portal");
  } catch (e) {
    error.value = e.message || "No pudimos iniciar sesión";
  } finally {
    cargando.value = false;
  }
}
</script>

<style scoped>
.portal-login {
  min-height: 100vh; display: grid; place-items: center;
  padding: 24px; background: var(--bg);
}
.pl-card {
  width: 100%; max-width: 400px;
  background: var(--bg-elev); border: 1px solid var(--line);
  border-radius: 18px; padding: 32px 28px; box-shadow: var(--shadow-lg);
}
.pl-logo {
  width: 52px; height: 52px; border-radius: 14px;
  background: var(--emerald); color: #fff;
  display: grid; place-items: center; margin-bottom: 18px;
  box-shadow: 0 6px 18px rgba(7, 177, 98, 0.28);
}
.pl-card h1 { font-size: 21px; margin: 0 0 6px; letter-spacing: -0.02em; color: var(--ink); }
.pl-sub { font-size: 13px; color: var(--ink-3); margin: 0 0 20px; line-height: 1.5; }
.pl-ayuda { font-size: 12px; color: var(--ink-4); margin: 16px 0 4px; text-align: center; }
.pl-staff {
  display: block; text-align: center; font-size: 12.5px;
  color: var(--emerald-deep); text-decoration: none; font-weight: 500;
}
.pl-staff:hover { text-decoration: underline; }
</style>
