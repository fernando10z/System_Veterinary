import { describe, it, expect } from "vitest";
import { mensajesValidacionES } from "./validation-messages";

describe("mensajesValidacionES", () => {
  it("traduce email inválido con etiqueta conocida", () => {
    const msgs = mensajesValidacionES([
      { property: "contactoCorreo", constraints: { isEmail: "contactoCorreo must be an email" } } as any,
    ]);
    expect(msgs).toEqual(["El correo no es válido"]);
  });

  it("traduce campo obligatorio y humaniza propiedades desconocidas", () => {
    const msgs = mensajesValidacionES([
      { property: "razonSocial", constraints: { isNotEmpty: "x" } } as any,
      { property: "fechaInicioEstimada", constraints: { isDateString: "x" } } as any,
    ]);
    expect(msgs).toEqual([
      "La razón social es obligatorio",
      "Fecha inicio estimada debe ser una fecha válida",
    ]);
  });

  it("recorre errores anidados (children)", () => {
    const msgs = mensajesValidacionES([
      { property: "items", children: [
        { property: "precioUnitario", constraints: { isNumber: "x" } },
      ] } as any,
    ]);
    expect(msgs).toEqual(["Precio unitario debe ser un número"]);
  });
});
