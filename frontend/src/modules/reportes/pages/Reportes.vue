<template>
  <div>
    <PageHeader
      eyebrow="Administración"
      title="Reportes"
      :subtitle="`Del ${fmtDate(desde)} al ${fmtDate(hasta)}`"
    >
      <template #actions>
        <div class="fil">
          <CalendarRange :size="14" />
          <input v-model="desde" type="date" @change="cargar" />
        </div>
        <div class="fil">
          <span class="muted">a</span>
          <input v-model="hasta" type="date" @change="cargar" />
        </div>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="cargando ? 'spin' : ''" /> Actualizar
        </button>
      </template>
    </PageHeader>

    <div class="toggle-group" style="margin-bottom: 16px">
      <button :class="tab === 'ventas' ? 'active' : ''" @click="tab = 'ventas'">Ventas</button>
      <button :class="tab === 'clinico' ? 'active' : ''" @click="tab = 'clinico'">Clínico</button>
      <button :class="tab === 'inventario' ? 'active' : ''" @click="tab = 'inventario'">Inventario</button>
      <button v-if="puedeEjecutivo" :class="tab === 'ejecutivo' ? 'active' : ''" @click="tab = 'ejecutivo'">Ejecutivo</button>
    </div>

    <!-- ---------- Ventas ---------- -->
    <template v-if="tab === 'ventas'">
      <div class="stat-row">
        <div class="stat">
          <div class="stat-label">Facturado <span class="icon-tile"><Receipt :size="14" /></span></div>
          <div class="stat-val">{{ fmtSoles(ventas.resumen?.facturado) }}</div>
          <div class="stat-meta">{{ ventas.resumen?.documentos ?? 0 }} documentos</div>
        </div>
        <div class="stat">
          <div class="stat-label">Cobrado <span class="icon-tile"><Wallet :size="14" /></span></div>
          <div class="stat-val">{{ fmtSoles(ventas.resumen?.cobrado) }}</div>
          <div class="stat-meta">{{ fmtSoles(ventas.resumen?.pendiente) }} pendiente</div>
        </div>
        <div class="stat">
          <div class="stat-label">IGV <span class="icon-tile amber"><Landmark :size="14" /></span></div>
          <div class="stat-val">{{ fmtSoles(ventas.resumen?.igv) }}</div>
          <div class="stat-meta">del periodo</div>
        </div>
        <div class="stat">
          <div class="stat-label">Ticket promedio <span class="icon-tile violet"><TrendingUp :size="14" /></span></div>
          <div class="stat-val">{{ fmtSoles(ventas.resumen?.ticket_promedio) }}</div>
          <div class="stat-meta">por comprobante</div>
        </div>
      </div>

      <div class="rep-cols">
        <TablaReporte
          titulo="Por servicio"
          :icono="Stethoscope"
          :filas="ventas.por_servicio ?? []"
          :columnas="[
            { k: 'servicio', l: 'Servicio' },
            { k: 'veces', l: 'Veces', num: true },
            { k: 'ingresos', l: 'Ingresos', num: true, money: true },
          ]"
        />
        <TablaReporte
          titulo="Por método de pago"
          :icono="CreditCard"
          :filas="ventas.por_metodo_pago ?? []"
          :columnas="[
            { k: 'metodo', l: 'Método', cap: true },
            { k: 'operaciones', l: 'Operaciones', num: true },
            { k: 'total', l: 'Total', num: true, money: true },
          ]"
        />
        <TablaReporte
          titulo="Por veterinario"
          :icono="Users"
          :filas="ventas.por_veterinario ?? []"
          :columnas="[
            { k: 'veterinario', l: 'Veterinario' },
            { k: 'atenciones', l: 'Atenciones', num: true },
            { k: 'ingresos', l: 'Ingresos', num: true, money: true },
          ]"
        />
        <TablaReporte
          titulo="Por tipo de comprobante"
          :icono="Receipt"
          :filas="ventas.por_tipo ?? []"
          :columnas="[
            { k: 'tipo', l: 'Tipo', cap: true },
            { k: 'documentos', l: 'Documentos', num: true },
            { k: 'total', l: 'Total', num: true, money: true },
          ]"
        />
      </div>
    </template>

    <!-- ---------- Clínico ---------- -->
    <template v-else-if="tab === 'clinico'">
      <div class="stat-row">
        <div class="stat">
          <div class="stat-label">Consultas <span class="icon-tile"><Stethoscope :size="14" /></span></div>
          <div class="stat-val">{{ clinico.resumen?.consultas ?? 0 }}</div>
          <div class="stat-meta">atenciones registradas</div>
        </div>
        <div class="stat">
          <div class="stat-label">Cirugías <span class="icon-tile violet"><Scissors :size="14" /></span></div>
          <div class="stat-val">{{ clinico.resumen?.cirugias ?? 0 }}</div>
          <div class="stat-meta">realizadas</div>
        </div>
        <div class="stat">
          <div class="stat-label">Vacunas <span class="icon-tile"><Syringe :size="14" /></span></div>
          <div class="stat-val">{{ clinico.resumen?.vacunas ?? 0 }}</div>
          <div class="stat-meta">{{ clinico.resumen?.desparasitaciones ?? 0 }} desparasitaciones</div>
        </div>
        <div class="stat">
          <div class="stat-label">Asistencia a citas <span class="icon-tile amber"><CalendarCheck :size="14" /></span></div>
          <div class="stat-val">{{ clinico.citas?.tasa_asistencia ?? 0 }}<span class="unit">%</span></div>
          <div class="stat-meta">
            {{ clinico.citas?.no_asistio ?? 0 }} no asistieron · {{ clinico.citas?.canceladas ?? 0 }} canceladas
          </div>
        </div>
      </div>

      <div class="rep-cols">
        <TablaReporte
          titulo="Diagnósticos más frecuentes"
          :icono="ClipboardList"
          :filas="clinico.diagnosticos_frecuentes ?? []"
          :columnas="[
            { k: 'diagnostico', l: 'Diagnóstico' },
            { k: 'casos', l: 'Casos', num: true },
          ]"
        />
        <TablaReporte
          titulo="Atenciones por especie"
          :icono="PawPrint"
          :filas="clinico.por_especie ?? []"
          :columnas="[
            { k: 'especie', l: 'Especie' },
            { k: 'atenciones', l: 'Atenciones', num: true },
          ]"
        />
      </div>
    </template>

    <!-- ---------- Inventario ---------- -->
    <template v-else-if="tab === 'inventario'">
      <div class="stat-row">
        <div class="stat">
          <div class="stat-label">Valor a costo <span class="icon-tile"><Package :size="14" /></span></div>
          <div class="stat-val">{{ fmtSoles(inventario.valorizacion?.valor_compra) }}</div>
          <div class="stat-meta">{{ inventario.valorizacion?.productos ?? 0 }} productos</div>
        </div>
        <div class="stat">
          <div class="stat-label">Valor a venta <span class="icon-tile"><TrendingUp :size="14" /></span></div>
          <div class="stat-val">{{ fmtSoles(inventario.valorizacion?.valor_venta) }}</div>
          <div class="stat-meta">{{ inventario.valorizacion?.unidades ?? 0 }} unidades</div>
        </div>
        <div class="stat">
          <div class="stat-label">Stock crítico <span class="icon-tile amber"><PackageX :size="14" /></span></div>
          <div class="stat-val">{{ inventario.valorizacion?.criticos ?? 0 }}</div>
          <div class="stat-meta">{{ inventario.valorizacion?.agotados ?? 0 }} agotados</div>
        </div>
        <div class="stat">
          <div class="stat-label">Mermas <span class="icon-tile violet"><Trash2 :size="14" /></span></div>
          <div class="stat-val">{{ inventario.movimientos?.mermas ?? 0 }}<span class="unit">unid.</span></div>
          <div class="stat-meta">
            {{ inventario.movimientos?.entradas ?? 0 }} entradas · {{ inventario.movimientos?.salidas ?? 0 }} salidas
          </div>
        </div>
      </div>

      <div class="rep-cols">
        <TablaReporte
          titulo="Más consumidos"
          :icono="ArrowDownUp"
          :filas="inventario.mas_consumidos ?? []"
          :columnas="[
            { k: 'producto', l: 'Producto' },
            { k: 'salidas', l: 'Salidas', num: true },
            { k: 'stock_actual', l: 'Stock', num: true },
          ]"
        />
        <TablaReporte
          titulo="Valorización por tipo"
          :icono="Package"
          :filas="inventario.por_tipo ?? []"
          :columnas="[
            { k: 'tipo', l: 'Tipo', cap: true },
            { k: 'productos', l: 'Productos', num: true },
            { k: 'valor', l: 'Valor', num: true, money: true },
          ]"
        />
      </div>
    </template>

    <!-- ---------- Ejecutivo ---------- -->
    <template v-else>
      <div class="rep-cols">
        <TablaReporte
          titulo="Comparativo por sede"
          :icono="Building2"
          :filas="ejecutivo.por_sede ?? []"
          :columnas="[
            { k: 'sede', l: 'Sede' },
            { k: 'citas', l: 'Citas', num: true },
            { k: 'facturado', l: 'Facturado', num: true, money: true },
            { k: 'por_cobrar', l: 'Por cobrar', num: true, money: true },
          ]"
        />
        <TablaReporte
          titulo="Clientes que más facturan"
          :icono="Users"
          :filas="ejecutivo.top_clientes ?? []"
          :columnas="[
            { k: 'cliente', l: 'Cliente' },
            { k: 'mascotas', l: 'Mascotas', num: true },
            { k: 'facturado', l: 'Facturado', num: true, money: true },
          ]"
        />
      </div>

      <section class="module-panel">
        <header class="module-panel-head">
          <h2><span class="head-icon"><Calculator :size="14" /></span> Margen aproximado</h2>
        </header>
        <div class="module-panel-body margen">
          <div><span>Ingresos facturados</span><span class="mono">{{ fmtSoles(ejecutivo.margen?.ingresos) }}</span></div>
          <div><span>Costo de insumos consumidos</span><span class="mono">− {{ fmtSoles(ejecutivo.margen?.costo_insumos) }}</span></div>
          <div><span>Compras del periodo</span><span class="mono">{{ fmtSoles(ejecutivo.margen?.compras) }}</span></div>
          <div class="total">
            <span>Margen bruto estimado</span>
            <span class="mono">{{ fmtSoles(margenBruto) }}</span>
          </div>
        </div>
      </section>
    </template>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, watch } from "vue";
import {
  Receipt, Wallet, Landmark, TrendingUp, Stethoscope, CreditCard, Users,
  Scissors, Syringe, CalendarCheck, ClipboardList, PawPrint, Package, PackageX,
  Trash2, ArrowDownUp, Building2, Calculator, RefreshCw, CalendarRange,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import TablaReporte from "../components/TablaReporte.vue";
import { reportesApi } from "../api/reportes.api.js";
import { useAuth } from "../../../shared/composables/useAuth.js";
import { fmtSoles, fmtDate } from "../../../shared/components/ui/format.js";

const { hasPermission } = useAuth();
const puedeEjecutivo = computed(() => hasPermission("reportes:ejecutivo"));

const tab = ref("ventas");
const cargando = ref(false);
const ventas = ref({});
const clinico = ref({});
const inventario = ref({});
const ejecutivo = ref({});

const hoy = new Date();
const inicioMes = new Date(hoy.getFullYear(), hoy.getMonth(), 1);
const desde = ref(inicioMes.toISOString().slice(0, 10));
const hasta = ref(hoy.toISOString().slice(0, 10));

const margenBruto = computed(() => {
  const m = ejecutivo.value.margen ?? {};
  return Number(m.ingresos ?? 0) - Number(m.costo_insumos ?? 0);
});

async function cargar() {
  cargando.value = true;
  const params = { desde: desde.value, hasta: hasta.value };
  try {
    if (tab.value === "ventas") ventas.value = (await reportesApi.ventas(params)).data ?? {};
    else if (tab.value === "clinico") clinico.value = (await reportesApi.clinico(params)).data ?? {};
    else if (tab.value === "inventario") inventario.value = (await reportesApi.inventario(params)).data ?? {};
    else ejecutivo.value = (await reportesApi.ejecutivo(params)).data ?? {};
  } finally {
    cargando.value = false;
  }
}

watch(tab, cargar);
onMounted(cargar);
</script>

<style scoped>
.rep-cols { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-bottom: 16px; align-items: start; }
@media (max-width: 1000px) { .rep-cols { grid-template-columns: 1fr; } }

.margen { display: flex; flex-direction: column; gap: 8px; }
.margen > div { display: flex; justify-content: space-between; font-size: 13px; color: var(--ink-2); }
.margen .total {
  border-top: 1px solid var(--line); padding-top: 10px; margin-top: 4px;
  font-size: 16px; font-weight: 700; color: var(--ink);
}
</style>
