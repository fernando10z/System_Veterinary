<template>
  <section class="module-panel">
    <header class="module-panel-head">
      <h2>
        <span class="head-icon"><component :is="icono" :size="14" /></span>
        {{ titulo }}
        <span class="head-meta">{{ filas.length }}</span>
      </h2>
    </header>

    <div v-if="!filas.length" class="module-panel-body module-empty">
      <div class="empty-icon"><component :is="icono" :size="22" /></div>
      <h3>Sin datos</h3>
      <p>No hay registros para el periodo seleccionado.</p>
    </div>

    <div v-else class="module-panel-body tabla-wrap">
      <table>
        <thead>
          <tr>
            <th v-for="col in columnas" :key="col.k" :class="col.num ? 'num' : ''">{{ col.l }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(f, i) in filas" :key="i">
            <td v-for="col in columnas" :key="col.k" :class="[col.num ? 'num mono' : '']">
              {{ formatear(f[col.k], col) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>

<script setup>
import { fmtSoles, fmtNum, capitalizar } from "../../../shared/components/ui/format.js";

defineProps({
  titulo: { type: String, required: true },
  icono: { type: [Object, Function], required: true },
  filas: { type: Array, default: () => [] },
  /** [{ k: clave, l: etiqueta, num?: bool, money?: bool, cap?: bool }] */
  columnas: { type: Array, required: true },
});

function formatear(valor, col) {
  if (valor === null || valor === undefined || valor === "") return "—";
  if (col.money) return fmtSoles(valor);
  if (col.num) return fmtNum(valor);
  if (col.cap) return capitalizar(valor);
  return valor;
}
</script>
