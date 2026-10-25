import { Injectable, Logger, OnApplicationBootstrap } from "@nestjs/common";
import { Cron } from "@nestjs/schedule";
import { SpExecutorService } from "../../infrastructure/database/sp-executor.service";

/**
 * El trabajo de madrugada: carga las cuotas de los planes que tocan y cierra
 * los que vencieron. Antes dependía de que alguien pulsara un botón, así que
 * un plan vencido seguía cubriendo y la cuota del mes no llegaba a la cuenta.
 *
 * Corre también al arrancar, por si el servidor estuvo apagado a esa hora. El
 * SP es idempotente y se protege con un candado: varias instancias del
 * backend (PM2 en cluster) no lo ejecutan dos veces.
 */
@Injectable()
export class TareasDiariasService implements OnApplicationBootstrap {
  private readonly logger = new Logger(TareasDiariasService.name);

  constructor(private readonly sp: SpExecutorService) {}

  onApplicationBootstrap() {
    if (process.env.NODE_ENV === "test") return;
    void this.ejecutar();
  }

  @Cron("0 5 * * *", { timeZone: "America/Lima" })
  async ejecutar() {
    try {
      const r = await this.sp.call<{ empresas?: unknown[] }>("app.sp_tareas_diarias", []);
      this.logger.log(`Tareas diarias: ${JSON.stringify(r)}`);
    } catch (e: any) {
      this.logger.error(`Tareas diarias fallaron: ${e?.message ?? e}`);
    }
  }
}
