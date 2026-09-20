export interface JwtPayload {
  sub: string;
  email: string;
  empresa_id: string | null;
  is_super_admin: boolean;
  roles?: string[];
  /** Clave temporal sin cambiar: el guard solo deja pasar a cambiarla. */
  must_change_password?: boolean;
  iat?: number;
  exp?: number;
  iss?: string;
  aud?: string;
}
