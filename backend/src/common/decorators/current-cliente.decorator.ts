import { createParamDecorator, ExecutionContext } from "@nestjs/common";
import { PortalPayload } from "../guards/portal-auth.guard";

/** Id del propietario autenticado en el portal. */
export const CurrentCliente = createParamDecorator(
  (_: unknown, ctx: ExecutionContext): string => {
    const req = ctx.switchToHttp().getRequest<{ cliente?: PortalPayload }>();
    return req.cliente!.sub;
  },
);
