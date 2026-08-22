// navigation.js
// Fuente única del menú principal. La consumen el Sidebar y el buscador ⌘K,
// así que gatear un módulo en un solo sitio los mantiene sincronizados.
//
// Cada item: { to, label, icon, requirePermission?, requireSuperAdmin?, keywords? }
//   - requirePermission: código de permiso necesario (null = visible siempre)
//   - requireSuperAdmin: además exige super admin
//   - keywords: sinónimos para que la búsqueda encuentre el módulo aunque el
//     usuario escriba otra palabra ("dueño" → Clientes, "historia" → Pacientes)
import {
  LayoutDashboard, CalendarClock, PawPrint, Users, Stethoscope, Syringe,
  Scissors, BedDouble, Package, Truck, Receipt, Wallet, CreditCard,
  BarChart3, UserCog, ShieldCheck, Building2, Library, History, Clock,
} from "lucide-vue-next";

export const NAV_SECTIONS = [
  {
    label: "Principal",
    items: [
      { to: "/dashboard", label: "Panel", icon: LayoutDashboard, requirePermission: null,
        keywords: "inicio home resumen tablero indicadores" },
      { to: "/agenda", label: "Agenda", icon: CalendarClock, requirePermission: "citas:listar",
        keywords: "citas calendario turnos sala de espera reservas" },
    ],
  },
  {
    label: "Clínica",
    items: [
      { to: "/pacientes", label: "Pacientes", icon: PawPrint, requirePermission: "mascotas:listar",
        keywords: "mascotas animales perros gatos historia clinica ficha" },
      { to: "/clientes", label: "Propietarios", icon: Users, requirePermission: "clientes:listar",
        keywords: "duenios dueños clientes tutores contactos cartera" },
      { to: "/consultas", label: "Consultas", icon: Stethoscope, requirePermission: "clinico:ver",
        keywords: "atenciones diagnostico soap examen" },
      { to: "/cirugias", label: "Cirugías", icon: Scissors, requirePermission: "clinico:ver",
        keywords: "quirofano operaciones esterilizacion" },
      { to: "/hospitalizacion", label: "Hospitalización", icon: BedDouble, requirePermission: "clinico:ver",
        keywords: "internamiento jaulas evolucion hospital" },
      { to: "/vacunacion", label: "Vacunación", icon: Syringe, requirePermission: "clinico:ver",
        keywords: "vacunas refuerzos carne esquemas desparasitacion" },
    ],
  },
  {
    label: "Operación",
    items: [
      { to: "/inventario", label: "Inventario", icon: Package, requirePermission: "inventario:ver",
        keywords: "stock productos medicamentos insumos almacen lotes vencimiento" },
      { to: "/compras", label: "Compras", icon: Truck, requirePermission: "compras:ver",
        keywords: "proveedores ordenes pedidos recepcion" },
    ],
  },
  {
    label: "Administración",
    items: [
      { to: "/facturacion", label: "Facturación", icon: Receipt, requirePermission: "facturacion:ver",
        keywords: "boletas facturas comprobantes sunat ventas" },
      { to: "/cobranzas", label: "Cobranzas", icon: CreditCard, requirePermission: "pagos:ver",
        keywords: "pagos cuentas por cobrar deuda saldos" },
      { to: "/caja", label: "Caja", icon: Wallet, requirePermission: "caja:ver",
        keywords: "arqueo turno cierre apertura efectivo" },
      { to: "/equipo", label: "Equipo", icon: Clock, requirePermission: "rrhh:ver",
        keywords: "rrhh personal turnos asistencia permisos vacaciones evaluaciones" },
      { to: "/reportes", label: "Reportes", icon: BarChart3, requirePermission: "reportes:ver",
        keywords: "estadisticas indicadores kpi ejecutivo analisis" },
    ],
  },
  {
    label: "Configuración",
    items: [
      { to: "/configuracion/usuarios", label: "Usuarios", icon: UserCog, requirePermission: "usuarios:listar",
        keywords: "cuentas accesos personal staff" },
      { to: "/configuracion/roles", label: "Roles y permisos", icon: ShieldCheck, requireSuperAdmin: true,
        keywords: "permisos accesos perfiles" },
      { to: "/configuracion/catalogos", label: "Catálogos", icon: Library, requirePermission: "catalogos:gestionar",
        keywords: "especies razas servicios categorias consultorios horarios esquemas" },
      { to: "/configuracion/sede", label: "Sede", icon: Building2, requirePermission: null,
        keywords: "empresa clinica ruc series facturacion datos fiscales" },
      { to: "/auditoria", label: "Auditoría", icon: History, requirePermission: "auditoria:ver",
        keywords: "bitacora log trazabilidad quien hizo cambios" },
    ],
  },
];

/** Aplana las secciones a los items visibles según permisos del usuario. */
export function visibleNavItems(can, superAdmin) {
  const out = [];
  for (const sec of NAV_SECTIONS) {
    for (const it of sec.items) {
      if (it.requirePermission && !can(it.requirePermission)) continue;
      if (it.requireSuperAdmin && !superAdmin) continue;
      out.push({ ...it, section: sec.label });
    }
  }
  return out;
}
