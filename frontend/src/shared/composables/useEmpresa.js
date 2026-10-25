import { ref, computed } from "vue";
import { empresasApi } from "../../modules/configuracion/api/empresas.api.js";

/**
 * Empresa (sede) activa del usuario, pedida una sola vez y compartida: el
 * sidebar muestra el nombre y compras/facturación usan la tasa de IGV
 * configurada en vez de un 18% fijo.
 */
const empresa = ref(null);
let pendiente = null;

function cargarEmpresa({ forzar = false } = {}) {
  if (pendiente && !forzar) return pendiente;
  pendiente = empresasApi.actual()
    .then((r) => { empresa.value = r.data ?? null; return empresa.value; })
    .catch(() => { pendiente = null; return null; });
  return pendiente;
}

/** Tasa de IGV como fracción (0.18). Si no hay empresa, el 18% legal vigente. */
const igvTasa = computed(() => {
  const t = Number(empresa.value?.igv_tasa);
  return Number.isFinite(t) && t >= 0 && t < 1 ? t : 0.18;
});

export function useEmpresa() {
  cargarEmpresa();
  return { empresa, igvTasa, cargarEmpresa };
}
