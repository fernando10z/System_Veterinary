import { Controller, Get, Query } from "@nestjs/common";
import { ReportesService } from "./reportes.service";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

/** Rango por defecto: el mes en curso. */
function rango(desde?: string, hasta?: string): [string, string] {
  const hoy = new Date();
  const inicioMes = new Date(hoy.getFullYear(), hoy.getMonth(), 1);
  return [
    desde ?? inicioMes.toISOString().slice(0, 10),
    hasta ?? hoy.toISOString().slice(0, 10),
  ];
}

@Controller("reportes")
export class ReportesController {
  constructor(private readonly rep: ReportesService) {}

  @Get("ventas")
  async ventas(
    @CurrentUser() u: JwtPayload,
    @Query("desde") desde?: string,
    @Query("hasta") hasta?: string,
  ) {
    const [d, h] = rango(desde, hasta);
    return { ok: true, data: await this.rep.ventas(u, d, h) };
  }

  @Get("clinico")
  async clinico(
    @CurrentUser() u: JwtPayload,
    @Query("desde") desde?: string,
    @Query("hasta") hasta?: string,
  ) {
    const [d, h] = rango(desde, hasta);
    return { ok: true, data: await this.rep.clinico(u, d, h) };
  }

  @Get("inventario")
  async inventario(
    @CurrentUser() u: JwtPayload,
    @Query("desde") desde?: string,
    @Query("hasta") hasta?: string,
  ) {
    return { ok: true, data: await this.rep.inventario(u, desde, hasta) };
  }

  @Get("ejecutivo")
  async ejecutivo(
    @CurrentUser() u: JwtPayload,
    @Query("desde") desde?: string,
    @Query("hasta") hasta?: string,
  ) {
    const [d, h] = rango(desde, hasta);
    return { ok: true, data: await this.rep.ejecutivo(u, d, h) };
  }
}
