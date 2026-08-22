import { Module } from "@nestjs/common";
import { ConfigModule } from "@nestjs/config";
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR } from "@nestjs/core";
import { ThrottlerModule, ThrottlerGuard } from "@nestjs/throttler";
import { ScheduleModule } from "@nestjs/schedule";
import { JwtModule } from "@nestjs/jwt";
import { join } from "path";

import {
  appConfig, databaseConfig, jwtConfig, storageConfig, redisConfig, mailConfig, validateEnv,
} from "./config";
import { DatabaseModule } from "./infrastructure/database/database.module";
import { StorageModule } from "./infrastructure/storage/storage.module";
import { CacheModule } from "./infrastructure/cache/cache.module";
import { MailModule } from "./infrastructure/mail/mail.module";
import { CryptoModule } from "./infrastructure/crypto/crypto.module";
import { LoggerModule } from "./infrastructure/logger/logger.module";
import { HealthModule } from "./infrastructure/health/health.module";
import { JwtAuthGuard } from "./common/guards/jwt-auth.guard";
import { RolesGuard } from "./common/guards/roles.guard";
import { GlobalExceptionFilter } from "./common/filters/global-exception.filter";
import { RequestIdInterceptor } from "./common/interceptors/request-id.interceptor";

// Módulos de negocio
import { AuthModule } from "./modules/auth/auth.module";
import { UsersModule } from "./modules/users/users.module";
import { RolesModule } from "./modules/roles/roles.module";
import { EmpresasModule } from "./modules/empresas/empresas.module";
import { DashboardModule } from "./modules/dashboard/dashboard.module";
import { ClientesModule } from "./modules/clientes/clientes.module";
import { MascotasModule } from "./modules/mascotas/mascotas.module";
import { CitasModule } from "./modules/citas/citas.module";
import { ClinicoModule } from "./modules/clinico/clinico.module";
import { CatalogosModule } from "./modules/catalogos/catalogos.module";
import { InventarioModule } from "./modules/inventario/inventario.module";
import { ComprasModule } from "./modules/compras/compras.module";
import { FacturacionModule } from "./modules/facturacion/facturacion.module";
import { PagosModule } from "./modules/pagos/pagos.module";
import { RrhhModule } from "./modules/rrhh/rrhh.module";
import { ReportesModule } from "./modules/reportes/reportes.module";
import { PortalModule } from "./modules/portal/portal.module";
import { AuditoriaModule } from "./modules/auditoria/auditoria.module";
import { ArchivosModule } from "./modules/archivos/archivos.module";

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: [join(process.cwd(), ".env")],
      load: [appConfig, databaseConfig, jwtConfig, storageConfig, redisConfig, mailConfig],
      validate: validateEnv,
    }),
    JwtModule.register({ global: true }),
    ScheduleModule.forRoot(),
    ThrottlerModule.forRoot([
      { ttl: 60_000, limit: Number(process.env.RATE_LIMIT_MAX ?? 200) },
    ]),

    // Infraestructura
    LoggerModule,
    DatabaseModule,
    StorageModule,
    CacheModule,
    MailModule,
    CryptoModule,
    HealthModule,

    // Negocio — 18 módulos, espejo del dominio de la clínica
    AuthModule,
    UsersModule,
    RolesModule,
    EmpresasModule,
    DashboardModule,
    ClientesModule,
    MascotasModule,
    CitasModule,
    ClinicoModule,
    CatalogosModule,
    InventarioModule,
    ComprasModule,
    FacturacionModule,
    PagosModule,
    RrhhModule,
    ReportesModule,
    PortalModule,
    AuditoriaModule,
    ArchivosModule,
  ],
  providers: [
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    { provide: APP_GUARD, useClass: RolesGuard },
    { provide: APP_FILTER, useClass: GlobalExceptionFilter },
    { provide: APP_INTERCEPTOR, useClass: RequestIdInterceptor },
  ],
})
export class AppModule {}
