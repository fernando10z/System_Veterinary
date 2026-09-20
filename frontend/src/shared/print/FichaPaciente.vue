<template>
  <section class="doc-bloque">
    <h3>Paciente y propietario</h3>
    <div class="doc-campos">
      <div class="doc-campo"><span class="k">Paciente:</span><span class="v">{{ paciente?.nombre }}</span></div>
      <div class="doc-campo"><span class="k">H.C.:</span><span class="v mono-doc">{{ paciente?.codigo || "—" }}</span></div>
      <div class="doc-campo"><span class="k">Especie:</span><span class="v">{{ paciente?.especie }}</span></div>
      <div class="doc-campo"><span class="k">Raza:</span><span class="v">{{ paciente?.raza }}</span></div>
      <div class="doc-campo"><span class="k">Sexo:</span><span class="v">{{ capitalizar(paciente?.sexo) }}</span></div>
      <div class="doc-campo"><span class="k">Edad:</span><span class="v">{{ paciente?.edad?.texto || "—" }}</span></div>
      <div class="doc-campo"><span class="k">Color:</span><span class="v">{{ paciente?.color || "—" }}</span></div>
      <div class="doc-campo">
        <span class="k">Peso:</span>
        <span class="v">{{ paciente?.peso_kg ? `${paciente.peso_kg} kg` : "—" }}</span>
      </div>
      <div v-if="paciente?.microchip" class="doc-campo">
        <span class="k">Microchip:</span><span class="v mono-doc">{{ paciente.microchip }}</span>
      </div>
      <div v-if="paciente?.senias" class="doc-campo ancho">
        <span class="k">Señas:</span><span class="v">{{ paciente.senias }}</span>
      </div>

      <div class="doc-campo ancho" style="margin-top: 4px">
        <span class="k">Propietario:</span><span class="v">{{ propietario?.nombre }}</span>
      </div>
      <div class="doc-campo">
        <span class="k">{{ propietario?.tipo_documento || "Doc." }}:</span>
        <span class="v mono-doc">{{ propietario?.numero_documento || "—" }}</span>
      </div>
      <div class="doc-campo"><span class="k">Teléfono:</span><span class="v">{{ propietario?.telefono || "—" }}</span></div>
      <div v-if="propietario?.direccion" class="doc-campo ancho">
        <span class="k">Dirección:</span><span class="v">{{ propietario.direccion }}</span>
      </div>
    </div>
  </section>

  <!-- Las alergias van en todo documento clínico: es el dato que evita el
       accidente si al animal lo atiende otro profesional. -->
  <div v-if="alertas && (paciente?.alergias || paciente?.condiciones_cronicas)" class="doc-aviso grave">
    <template v-if="paciente?.alergias"><strong>Alergias:</strong> {{ paciente.alergias }}</template>
    <template v-if="paciente?.alergias && paciente?.condiciones_cronicas"> · </template>
    <template v-if="paciente?.condiciones_cronicas">
      <strong>Condiciones crónicas:</strong> {{ paciente.condiciones_cronicas }}
    </template>
  </div>
</template>

<script setup>
import { capitalizar } from "../components/ui/format.js";

defineProps({
  paciente: { type: Object, default: () => ({}) },
  propietario: { type: Object, default: () => ({}) },
  /** Muestra el recuadro de alergias y crónicos. */
  alertas: { type: Boolean, default: true },
});
</script>
