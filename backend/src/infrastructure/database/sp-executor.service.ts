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

  // Los helpers de `internal` lanzan excepciones nativas de Postgres y el bloque
  // EXCEPTION del SP devuelve el SQLSTATE tal cual. Sin estas entradas, un
  // "sin acceso a la empresa" llegaba al cliente como 422 en vez de 403.
  "42501": HttpStatus.FORBIDDEN,           // insufficient_privilege
  P0001: HttpStatus.UNPROCESSABLE_ENTITY,  // raise_exception (regla de negocio)
  "23505": HttpStatus.CONFLICT,            // unique_violation
  "23503": HttpStatus.UNPROCESSABLE_ENTITY, // foreign_key_violation
  "23514": HttpStatus.UNPROCESSABLE_ENTITY, // check_violation
};

/**
 * SQLSTATE → código semántico. El cliente no debe recibir "42501": no le dice
 * nada y filtra que la comprobación vino de Postgres, no de una regla del ERP.
 */
const CODIGO_SEMANTICO: Record<string, string> = {
  "42501": "FORBIDDEN",
  P0001: "BUSINESS_RULE",
  "23505": "CONFLICT",
  "23503": "BUSINESS_RULE",
  "23514": "VALIDATION_ERROR",
};

/** Códigos SQLSTATE cuyo mensaje interno no debe llegar al cliente. */
const MENSAJE_GENERICO: Record<string, string> = {
  "23503": "La operación afecta a registros relacionados",
  "23514": "Los datos no cumplen una restricción del sistema",
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
      const bruto = row.error?.code ?? "BUSINESS_RULE";
      const status = ERROR_STATUS[bruto] ?? HttpStatus.UNPROCESSABLE_ENTITY;
      // Un SQLSTATE crudo no le dice nada al usuario y describe de dónde salió la
      // comprobación: se traduce a un código del dominio y, si el mensaje viene
      // de Postgres, se sustituye por uno entendible.
      const code = CODIGO_SEMANTICO[bruto] ?? bruto;
      const message =
        MENSAJE_GENERICO[bruto] ?? row.error?.message ?? "Operación rechazada";
      if (CODIGO_SEMANTICO[bruto]) {
        this.logger.warn(`${fnName} → SQLSTATE ${bruto}: ${row.error?.message}`);
      }
      throw new HttpException({ code, message, detail: row.error?.detail }, status);
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
