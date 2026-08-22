<template>
  <div class="login-hero">
    <div class="login-bg" aria-hidden="true"></div>

    <div class="login-hero-grid">
      <!-- Formulario -->
      <div>
        <div class="login-hero-card">
          <div class="hero-logo-tile"><PawPrint :size="26" /></div>

          <h1>Iniciar sesión</h1>
          <p class="lf-sub-hero">
            Accede para gestionar la agenda, la historia clínica de tus pacientes
            y la operación completa de la clínica.
          </p>

          <div v-if="bannerError" class="lf-error" role="alert">
            <AlertCircle :size="14" />
            <span>{{ bannerError }}</span>
          </div>

          <form novalidate class="lf" @submit.prevent="handleSubmit">
            <div class="lf-field">
              <label for="email">Correo</label>
              <div :class="['input-wrap', errors.email ? 'error' : '']">
                <Mail :size="16" />
                <input
                  id="email"
                  v-model.trim="email"
                  type="email"
                  autocomplete="username"
                  placeholder="nombre@clinica.pe"
                  :disabled="submitting"
                />
              </div>
              <div v-if="errors.email" class="login-error-msg">{{ errors.email }}</div>
            </div>

            <div class="lf-field">
              <label for="password">Contraseña</label>
              <div :class="['input-wrap', errors.password ? 'error' : '']">
                <Lock :size="16" />
                <input
                  id="password"
                  v-model="password"
                  :type="showPass ? 'text' : 'password'"
                  autocomplete="current-password"
                  placeholder="••••••••••"
                  :disabled="submitting"
                />
                <button
                  type="button"
                  class="eye"
                  tabindex="-1"
                  :aria-label="showPass ? 'Ocultar contraseña' : 'Mostrar contraseña'"
                  @click="showPass = !showPass"
                >
                  <EyeOff v-if="showPass" :size="16" />
                  <Eye v-else :size="16" />
                </button>
              </div>
              <div v-if="errors.password" class="login-error-msg">{{ errors.password }}</div>
            </div>

            <div class="lf-row">
              <router-link to="/portal/login">Soy propietario de una mascota</router-link>
            </div>

            <button type="submit" class="lf-submit" :disabled="submitting">
              <template v-if="submitting"><span class="spinner" /> Ingresando…</template>
              <template v-else>Entrar <ArrowRight :size="14" /></template>
            </button>
          </form>

          <div class="lf-foot">© {{ anio }} Vet Patitas — ERP Veterinario</div>
        </div>
      </div>

      <!-- Escenario: módulos reales del sistema -->
      <div class="login-hero-right">
        <div class="login-hero-stage">
          <div class="login-hero-center">
            <div class="hero-center-mark"><PawPrint :size="52" /></div>
          </div>

          <div
            v-for="(f, i) in modulos"
            :key="f.name"
            :class="['feat-card', f.tone, `pos-${i + 1}`]"
          >
            <div class="icon-tile"><component :is="f.icon" :size="18" /></div>
            <div class="body">
              <div class="l">Módulo</div>
              <div class="v">{{ f.name }}</div>
            </div>
          </div>
        </div>

        <div class="login-hero-foot">
          <h2>Vet Patitas</h2>
          <p>La clínica completa, de la sala de espera a la caja</p>
          <div class="feat-chips">
            <span v-for="f in modulos" :key="f.name" :class="['feat-chip', `tone-${f.tone}`]">
              <component :is="f.icon" :size="14" /> {{ f.name }}
            </span>
          </div>
        </div>
      </div>
    </div>

    <div class="login-hero-copy">© {{ anio }} Vet Patitas — Todos los derechos reservados</div>
  </div>
</template>

<script setup>
import { ref, reactive, computed } from "vue";
import { useRoute, useRouter } from "vue-router";
import {
  Mail, Lock, Eye, EyeOff, ArrowRight, AlertCircle, PawPrint,
  CalendarClock, Stethoscope, Package, Receipt,
} from "lucide-vue-next";
import { useAuth } from "../../../shared/composables/useAuth.js";

const route = useRoute();
const router = useRouter();
const { login } = useAuth();

const email = ref("");
const password = ref("");
const showPass = ref(false);
const submitting = ref(false);
const bannerError = ref("");
const errors = reactive({ email: "", password: "" });
const anio = computed(() => new Date().getFullYear());

const modulos = [
  { name: "Agenda", icon: CalendarClock, tone: "green" },
  { name: "Historia clínica", icon: Stethoscope, tone: "blue" },
  { name: "Inventario", icon: Package, tone: "amber" },
  { name: "Facturación", icon: Receipt, tone: "violet" },
];

function validar() {
  errors.email = "";
  errors.password = "";
  if (!email.value) errors.email = "Ingresa tu correo";
  else if (!/^\S+@\S+\.\S+$/.test(email.value)) errors.email = "El correo no tiene un formato válido";
  if (!password.value) errors.password = "Ingresa tu contraseña";
  return !errors.email && !errors.password;
}

async function handleSubmit() {
  bannerError.value = "";
  if (!validar()) return;

  submitting.value = true;
  const r = await login(email.value, password.value);
  submitting.value = false;

  if (!r.ok) {
    bannerError.value = r.error || "No pudimos iniciar sesión";
    return;
  }
  router.replace(route.query.from ? String(route.query.from) : "/dashboard");
}
</script>

<style scoped>
.hero-logo-tile {
  width: 52px; height: 52px; border-radius: 14px;
  background: var(--emerald); color: #fff;
  display: grid; place-items: center; margin-bottom: 18px;
  box-shadow: 0 6px 18px rgba(7, 177, 98, 0.28);
}
.hero-center-mark {
  width: 128px; height: 128px; border-radius: 34px;
  background: var(--bg-elev); color: var(--emerald);
  display: grid; place-items: center;
  box-shadow: var(--shadow-lg), 0 0 0 1px var(--line);
}
.lf-row a { font-size: 12.5px; color: var(--emerald-deep); text-decoration: none; font-weight: 500; }
.lf-row a:hover { text-decoration: underline; }
</style>
