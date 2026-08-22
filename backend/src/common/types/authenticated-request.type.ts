import { FastifyRequest } from "fastify";
import { JwtPayload } from "./jwt-payload.type";

export interface AuthenticatedRequest extends FastifyRequest {
  user: JwtPayload;
}
