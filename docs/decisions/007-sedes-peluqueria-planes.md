# ADR-007 · Sedes, peluquería y planes: dónde se coloca cada uno

**Estado:** aceptada · **Fecha:** 2026-09-26

## Contexto

Tres huecos que salieron de mirar el ERP como lo miraría una clínica que va a
pagarlo:

1. **No había sedes.** Abrir un segundo local obligaba a crear una segunda
   empresa, y eso parte la cartera de propietarios en dos
   ([ADR-002](002-cartera-por-empresa.md)): el mismo perro tendría dos historias
   clínicas, una por local.
2. **La peluquería era una línea del catálogo.** Existía el tipo de servicio
   `grooming` y hasta un consultorio llamado "Sala de grooming", pero no había
   flujo: ni recepción, ni estado de entrega, ni constancia de cómo llegó el
   animal. En Lima, la peluquería es la mitad del ticket de muchas clínicas.
3. **No había planes preventivos.** Sí estaba `esquemas_vacunacion`, que es el
   protocolo clínico —qué vacuna toca a las seis semanas—, y es otra cosa.

## Decisión

### Sedes: la línea está en lo que ocupa espacio

Lo que comparten los locales es lo que define al negocio: propietarios, historia
clínica, catálogo de servicios y productos, personal. Lo que **no** comparten es
todo lo físico: agenda, consultorios, stock, caja y horario de atención.

Un propietario que viene al local de Surco y la semana siguiente al de
Miraflores es el mismo propietario y su perro tiene una sola historia; pero el
frasco de amoxicilina está en un local concreto y la caja la cuadra quien estuvo
en ese mostrador.

`sede_id` es **nullable** en todas las tablas que la referencian y la rellena el
trigger `trg_sede_por_defecto`. Una clínica de un solo local no se entera de que
esto existe. Va en un trigger y no en cada SP porque son nueve tablas y tres
módulos: el día que se olvide en uno, los informes por local empiezan a mentir
en vez de fallar, que es peor.

### Peluquería: una estancia, no una cita

Una consulta dura veinte minutos con el propietario delante. Un baño con corte
son cuatro horas con el animal solo y la clínica respondiendo por él. El flujo
sostiene tres cosas que ninguna otra tabla sostenía:

- **El estado en que llegó**, con foto. La discusión clásica de una peluquería
  canina es "mi perro no tenía esa herida cuando lo traje". Si nadie dejó
  constancia al recibirlo, esa discusión la pierde la clínica siempre.
- **Lo que el peluquero encuentra.** Es quien más toca al animal: le mira la
  piel entera, las orejas, las uñas, los dientes. Encuentra pulgas, bultos y
  otitis antes que nadie. Ese hallazgo entra en la historia clínica como evento
  propio y, si se marca urgente, notifica a los veterinarios de la sede y
  **bloquea la entrega** hasta que alguien lo revise o lo confirme.
- **El cobro.** Al terminar, cada servicio genera su cargo por
  `internal.registrar_cargo_servicio`, igual que todo lo demás.

### Planes preventivos: la cobertura se aplica en la puerta única

Un plan que no cambia lo que se cobra es una etiqueta en la ficha. Por eso la
cobertura no vive en la pantalla de planes: vive en
`internal.registrar_cargo_servicio`, por donde pasan **todos** los cargos del
sistema —consulta, vacuna, desparasitación, cirugía, día de hospitalización y
baño—. Aplicar el plan ahí es lo que hace que contratarlo se note.

El orden es: beneficio del servicio exacto ("4 consultas incluidas") → beneficio
de su categoría → descuento general del plan. Un beneficio con el cupo agotado
cae al descuento, y **deja de contar como consumo**: si no, la ficha del
propietario acabaría diciendo "4 usadas de 3".

Se suscribe la **mascota**, no el propietario: quien se vacuna es el animal, y
un cliente con tres perros puede tener a uno en plan y a los otros no. Uno solo
activo por paciente, porque al cobrar habría que decidir cuál cubre y esa
decisión no la puede tomar el sistema.

## Consecuencias

**A favor**

- Una clínica con dos locales ya no necesita dos empresas, así que no parte la
  historia clínica de sus pacientes.
- El peluquero deja de ser un servicio y pasa a ser una fuente de hallazgos
  clínicos, que es lo que en la práctica ya era.
- El plan preventivo es ingreso recurrente que no depende de que alguien se
  enferme, y el mostrador puede explicar por qué una consulta sale en cero
  porque el motivo viaja en la descripción del cargo.

**En contra**

- `sede_id` nullable significa que hay un estado de tránsito —entre la migración
  y el relleno— en el que los informes por local están incompletos. El relleno
  de `39_app_sedes.sql` lo cierra en el mismo despliegue.
- Editar un plan a mitad de año es delicado: los beneficios se actualizan en su
  sitio en vez de borrarse y rehacerse, porque borrar pone a NULL el
  `beneficio_id` de cada consumo y le devuelve el cupo entero a todos los
  suscriptores. Eso obliga a que el upsert tenga clave estable, y los beneficios
  por categoría (que no la tienen) sí se rehacen.

## Alternativas descartadas

**Una empresa por local.** Es lo que se podía hacer ya. Parte la cartera y la
historia clínica, que es justo lo que un dueño de dos locales no quiere: el
motivo de tener dos locales es que el cliente pueda ir al que le pille cerca.

**La peluquería como estado de una cita.** La cita tiene una hora y un
veterinario; la estancia tiene una hora de entrada, una de salida, alguien que
recoge al animal y un estado de recepción. Forzarlo en `citas` habría llenado
esa tabla de columnas que el 90% de sus filas no usa.

**Aplicar el plan al emitir el comprobante.** Es donde primero se piensa, y
llega tarde: para entonces el cargo ya existe con su precio, y lo que el
veterinario ve en la pantalla de pendientes no coincide con lo que el mostrador
va a cobrar. Aplicarlo al generar el cargo mantiene una sola verdad.

**Descuento por cliente en vez de plan por mascota.** Más simple de programar y
no es lo que se vende: el propietario no paga una cuota por tener descuento,
paga por tener cubierto el año de salud de un animal concreto, con sus vacunas y
sus controles contados.
