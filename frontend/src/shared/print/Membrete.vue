<template>
  <header class="doc-membrete">
    <div>
      <img v-if="emisor?.logo_url" class="logo" :src="emisor.logo_url" :alt="emisor.nombre_comercial" />
      <div v-else class="marca">{{ emisor?.nombre_comercial || "—" }}</div>
      <div class="datos">
        <template v-if="emisor?.logo_url">{{ emisor.nombre_comercial }}<br /></template>
        {{ emisor?.razon_social }}<br />
        RUC {{ emisor?.ruc }}<br />
        <template v-if="emisor?.direccion">{{ emisor.direccion }}<br /></template>
        <template v-if="emisor?.telefono">T. {{ emisor.telefono }}</template>
        <template v-if="emisor?.correo"> · {{ emisor.correo }}</template>
      </div>
    </div>

    <!-- Recuadro de la derecha: el número del documento, o el tipo si no lo
         tiene (una receta no se numera; una boleta sí). -->
    <div v-if="numero || tipo" class="doc-tipo">
      <div class="t">{{ tipo }}</div>
      <div v-if="numero" class="n mono-doc">{{ numero }}</div>
      <div v-if="subtitulo" class="t" style="margin-top: 3px">{{ subtitulo }}</div>
    </div>
  </header>
</template>

<script setup>
defineProps({
  emisor: { type: Object, default: () => ({}) },
  tipo: { type: String, default: "" },
  numero: { type: String, default: "" },
  subtitulo: { type: String, default: "" },
});
</script>
