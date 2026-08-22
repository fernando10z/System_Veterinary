import { createRouter, createWebHistory } from "vue-router";
import { ACCESS_TOKEN_KEY, USER_KEY, PORTAL_TOKEN_KEY } from "../shared/config/api.config.js";
import MainLayout from "../layouts/MainLayout.vue";

// El login y el panel se cargan eager (son lo primero que ve el usuario);
// el resto va lazy para que el bundle inicial no cargue todo el ERP.
import Login from "../modules/auth/pages/Login.vue";
import Dashboard from "../modules/dashboard/pages/Dashboard.vue";

const routes = [
  { path: "/", redirect: "/dashboard" },
  { path: "/login", name: "login", component: Login, meta: { publica: true } },

  // ---- Portal del propietario: auth propia, sin el layout del backoffice ----
  {
    path: "/portal/login",
    name: "portal-login",
    component: () => import("../modules/portal/pages/PortalLogin.vue"),
    meta: { publica: true },
  },
  {
    path: "/portal",
    name: "portal",
    component: () => import("../modules/portal/pages/PortalHome.vue"),
    meta: { publica: true, requierePortal: true },
  },

  // ---- Backoffice ----
  {
    path: "/",
    component: MainLayout,
    meta: { requiereAuth: true },
    children: [
      { path: "dashboard", name: "dashboard", component: Dashboard },
      { path: "cambiar-password", name: "cambiar-password",
        component: () => import("../modules/auth/pages/CambiarPassword.vue"),
        meta: { titulo: "Contraseña" } },

      // Agenda clínica
      { path: "agenda", name: "agenda",
        component: () => import("../modules/citas/pages/Agenda.vue") },

      // Pacientes y propietarios
      { path: "pacientes", name: "pacientes",
        component: () => import("../modules/mascotas/pages/Pacientes.vue") },
      { path: "pacientes/:id", name: "paciente-detalle",
        component: () => import("../modules/mascotas/pages/PacienteDetalle.vue"),
        meta: { titulo: "Ficha clínica" } },
      { path: "clientes", name: "clientes",
        component: () => import("../modules/clientes/pages/Clientes.vue") },
      { path: "clientes/:id", name: "cliente-detalle",
        component: () => import("../modules/clientes/pages/ClienteDetalle.vue"),
        meta: { titulo: "Ficha del propietario" } },

      // Historia clínica
      { path: "consultas", name: "consultas",
        component: () => import("../modules/clinico/pages/Consultas.vue") },
      { path: "consultas/:id", name: "consulta-detalle",
        component: () => import("../modules/clinico/pages/ConsultaDetalle.vue"),
        meta: { titulo: "Consulta" } },
      { path: "cirugias", name: "cirugias",
        component: () => import("../modules/clinico/pages/Cirugias.vue") },
      { path: "hospitalizacion", name: "hospitalizacion",
        component: () => import("../modules/clinico/pages/Hospitalizacion.vue") },
      { path: "vacunacion", name: "vacunacion",
        component: () => import("../modules/clinico/pages/Vacunacion.vue") },

      // Operación
      { path: "inventario", name: "inventario",
        component: () => import("../modules/inventario/pages/Inventario.vue") },
      { path: "compras", name: "compras",
        component: () => import("../modules/compras/pages/Compras.vue") },

      // Administración
      { path: "facturacion", name: "facturacion",
        component: () => import("../modules/facturacion/pages/Facturacion.vue") },
      { path: "cobranzas", name: "cobranzas",
        component: () => import("../modules/pagos/pages/Cobranzas.vue") },
      { path: "caja", name: "caja",
        component: () => import("../modules/pagos/pages/Caja.vue") },
      { path: "equipo", name: "equipo",
        component: () => import("../modules/rrhh/pages/Equipo.vue") },
      { path: "reportes", name: "reportes",
        component: () => import("../modules/reportes/pages/Reportes.vue") },

      // Configuración
      { path: "configuracion/usuarios", name: "usuarios",
        component: () => import("../modules/users/pages/Usuarios.vue") },
      { path: "configuracion/roles", name: "roles",
        component: () => import("../modules/roles/pages/RolesPermisos.vue"),
        meta: { requiereSuperAdmin: true } },
      { path: "configuracion/catalogos", name: "catalogos",
        component: () => import("../modules/configuracion/pages/Catalogos.vue") },
      { path: "configuracion/sede", name: "sede",
        component: () => import("../modules/configuracion/pages/Sede.vue") },
      { path: "auditoria", name: "auditoria",
        component: () => import("../modules/auditoria/pages/Auditoria.vue") },
    ],
  },

  { path: "/:pathMatch(.*)*", redirect: "/dashboard" },
];

const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior: () => ({ top: 0 }),
});

function esSuperAdmin() {
  try {
    const raw = localStorage.getItem(USER_KEY);
    return raw ? !!JSON.parse(raw).is_super_admin : false;
  } catch {
    return false;
  }
}

router.beforeEach((to) => {
  // El portal tiene su propio token: no se mezcla con la sesión del staff.
  if (to.meta.requierePortal) {
    return localStorage.getItem(PORTAL_TOKEN_KEY) ? true : { path: "/portal/login" };
  }
  if (to.meta.publica) return true;

  const autenticado = !!localStorage.getItem(ACCESS_TOKEN_KEY);
  if (to.meta.requiereAuth && !autenticado) {
    return { path: "/login", query: { from: to.fullPath } };
  }
  if (to.path === "/login" && autenticado) return { path: "/dashboard" };

  // Defensa ante acceso por URL directa; el sidebar ya oculta estas rutas.
  if (to.meta.requiereSuperAdmin && autenticado && !esSuperAdmin()) {
    return { path: "/dashboard" };
  }
  return true;
});

export default router;
