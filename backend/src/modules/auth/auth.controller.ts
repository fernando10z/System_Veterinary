import { Body, Controller, Get, HttpCode, Post } from "@nestjs/common";
import { Throttle } from "@nestjs/throttler";
import { AuthService } from "./auth.service";
import { LoginDto } from "./dto/login.dto";
import { RefreshDto } from "./dto/refresh.dto";
import { CambiarPasswordDto } from "./dto/cambiar-password.dto";
import { SolicitarResetDto, ResetPasswordDto } from "./dto/reset-password.dto";
import { PortalLoginDto } from "./dto/portal-login.dto";
import { Public } from "../../common/decorators/public.decorator";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

/**
 * Los endpoints que aceptan credenciales llevan un límite propio y estrecho.
 * El global (200/min) sirve para la operación normal, pero deja espacio de sobra
 * para probar contraseñas. La base ya bloquea la cuenta a los 5 intentos; esto
 * frena además el barrido de cuentas distintas desde la misma IP.
 */
const LIMITE_CREDENCIALES = { default: { limit: 10, ttl: 60_000 } };

@Controller("auth")
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Public()
  @Throttle(LIMITE_CREDENCIALES)
  @HttpCode(200)
  @Post("login")
  async login(@Body() dto: LoginDto) {
    const data = await this.auth.login(dto.email, dto.password);
    return { ok: true, data };
  }

  @Public()
  @HttpCode(200)
  @Post("refresh")
  async refresh(@Body() dto: RefreshDto) {
    const data = await this.auth.refresh(dto.refresh_token);
    return { ok: true, data };
  }

  @Public()
  @HttpCode(200)
  @Post("logout")
  async logout(@Body() dto: RefreshDto) {
    const data = await this.auth.logout(dto.refresh_token);
    return { ok: true, data };
  }

  @Get("perfil")
  async perfil(@CurrentUser() u: JwtPayload) {
    const data = await this.auth.perfil(u.sub);
    return { ok: true, data };
  }

  @HttpCode(200)
  @Post("cambiar-password")
  async cambiarPassword(@CurrentUser() u: JwtPayload, @Body() dto: CambiarPasswordDto) {
    const data = await this.auth.cambiarPassword(u, dto.password_actual, dto.password_nuevo);
    return { ok: true, data };
  }

  @Public()
  @Throttle(LIMITE_CREDENCIALES)
  @HttpCode(200)
  @Post("solicitar-reset")
  async solicitarReset(@Body() dto: SolicitarResetDto) {
    const data = await this.auth.solicitarReset(dto.email);
    // Nunca se devuelve el token al cliente: viaja por correo.
    return { ok: true, data: { enviado: true } };
  }

  @Public()
  @Throttle(LIMITE_CREDENCIALES)
  @HttpCode(200)
  @Post("reset-password")
  async resetPassword(@Body() dto: ResetPasswordDto) {
    const data = await this.auth.resetPassword(dto.token, dto.password_nuevo);
    return { ok: true, data };
  }

  // ---- Portal del propietario ------------------------------------------------
  @Public()
  @Throttle(LIMITE_CREDENCIALES)
  @HttpCode(200)
  @Post("portal/login")
  async portalLogin(@Body() dto: PortalLoginDto) {
    const data = await this.auth.portalLogin(dto.documento, dto.password);
    return { ok: true, data };
  }
}
