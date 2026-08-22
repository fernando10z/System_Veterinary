<template>
  <div>
    <PageHeader
      eyebrow="Configuración"
      title="Catálogos"
      subtitle="Especies, servicios, consultorios, horarios y protocolos"
    >
      <template #actions>
        <button class="btn" :disabled="cargando" @click="cargar">
          <RefreshCw :size="14" :class="cargando ? 'spin' : ''" /> Actualizar
        </button>
      </template>
    </PageHeader>

    <div class="toggle-group" style="margin-bottom: 16px">
      <button :class="tab === 'servicios' ? 'active' : ''" @click="tab = 'servicios'">Servicios</button>
      <button :class="tab === 'especies' ? 'active' : ''" @click="tab = 'especies'">Especies y razas</button>
      <button :class="tab === 'consultorios' ? 'active' : ''" @click="tab = 'consultorios'">Consultorios</button>
      <button :class="tab === 'horarios' ? 'active' : ''" @click="tab = 'horarios'">Horario</button>
      <button :class="tab === 'esquemas' ? 'active' : ''" @click="tab = 'esquemas'">Vacunación</button>
      <button :class="tab === 'especialidades' ? 'active' : ''" @click="tab = 'especialidades'">Especialidades</button>
    </div>

    <!-- ---------- Servicios ---------- -->
    <section v-if="tab === 'servicios'" class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><Stethoscope :size="14" /></span>
          Catálogo de servicios
          <span class="head-meta">{{ servicios.length }}</span>
        </h2>
        <div class="module-panel-head-actions">
          <button class="btn primary" @click="abrirServicio()"><Plus :size="13" /> Nuevo servicio</button>
        </div>
      </header>

      <div v-if="!servicios.length" class="module-panel-body module-empty">
        <div class="empty-icon"><Stethoscope :size="22" /></div>
        <h3>Sin servicios</h3>
        <p>Define los servicios que ofrece la clínica y su precio.</p>
      </div>

      <div v-else class="module-panel-body tabla-wrap">
        <table>
          <thead>
            <tr>
              <th>Servicio</th><th>Tipo</th><th class="num">Precio</th><th class="num">Costo</th>
              <th class="num">Duración</th><th class="num">Usos del mes</th><th>Estado</th><th class="acciones-col"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="s in servicios" :key="s.id">
              <td>
                <div class="stack">
                  <strong>{{ s.nombre }}</strong>
                  <small class="muted mono">{{ s.codigo }}</small>
                </div>
              </td>
              <td><span class="tag">{{ capitalizar(s.tipo) }}</span></td>
              <td class="num mono">{{ fmtSoles(s.precio) }}</td>
              <td class="num mono muted">{{ fmtSoles(s.costo_estimado) }}</td>
              <td class="num mono">{{ s.duracion_min }}′</td>
              <td class="num mono">{{ s.usos_mes }}</td>
              <td>
                <span :class="['estado-pill', s.estado === 'activo' ? 'ok' : 'neutral']">
                  <span class="dot"></span>{{ capitalizar(s.estado) }}
                </span>
              </td>
              <td class="acciones-col">
                <div class="row-actions">
                  <button class="btn mini" title="Editar" @click="abrirServicio(s)"><Pencil :size="13" /></button>
                  <button class="btn mini" title="Eliminar" @click="eliminarServicio(s)"><Trash2 :size="13" /></button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- ---------- Especies y razas ---------- -->
    <section v-else-if="tab === 'especies'" class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><PawPrint :size="14" /></span>
          Especies y razas
          <span class="head-meta">{{ especies.length }}</span>
        </h2>
        <div class="module-panel-head-actions">
          <button class="btn" @click="abrirRaza()"><Plus :size="13" /> Nueva raza</button>
          <button class="btn primary" @click="abrirEspecie()"><Plus :size="13" /> Nueva especie</button>
        </div>
      </header>

      <div class="module-panel-body especies-lista">
        <div v-for="e in especies" :key="e.id" class="especie-bloque">
          <div class="especie-head">
            <div>
              <strong>{{ e.nombre }}</strong>
              <small class="muted">{{ e.total_pacientes }} pacientes · {{ e.razas.length }} razas</small>
            </div>
            <button class="btn mini" @click="abrirEspecie(e)"><Pencil :size="13" /></button>
          </div>
          <div class="razas">
            <span v-for="r in e.razas" :key="r.id" class="tag raza" @click="abrirRaza(r, e)">
              {{ r.nombre }}
            </span>
            <span v-if="!e.razas.length" class="muted">Sin razas registradas</span>
          </div>
        </div>
      </div>
    </section>

    <!-- ---------- Consultorios ---------- -->
    <section v-else-if="tab === 'consultorios'" class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><DoorOpen :size="14" /></span>
          Consultorios y salas
          <span class="head-meta">{{ consultorios.length }}</span>
        </h2>
        <div class="module-panel-head-actions">
          <button class="btn primary" @click="abrirConsultorio()"><Plus :size="13" /> Nuevo</button>
        </div>
      </header>

      <div class="module-panel-body tabla-wrap">
        <table>
          <thead><tr><th>Nombre</th><th>Tipo</th><th class="num">Capacidad</th><th>Estado</th><th class="acciones-col"></th></tr></thead>
          <tbody>
            <tr v-for="c in consultorios" :key="c.id">
              <td><strong>{{ c.nombre }}</strong></td>
              <td><span class="tag">{{ capitalizar(c.tipo) }}</span></td>
              <td class="num mono">{{ c.capacidad }}</td>
              <td>
                <span :class="['estado-pill', c.estado === 'activo' ? 'ok' : 'neutral']">
                  <span class="dot"></span>{{ capitalizar(c.estado) }}
                </span>
              </td>
              <td class="acciones-col">
                <button class="btn mini" @click="abrirConsultorio(c)"><Pencil :size="13" /></button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- ---------- Horario de atención ---------- -->
    <section v-else-if="tab === 'horarios'" class="module-panel">
      <header class="module-panel-head">
        <h2><span class="head-icon"><Clock :size="14" /></span> Horario de atención</h2>
        <div class="module-panel-head-actions">
          <button class="btn primary" :disabled="guardando" @click="guardarHorarios">
            {{ guardando ? "Guardando…" : "Guardar horario" }}
          </button>
        </div>
      </header>

      <div class="module-panel-body">
        <p class="muted" style="margin-top: 0">
          Define en qué franjas se puede agendar. Los huecos disponibles de cada
          veterinario se calculan a partir de este horario.
        </p>
        <div class="horario-grid">
          <div v-for="(h, i) in horarioSemana" :key="i" class="dia-row">
            <label class="check-line">
              <input v-model="h.activo" type="checkbox" />
              <strong>{{ DIAS[h.dia_semana] }}</strong>
            </label>
            <input v-model="h.hora_inicio" type="time" :disabled="!h.activo" />
            <span class="muted">a</span>
            <input v-model="h.hora_fin" type="time" :disabled="!h.activo" />
          </div>
        </div>
      </div>
    </section>

    <!-- ---------- Esquemas de vacunación ---------- -->
    <section v-else-if="tab === 'esquemas'" class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><Syringe :size="14" /></span>
          Protocolos de vacunación
          <span class="head-meta">{{ esquemas.length }}</span>
        </h2>
        <div class="module-panel-head-actions">
          <button class="btn primary" @click="abrirEsquema()"><Plus :size="13" /> Nuevo protocolo</button>
        </div>
      </header>

      <div class="module-panel-body tabla-wrap">
        <table>
          <thead>
            <tr>
              <th>Protocolo</th><th>Especie</th><th class="num">Inicio</th>
              <th class="num">Dosis</th><th class="num">Intervalo</th><th class="num">Revacunación</th>
              <th>Obligatoria</th><th class="acciones-col"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="e in esquemas" :key="e.id">
              <td><strong>{{ e.nombre }}</strong></td>
              <td>{{ e.especie }}</td>
              <td class="num mono">{{ e.edad_inicio_semanas ? `${e.edad_inicio_semanas} sem` : "—" }}</td>
              <td class="num mono">{{ e.dosis_totales }}</td>
              <td class="num mono">{{ e.intervalo_dias ? `${e.intervalo_dias} d` : "—" }}</td>
              <td class="num mono">{{ e.revacunacion_meses ? `${e.revacunacion_meses} m` : "—" }}</td>
              <td>
                <span :class="['estado-pill', e.obligatoria ? 'danger' : 'neutral']">
                  <span class="dot"></span>{{ e.obligatoria ? "Sí" : "No" }}
                </span>
              </td>
              <td class="acciones-col">
                <button class="btn mini" @click="abrirEsquema(e)"><Pencil :size="13" /></button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- ---------- Especialidades ---------- -->
    <section v-else class="module-panel">
      <header class="module-panel-head">
        <h2>
          <span class="head-icon"><GraduationCap :size="14" /></span>
          Especialidades veterinarias
          <span class="head-meta">{{ especialidades.length }}</span>
        </h2>
        <div class="module-panel-head-actions">
          <button class="btn primary" @click="abrirEspecialidad()"><Plus :size="13" /> Nueva</button>
        </div>
      </header>

      <div class="module-panel-body tabla-wrap">
        <table>
          <thead><tr><th>Especialidad</th><th>Descripción</th><th class="num">Veterinarios</th><th>Estado</th><th class="acciones-col"></th></tr></thead>
          <tbody>
            <tr v-for="e in especialidades" :key="e.id">
              <td><strong>{{ e.nombre }}</strong></td>
              <td class="muted">{{ e.descripcion || "—" }}</td>
              <td class="num mono">{{ e.veterinarios }}</td>
              <td>
                <span :class="['estado-pill', e.estado === 'activo' ? 'ok' : 'neutral']">
                  <span class="dot"></span>{{ capitalizar(e.estado) }}
                </span>
              </td>
              <td class="acciones-col">
                <button class="btn mini" @click="abrirEspecialidad(e)"><Pencil :size="13" /></button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- ---------- Modal genérico de catálogo ---------- -->
    <div v-if="modal" class="modal-back" @click="modal = null">
      <div class="modal modal-wide" @click.stop>
        <div class="m-head"><h3>{{ modal.titulo }}</h3></div>
        <div class="m-body">
          <div v-if="error" class="callout danger" style="margin-bottom: 12px">
            <AlertCircle :size="15" /> <span>{{ error }}</span>
          </div>
          <div class="form-grid">
            <div
              v-for="c in modal.campos"
              :key="c.k"
              class="field"
              :style="c.ancho ? 'grid-column: 1 / -1' : ''"
            >
              <label>{{ c.l }} <span v-if="c.req" class="req">*</span></label>
              <select v-if="c.tipo === 'select'" v-model="modal.datos[c.k]">
                <option v-if="!c.req" value="">Sin definir</option>
                <option v-for="o in c.opciones" :key="o.v" :value="o.v">{{ o.l }}</option>
              </select>
              <label v-else-if="c.tipo === 'check'" class="check-line">
                <input v-model="modal.datos[c.k]" type="checkbox" />
                <span>{{ c.ayuda }}</span>
              </label>
              <textarea v-else-if="c.tipo === 'textarea'" v-model="modal.datos[c.k]" rows="2"></textarea>
              <input
                v-else
                v-model="modal.datos[c.k]"
                :type="c.tipo || 'text'"
                :step="c.tipo === 'number' ? c.step || 1 : undefined"
              />
              <small v-if="c.ayuda && c.tipo !== 'check'" class="muted">{{ c.ayuda }}</small>
            </div>
          </div>
        </div>
        <div class="m-foot modal-actions">
          <button class="btn" @click="modal = null">Cancelar</button>
          <button class="btn primary" :disabled="guardando" @click="guardarModal">
            {{ guardando ? "Guardando…" : "Guardar" }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, watch } from "vue";
import {
  Stethoscope, PawPrint, DoorOpen, Clock, Syringe, GraduationCap,
  Plus, Pencil, Trash2, RefreshCw, AlertCircle,
} from "lucide-vue-next";
import PageHeader from "../../../layouts/PageHeader.vue";
import { catalogosApi } from "../../catalogos/api/catalogos.api.js";
import { fmtSoles, capitalizar } from "../../../shared/components/ui/format.js";
import { notify } from "../../../shared/composables/useNotify.js";

const DIAS = ["Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado"];

const tab = ref("servicios");
const cargando = ref(false);
const guardando = ref(false);
const error = ref("");

const servicios = ref([]);
const especies = ref([]);
const consultorios = ref([]);
const esquemas = ref([]);
const especialidades = ref([]);
const categorias = ref([]);
const horarioSemana = ref([]);

const modal = ref(null);

// ---------------------------------------------------------------- servicios
function abrirServicio(s = null) {
  error.value = "";
  modal.value = {
    titulo: s ? "Editar servicio" : "Nuevo servicio",
    guardar: catalogosApi.guardarServicio,
    datos: {
      id: s?.id,
      nombre: s?.nombre ?? "",
      tipo: s?.tipo ?? "consulta",
      categoria_id: s?.categoria_id ?? "",
      precio: Number(s?.precio ?? 0),
      costo_estimado: Number(s?.costo_estimado ?? 0),
      duracion_min: s?.duracion_min ?? 30,
      requiere_ayuno: s?.requiere_ayuno ?? false,
      estado: s?.estado ?? "activo",
      descripcion: s?.descripcion ?? "",
    },
    campos: [
      { k: "nombre", l: "Nombre", req: true, ancho: true },
      { k: "tipo", l: "Tipo", tipo: "select", req: true, opciones: [
        { v: "consulta", l: "Consulta" }, { v: "vacunacion", l: "Vacunación" },
        { v: "cirugia", l: "Cirugía" }, { v: "laboratorio", l: "Laboratorio" },
        { v: "imagen", l: "Imagen" }, { v: "grooming", l: "Grooming" },
        { v: "hospitalizacion", l: "Hospitalización" },
        { v: "desparasitacion", l: "Desparasitación" }, { v: "otro", l: "Otro" },
      ] },
      { k: "categoria_id", l: "Categoría", tipo: "select",
        opciones: categorias.value.map((c) => ({ v: c.id, l: c.nombre })) },
      { k: "precio", l: "Precio (S/)", tipo: "number", step: 0.5, req: true },
      { k: "costo_estimado", l: "Costo estimado (S/)", tipo: "number", step: 0.5 },
      { k: "duracion_min", l: "Duración (min)", tipo: "number", step: 5 },
      { k: "requiere_ayuno", l: "Ayuno", tipo: "check", ayuda: "Requiere ayuno previo" },
      { k: "estado", l: "Estado", tipo: "select", req: true, opciones: [
        { v: "activo", l: "Activo" }, { v: "inactivo", l: "Inactivo" },
      ] },
      { k: "descripcion", l: "Descripción", tipo: "textarea", ancho: true },
    ],
  };
}

async function eliminarServicio(s) {
  const ok = await notify.confirm(`¿Eliminar ${s.nombre}?`, "Si ya fue prestado, se desactivará en lugar de eliminarse.", { danger: true });
  if (!ok) return;
  try {
    const r = await catalogosApi.eliminarServicio(s.id);
    if (r.data?.mensaje) notify.info("Servicio desactivado", r.data.mensaje);
    cargar();
  } catch (e) {
    notify.error("No se pudo eliminar", e.message);
  }
}

// ---------------------------------------------------------- especies y razas
function abrirEspecie(e = null) {
  error.value = "";
  modal.value = {
    titulo: e ? "Editar especie" : "Nueva especie",
    guardar: catalogosApi.guardarEspecie,
    datos: {
      id: e?.id, nombre: e?.nombre ?? "", nombre_cria: e?.nombre_cria ?? "",
      icono: e?.icono ?? "PawPrint", estado: e?.estado ?? "activo",
    },
    campos: [
      { k: "nombre", l: "Nombre", req: true },
      { k: "nombre_cria", l: "Nombre de la cría", ayuda: "Cachorro, gatito…" },
      { k: "icono", l: "Icono", ayuda: "Nombre del icono lucide (Dog, Cat, Bird…)" },
      { k: "estado", l: "Estado", tipo: "select", req: true, opciones: [
        { v: "activo", l: "Activo" }, { v: "inactivo", l: "Inactivo" },
      ] },
    ],
  };
}

function abrirRaza(r = null, esp = null) {
  error.value = "";
  modal.value = {
    titulo: r ? "Editar raza" : "Nueva raza",
    guardar: catalogosApi.guardarRaza,
    datos: {
      id: r?.id,
      especie_id: esp?.id ?? "",
      nombre: r?.nombre ?? "",
      tamanio_referencia: r?.tamanio_referencia ?? "",
      peso_min_kg: r?.peso_min_kg ?? null,
      peso_max_kg: r?.peso_max_kg ?? null,
      esperanza_vida: r?.esperanza_vida ?? null,
      estado: r?.estado ?? "activo",
    },
    campos: [
      { k: "especie_id", l: "Especie", tipo: "select", req: !r,
        opciones: especies.value.map((e) => ({ v: e.id, l: e.nombre })) },
      { k: "nombre", l: "Nombre", req: true },
      { k: "tamanio_referencia", l: "Tamaño", tipo: "select", opciones: [
        { v: "toy", l: "Toy" }, { v: "pequenio", l: "Pequeño" },
        { v: "mediano", l: "Mediano" }, { v: "grande", l: "Grande" }, { v: "gigante", l: "Gigante" },
      ] },
      { k: "peso_min_kg", l: "Peso mínimo (kg)", tipo: "number", step: 0.1 },
      { k: "peso_max_kg", l: "Peso máximo (kg)", tipo: "number", step: 0.1 },
      { k: "esperanza_vida", l: "Esperanza de vida (años)", tipo: "number" },
      { k: "estado", l: "Estado", tipo: "select", req: true, opciones: [
        { v: "activo", l: "Activo" }, { v: "inactivo", l: "Inactivo" },
      ] },
    ],
  };
}

// ------------------------------------------------------------- consultorios
function abrirConsultorio(c = null) {
  error.value = "";
  modal.value = {
    titulo: c ? "Editar consultorio" : "Nuevo consultorio",
    guardar: catalogosApi.guardarConsultorio,
    datos: {
      id: c?.id, nombre: c?.nombre ?? "", tipo: c?.tipo ?? "consulta",
      capacidad: c?.capacidad ?? 1, estado: c?.estado ?? "activo",
    },
    campos: [
      { k: "nombre", l: "Nombre", req: true },
      { k: "tipo", l: "Tipo", tipo: "select", req: true, opciones: [
        { v: "consulta", l: "Consultorio" }, { v: "quirofano", l: "Quirófano" },
        { v: "hospitalizacion", l: "Hospitalización" }, { v: "grooming", l: "Grooming" },
      ] },
      { k: "capacidad", l: "Capacidad", tipo: "number" },
      { k: "estado", l: "Estado", tipo: "select", req: true, opciones: [
        { v: "activo", l: "Activo" }, { v: "inactivo", l: "Inactivo" },
      ] },
    ],
  };
}

// ------------------------------------------------------------- esquemas
function abrirEsquema(e = null) {
  error.value = "";
  modal.value = {
    titulo: e ? "Editar protocolo" : "Nuevo protocolo",
    guardar: catalogosApi.guardarEsquema,
    datos: {
      id: e?.id,
      especie_id: e?.especie_id ?? "",
      nombre: e?.nombre ?? "",
      obligatoria: e?.obligatoria ?? false,
      edad_inicio_semanas: e?.edad_inicio_semanas ?? null,
      intervalo_dias: e?.intervalo_dias ?? null,
      dosis_totales: e?.dosis_totales ?? 1,
      revacunacion_meses: e?.revacunacion_meses ?? 12,
      estado: e?.estado ?? "activo",
    },
    campos: [
      { k: "especie_id", l: "Especie", tipo: "select", req: !e,
        opciones: especies.value.map((x) => ({ v: x.id, l: x.nombre })) },
      { k: "nombre", l: "Nombre", req: true },
      { k: "edad_inicio_semanas", l: "Edad de inicio (semanas)", tipo: "number" },
      { k: "dosis_totales", l: "Dosis totales", tipo: "number" },
      { k: "intervalo_dias", l: "Intervalo entre dosis (días)", tipo: "number" },
      { k: "revacunacion_meses", l: "Revacunación (meses)", tipo: "number" },
      { k: "obligatoria", l: "Obligatoria", tipo: "check", ayuda: "Exigida por normativa" },
      { k: "estado", l: "Estado", tipo: "select", req: true, opciones: [
        { v: "activo", l: "Activo" }, { v: "inactivo", l: "Inactivo" },
      ] },
    ],
  };
}

// -------------------------------------------------------- especialidades
function abrirEspecialidad(e = null) {
  error.value = "";
  modal.value = {
    titulo: e ? "Editar especialidad" : "Nueva especialidad",
    guardar: catalogosApi.guardarEspecializacion,
    datos: { id: e?.id, nombre: e?.nombre ?? "", descripcion: e?.descripcion ?? "", estado: e?.estado ?? "activo" },
    campos: [
      { k: "nombre", l: "Nombre", req: true, ancho: true },
      { k: "descripcion", l: "Descripción", tipo: "textarea", ancho: true },
      { k: "estado", l: "Estado", tipo: "select", req: true, opciones: [
        { v: "activo", l: "Activo" }, { v: "inactivo", l: "Inactivo" },
      ] },
    ],
  };
}

async function guardarModal() {
  error.value = "";
  const faltante = modal.value.campos.find((c) => c.req && !modal.value.datos[c.k]);
  if (faltante) {
    error.value = `${faltante.l} es obligatorio.`;
    return;
  }
  guardando.value = true;
  try {
    const p = {};
    for (const [k, v] of Object.entries(modal.value.datos)) {
      if (v === "" || v === null || v === undefined) continue;
      p[k] = v;
    }
    // Los booleanos deben viajar aunque sean false.
    for (const c of modal.value.campos) {
      if (c.tipo === "check") p[c.k] = !!modal.value.datos[c.k];
    }
    await modal.value.guardar(p);
    modal.value = null;
    cargar();
  } catch (e) {
    error.value = e.message;
  } finally {
    guardando.value = false;
  }
}

// -------------------------------------------------------------- horarios
async function guardarHorarios() {
  guardando.value = true;
  try {
    await catalogosApi.guardarHorarios(
      horarioSemana.value
        .filter((h) => h.activo)
        .map((h) => ({
          dia_semana: h.dia_semana,
          hora_inicio: h.hora_inicio,
          hora_fin: h.hora_fin,
          activo: true,
        })),
    );
    notify.success("Horario actualizado");
    cargar();
  } catch (e) {
    notify.error("No se pudo guardar el horario", e.message);
  } finally {
    guardando.value = false;
  }
}

/** La semana siempre se muestra completa; lo guardado marca qué días están activos. */
function armarSemana(guardados) {
  horarioSemana.value = Array.from({ length: 7 }, (_, dia) => {
    const h = guardados.find((x) => x.dia_semana === dia);
    return {
      dia_semana: dia,
      activo: !!h?.activo,
      hora_inicio: h?.hora_inicio?.slice(0, 5) ?? "09:00",
      hora_fin: h?.hora_fin?.slice(0, 5) ?? "18:00",
    };
  });
}

async function cargar() {
  cargando.value = true;
  try {
    const [srv, esp, con, esq, especialidad, cat, hor] = await Promise.all([
      catalogosApi.servicios(),
      catalogosApi.especies(true),
      catalogosApi.consultorios(),
      catalogosApi.esquemasVacunacion(),
      catalogosApi.especializaciones(),
      catalogosApi.categorias("servicio"),
      catalogosApi.horarios(),
    ]);
    servicios.value = srv.data ?? [];
    especies.value = esp.data ?? [];
    consultorios.value = con.data ?? [];
    esquemas.value = esq.data ?? [];
    especialidades.value = especialidad.data ?? [];
    categorias.value = cat.data ?? [];
    armarSemana(hor.data ?? []);
  } finally {
    cargando.value = false;
  }
}

onMounted(cargar);
</script>

<style scoped>
.especies-lista { display: flex; flex-direction: column; gap: 14px; }
.especie-bloque { border: 1px solid var(--line); border-radius: 11px; padding: 12px 14px; }
.especie-head { display: flex; justify-content: space-between; align-items: center; margin-bottom: 9px; }
.especie-head strong { font-size: 13.5px; color: var(--ink); }
.especie-head small { display: block; font-size: 11.5px; }
.razas { display: flex; flex-wrap: wrap; gap: 5px; }
.razas .raza { cursor: pointer; }
.razas .raza:hover { background: var(--emerald-soft); border-color: var(--emerald-line); color: var(--emerald-ink); }

.horario-grid { display: flex; flex-direction: column; gap: 9px; margin-top: 14px; }
.dia-row { display: grid; grid-template-columns: 160px 120px 24px 120px; align-items: center; gap: 10px; }
.dia-row input[type="time"] {
  height: 32px; padding: 0 8px; border: 1px solid var(--line);
  border-radius: 8px; background: var(--bg-elev); color: var(--ink); font-size: 13px;
}
.check-line { display: inline-flex; align-items: center; gap: 8px; font-size: 13px; color: var(--ink-2); }
.req { color: var(--red); }
.btn.mini { height: 26px; padding: 0 8px; font-size: 11.5px; }
</style>
