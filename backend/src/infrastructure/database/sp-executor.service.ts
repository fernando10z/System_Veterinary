import {
  HttpException,
  HttpStatus,
  Inject,
  Injectable,
  Logger,
} from "@nestjs/common";
import { Pool, PoolClient } from "pg";
import { PG_POOL } from "./database.constants";
import { SpContext, SpResult } from "../../common/types/sp-result.type";
import { contextoActual } from "../../common/context/request-context";

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

/**
 * Fija la IP y el agente de la petición como ajustes de sesión de Postgres.
 * `internal.registrar_auditoria` los lee con `current_setting(..., true)`.
 *
 * Se fijan SIEMPRE, aunque vengan vacíos: la conexión sale de un pool y se
 * reutiliza, así que no reescribirlos dejaría a esta petición firmando la
 * bitácora con la IP de la anterior.
 */
const SQL_CONTEXTO =
  "SELECT set_config('app.client_ip', $1, false), set_config('app.user_agent', $2, false)";

@Injectable()
export class SpExecutorService {
  private readonly logger = new Logger(SpExecutorService.name);

  constructor(@Inject(PG_POOL) private readonly pool: Pool) {}

  /**
   * Ejecuta el SP y devuelve su sobre `{ok, data, error, meta}` sin interpretar.
   * Traduce los errores que Postgres lanza —los que el SP no atrapó— al mismo
   * formato, para que arriba haya un solo camino de error.
   */
  private async ejecutar<T>(fnName: string, params: unknown[]): Promise<SpResult<T>> {
    const placeholders = params.map((_, i) => `$${i + 1}`).join(", ");
    const sql = `SELECT ${fnName}(${placeholders}) AS result`;
    const ctx = contextoActual();

    let client: PoolClient | undefined;
    try {
      client = await this.pool.connect();
      await client.query(SQL_CONTEXTO, [
        ctx?.ip ?? "",
        (ctx?.userAgent ?? "").slice(0, 300),
      ]);
      const r = await client.query<{ result: SpResult<T> }>(sql, params as any[]);
      const row = r.rows[0]?.result;
      if (!row || typeof row !== "object") {
        throw new HttpException(
          { code: "DATABASE_ERROR", message: `Respuesta inválida de ${fnName}` },
          HttpStatus.INTERNAL_SERVER_ERROR,
        );
      }
      return row;
    } catch (err: any) {
      if (err instanceof HttpException) throw err;

      // Un SP sin bloque EXCEPTION deja escapar la excepción de Postgres. El
      // SQLSTATE sigue siendo una respuesta del dominio (permiso, unicidad,
      // regla): se convierte al mismo sobre en vez de degradar todo a un 500.
      if (typeof err?.code === "string" && ERROR_STATUS[err.code] !== undefined) {
        return {
          ok: false,
          error: { code: err.code, message: err.message ?? "Operación rechazada" },
        };
      }

      // Lo que queda es un fallo de verdad. El mensaje de Postgres nombra
      // tablas, columnas y a veces el dato que falló: se queda en el log.
      this.logger.error(`Error en ${fnName}: ${err?.message}`, err?.stack);
      throw new HttpException(
        { code: "DATABASE_ERROR", message: "Error interno al procesar la operación" },
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    } finally {
      client?.release();
    }
  }

  /** Convierte un sobre con `ok:false` en la excepción HTTP que le corresponde. */
  private lanzarSiFalla(fnName: string, row: SpResult<unknown>): void {
    if (row.ok) return;
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

  async call<T = unknown>(fnName: string, params: unknown[]): Promise<T> {
    const row = await this.ejecutar<T>(fnName, params);
    this.lanzarSiFalla(fnName, row);
    return (row.data as T) ?? (row as unknown as T);
  }

  /**
   * Variante que devuelve {data, meta} sin desempacar, para propagar la
   * paginación al cliente.
   *
   * Rechaza igual que `call`. Antes devolvía el sobre tal cual y quien llamaba
   * hacía `r?.data ?? []`: un 403 del SP se convertía en un 200 con la lista
   * vacía, así que el usuario sin permiso veía "no hay registros" en vez de un
   * "no tienes acceso" —y el ERP parecía funcionar—.
   */
  async callRaw<T = unknown>(fnName: string, params: unknown[]): Promise<SpResult<T>> {
    const row = await this.ejecutar<T>(fnName, params);
    this.lanzarSiFalla(fnName, row);
    return row;
  }

  /** Helper: invoca un SP que sigue la convención (user_id, empresa_id, is_super_admin, ...args). */
  callCtx<T = unknown>(fnName: string, ctx: SpContext, args: unknown[] = []): Promise<T> {
    return this.call<T>(fnName, [ctx.userId, ctx.empresaId, ctx.isSuperAdmin, ...args]);
  }
}
