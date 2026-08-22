import { ValidationError } from "class-validator";

// Traducción de errores de class-validator a español, por TIPO de constraint.
// Centralizar acá evita poner { message } en cada uno de los ~140 DTOs.
//
// Etiqueta del campo: artículo + nombre legible. Para campos no listados se
// "humaniza" el nombre de la propiedad (camelCase/snake_case → palabras).

const ETIQUETAS: Record<string, string> = {
  origen: "El origen",
  razonSocial: "La razón social",
  tipoDoc: "El tipo de documento",
  numDoc: "El número de documento",
  contactoNombres: "El nombre del contacto",
  contactoTelefono: "El teléfono",
  contactoCorreo: "El correo",
  vendedorId: "El vendedor",
  empresaDestinoId: "La empresa destino",
  notas: "Las notas",
  campaniaId: "La campaña",
  motivo: "El motivo",
  email: "El correo",
  password: "La contraseña",
};

// Frase por tipo de constraint, redactada para encajar tras la etiqueta:
//   "El correo" + " no es válido" → "El correo no es válido".
const FRASES: Record<string, string> = {
  isEmail: "no es válido",
  isNotEmpty: "es obligatorio",
  isDefined: "es obligatorio",
  isString: "debe ser texto",
  isInt: "debe ser un número entero",
  isNumber: "debe ser un número",
  isNumberString: "debe ser un número",
  isPositive: "debe ser un número positivo",
  isUuid: "no es válido",
  isUUID: "no es válido",
  isIn: "tiene un valor no permitido",
  isEnum: "tiene un valor no permitido",
  maxLength: "es demasiado largo",
  minLength: "es demasiado corto",
  max: "supera el valor máximo",
  min: "es menor al mínimo permitido",
  isDateString: "debe ser una fecha válida",
  isDate: "debe ser una fecha válida",
  isBoolean: "debe ser verdadero o falso",
  matches: "tiene un formato inválido",
  isArray: "debe ser una lista",
  arrayNotEmpty: "no puede estar vacío",
};

function humanizar(prop: string): string {
  const s = prop
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/_/g, " ")
    .toLowerCase()
    .trim();
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : prop;
}

function etiqueta(prop: string): string {
  return ETIQUETAS[prop] ?? humanizar(prop);
}

// Aplana los ValidationError (incl. hijos anidados) a mensajes en español.
export function mensajesValidacionES(errors: ValidationError[]): string[] {
  const out: string[] = [];
  for (const e of errors) {
    if (e.constraints) {
      for (const key of Object.keys(e.constraints)) {
        out.push(`${etiqueta(e.property)} ${FRASES[key] ?? "no es válido"}`);
      }
    }
    if (e.children?.length) {
      out.push(...mensajesValidacionES(e.children));
    }
  }
  return out;
}
