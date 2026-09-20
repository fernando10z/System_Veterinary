<template>
  <DocumentoBase :cargando="cargando" :error="error" :aviso="aviso" :auto="auto">
    <div v-if="d" class="hoja">
      <Membrete
        :emisor="d.emisor"
        tipo="Alta hospitalaria"
        :numero="d.hospitalizacion?.codigo"
        :subtitulo="`${d.hospitalizacion?.dias} día(s)`"
      />

      <h1 class="doc-titulo">Informe de alta hospitalaria</h1>

      <FichaPaciente :paciente="d.paciente" :propietario="d.propietario" />

      <section class="doc-bloque">
        <h3>Internamiento</h3>
        <div class="doc-campos">
          <div class="doc-campo">
            <span class="k">Ingreso:</span><span class="v">{{ fmtFechaHora(d.hospitalizacion?.fecha_ingreso) }}</span>
          </div>
          <div class="doc-campo">
            <span class="k">Alta:</span>
            <span class="v">{{ d.hospitalizacion?.fecha_alta ? fmtFechaHora(d.hospitalizacion.fecha_alta) : "En curso" }}</span>
          </div>
          <div class="doc-campo"><span class="k">Días:</span><span class="v">{{ d.hospitalizacion?.dias }}</span></div>
          <div class="doc-campo"><span class="k">Ubicación:</span><span class="v">{{ d.hospitalizacion?.jaula || "—" }}</span></div>
          <div class="doc-campo"><span class="k">Condición de egreso:</span><span class="v">{{ capitalizar(d.hospitalizacion?.estado) }}</span></div>
          <div class="doc-campo ancho"><span class="k">Motivo de ingreso:</span><span class="v">{{ d.hospitalizacion?.motivo }}</span></div>
          <div class="doc-campo ancho"><span class="k">Diagnóstico:</span><span class="v">{{ d.hospitalizacion?.diagnostico || "—" }}</span></div>
        </div>
      </section>

      <section v-if="(d.medicacion ?? []).length" class="doc-bloque">
        <h3>Medicación administrada durante el internamiento</h3>
        <table class="doc-tabla">
          <thead><tr><th>Producto</th><th class="num">Cantidad</th><th>Fecha</th></tr></thead>
          <tbody>
            <tr v-for="(m, i) in d.medicacion" :key="i">
              <td>{{ m.producto }}</td>
              <td class="num">{{ m.cantidad }}</td>
              <td class="mono-doc">{{ fmtFechaHora(m.fecha) }}</td>
            </tr>
          </tbody>
        </table>
      </section>

      <section v-if="(d.evoluciones ?? []).length" class="doc-bloque">
        <h3>Evolución</h3>
        <table class="doc-tabla">
          <thead>
            <tr>
              <th>Fecha y hora</th>
              <th class="num">T.º</th>
              <th class="num">FC</th>
              <th class="num">FR</th>
              <th>Come</th>
              <th>Orina</th>
              <th>Defeca</th>
              <th style="width: 34%">Observación</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(e, i) in d.evoluciones" :key="i">
              <td class="mono-doc">{{ fmtFechaHora(e.fecha_hora) }}</td>
              <td class="num">{{ e.temperatura_c ?? "—" }}</td>
              <td class="num">{{ e.frecuencia_cardiaca ?? "—" }}</td>
              <td class="num">{{ e.frecuencia_respiratoria ?? "—" }}</td>
              <td>{{ siNo(e.come) }}</td>
              <td>{{ siNo(e.orina) }}</td>
              <td>{{ siNo(e.defeca) }}</td>
              <td>
                {{ e.nota || "—" }}
                <div v-if="e.registrado_por" style="color: #5a625f">{{ e.registrado_por }}</div>
              </td>
            </tr>
          </tbody>
        </table>
      </section>

      <section class="doc-bloque">
        <h3>Indicaciones al alta</h3>
        <p class="doc-texto">{{ d.hospitalizacion?.indicaciones_alta || "Sin indicaciones registradas." }}</p>
      </section>

      <Firmas
        :firmas="[
          d.profesional,
          { nombre: d.propietario?.nombre, rol: 'Recibe conforme' },
        ]"
      />
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
import { fmtFechaHora, capitalizar } from "../../../shared/components/ui/format.js";

const route = useRoute();
const d = ref(null);
const cargando = ref(true);
const error = ref("");
const auto = computed(() => route.query.auto === "1");

// null no es "no": es que nadie lo registró en ese turno.
const siNo = (v) => (v === true ? "Sí" : v === false ? "No" : "—");

const aviso = computed(() =>
  d.value && !d.value.hospitalizacion?.fecha_alta
    ? "El paciente sigue internado: este informe es un corte, no el alta definitiva."
    : "",
);

onMounted(async () => {
  try {
    const r = await documentosApi.altaHospitalaria(route.params.id);
    d.value = r.data;
  } catch (e) {
    error.value = e.message;
  } finally {
    cargando.value = false;
  }
});
</script>
