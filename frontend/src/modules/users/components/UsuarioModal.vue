<template>
  <div class="modal-back" v-dialogo="() => $emit('close')">
    <div class="modal modal-wide" @click.stop>
      <div class="m-head"><h3>{{ esEdicion ? "Editar usuario" : "Nuevo usuario" }}</h3></div>

      <div class="m-body">
        <div v-if="error" class="callout danger" style="margin-bottom: 14px">
          <AlertCircle :size="15" /> <span>{{ error }}</span>
        </div>

        <div class="form-grid">
          <div class="field">
            <label for="usuariomod-nombres">Nombres <span class="req">*</span></label>
            <input id="usuariomod-nombres" v-model.trim="form.nombres" type="text" />
          </div>
          <div class="field">
            <label for="usuariomod-apellido-paterno">Apellido paterno <span class="req">*</span></label>
            <input id="usuariomod-apellido-paterno" v-model.trim="form.apellido_paterno" type="text" />
          </div>
          <div class="field">
            <label for="usuariomod-apellido-materno">Apellido materno</label>
            <input id="usuariomod-apellido-materno" v-model.trim="form.apellido_materno" type="text" />
          </div>
          <div class="field">
            <label for="usuariomod-tipo-documento">Tipo de documento</label>
            <select id="usuariomod-tipo-documento" v-model="form.tipo_documento">
              <option value="DNI">DNI</option>
              <option value="CE">Carné de extranjería</option>
              <option value="PASAPORTE">Pasaporte</option>
            </select>
          </div>
          <div class="field">
            <label for="usuariomod-numero-documento">Número <span class="req">*</span></label>
            <input id="usuariomod-numero-documento" v-model.trim="form.numero_documento" type="text" />
          </div>
          <div class="field">
            <label for="usuariomod-telefono">Teléfono</label>
            <input id="usuariomod-telefono" v-model.trim="form.telefono" type="tel" />
          </div>
          <div class="field">
            <label for="usuariomod-email">Correo <span class="req">*</span></label>
            <input id="usuariomod-email" v-model.trim="form.email" type="email" :disabled="esEdicion" />
          </div>
          <div v-if="!esEdicion" class="field">
            <label for="usuariomod-password">Contraseña temporal <span class="req">*</span></label>
            <input id="usuariomod-password" v-model="form.password" type="text" placeholder="Mínimo 8 caracteres" />
            <small class="muted">El usuario deberá cambiarla al ingresar.</small>
          </div>
          <div v-if="!esEdicion" class="field">
            <label for="usuariomod-rol-id">Rol</label>
            <select id="usuariomod-rol-id" v-model="form.rol_id" @change="onRol">
              <option value="">Sin rol</option>
              <option v-for="r in roles" :key="r.id" :value="r.id">
                {{ r.nombre }} ({{ labelScope(r.scope) }})
              </option>
            </select>
          </div>
          <div v-if="!esEdicion && rolRequiereEmpresa" class="field">
            <label for="usuariomod-empresa-id">Empresa <span class="req">*</span></label>
            <select id="usuariomod-empresa-id" v-model="form.empresa_id">
              <option value="">Seleccionar…</option>
              <option v-for="e in empresas" :key="e.id" :value="e.id">
                {{ e.nombre_comercial || e.razon_social }}
              </option>
            </select>
          </div>
        </div>

        <div class="section-title" style="margin-top: 16px">Perfil clínico</div>
        <label class="check-line" style="margin: 8px 0">
          <input v-model="form.es_veterinario" type="checkbox" />
          <span>Es veterinario colegiado</span>
        </label>

        <div v-if="form.es_veterinario" class="form-grid">
          <div class="field">
            <label for="usuariomod-colegiatura">Colegiatura <span class="req">*</span></label>
            <input id="usuariomod-colegiatura" v-model.trim="form.colegiatura" type="text" placeholder="CMVP-0000" />
            <small class="muted">Necesaria para firmar la historia clínica.</small>
          </div>
          <div class="field">
            <label for="usuariomod-especializacion-id">Especialidad</label>
            <select id="usuariomod-especializacion-id" v-model="form.especializacion_id">
              <option value="">Sin especialidad</option>
              <option v-for="e in especializaciones" :key="e.id" :value="e.id">{{ e.nombre }}</option>
            </select>
          </div>
          <div class="field">
            <label for="usuariomod-color-agenda">Color en la agenda</label>
            <input id="usuariomod-color-agenda" v-model="form.color_agenda" type="color" class="color-input" />
          </div>
        </div>
      </div>

      <div class="m-foot modal-actions">
        <button class="btn" @click="$emit('close')">Cancelar</button>
        <button class="btn primary" :disabled="guardando" @click="guardar">
          {{ guardando ? "Guardando…" : esEdicion ? "Guardar cambios" : "Crear usuario" }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { reactive, ref, computed } from "vue";
import { AlertCircle } from "lucide-vue-next";
import { usersApi } from "../api/users.api.js";

const props = defineProps({
  usuario: { type: Object, default: null },
  roles: { type: Array, default: () => [] },
  especializaciones: { type: Array, default: () => [] },
  empresas: { type: Array, default: () => [] },
});
const emit = defineEmits(["close", "guardado"]);

const esEdicion = computed(() => !!props.usuario?.id);
const guardando = ref(false);
const error = ref("");

const form = reactive({
  nombres: props.usuario?.nombres ?? "",
  apellido_paterno: props.usuario?.apellido_paterno ?? "",
  apellido_materno: props.usuario?.apellido_materno ?? "",
  tipo_documento: props.usuario?.tipo_documento ?? "DNI",
  numero_documento: props.usuario?.numero_documento ?? "",
  telefono: props.usuario?.telefono ?? "",
  email: props.usuario?.email ?? "",
  password: "",
  rol_id: props.usuario?.rol_id ?? "",
  empresa_id: props.usuario?.empresa_id ?? "",
  es_veterinario: props.usuario?.es_veterinario ?? false,
  colegiatura: props.usuario?.colegiatura ?? "",
  especializacion_id: props.usuario?.especializacion_id ?? "",
  color_agenda: props.usuario?.color_agenda ?? "#178A72",
});

/** Un rol de alcance global no se ancla a una empresa: el backend la exige NULL. */
const rolRequiereEmpresa = computed(() => {
  const r = props.roles.find((x) => x.id === form.rol_id);
  return r ? r.scope === "empresa" : false;
});

function labelScope(s) {
  return { global: "todas las empresas", global_restricted: "lectura global", empresa: "una empresa" }[s] || s;
}
function onRol() {
  if (!rolRequiereEmpresa.value) form.empresa_id = "";
}

async function guardar() {
  error.value = "";
  if (!form.nombres || !form.apellido_paterno) { error.value = "Nombre y apellido son obligatorios."; return; }
  if (!esEdicion.value) {
    if (!form.email) { error.value = "Ingresa el correo."; return; }
    if (form.password.length < 8) { error.value = "La contraseña debe tener al menos 8 caracteres."; return; }
    if (rolRequiereEmpresa.value && !form.empresa_id) { error.value = "Este rol necesita una empresa."; return; }
  }
  if (form.es_veterinario && !form.colegiatura) {
    error.value = "Un veterinario necesita su número de colegiatura.";
    return;
  }

  guardando.value = true;
  try {
    if (esEdicion.value) {
      const p = {
        nombres: form.nombres,
        apellido_paterno: form.apellido_paterno,
        apellido_materno: form.apellido_materno || undefined,
        telefono: form.telefono || undefined,
        tipo_documento: form.tipo_documento,
        numero_documento: form.numero_documento,
        es_veterinario: form.es_veterinario,
        colegiatura: form.colegiatura || undefined,
        especializacion_id: form.especializacion_id || undefined,
        color_agenda: form.color_agenda,
      };
      await usersApi.actualizar(props.usuario.id, p);
      // El rol se cambia por su propio endpoint: puede mover al usuario de empresa.
      if (form.rol_id && form.rol_id !== props.usuario.rol_id) {
        await usersApi.cambiarRol(props.usuario.id, form.rol_id, form.empresa_id || undefined);
      }
    } else {
      const p = {};
      for (const [k, v] of Object.entries(form)) {
        if (v === "" || v === null) continue;
        p[k] = v;
      }
      p.es_veterinario = form.es_veterinario;
      await usersApi.crear(p);
    }
    emit("guardado");
  } catch (e) {
    error.value = e.message;
  } finally {
    guardando.value = false;
  }
}
</script>

<style scoped>
.check-line { display: inline-flex; align-items: center; gap: 8px; font-size: 13px; color: var(--ink-2); }
.color-input { height: 34px; padding: 2px; cursor: pointer; }
.req { color: var(--red); }
</style>
