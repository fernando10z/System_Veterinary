<template>
  <DocumentoBase :cargando="cargando" :error="error" :auto="auto">
    <div v-if="d" class="hoja">
      <Membrete :emisor="d.emisor" tipo="Historia clínica" :numero="d.paciente?.codigo" />

      <h1 class="doc-titulo">Historia clínica</h1>

      <FichaPaciente :paciente="d.paciente" :propietario="d.propietario" />

      <section v-if="(d.vacunas ?? []).length" class="doc-bloque">
        <h3>Vacunación</h3>
        <table class="doc-tabla">
          <thead>
            <tr><th>Vacuna</th><th>Lote</th><th>Aplicación</th><th>Refuerzo</th><th>Profesional</th></tr>
          </thead>
          <tbody>
            <tr v-for="(v, i) in d.vacunas" :key="i">
              <td>{{ v.nombre_vacuna }}</td>
              <td class="mono-doc">{{ v.lote || "—" }}</td>
              <td class="mono-doc">{{ fmtDate(v.fecha_aplicacion) }}</td>
              <td class="mono-doc">{{ v.proximo_refuerzo ? fmtDate(v.proximo_refuerzo) : "—" }}</td>
              <td>{{ v.veterinario || "—" }}</td>
            </tr>
          </tbody>
        </table>
      </section>

      <section class="doc-bloque">
        <h3>Consultas</h3>
        <p v-if="!(d.consultas ?? []).length" class="doc-texto">
          Sin consultas cerradas registradas.
        </p>

        <!-- Una consulta por bloque, en formato SOAP: es como la lee el colega
             que recibe la derivación. -->
        <article v-for="(c, i) in d.consultas" :key="i" class="consulta">
          <header class="consulta-head">
            <strong>{{ fmtFechaHora(c.fecha) }}</strong>
            <span class="mono-doc">{{ c.codigo || "" }}</span>
            <span class="sep"></span>
            <span>
              {{ c.veterinario || "—" }}
              <template v-if="c.colegiatura">· C.M.V.P. {{ c.colegiatura }}</template>
            </span>
          </header>

          <div class="doc-campos" style="margin-bottom: 5px">
            <div class="doc-campo ancho"><span class="k">Motivo:</span><span class="v">{{ c.motivo }}</span></div>
            <div v-if="c.anamnesis" class="doc-campo ancho">
              <span class="k">Anamnesis:</span><span class="v">{{ c.anamnesis }}</span>
            </div>
          </div>

          <div class="constantes">
            <span v-if="c.peso_kg">Peso {{ c.peso_kg }} kg</span>
            <span v-if="c.temperatura_c">T.º {{ c.temperatura_c }} °C</span>
            <span v-if="c.frecuencia_cardiaca">FC {{ c.frecuencia_cardiaca }}</span>
            <span v-if="c.frecuencia_respiratoria">FR {{ c.frecuencia_respiratoria }}</span>
            <span v-if="c.mucosas">Mucosas {{ c.mucosas }}</span>
            <span v-if="c.condicion_corporal">CC {{ c.condicion_corporal }}/9</span>
          </div>

          <div class="doc-campos">
            <div v-if="c.examen_fisico" class="doc-campo ancho">
              <span class="k">Examen físico:</span><span class="v">{{ c.examen_fisico }}</span>
            </div>
            <div class="doc-campo ancho">
              <span class="k">Diagnóstico:</span><span class="v">{{ c.diagnostico || "—" }}</span>
            </div>
            <div v-if="c.diagnostico_diferencial" class="doc-campo ancho">
              <span class="k">Diferencial:</span><span class="v">{{ c.diagnostico_diferencial }}</span>
            </div>
            <div v-if="c.pronostico" class="doc-campo">
              <span class="k">Pronóstico:</span><span class="v">{{ capitalizar(c.pronostico) }}</span>
            </div>
            <div v-if="c.plan_terapeutico" class="doc-campo ancho">
              <span class="k">Plan:</span><span class="v">{{ c.plan_terapeutico }}</span>
            </div>
            <div v-if="c.prescripcion" class="doc-campo ancho">
              <span class="k">Prescripción:</span><span class="v">{{ c.prescripcion }}</span>
            </div>
            <div v-if="c.indicaciones_casa" class="doc-campo ancho">
              <span class="k">Indicaciones:</span><span class="v">{{ c.indicaciones_casa }}</span>
            </div>
          </div>
        </article>
      </section>

      <section v-if="(d.linea_tiempo ?? []).length" class="doc-bloque">
        <h3>Otros registros</h3>
        <table class="doc-tabla">
          <thead><tr><th style="width: 16%">Fecha</th><th style="width: 16%">Tipo</th><th>Registro</th></tr></thead>
          <tbody>
            <tr v-for="(e, i) in otrosEventos" :key="i">
              <td class="mono-doc">{{ fmtDate(e.fecha) }}</td>
              <td>{{ capitalizar(e.tipo_evento) }}</td>
              <td>
                {{ e.titulo }}
                <div v-if="e.resumen" style="color: #5a625f">{{ e.resumen }}</div>
              </td>
            </tr>
          </tbody>
        </table>
      </section>

      <p class="doc-texto" style="margin-top: 12px; color: #5a625f">
        Documento emitido el {{ fmtDate(d.fecha_emision) }} a solicitud del propietario. Recoge la
        atención registrada en {{ d.emisor?.nombre_comercial }}.
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
import { fmtDate, fmtFechaHora, capitalizar } from "../../../shared/components/ui/format.js";

const route = useRoute();
const d = ref(null);
const cargando = ref(true);
const error = ref("");
const auto = computed(() => route.query.auto === "1");

// Las consultas ya van desarrolladas arriba: repetirlas en la línea de tiempo
// alarga el documento sin agregar nada.
const otrosEventos = computed(() =>
  (d.value?.linea_tiempo ?? []).filter((e) => e.tipo_evento !== "consulta"),
);

onMounted(async () => {
  try {
    const r = await documentosApi.historiaClinica(route.params.id);
    d.value = r.data;
  } catch (e) {
    error.value = e.message;
  } finally {
    cargando.value = false;
  }
});
</script>

<style scoped>
.consulta {
  border-left: 2px solid #d8dedb;
  padding: 0 0 9px 10px;
  margin-bottom: 11px;
  break-inside: avoid;
}
.consulta-head {
  display: flex;
  gap: 8px;
  align-items: baseline;
  font-size: 11px;
  margin-bottom: 4px;
  color: #4a5250;
}
.consulta-head .sep { flex: 1 }
.constantes {
  display: flex;
  flex-wrap: wrap;
  gap: 4px 10px;
  font-size: 10.5px;
  color: #232b2a;
  margin-bottom: 5px;
}
.constantes span {
  background: #f1f4f2;
  border-radius: 4px;
  padding: 1px 6px;
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
}
</style>
