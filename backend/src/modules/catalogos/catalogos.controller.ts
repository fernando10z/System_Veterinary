import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Post, Put, Query } from "@nestjs/common";
import { CatalogosService } from "./catalogos.service";
import { GuardarEspecieDto, GuardarRazaDto } from "./dto/guardar-especie.dto";
import { GuardarServicioDto } from "./dto/guardar-servicio.dto";
import { GuardarCategoriaDto } from "./dto/guardar-categoria.dto";
import { GuardarConsultorioDto } from "./dto/guardar-consultorio.dto";
import { GuardarHorariosDto } from "./dto/guardar-horarios.dto";
import { GuardarEspecializacionDto } from "./dto/guardar-especializacion.dto";
import { GuardarEsquemaVacunacionDto } from "./dto/guardar-esquema-vacunacion.dto";
import { GuardarClausulaDto } from "./dto/guardar-clausula.dto";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtPayload } from "../../common/types/jwt-payload.type";

@Controller("catalogos")
export class CatalogosController {
  constructor(private readonly cat: CatalogosService) {}

  // ---- especies y razas (con las razas anidadas en cada especie) ----
  @Get("especies")
  async especies(@CurrentUser() u: JwtPayload, @Query("todas") todas?: string) {
    return { ok: true, data: await this.cat.especies(u, todas === "true") };
  }
  @Post("especies")
  async especieGuardar(@CurrentUser() u: JwtPayload, @Body() dto: GuardarEspecieDto) {
    return { ok: true, data: await this.cat.especieGuardar(u, dto) };
  }
  @Post("razas")
  async razaGuardar(@CurrentUser() u: JwtPayload, @Body() dto: GuardarRazaDto) {
    return { ok: true, data: await this.cat.razaGuardar(u, dto) };
  }

  // ---- servicios ----
  @Get("servicios")
  async servicios(
    @CurrentUser() u: JwtPayload,
    @Query("buscar") buscar?: string,
    @Query("tipo") tipo?: string,
    @Query("estado") estado?: string,
    @Query("categoriaId") categoriaId?: string,
  ) {
    const f: Record<string, unknown> = {};
    if (buscar) f.buscar = buscar;
    if (tipo) f.tipo = tipo;
    if (estado) f.estado = estado;
    if (categoriaId) f.categoria_id = categoriaId;
    return { ok: true, data: await this.cat.servicios(u, f) };
  }
  @Post("servicios")
  async servicioGuardar(@CurrentUser() u: JwtPayload, @Body() dto: GuardarServicioDto) {
    return { ok: true, data: await this.cat.servicioGuardar(u, dto) };
  }
  @Delete("servicios/:id")
  async servicioEliminar(@CurrentUser() u: JwtPayload, @Param("id", ParseUUIDPipe) id: string) {
    return { ok: true, data: await this.cat.servicioEliminar(u, id) };
  }

  // ---- categorías (servicio | producto | proveedor) ----
  @Get("categorias")
  async categorias(@CurrentUser() u: JwtPayload, @Query("ambito") ambito?: string) {
    return { ok: true, data: await this.cat.categorias(u, ambito) };
  }
  @Post("categorias")
  async categoriaGuardar(@CurrentUser() u: JwtPayload, @Body() dto: GuardarCategoriaDto) {
    return { ok: true, data: await this.cat.categoriaGuardar(u, dto) };
  }

  // ---- consultorios ----
  @Get("consultorios")
  async consultorios(@CurrentUser() u: JwtPayload) {
    return { ok: true, data: await this.cat.consultorios(u) };
  }
  @Post("consultorios")
  async consultorioGuardar(@CurrentUser() u: JwtPayload, @Body() dto: GuardarConsultorioDto) {
    return { ok: true, data: await this.cat.consultorioGuardar(u, dto) };
  }

  // ---- horario de atención (se reemplaza la semana completa) ----
  @Get("horarios")
  async horarios(@CurrentUser() u: JwtPayload) {
    return { ok: true, data: await this.cat.horarios(u) };
  }
  @Put("horarios")
  async horariosGuardar(@CurrentUser() u: JwtPayload, @Body() dto: GuardarHorariosDto) {
    return { ok: true, data: await this.cat.horariosGuardar(u, dto.horarios) };
  }

  // ---- especializaciones ----
  @Get("especializaciones")
  async especializaciones(@CurrentUser() u: JwtPayload) {
    return { ok: true, data: await this.cat.especializaciones(u) };
  }
  @Post("especializaciones")
  async especializacionGuardar(@CurrentUser() u: JwtPayload, @Body() dto: GuardarEspecializacionDto) {
    return { ok: true, data: await this.cat.especializacionGuardar(u, dto) };
  }

  // ---- esquemas de vacunación ----
  @Get("esquemas-vacunacion")
  async esquemas(@CurrentUser() u: JwtPayload, @Query("especieId") especieId?: string) {
    return { ok: true, data: await this.cat.esquemasVacunacion(u, especieId) };
  }
  @Post("esquemas-vacunacion")
  async esquemaGuardar(@CurrentUser() u: JwtPayload, @Body() dto: GuardarEsquemaVacunacionDto) {
    return { ok: true, data: await this.cat.esquemaGuardar(u, dto) };
  }

  // ---- cláusulas y consentimientos ----
  @Get("clausulas")
  async clausulas(@CurrentUser() u: JwtPayload, @Query("tipo") tipo?: string) {
    return { ok: true, data: await this.cat.clausulas(u, tipo) };
  }
  @Post("clausulas")
  async clausulaGuardar(@CurrentUser() u: JwtPayload, @Body() dto: GuardarClausulaDto) {
    return { ok: true, data: await this.cat.clausulaGuardar(u, dto) };
  }
}
