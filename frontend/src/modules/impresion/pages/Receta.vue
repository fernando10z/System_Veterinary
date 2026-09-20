<template>
  <DocumentoBase :cargando="cargando" :error="error" :aviso="aviso" :auto="auto">
    <div v-if="d" class="hoja">
      <Membrete :emisor="d.emisor" tipo="Receta médico veterinaria" :numero="d.consulta?.codigo" />

      <h1 class="doc-titulo">Receta médico veterinaria</h1>

      <FichaPaciente :paciente="d.paciente" :propietario="d.propietario" />

      <section class="doc-bloque">
        <h3>Diagnóstico</h3>
        <div class="doc-campos">
          <div class="doc-campo"><span class="k">Fecha:</span><span class="v">{{ fmtFechaHora(d.consulta?.fecha) }}</span></div>
          <div class="doc-campo">
            <span class="k">Peso al prescribir:</span>
            <span class="v">{{ d.consulta?.peso_kg ? `${d.consulta.peso_kg} kg` : "—" }}</span>
          </div>
          <div class="doc-campo ancho"><span class="k">Motivo:</span><span class="v">{{ d.consulta?.motivo || "—" }}</span></div>
          <div class="doc-campo ancho"><span class="k">Diagnóstico:</span><span class="v">{{ d.consulta?.diagnostico || "—" }}</span></div>
        </div>
      </section>

      <!-- Un producto controlado cambia cómo se despacha y cómo se archiva la
           receta: el papel tiene que decirlo. -->
      <div v-if="d.tiene_controlados" class="doc-aviso grave">
        <strong>Contiene medicamento sujeto a control.</strong>
        Se despacha únicamente contra la presentación de esta receta, que queda
        en poder del establecimiento que la atiende.
      </div>

      <section class="doc-bloque">
        <h3>Rp.</h3>
        <table v-if="(d.medicamentos ?? []).length" class="doc-tabla">
          <thead>
            <tr>
              <th style="width: 34%">Medicamento</th>
              <th style="width: 18%">Dosis</th>
              <th style="width: 14%">Vía</th>
              <th style="width: 34%">Pauta e indicaciones</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(m, i) in d.medicamentos" :key="i" :class="{ destacada: m.controlado }">
              <td>
                <strong>{{ m.medicamento }}</strong>
                <template v-if="m.controlado"> ⚠</template>
                <div v-if="m.principio_activo" style="color: #5a625f">{{ m.principio_activo }}</div>
                <div v-if="m.presentacion" style="color: #5a625f">{{ m.presentacion }}</div>
              </td>
              <td>{{ m.dosis || "—" }}</td>
              <td>{{ capitalizar(m.via) }}</td>
              <td>
                <template v-if="m.frecuencia_horas">Cada {{ m.frecuencia_horas }} h</template>
                <template v-if="m.frecuencia_horas && m.duracion_dias"> · </template>
                <template v-if="m.duracion_dias">{{ m.duracion_dias }} día(s)</template>
                <div v-if="m.indicaciones">{{ m.indicaciones }}</div>
              </td>
            </tr>
          </tbody>
        </table>

        <!-- La prescripción escrita a mano en la consulta vale aunque no se
             hayan cargado tratamientos estructurados. -->
        <p v-else-if="d.consulta?.prescripcion" class="doc-texto">{{ d.consulta.prescripcion }}</p>
        <p v-else class="doc-texto">Sin medicación indicada.</p>

        <p v-if="(d.medicamentos ?? []).length && d.consulta?.prescripcion" class="doc-texto" style="margin-top: 8px">
          {{ d.consulta.prescripcion }}
        </p>
      </section>

      <section v-if="d.consulta?.indicaciones_casa" class="doc-bloque">
        <h3>Indicaciones para casa</h3>
        <p class="doc-texto">{{ d.consulta.indicaciones_casa }}</p>
      </section>

      <section v-if="d.consulta?.proxima_visita" class="doc-bloque">
        <h3>Control</h3>
        <p class="doc-texto">Próxima visita: <strong>{{ fmtDate(d.consulta.proxima_visita) }}</strong></p>
      </section>

      <Firmas :firmas="[d.profesional]" />
      <PieDocumento :emisor="d.emisor" />
    </div>
  </DocumentoBase>
</template>

<script setup>
import { ref, computed, onMounted } from "vue";
import { useRoute } from "vue-router";
import DocumentoBase from "../../../shared/print/DocumentoBase.vue";
import Membrete from "../../../shared/print/Membrete.vue";
import FichaPaciente from "../../../shared/print/FichaPaciente.vue";
import Firmas from "../../../shared/print/Firmas.vue";
import PieDocumento from "../../../shared/print/PieDocumento.vue";
import { documentosApi } from "../api/documentos.api.js";
import { fmtDate, fmtFechaHora, capitalizar } from "../../../shared/components/ui/format.js";

const route = useRoute();
const d = ref(null);
const cargando = ref(true);
const error = ref("");
const auto = computed(() => route.query.auto === "1");

// Una receta de una consulta en borrador es un borrador: se puede imprimir
// —el veterinario a veces la entrega antes de cerrar—, pero hay que avisarlo.
const aviso = computed(() => {
  if (!d.value) return "";
  if (!d.value.consulta?.cerrada) return "La consulta aún no está cerrada: esta receta es provisional.";
  if (!d.value.profesional?.colegiatura) return "El profesional no tiene colegiatura registrada.";
  return "";
});

onMounted(async () => {
  try {
    const r = await documentosApi.receta(route.params.id);
    d.value = r.data;
  } catch (e) {
    error.value = e.message;
  } finally {
    cargando.value = false;
  }
});
</script>
