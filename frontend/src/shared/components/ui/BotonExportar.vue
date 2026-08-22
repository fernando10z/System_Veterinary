<template>
  <button
    class="btn-exportar"
    :disabled="!filas.length"
    :title="filas.length ? `Descargar ${filas.length} registro(s)` : 'No hay datos para exportar'"
    @click="exportar"
  >
    <Download :size="14" />
    <span v-if="!soloIcono">{{ etiqueta }}</span>
  </button>
</template>

<script setup>
// Botón estándar de exportación a Excel. Se usa en todos los módulos con tabla
// para que el archivo salga siempre con el mismo formato (ver shared/utils/exportar.js).
//
//   <BotonExportar
//     nombre="tesoreria-movimientos"
//     :columnas="[{ key: 'fecha', label: 'Fecha', tipo: 'fecha' }, ...]"
//     :filas="movimientosFiltrados"
//   />
//
// Exportá SIEMPRE las filas ya filtradas que ve el usuario: lo que descarga
// debe coincidir con lo que tiene en pantalla.
import { Download } from "lucide-vue-next";
import { exportarExcel } from "../../utils/exportar.js";
import { notify } from "../../composables/useNotify.js";

const props = defineProps({
  // Nombre base del archivo, sin extensión ni fecha (se agregan solos).
  nombre: { type: String, required: true },
  // [{ key, label, tipo?: 'texto'|'numero'|'fecha', valor?: (fila) => any }]
  columnas: { type: Array, required: true },
  filas: { type: Array, default: () => [] },
  etiqueta: { type: String, default: "Exportar Excel" },
  soloIcono: { type: Boolean, default: false },
});

function exportar() {
  if (!props.filas.length) return;
  try {
    exportarExcel(props.nombre, props.columnas, props.filas);
    notify.toast("Archivo descargado");
  } catch (e) {
    notify.error("No se pudo exportar", e?.message || String(e));
  }
}
</script>

<style scoped>
.btn-exportar {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 7px 14px;
  border-radius: var(--radius-sm);
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  border: 1px solid var(--line);
  background: var(--bg-elev);
  color: var(--ink);
  white-space: nowrap;
}
.btn-exportar:hover:not(:disabled) { border-color: var(--ink-3); }
.btn-exportar:disabled { opacity: 0.5; cursor: not-allowed; }
</style>
