<template>
  <DocumentoBase :cargando="cargando" :error="error" :aviso="aviso" :auto="auto">
    <template #acciones>
      <button class="btn" :class="{ primary: formato === 'a4' }" @click="formato = 'a4'">A4</button>
      <button class="btn" :class="{ primary: formato === 'ticket' }" @click="formato = 'ticket'">
        Ticket 80 mm
      </button>
    </template>

    <div v-if="c" :class="['hoja', formato === 'ticket' && 'hoja--ticket']">
      <!-- ---------------- Ticket 80 mm ---------------- -->
      <template v-if="formato === 'ticket'">
        <div style="text-align: center">
          <div style="font-size: 13px; font-weight: 700">{{ c.emisor?.nombre_comercial }}</div>
          <div>{{ c.emisor?.razon_social }}</div>
          <div>RUC {{ c.emisor?.ruc }}</div>
          <div v-if="c.emisor?.direccion">{{ c.emisor.direccion }}</div>
          <div v-if="c.emisor?.telefono">T. {{ c.emisor.telefono }}</div>
          <div style="margin: 7px 0; border-top: 1px dashed #101615"></div>
          <div style="font-weight: 700">{{ tituloDoc.toUpperCase() }}</div>
          <div style="font-weight: 700">{{ c.numero_completo }}</div>
        </div>

        <div style="margin: 7px 0; border-top: 1px dashed #101615"></div>
        <div>{{ fmtFechaHora(c.fecha_emision) }}</div>
        <div>{{ c.cliente?.razon_social || c.cliente?.nombre_completo }}</div>
        <div>{{ c.cliente?.tipo_documento }} {{ c.cliente?.numero_documento }}</div>
        <div v-if="c.mascota">Paciente: {{ c.mascota }}</div>

        <div style="margin: 7px 0; border-top: 1px dashed #101615"></div>
        <div v-for="i in c.items" :key="i.id" style="margin-bottom: 4px">
          <div>{{ i.descripcion }}</div>
          <div style="display: flex; justify-content: space-between">
            <span>{{ i.cantidad }} x {{ fmtSoles(i.precio_unitario) }}</span>
            <span>{{ fmtSoles(i.total) }}</span>
          </div>
        </div>

        <div style="margin: 7px 0; border-top: 1px dashed #101615"></div>
        <div style="display: flex; justify-content: space-between"><span>Op. gravada</span><span>{{ fmtSoles(c.subtotal) }}</span></div>
        <div style="display: flex; justify-content: space-between"><span>IGV</span><span>{{ fmtSoles(c.igv) }}</span></div>
        <div style="display: flex; justify-content: space-between; font-weight: 700; font-size: 13px">
          <span>TOTAL</span><span>{{ fmtSoles(c.total) }}</span>
        </div>
        <div v-if="Number(c.saldo_pendiente) > 0" style="display: flex; justify-content: space-between">
          <span>Saldo</span><span>{{ fmtSoles(c.saldo_pendiente) }}</span>
        </div>

        <div v-if="(c.pagos ?? []).length" style="margin-top: 5px">
          <div v-for="p in c.pagos" :key="p.id" style="display: flex; justify-content: space-between">
            <span>{{ capitalizar(p.metodo) }}</span><span>{{ fmtSoles(p.monto_aplicado) }}</span>
          </div>
        </div>

        <div style="margin: 8px 0; border-top: 1px dashed #101615"></div>
        <div style="text-align: center">
          <img v-if="qr" class="doc-qr" :src="qr" alt="Código QR del comprobante" style="margin: 0 auto" />
          <div style="margin-top: 5px; font-size: 9.5px">{{ leyendaSunat }}</div>
          <div style="margin-top: 5px">¡Gracias por cuidar a {{ c.mascota || "tu mascota" }}!</div>
        </div>
      </template>

      <!-- ---------------- A4 ---------------- -->
      <template v-else>
        <Membrete
          :emisor="c.emisor"
          :tipo="tituloDoc"
          :numero="c.numero_completo"
          :subtitulo="`RUC ${c.emisor?.ruc}`"
        />

        <div v-if="c.estado === 'anulado'" class="doc-aviso grave">
          <strong>Comprobante anulado.</strong>
          <template v-if="c.motivo_nota"> {{ c.motivo_nota }}</template>
        </div>

        <div v-if="c.documento_ref" class="doc-aviso">
          Modifica el comprobante <strong class="mono-doc">{{ c.documento_ref.numero_completo }}</strong>.
          <template v-if="c.motivo_nota"> Motivo: {{ c.motivo_nota }}.</template>
        </div>

        <section class="doc-bloque">
          <h3>Adquiriente</h3>
          <div class="doc-campos">
            <div class="doc-campo ancho">
              <span class="k">Señor(es):</span>
              <span class="v">{{ c.cliente?.razon_social || c.cliente?.nombre_completo }}</span>
            </div>
            <div class="doc-campo">
              <span class="k">{{ c.cliente?.tipo_documento }}:</span>
              <span class="v mono-doc">{{ c.cliente?.numero_documento }}</span>
            </div>
            <div class="doc-campo">
              <span class="k">Fecha de emisión:</span>
              <span class="v mono-doc">{{ fmtFechaHora(c.fecha_emision) }}</span>
            </div>
            <div class="doc-campo">
              <span class="k">Moneda:</span>
              <span class="v">{{ c.moneda === "USD" ? "Dólares americanos" : "Soles" }}</span>
            </div>
            <div class="doc-campo">
              <span class="k">Condición:</span>
              <span class="v">{{ esCredito ? `Crédito · vence ${fmtDate(c.fecha_vencimiento)}` : "Contado" }}</span>
            </div>
            <div v-if="c.cliente?.direccion" class="doc-campo ancho">
              <span class="k">Dirección:</span><span class="v">{{ c.cliente.direccion }}</span>
            </div>
            <div v-if="c.mascota" class="doc-campo">
              <span class="k">Paciente:</span><span class="v">{{ c.mascota }}</span>
            </div>
          </div>
        </section>

        <table class="doc-tabla">
          <thead>
            <tr>
              <th style="width: 8%">Cant.</th>
              <th style="width: 8%">U.M.</th>
              <th>Descripción</th>
              <th class="num" style="width: 14%">P. unitario</th>
              <th class="num" style="width: 14%">Importe</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="i in c.items" :key="i.id">
              <td class="num">{{ i.cantidad }}</td>
              <td>{{ i.unidad_medida || "NIU" }}</td>
              <td>
                {{ i.descripcion }}
                <span v-if="i.codigo" class="mono-doc" style="color: #5a625f"> · {{ i.codigo }}</span>
                <template v-if="i.tipo_afectacion_igv === '20'"> (exonerado)</template>
              </td>
              <td class="num">{{ fmtSoles(i.precio_unitario) }}</td>
              <td class="num">{{ fmtSoles(i.total) }}</td>
            </tr>
          </tbody>
        </table>

        <div style="display: flex; gap: 20px; margin-top: 14px; align-items: flex-start">
          <div style="flex: 1">
            <p class="doc-texto"><strong>SON:</strong> {{ enLetras }}</p>
            <div v-if="(c.pagos ?? []).length" style="margin-top: 10px">
              <h3 style="font-size: 10px; letter-spacing: 0.1em; text-transform: uppercase; color: #4a5250">
                Pagos aplicados
              </h3>
              <table class="doc-tabla">
                <tbody>
                  <tr v-for="p in c.pagos" :key="p.id">
                    <td>{{ capitalizar(p.metodo) }}</td>
                    <td class="mono-doc">{{ fmtDate(p.fecha_pago) }}</td>
                    <td class="num">{{ fmtSoles(p.monto_aplicado) }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <div style="width: 240px">
            <table class="doc-tabla">
              <tbody>
                <tr><td>Op. gravada</td><td class="num">{{ fmtSoles(c.subtotal) }}</td></tr>
                <tr v-if="Number(c.descuento_global) > 0">
                  <td>Descuento</td><td class="num">− {{ fmtSoles(c.descuento_global) }}</td>
                </tr>
                <tr><td>IGV</td><td class="num">{{ fmtSoles(c.igv) }}</td></tr>
                <tr style="font-weight: 800; font-size: 12.5px">
                  <td>Importe total</td><td class="num">{{ fmtSoles(c.total) }}</td>
                </tr>
                <tr v-if="Number(c.saldo_pendiente) > 0">
                  <td>Saldo pendiente</td><td class="num">{{ fmtSoles(c.saldo_pendiente) }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div style="display: flex; gap: 16px; margin-top: 20px; align-items: center">
          <img v-if="qr" class="doc-qr" :src="qr" alt="Código QR del comprobante" />
          <div class="doc-texto" style="flex: 1; font-size: 10px; color: #4a5250">
            {{ leyendaSunat }}
            <div v-if="c.hash_cpe" class="mono-doc" style="margin-top: 3px">
              Resumen: {{ c.hash_cpe }}
            </div>
            <div v-if="c.observaciones" style="margin-top: 5px">{{ c.observaciones }}</div>
          </div>
        </div>

        <PieDocumento :emisor="c.emisor" />
      </template>
    </div>
  </DocumentoBase>
</template>

<script setup>
import { ref, computed, onMounted, watch } from "vue";
import { useRoute } from "vue-router";
import QRCode from "qrcode";
import DocumentoBase from "../../../shared/print/DocumentoBase.vue";
import Membrete from "../../../shared/print/Membrete.vue";
import PieDocumento from "../../../shared/print/PieDocumento.vue";
import { facturacionApi } from "../../facturacion/api/facturacion.api.js";
import { fmtSoles, fmtDate, fmtFechaHora, capitalizar } from "../../../shared/components/ui/format.js";
import { montoEnLetras } from "../../../shared/print/monto-en-letras.js";

const route = useRoute();
const c = ref(null);
const cargando = ref(true);
const error = ref("");
const qr = ref("");
// El ticket es el formato del mostrador; el A4, el que se manda por correo.
const formato = ref(route.query.formato === "ticket" ? "ticket" : "a4");
const auto = computed(() => route.query.auto === "1");

const TITULOS = {
  factura: "Factura electrónica",
  boleta: "Boleta de venta electrónica",
  nota_credito: "Nota de crédito electrónica",
  nota_debito: "Nota de débito electrónica",
  nota_venta: "Nota de venta",
};
const tituloDoc = computed(() => TITULOS[c.value?.tipo] ?? "Comprobante");
const esCredito = computed(
  () => c.value?.fecha_vencimiento &&
    new Date(c.value.fecha_vencimiento) > new Date(String(c.value.fecha_emision).slice(0, 10)),
);
const enLetras = computed(() => montoEnLetras(c.value?.total, c.value?.moneda));

/** La nota de venta es interna: no lleva la leyenda de SUNAT ni QR. */
const esElectronico = computed(() => c.value && c.value.tipo !== "nota_venta");

const leyendaSunat = computed(() => {
  if (!esElectronico.value) return "Documento interno. No tiene validez tributaria.";
  if (c.value?.estado === "aceptado_sunat") {
    return "Representación impresa del comprobante electrónico, aceptado por SUNAT. " +
      "Consulte su validez en www.sunat.gob.pe";
  }
  return "Representación impresa del comprobante electrónico. " +
    "Consulte su validez en www.sunat.gob.pe";
});

const aviso = computed(() => {
  if (!esElectronico.value) return "";
  if (c.value?.estado === "aceptado_sunat") return "";
  return "Este comprobante todavía no fue aceptado por SUNAT.";
});

/**
 * Contenido del QR según SUNAT: RUC | tipo | serie | número | IGV | total |
 * fecha | tipo doc. adquiriente | nro. doc. adquiriente | hash del CPE.
 */
const TIPO_SUNAT = { factura: "01", boleta: "03", nota_credito: "07", nota_debito: "08" };
const TIPO_DOC_ID = { DNI: "1", CE: "4", RUC: "6", PASAPORTE: "7" };

async function generarQr() {
  if (!c.value || !esElectronico.value) return;
  const partes = [
    c.value.emisor?.ruc ?? "",
    TIPO_SUNAT[c.value.tipo] ?? "",
    c.value.serie ?? "",
    c.value.numero ?? "",
    Number(c.value.igv ?? 0).toFixed(2),
    Number(c.value.total ?? 0).toFixed(2),
    String(c.value.fecha_emision ?? "").slice(0, 10),
    TIPO_DOC_ID[c.value.cliente?.tipo_documento] ?? "1",
    c.value.cliente?.numero_documento ?? "",
    c.value.hash_cpe ?? "",
  ];
  qr.value = await QRCode.toDataURL(partes.join("|"), {
    margin: 0,
    width: 200,
    errorCorrectionLevel: "M",
  });
}

watch(c, generarQr);

onMounted(async () => {
  try {
    const r = await facturacionApi.obtener(route.params.id);
    c.value = r.data;
  } catch (e) {
    error.value = e.message;
  } finally {
    cargando.value = false;
  }
});
</script>
