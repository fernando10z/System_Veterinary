<template>
  <DocumentoBase :cargando="cargando" :error="error" :aviso="aviso" :auto="auto">
    <div v-if="d" class="hoja">
      <Membrete :emisor="d.emisor" tipo="Carné de vacunación" :numero="d.paciente?.codigo" />

      <h1 class="doc-titulo">Carné de vacunación y desparasitación</h1>

      <FichaPaciente :paciente="d.paciente" :propietario="d.propietario" :alertas="false" />

      <!-- La antirrábica es la que piden municipalidades, parques y traslados:
           su estado va arriba, no perdido en la tabla. -->
      <div :class="['doc-aviso', d.antirrabica_vigente ? '' : 'grave']">
        <strong>Vacunación antirrábica:</strong>
        <template v-if="d.antirrabica_vigente">
          vigente.
          <template v-if="proximaRabia">Próximo refuerzo: {{ fmtDate(proximaRabia) }}.</template>
        </template>
        <template v-else>
          sin registro vigente. Corresponde aplicarla o actualizar el refuerzo.
        </template>
      </div>

      <section class="doc-bloque">
        <h3>Vacunas aplicadas</h3>
        <table v-if="(d.vacunas ?? []).length" class="doc-tabla">
          <thead>
            <tr>
              <th>Vacuna</th>
              <th>Laboratorio</th>
              <th>Lote</th>
              <th class="num">Dosis</th>
              <th>Aplicación</th>
              <th>Refuerzo</th>
              <th>Profesional</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(v, i) in d.vacunas" :key="i" :class="{ destacada: v.antirrabica }">
              <td>
                <strong>{{ v.nombre_vacuna }}</strong>
                <div v-if="v.situacion === 'vencida'" style="color: #a33">Refuerzo vencido</div>
              </td>
              <td>{{ v.laboratorio || "—" }}</td>
              <td class="mono-doc">{{ v.lote || "—" }}</td>
              <td class="num">{{ v.dosis_numero }}</td>
              <td class="mono-doc">{{ fmtDate(v.fecha_aplicacion) }}</td>
              <td class="mono-doc">{{ v.proximo_refuerzo ? fmtDate(v.proximo_refuerzo) : "—" }}</td>
              <td>
                {{ v.veterinario || "—" }}
                <div v-if="v.colegiatura" style="color: #5a625f">C.M.V.P. {{ v.colegiatura }}</div>
              </td>
            </tr>
          </tbody>
        </table>
        <p v-else class="doc-texto">Sin vacunas registradas en esta clínica.</p>
      </section>

      <section class="doc-bloque">
        <h3>Desparasitaciones</h3>
        <table v-if="(d.desparasitaciones ?? []).length" class="doc-tabla">
          <thead>
            <tr><th>Producto</th><th>Tipo</th><th>Dosis</th><th>Aplicación</th><th>Próxima</th></tr>
          </thead>
          <tbody>
            <tr v-for="(x, i) in d.desparasitaciones" :key="i">
              <td><strong>{{ x.producto }}</strong></td>
              <td>{{ capitalizar(x.tipo) }}</td>
              <td>{{ x.dosis || "—" }}</td>
              <td class="mono-doc">{{ fmtDate(x.fecha_aplicacion) }}</td>
              <td class="mono-doc">{{ x.proxima_dosis ? fmtDate(x.proxima_dosis) : "—" }}</td>
            </tr>
          </tbody>
        </table>
        <p v-else class="doc-texto">Sin desparasitaciones registradas en esta clínica.</p>
      </section>

      <p class="doc-texto" style="margin-top: 14px; color: #5a625f">
        Este carné recoge lo aplicado y registrado en {{ d.emisor?.nombre_comercial }}. Las dosis
        administradas en otro establecimiento no figuran aquí.
      </p>

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
import PieDocumento from "../../../shared/print/PieDocumento.vue";
import { documentosApi } from "../api/documentos.api.js";
import { fmtDate, capitalizar } from "../../../shared/components/ui/format.js";

const route = useRoute();
const d = ref(null);
const cargando = ref(true);
const error = ref("");
const auto = computed(() => route.query.auto === "1");

const proximaRabia = computed(
  () => (d.value?.vacunas ?? []).find((v) => v.antirrabica && v.proximo_refuerzo)?.proximo_refuerzo,
);

const vencidas = computed(() => (d.value?.vacunas ?? []).filter((v) => v.situacion === "vencida").length);
const aviso = computed(() =>
  vencidas.value ? `${vencidas.value} refuerzo(s) vencido(s) en este carné.` : "",
);

onMounted(async () => {
  try {
    const r = await documentosApi.carneVacunacion(route.params.id);
    d.value = r.data;
  } catch (e) {
    error.value = e.message;
  } finally {
    cargando.value = false;
  }
});
</script>
