import { ArgumentMetadata, Injectable, PipeTransform } from "@nestjs/common";

/**
 * Limpia el texto que entra por el cuerpo de la petición ANTES de validarlo.
 *
 * La normalización de fondo vive en la base (triggers de `11_normalizacion.sql`),
 * pero la validación del DTO corre mucho antes: sin este paso, un correo pegado
 * con espacios (`"  Ana@GMAIL.COM  "`) o un DNI escrito `12.345.678` se rechazan
 * con "no es válido" aunque el sistema los habría guardado perfectamente. El
 * usuario ve un error por algo que no es un error.
 *
 * Solo hace el saneo mínimo y seguro:
 *   - recorta extremos y colapsa espacios internos,
 *   - convierte la cadena vacía en `null` (que es lo que significa),
 *   - deja intactas las contraseñas: ahí un espacio es parte del secreto.
 */
@Injectable()
export class SanearEntradaPipe implements PipeTransform {
  /** Campos donde el espacio es significativo y no se toca. */
  private static readonly INTOCABLES = /password|token|hash|firma|observaciones|descripcion|notas|motivo|diagnostico|tratamiento|anamnesis/i;

  transform(valor: unknown, meta: ArgumentMetadata): unknown {
    // Solo lo que escribe el usuario. Los objetos que arma el propio backend
    // (el payload del JWT, por ejemplo) no se tocan.
    if (meta.type !== "body" && meta.type !== "query") return valor;
    return this.limpiar(valor, "");
  }

  private limpiar(valor: unknown, clave: string): unknown {
    if (typeof valor === "string") {
      if (SanearEntradaPipe.INTOCABLES.test(clave)) return valor;
      const limpio = valor.trim().replace(/\s+/g, " ");
      return limpio === "" ? null : limpio;
    }
    if (Array.isArray(valor)) return valor.map((v) => this.limpiar(v, clave));
    if (valor && typeof valor === "object" && valor.constructor === Object) {
      const salida: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(valor)) salida[k] = this.limpiar(v, k);
      return salida;
    }
    return valor;
  }
}
