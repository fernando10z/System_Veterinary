export interface JwtPayload {
  sub: string;
  email: string;
  empresa_id: string | null;
  is_super_admin: boolean;
  roles?: string[];
  iat?: number;
  exp?: number;
  iss?: string;
  aud?: string;
}
