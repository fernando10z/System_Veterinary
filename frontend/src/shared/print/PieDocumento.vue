<template>
  <footer class="doc-pie">
    <span>{{ emisor?.nombre_comercial }} · RUC {{ emisor?.ruc }}</span>
    <span>Emitido el {{ fmtFechaHora(new Date()) }}</span>
  </footer>
</template>

<script setup>
import { fmtFechaHora } from "../components/ui/format.js";
defineProps({ emisor: { type: Object, default: () => ({}) } });
</script>
