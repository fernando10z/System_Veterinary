import {
  HttpException,
  HttpStatus,
  Inject,
  Injectable,
  Logger,
} from "@nestjs/common";
import { Pool } from "pg";
import { PG_POOL } from "./database.constants";
import { SpContext, SpResult } from "../../common/types/sp-result.type";

const ERROR_STATUS: Record<string, HttpStatus> = {
  NOT_FOUND: HttpStatus.NOT_FOUND,
  FORBIDDEN: HttpStatus.FORBIDDEN,
  UNAUTHORIZED: HttpStatus.UNAUTHORIZED,
  VALIDATION_ERROR: HttpStatus.UNPROCESSABLE_ENTITY,
  BAD_REQUEST: HttpStatus.BAD_REQUEST,
  CONFLICT: HttpStatus.CONFLICT,
  BUSINESS_RULE: HttpStatus.UNPROCESSABLE_ENTITY,
};

@Injectable()
export class SpExecutorService {
  private readonly logger = new Logger(SpExecutorService.name);

  constructor(@Inject(PG_POOL) private readonly pool: Pool) {}

  async call<T = unknown>(fnName: string, params: unknown[]): Promise<T> {
    const placeholders = params.map((_, i) => `$${i + 1}`).join(", ");
    const sql = `SELECT ${fnName}(${placeholders}) AS result`;
    let row;
    try {
      const r = await this.pool.query<{ result: SpResult<T> }>(sql, params as any[]);
      row = r.rows[0]?.result;
    } catch (err: any) {
      this.logger.error(`Error en ${fnName}: ${err?.message}`, err?.stack);
      throw new HttpException(
        { code: "DATABASE_ERROR", message: err?.message ?? "Error de base de datos" },
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
    if (!row || typeof row !== "object") {
      throw new HttpException(
        { code: "DATABASE_ERROR", message: `Respuesta inválida de ${fnName}` },
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
    if (!row.ok) {
      const code = row.error?.code ?? "BUSINESS_RULE";
      const status = ERROR_STATUS[code] ?? HttpStatus.UNPROCESSABLE_ENTITY;
      throw new HttpException(
        {
          code,
          message: row.error?.message ?? "Operación rechazada",
          detail: row.error?.detail,
        },
        status,
      );
    }
    return (row.data as T) ?? (row as unknown as T);
  }

  /**
   * Variante que devuelve {ok, data, meta} sin desempacar.
   * Útil cuando el endpoint quiere propagar `meta` (paginación) al cliente.
   */
  async callRaw<T = unknown>(fnName: string, params: unknown[]): Promise<SpResult<T>> {
    const placeholders = params.map((_, i) => `$${i + 1}`).join(", ");
    const sql = `SELECT ${fnName}(${placeholders}) AS result`;
    const r = await this.pool.query<{ result: SpResult<T> }>(sql, params as any[]);
    return r.rows[0]?.result;
  }

  /** Helper: invoca un SP que sigue la convención (user_id, empresa_id, is_super_admin, ...args). */
  callCtx<T = unknown>(fnName: string, ctx: SpContext, args: unknown[] = []): Promise<T> {
    return this.call<T>(fnName, [ctx.userId, ctx.empresaId, ctx.isSuperAdmin, ...args]);
  }
}
