export interface SpError {
  code: string;
  message: string;
  detail?: unknown;
}

export interface SpResult<T = unknown> {
  ok: boolean;
  data?: T;
  error?: SpError;
  meta?: Record<string, unknown>;
}

export interface SpContext {
  userId: string;
  empresaId: string | null;
  isSuperAdmin: boolean;
}
