<template>
  <div v-if="open" class="visor-back" @click="cerrar">
    <div class="visor" @click.stop>
      <header class="v-head">
        <div class="v-title">
          <FileText :size="16" />
          <div class="v-names">
            <span class="v-name" :title="doc?.nombre">{{ doc?.nombre ?? "Documento" }}</span>
            <span v-if="subtitulo" class="v-sub">{{ subtitulo }}</span>
          </div>
        </div>
        <div class="v-acts">
          <button class="v-btn" title="Abrir en pestaña nueva" :disabled="!url" @click="abrirAparte">
            <ExternalLink :size="15" />
          </button>
          <button class="v-btn" title="Descargar" :disabled="!url" @click="descargar">
            <Download :size="15" />
          </button>
          <button class="v-btn close" title="Cerrar (Esc)" @click="cerrar"><X :size="16" /></button>
        </div>
      </header>

      <div class="v-body">
        <div v-if="cargando" class="v-state"><Loader2 :size="20" class="spin" /> Cargando documento…</div>
        <div v-else-if="error" class="v-state error"><AlertCircle :size="16" /> {{ error }}</div>

        <img
          v-else-if="tipo === 'imagen'" :src="url" :alt="doc?.nombre" class="v-img"
          @error="error = 'No se pudo cargar la imagen. Intenta abrirla en una pestaña nueva.'"
        />

        <iframe v-else-if="tipo === 'pdf'" :src="url" class="v-frame" title="Vista previa del documento" />

        <div v-else class="v-state">
          <FileText :size="34" class="v-noprev-icon" />
          <p>Este tipo de archivo no se puede previsualizar aquí.</p>
          <button class="btn primary" @click="descargar"><Download :size="14" /> Descargar</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch, onUnmounted } from "vue";
import { FileText, Download, ExternalLink, X, Loader2, AlertCircle } from "lucide-vue-next";
import { useDms } from "../../../modules/dms/api/dms.api.js";

const props = defineProps({
  open: { type: Boolean, required: true },
  // Documento tal como lo devuelve fn_contrato_obtener: { nombre, extension, mime_type, storage_path, ... }
  doc: { type: Object, default: null },
  subtitulo: { type: String, default: null },
});
const emit = defineEmits(["close"]);

const dms = useDms();
const url = ref(null);
const cargando = ref(false);
const error = ref(null);

const tipo = computed(() => {
  const mime = (props.doc?.mime_type ?? "").toLowerCase();
  // La extensión puede venir vacía; en ese caso se deduce del nombre del archivo.
  const ext = ((props.doc?.extension || props.doc?.nombre?.split(".").pop()) ?? "")
    .toLowerCase().replace(".", "").trim();
  if (mime.startsWith("image/") || ["jpg", "jpeg", "png", "webp", "gif", "bmp", "heic", "avif"].includes(ext)) return "imagen";
  if (mime.includes("pdf") || ext === "pdf") return "pdf";
  return "otro";
});

async function resolverUrl() {
  url.value = null; error.value = null;
  if (!props.doc?.storage_path) { error.value = "El documento no tiene archivo asociado"; return; }
  cargando.value = true;
  try {
    url.value = await dms.urlFirmada(props.doc.storage_path);
  } catch (e) {
    error.value = e.message ?? "No se pudo abrir el documento";
  } finally {
    cargando.value = false;
  }
}

function cerrar() { emit("close"); }
function abrirAparte() { if (url.value) window.open(url.value, "_blank", "noopener"); }
function descargar() { if (url.value) window.open(url.value, "_blank", "noopener"); }

function onKey(e) { if (e.key === "Escape") cerrar(); }

watch(() => props.open, (abierto) => {
  if (abierto) {
    window.addEventListener("keydown", onKey);
    resolverUrl();
  } else {
    window.removeEventListener("keydown", onKey);
    url.value = null; error.value = null;
  }
}, { immediate: true });

onUnmounted(() => window.removeEventListener("keydown", onKey));
</script>

<style scoped>
.visor-back {
  position: fixed; inset: 0; z-index: 1200;
  background: rgba(0, 0, 0, 0.62);
  display: flex; align-items: center; justify-content: center; padding: 24px;
}
.visor {
  display: flex; flex-direction: column;
  width: min(1080px, 100%); height: min(90vh, 100%);
  background: var(--bg-elev); border: 1px solid var(--line);
  border-radius: var(--radius); overflow: hidden;
}
.v-head {
  display: flex; align-items: center; justify-content: space-between; gap: 12px;
  padding: 10px 14px; border-bottom: 1px solid var(--line); flex-shrink: 0;
}
.v-title { display: flex; align-items: center; gap: 10px; min-width: 0; color: var(--ink-3); }
.v-names { display: flex; flex-direction: column; min-width: 0; }
.v-name {
  font-size: 13.5px; font-weight: 600; color: var(--ink);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.v-sub { font-size: 11px; color: var(--ink-3); }
.v-acts { display: flex; align-items: center; gap: 4px; flex-shrink: 0; }
.v-btn {
  display: inline-flex; align-items: center; justify-content: center;
  width: 30px; height: 30px; border-radius: var(--radius-sm);
  border: 1px solid transparent; background: transparent; color: var(--ink-3); cursor: pointer;
}
.v-btn:hover:not(:disabled) { background: var(--bg-soft); color: var(--ink); }
.v-btn:disabled { opacity: 0.4; cursor: default; }
.v-btn.close:hover { color: var(--danger-ink, #c0392b); }

.v-body {
  flex: 1; min-height: 0; display: flex; align-items: center; justify-content: center;
  background: var(--bg-soft); overflow: auto;
}
.v-frame { width: 100%; height: 100%; border: 0; background: #fff; }
.v-img { max-width: 100%; max-height: 100%; object-fit: contain; }
.v-state {
  display: flex; flex-direction: column; align-items: center; gap: 10px;
  font-size: 13px; color: var(--ink-3); padding: 32px; text-align: center;
}
.v-state.error { color: var(--danger-ink, #c0392b); }
.v-noprev-icon { color: var(--ink-4); }
.spin { animation: spin 0.9s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }
</style>
