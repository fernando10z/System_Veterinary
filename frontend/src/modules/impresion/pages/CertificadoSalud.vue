<template>
  <DocumentoBase :cargando="cargando" :error="error" :aviso="aviso" :auto="auto">
    <template #acciones>
      <input
        v-model.trim="motivo"
        class="mini-input"
        type="text"
        placeholder="Motivo (viaje, mudanza…)"
        @change="recargar"
      />
      <input
        v-model.trim="destino"
        class="mini-input"
        type="text"
        placeholder="Destino"
        @change="recargar"
      />
    </template>

    <div v-if="d" class="hoja">
      <Membrete :emisor="d.emisor" tipo="Certificado de salud animal" :numero="d.paciente?.codigo" />

      <h1 class="doc-titulo">Certificado de salud animal</h1>

      <!-- Lo que impide que el certificado sirva, antes de firmarlo. No se
           imprime: es para el veterinario, no para la ventanilla. -->
      <div v-if="!d.apto" class="doc-aviso grave no-imprimir">
        <strong>Revisa antes de firmar:</strong>
        <ul style="margin: 4px 0 0; padding-left: 18px">
          <li v-for="(o, i) in d.observaciones_previas" :key="i">{{ o }}</li>
        </ul>
      </div>

      <FichaPaciente :paciente="d.paciente" :propietario="d.propietario" :alertas="false" />

      <section class="doc-bloque">
        <h3>Certificación</h3>
        <p class="doc-texto">
          El(la) que suscribe, <strong>{{ d.profesional?.nombre }}</strong>, médico veterinario
          colegiado con C.M.V.P. N.º
          <strong class="mono-doc">{{ d.profesional?.colegiatura || "—" }}</strong>, deja
          constancia de haber examinado clínicamente al paciente
          <strong>{{ d.paciente?.nombre }}</strong>, de propiedad de
          <strong>{{ d.propietario?.nombre }}</strong>
          ({{ d.propietario?.tipo_documento }} N.º {{ d.propietario?.numero_documento }}),
          encontrándolo <strong>clínicamente sano</strong>, sin signos de enfermedad infecto-contagiosa
          ni parasitaria al momento de la evaluación, y en condiciones aptas para
          <strong>{{ (d.motivo || "viaje").toLowerCase() }}</strong><template v-if="d.destino">
            con destino a <strong>{{ d.destino }}</strong></template>.
        </p>
      </section>

      <section v-if="d.examen_clinico" class="doc-bloque">
        <h3>Examen clínico</h3>
        <div class="doc-campos">
          <div class="doc-campo"><span class="k">Fecha:</span><span class="v">{{ fmtDate(d.examen_clinico.fecha) }}</span></div>
          <div class="doc-campo">
            <span class="k">Peso:</span>
            <span class="v">{{ d.examen_clinico.peso_kg ? `${d.examen_clinico.peso_kg} kg` : "—" }}</span>
          </div>
          <div class="doc-campo">
            <span class="k">Temperatura:</span>
            <span class="v">{{ d.examen_clinico.temperatura_c ? `${d.examen_clinico.temperatura_c} °C` : "—" }}</span>
          </div>
          <div v-if="d.examen_clinico.examen_fisico" class="doc-campo ancho">
            <span class="k">Hallazgos:</span><span class="v">{{ d.examen_clinico.examen_fisico }}</span>
          </div>
        </div>
      </section>

      <section class="doc-bloque">
        <h3>Vacunación antirrábica</h3>
        <div v-if="d.antirrabica" class="doc-campos">
          <div class="doc-campo"><span class="k">Vacuna:</span><span class="v">{{ d.antirrabica.nombre_vacuna }}</span></div>
          <div class="doc-campo"><span class="k">Laboratorio:</span><span class="v">{{ d.antirrabica.laboratorio || "—" }}</span></div>
          <div class="doc-campo"><span class="k">Lote:</span><span class="v mono-doc">{{ d.antirrabica.lote || "—" }}</span></div>
          <div class="doc-campo"><span class="k">Aplicación:</span><span class="v mono-doc">{{ fmtDate(d.antirrabica.fecha_aplicacion) }}</span></div>
          <div class="doc-campo">
            <span class="k">Vigencia:</span>
            <span class="v mono-doc">{{ d.antirrabica.proximo_refuerzo ? fmtDate(d.antirrabica.proximo_refuerzo) : "—" }}</span>
          </div>
        </div>
        <p v-else class="doc-texto">Sin registro de vacunación antirrábica en esta clínica.</p>
      </section>

      <section class="doc-bloque">
        <h3>Desparasitación</h3>
        <div v-if="d.desparasitacion" class="doc-campos">
          <div class="doc-campo"><span class="k">Producto:</span><span class="v">{{ d.desparasitacion.producto }}</span></div>
          <div class="doc-campo"><span class="k">Tipo:</span><span class="v">{{ capitalizar(d.desparasitacion.tipo) }}</span></div>
          <div class="doc-campo"><span class="k">Aplicación:</span><span class="v mono-doc">{{ fmtDate(d.desparasitacion.fecha_aplicacion) }}</span></div>
        </div>
        <p v-else class="doc-texto">Sin registro de desparasitación en esta clínica.</p>
      </section>

      <p class="doc-texto" style="margin-top: 12px; color: #5a625f">
        Este certificado acredita el estado sanitario del animal a la fecha de emisión. Para el
        traslado internacional, SENASA emite el Certificado Sanitario de Exportación a partir de
        este documento y de la demás documentación que esa entidad exija.
      </p>

      <div class="doc-campos" style="margin-top: 10px">
        <div class="doc-campo">
          <span class="k">Lugar y fecha:</span>
          <span class="v">{{ d.emisor?.distrito || "—" }}, {{ fmtDate(d.fecha_emision) }}</span>
        </div>
      </div>

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
import { fmtDate, capitalizar } from "../../../shared/components/ui/format.js";

const route = useRoute();
const d = ref(null);
const cargando = ref(true);
const error = ref("");
const motivo = ref(route.query.motivo || "");
const destino = ref(route.query.destino || "");
const auto = computed(() => route.query.auto === "1");

const aviso = computed(() =>
  d.value && !d.value.apto
    ? `${d.value.observaciones_previas.length} observación(es) antes de firmar.`
    : "",
);

async function recargar() {
  cargando.value = true;
  error.value = "";
  try {
    const params = {};
    if (motivo.value) params.motivo = motivo.value;
    if (destino.value) params.destino = destino.value;
    const r = await documentosApi.certificadoSalud(route.params.id, params);
    d.value = r.data;
  } catch (e) {
    error.value = e.message;
  } finally {
    cargando.value = false;
  }
}

onMounted(recargar);
</script>

<style scoped>
.mini-input {
  height: 30px;
  padding: 0 9px;
  font-size: 12px;
  border: 1px solid var(--line-strong);
  border-radius: 7px;
  width: 170px;
}
</style>
