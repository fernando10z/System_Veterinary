// Exportación de tablas a Excel, sin dependencias externas.
//
// Genera un CSV UTF-8 con BOM y separador ";" — que es lo que espera Excel en
// configuración regional es-PE (donde la coma es el separador decimal). Se abre
// con doble click en Excel/LibreOffice sin pasos intermedios.
//
// Uso:
//   exportarExcel("cuentas-por-cobrar", [
//     { key: "razon_social", label: "Cliente" },
//     { key: "saldo", label: "Saldo", tipo: "numero" },
//     { key: "fecha", label: "Emisión", tipo: "fecha" },
//   ], filas);

function celdaTexto(valor, tipo) {
  if (valor === null || valor === undefined) return "";
  if (tipo === "numero") {
    const n = Number(valor);
    if (!Number.isFinite(n)) return "";
    // Decimal con coma: Excel es-PE lo interpreta como número, no como texto.
    return n.toFixed(2).replace(".", ",");
  }
  if (tipo === "fecha") {
    const d = new Date(valor);
    if (Number.isNaN(d.getTime())) return String(valor);
    return d.toLocaleDateString("es-PE", { day: "2-digit", month: "2-digit", year: "numeric" });
  }
  return String(valor);
}

// Escapa según RFC 4180: comillas dobladas y entrecomillado si hay ; " o salto.
function escapar(s) {
  const t = s.replace(/"/g, '""');
  return /[";\n\r]/.test(t) ? `"${t}"` : t;
}

/**
 * @param {string} nombre    nombre base del archivo (sin extensión)
 * @param {Array<{key:string,label:string,tipo?:'texto'|'numero'|'fecha',valor?:Function}>} columnas
 * @param {Array<Object>} filas
 */
export function exportarExcel(nombre, columnas, filas) {
  const lineas = [columnas.map((c) => escapar(c.label)).join(";")];

  for (const fila of filas) {
    lineas.push(
      columnas
        .map((c) => {
          const bruto = c.valor ? c.valor(fila) : fila[c.key];
          return escapar(celdaTexto(bruto, c.tipo));
        })
        .join(";"),
    );
  }

  const contenido = "﻿" + lineas.join("\r\n"); // BOM: Excel respeta los acentos
  const blob = new Blob([contenido], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `${nombre}-${new Date().toLocaleDateString("en-CA")}.csv`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
