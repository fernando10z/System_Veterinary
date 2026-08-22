import { registerAs } from "@nestjs/config";

export default registerAs("jwt", () => ({
  accessSecret: process.env.JWT_ACCESS_SECRET,
  accessExpires: process.env.JWT_ACCESS_EXPIRES ?? "15m",
  refreshSecret: process.env.JWT_REFRESH_SECRET,
  refreshExpires: process.env.JWT_REFRESH_EXPIRES ?? "7d",
  issuer: process.env.JWT_ISSUER ?? "veterp",
  audience: process.env.JWT_AUDIENCE ?? "veterp-backoffice",
}));

/**
 * Config del token del portal del propietario. Issuer y audience distintos del
 * backoffice: un token del portal no puede validar contra el guard del staff.
 */
export const portalJwtConfig = () => ({
  issuer: process.env.JWT_PORTAL_ISSUER ?? "veterp-portal",
  audience: process.env.JWT_PORTAL_AUDIENCE ?? "veterp-clientes",
  expires: process.env.JWT_PORTAL_EXPIRES ?? "8h",
});
