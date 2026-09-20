<template>
  <DocumentoBase :cargando="cargando" :error="error" :aviso="aviso" :auto="auto">
    <div v-if="d" class="hoja">
      <Membrete :emisor="d.emisor" tipo="Consentimiento informado" :numero="d.cirugia?.codigo" />

      <h1 class="doc-titulo">Consentimiento informado para procedimiento quirúrgico</h1>

      <FichaPaciente :paciente="d.paciente" :propietario="d.propietario" />

      <section class="doc-bloque">
        <h3>Procedimiento</h3>
        <div class="doc-campos">
          <div class="doc-campo ancho">
            <span class="k">Intervención:</span><span class="v">{{ d.cirugia?.nombre }}</span>
          </div>
          <div class="doc-campo">
            <span class="k">Fecha programada:</span>
            <span class="v">{{ d.cirugia?.fecha_programada ? fmtFechaHora(d.cirugia.fecha_programada) : "Por definir" }}</span>
          </div>
          <div class="doc-campo">
            <span class="k">Anestesia:</span><span class="v">{{ d.cirugia?.anestesia_tipo || "Según evaluación" }}</span>
          </div>
          <div v-if="d.cirugia?.precio_referencial" class="doc-campo">
            <span class="k">Costo referencial:</span>
            <span class="v">{{ fmtSoles(d.cirugia.precio_referencial) }}</span>
          </div>
          <div v-if="d.cirugia?.descripcion" class="doc-campo ancho">
            <span class="k">Descripción:</span><span class="v">{{ d.cirugia.descripcion }}</span>
          </div>
        </div>
      </section>

      <section class="doc-bloque">
        <h3>Declaración</h3>
        <p class="doc-texto">
          Yo, <strong>{{ d.propietario?.nombre }}</strong>, identificado(a) con
          {{ d.propietario?.tipo_documento }} N.º
          <strong class="mono-doc">{{ d.propietario?.numero_documento }}</strong>, en calidad de
          propietario(a) o responsable del paciente <strong>{{ d.paciente?.nombre }}</strong>
          ({{ d.paciente?.especie }}<template v-if="d.paciente?.raza">, {{ d.paciente.raza }}</template>),
          declaro que se me ha explicado en términos comprensibles la naturaleza del procedimiento
          indicado, sus beneficios esperados, las alternativas disponibles y los riesgos inherentes
          a toda intervención quirúrgica y anestésica, incluida la posibilidad de complicaciones y
          de muerte del animal, y que he podido hacer las preguntas que consideré necesarias.
        </p>
      </section>

      <!-- El texto legal lo redacta cada clínica en Configuración → Cláusulas.
           Si no cargó ninguna, se imprime igual: el bloque de arriba y las
           firmas son lo que sustenta el acto. -->
      <section v-if="(d.clausulas ?? []).length" class="doc-bloque">
        <h3>Condiciones</h3>
        <div v-for="(c, i) in d.clausulas" :key="i" class="doc-clausula">
          <h4>{{ i + 1 }}. {{ c.titulo }}</h4>
          <p class="doc-texto">{{ c.contenido }}</p>
        </div>
      </section>

      <div v-else class="doc-aviso">
        Esta clínica todavía no cargó sus cláusulas de consentimiento.
        Se configuran en <strong>Configuración → Catálogos → Cláusulas</strong> y se imprimen aquí.
      </div>

      <section class="doc-bloque">
        <h3>Autorización</h3>
        <p class="doc-texto">
          En consecuencia, <strong>autorizo</strong> al equipo médico de
          {{ d.emisor?.nombre_comercial }} a realizar el procedimiento descrito, así como las
          maniobras adicionales que resulten necesarias durante el acto quirúrgico para preservar
          la vida del paciente.
        </p>
        <div class="doc-campos" style="margin-top: 8px">
          <div class="doc-campo"><span class="k">Lugar y fecha:</span><span class="v">{{ d.emisor?.distrito || "—" }}, {{ fmtDate(hoy) }}</span></div>
        </div>
      </section>

      <Firmas :firmas="firmas" />
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
import { fmtDate, fmtFechaHora, fmtSoles } from "../../../shared/components/ui/format.js";

const route = useRoute();
const d = ref(null);
const cargando = ref(true);
const error = ref("");
const hoy = new Date();
const auto = computed(() => route.query.auto === "1");

// Quien firma primero es el propietario: es su consentimiento, no el del
// equipo médico. El anestesista aparece sólo si se le asignó.
const firmas = computed(() => [
  { nombre: d.value?.propietario?.nombre, rol: "Propietario / responsable" },
  d.value?.profesional,
  d.value?.anestesista?.nombre ? { ...d.value.anestesista, rol: "Anestesista" } : null,
]);

const aviso = computed(() =>
  d.value?.cirugia?.consentimiento_firmado
    ? "Esta cirugía ya figura con el consentimiento firmado."
    : "",
);

onMounted(async () => {
  try {
    const r = await documentosApi.consentimiento(route.params.id);
    d.value = r.data;
  } catch (e) {
    error.value = e.message;
  } finally {
    cargando.value = false;
  }
});
</script>
