---
name: spec-drive
description: |
  Spec-driven development workflow: idea, research, requirements, design, tasks, and implementation,
  with markdown artifacts and approval gates between phases. Use when the user wants to start, resume,
  or check a spec-drive project (e.g. "new spec-drive project", "run requirements", "spec status",
  "implement the tasks", "switch spec project"). Thin router over an explicitly selected spec-drive plugin core;
  does not duplicate its command logic.
---

# Spec Drive (Codex adapter)

Companion Codex distribuido junto al core, con instalación separada. Lee los comandos
y contratos del core seleccionado; no duplica su lógica. La copia de este checkout no
modifica por sí sola ninguna skill instalada.

## Paso 0 - Resolver la fuente

Precedencia: `SPEC_DRIVE_TEST_CORE` para pruebas aisladas, luego `SPEC_DRIVE_DIR` para
la instalación elegida. Ambas apuntan a la raíz que contiene `commands/`, `agents/`
y `hooks/`, no a la carpeta de este companion. Una ruta explícita inválida detiene
la ejecución: no se ignora ni se busca otra versión en caches.

Si ninguna variable está definida, se admite el layout anterior de una skill instalada
con un core en `../../core`, sólo cuando esa ruta contiene los archivos requeridos.
Este fallback es compatibilidad opcional, no un requisito de instalación.

Ejecutá este bloque en el mismo shell que los comandos dependientes:

```bash
if [ -n "${SPEC_DRIVE_TEST_CORE:-}" ]; then
  spec_drive_core_candidate="$SPEC_DRIVE_TEST_CORE"
elif [ -n "${SPEC_DRIVE_DIR:-}" ]; then
  spec_drive_core_candidate="$SPEC_DRIVE_DIR"
else
  spec_drive_adapter_real="$(python3 -c "import os; print(os.path.realpath(os.path.expanduser('~/.codex/skills/spec-drive')))")" || exit 1
  spec_drive_core_candidate="$spec_drive_adapter_real/../../core"
fi

if [ ! -f "$spec_drive_core_candidate/hooks/scripts/resolve-model.sh" ] ||
   [ ! -f "$spec_drive_core_candidate/commands/implement.md" ] ||
   [ ! -f "$spec_drive_core_candidate/agents/executor.md" ]; then
  echo "Spec-Drive: core no encontrado o incompleto; definí SPEC_DRIVE_DIR (instalación) o SPEC_DRIVE_TEST_CORE (prueba) con la raíz del core." >&2
  exit 1
fi
CLAUDE_PLUGIN_ROOT="$(cd "$spec_drive_core_candidate" && pwd -P)" || exit 1
export CLAUDE_PLUGIN_ROOT
```

Conservá esa raíz durante la sesión y registrá qué candidato se está usando.
Un export no sobrevive entre llamadas independientes de shell: repetí este bloque
o pasá la misma ruta explícita en cada comando que lo necesite. Para un piloto,
leé este companion por su ruta y usá `SPEC_DRIVE_TEST_CORE` en una sesión y proyecto
aislados, sin reemplazar la skill estable ni sus overrides.

## Paso 1 - Enrutar la intención del usuario

| El usuario quiere... | Comando | Archivo a leer y seguir |
|---|---|---|
| Crear un proyecto nuevo | `new` | `$CLAUDE_PLUGIN_ROOT/commands/new.md` |
| Correr o repetir research | `research` | `$CLAUDE_PLUGIN_ROOT/commands/research.md` |
| Generar requirements | `requirements` | `$CLAUDE_PLUGIN_ROOT/commands/requirements.md` |
| Generar design | `design` | `$CLAUDE_PLUGIN_ROOT/commands/design.md` |
| Generar tasks | `tasks` | `$CLAUDE_PLUGIN_ROOT/commands/tasks.md` |
| Ejecutar el loop de implementación | `implement` | `$CLAUDE_PLUGIN_ROOT/commands/implement.md` |
| Ver estado del proyecto activo | `status` | `$CLAUDE_PLUGIN_ROOT/commands/status.md` |
| Listar todos los proyectos | `list` | `$CLAUDE_PLUGIN_ROOT/commands/list.md` |
| Cambiar de proyecto activo | `switch` | `$CLAUDE_PLUGIN_ROOT/commands/switch.md` |
| Cancelar la ejecución activa | `cancel` | `$CLAUDE_PLUGIN_ROOT/commands/cancel.md` |
| Iterar specs tras un hallazgo en ejecución | `refactor` | `$CLAUDE_PLUGIN_ROOT/commands/refactor.md` |
| Pedir ayuda / ver comandos | `help` | `$CLAUDE_PLUGIN_ROOT/commands/help.md` |

Leé el archivo correspondiente completo y seguí sus pasos literalmente, con tus propias
herramientas (lectura de archivos, shell, edición) en lugar de las de Claude Code: son
equivalentes. El `cwd` relevante es el directorio de trabajo actual del usuario, igual que en
Claude Code: los comandos ya saben buscar `.spec-drive-state.json` ahí, en `spec/`, o en el
directorio padre.

`tasks-cmd.md` es un duplicado exacto de `tasks.md` (existe por una colisión de nombre de comando
propia de Claude Code): no hace falta leerlo aparte.

## Paso 2 - Traducir delegación a subagente

Los comandos `new`, `research`, `requirements`, `design`, `tasks` y `implement` enlazan
este paso. Antes de cada despacho, normalizá una delegación `Agent` o `Task tool` a:

```text
role, prompt, basePath, unitKey, tier
```

- `Agent: spec-drive:<role>`: `role` viene del encabezado y `prompt` del contenido que
  sigue al encabezado, con variables resueltas.
- `Task tool`: `role` viene de `subagent_type` y `prompt` de `prompt`; resolvé variables
  antes de conservarlo.
- `basePath` es la ruta absoluta del proyecto activo.
- `unitKey` identifica fase/rol para una definición y task ID más hash estable del bloque
  para una tarea. En VERIFY, conserva la identidad del checkpoint.
- `tier` conserva el tier explícito de la delegación o tarea. Para una definición sin tier,
  usa `standard`; para tareas sin tier, pasa cadena vacía al resolver y conserva inherit. `model: inherit` del rol no
  sustituye un tier explícito. `model_used` es historia y nunca selecciona el modelo.

Resolvé antes de cada despacho con `bash "$CLAUDE_PLUGIN_ROOT/hooks/scripts/resolve-model.sh"
"$TIER" codex`. Para tareas paralelas, repetí la resolución por unidad. VERIFY conserva
su identidad y su tier de sesión; si cruza un subprocess, pasa por este protocolo sin
asignarle un tier comercial nuevo. Usá el resultado actual del resolver y su `source`;
no reutilices una selección histórica.

Tres comandos (`new`, `research`, `implement`) incluyen un bloque como:

```
Task tool:
  subagent_type: spec-drive:<agente>
  description: "..."
  prompt: |
    ...
```

Vos no tenés "Task tool" con `subagent_type`. Traducí así:

1. Identificá `<agente>` (`researcher`, `product-manager`, `architect`, `task-planner`,
   `qa-engineer`, `executor`, `executor-subprocess`, `coordinator`).
2. Leé `$CLAUDE_PLUGIN_ROOT/agents/<agente>.md` completo: es el protocolo/persona de ese rol.
3. Armá un promptfile temporal (`mktemp`) con el contenido de `agents/<agente>.md` seguido del
   `prompt:` específico que traía el bloque de delegación (con sus variables ya resueltas:
   `basePath`, `projectName`, etc.).
4. Resolvé el tier explícito; sólo definición sin tier usa `standard`. Una tarea sin tier
   usa cadena vacía (inherit); VERIFY conserva tier de sesión o cadena vacía. Corré:
   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/hooks/scripts/resolve-model.sh" "$TIER" codex
   ```
   Si mechanism=inherit, delegá nativamente con el modelo de sesión. Si mechanism=agent,
   delegá nativamente con el modelo resuelto cuando la herramienta lo permita. Si esa vía
   no está disponible, detené y explicá el bloqueo; no inventes un subprocess.
   Sólo mechanism=subprocess continúa en los pasos 5–11, con `model=` separado y `cmd=` con el
   comando completo ya resuelto para Codex, sin placeholders que completar a mano (a diferencia del
   profile de Coda, este viene listo de fábrica: `codex exec -m <modelo-real> -s workspace-write
   -- < {promptfile}`).
5. Conservá la plantilla efectiva antes de sustituir `{MODEL}`, leyendo la entrada/base
   indicada por el resolver. Sustituí `{promptfile}` respetando las comillas del comando.
6. En el template Codex conocido, añadí `--skip-git-repo-check` y `--json` exactamente una
   vez cada uno. No reescribas un comando personalizado/legacy opaco: ejecutalo como fue
   resuelto y no infieras un modelo ni banderas para él. Escapá la ruta del promptfile como
   un único argumento shell; nunca interpolés el prompt en la orden.
7. Capturá stdout, stderr y exit hasta EOF. Sólo template Codex conocido exige JSONL
   completo y parseable. Comandos opacos conservan su formato, sin flags ni requisito JSONL.
8. Registra `unitKey`, `cli`, `tier`, modelo seleccionado (también en subprocess), `source`,
   código de salida y resultado. Sólo `exitCode=0` y el artefacto requerido presente y
   válido permiten seguir los pasos "after delegation". Un proceso exitoso sin artefacto
   es fallo de delegación y no avanza fase, cursor ni checkpoint. Un fallo tampoco avanza.
9. Clasificá el despacho antes del manejo genérico de errores. El único rechazo de modelo que
   permite recuperación automática de Codex es la firma
   `codex-0.156.1-chatgpt-model-rejection-v1`, comparada contra el ID que resolvió el adaptador:
   proceso terminado con exit 1 y JSONL completo y válido con `thread.started`, opcionalmente
   el único aviso de metadata `item.completed`/`item.type=error` de la captura de rechazo
   (mismo texto, sólo cambia el ID), `turn.started`, `error` y `turn.failed` terminal. Tanto
   `error.message` como `turn.failed.error.message` deben ser JSON anidado y parsear al mismo
   objeto: `type=error`, `status=400`, `error.type=invalid_request_error` y
   `error.message="The '<selectedModel>' model is not supported when using Codex with a ChatGPT account."`.
   No busques la frase en texto libre ni aceptes eventos adicionales.
10. Para esa firma, registra `outcome=unavailable_before_work`, `started=no` y evidencia con
    versión, firma y causa fija sanitizada. `turn.started`, metadata aislada, exit 1, HTTP 400,
    ausencia de archivos cambiados o un mensaje parecido no demuestran rechazo ni trabajo.
    Auth, red, truncamiento, JSON inválido, versión/formato desconocido, ID diferente, eventos
    de trabajo u otra evidencia ambigua son `other_failure`; el trabajo observado da
    `started=yes`, y lo ambiguo `started=unknown`. Agent nativo, Coda y comandos opacos no
    tienen esta evidencia y siguen el manejo normal. No copies mensaje bruto, stderr ni prompt
    al diagnóstico.
11. Tras el rechazo confirmado, el coordinador puede resolver otra vez sólo la misma CLI y
    tier. Un ID configurado distinto permite un reintento total. Si no hay un ID distinto,
    persiste `awaiting_choice` antes de pedir una sola elección. Sin respuesta, elección
    inválida o error de persistencia, bloquea sin despachar ni volver a preguntar. Una elección
    válida persiste únicamente `profiles[cli][tier].model`; mantiene los demás valores y el
    mecanismo, verifica archivo regular, permisos, lock y conflicto concurrente, escribe un
    temporal hermano y reemplaza atómicamente. No persistas sobre comando opaco o base
    incompatible. Re-resuelve y comprueba que CLI, tier, mecanismo, plantilla y proveedor sean
    los mismos, y argumentos idénticos salvo el ID sustituido. El cmd expandido cambia con el ID;
    no se compara por igualdad literal. Otro cambio bloquea. Reserva el único reintento antes de invocar;
    usa el mismo rol, prompt y unidad. Un segundo rechazo bloquea sin otra consulta ni despacho.
    No agregues un ejecutable dispatcher.

Persistí la recuperación en el campo opcional `modelRecovery.episodes` del `.spec-drive-state.json`
existente; los estados legacy sin ese campo siguen siendo válidos. Derivá `unitKey` del
phase/role estable o ID de tarea más el hash estable del bloque. Derivá `selectionFingerprint`
de CLI, tier, mecanismo, modelo seleccionado, comando y proveedor efectivos; excluí los bytes
del prompt y `model_used` histórico. La clave del episodio combina ambos. Usá el lock existente
`{basePath}/.execution-state.lock` para preparar despachos de definición y tareas, y para
reservar consultas y reintentos. Bajo el lock, compará estado y selección y persistí
`awaiting_choice` antes de preguntar o `retry_reserved` antes de reintentar. Liberá el lock
antes de interactuar o iniciar subprocess; volvé a tomarlo para registrar el resultado y
rechazá cambios concurrentes. Tras reiniciar, una reserva de reintento incierta bloquea sin
consultar ni despachar otra vez automáticamente. Reconciliá bajo supervisión: inspeccioná
proceso, capturas completas, artefacto y unidad; explicá qué se ejecutó y qué sigue incierto.
Si se acredita el éxito ya producido, registralo bajo lock y avanzá una sola vez sin exigir
otro modelo. Si no se acredita, conservá la reserva y pedí autorización explícita antes de
cualquier nueva ejecución; nunca reinicies límites por inferencia.

La misma unidad y fingerprint reanudan el mismo episodio. Una invocación repetida, cambios de
configuración ajenos, estado corrupto, symlinks inesperados o conflicto concurrente no reinician
límites. El rechazo confirmado previo al trabajo preserva cursor, checks, contadores normales,
progreso e historial. Si un reintento inicia trabajo y luego falla, usa el conteo normal de
intentos y conserva efectos parciales. Avanzá sólo tras validar el artefacto de esa unidad.
Archivá el episodio agotado y abrí otro sólo si una corrección explícita cambia la selección
efectiva y el usuario solicita continuar; conservá el archivo y hacé la transición bajo el
mismo lock.

### Evidencia local 1.4.3

`test/test-model-recovery.sh` usa exclusivamente una captura sintética
del repositorio; no consume los booleanos de `cases.json/rejection.jsonl` históricos.
`--evidence DIR` exige `agent.json` y `task.json`, producidos por un coordinador siguiendo
este protocolo con CLI controlada (sin proveedor), y abre los archivos referenciados.

Cada manifest tiene `schemaVersion:2`, `guided:true`, `shellReplay:false`, `kind` Agent/Task,
`role`, `unitKey`, `episodeKey`, `scenario` success/interrupted, `dispatches` 2/1,
`choiceQueries` 0/1, `templateArgv` con un argumento `{MODEL}`, e `invocations` (rutas JSON).
Cada invocation contiene `unitKey,role,cli,tier,mechanism,provider,model,argv,prompt,
stdoutJsonl,stderr,exitCode`. Las rutas son relativas al manifest y quedan dentro de DIR.
`prompt` referencia bytes sintéticos efectivamente recibidos por la CLI; stdout y stderr
son capturas completas. Un manifest booleano no sustituye estos archivos.

`snapshots` referencia estados Spec-Drive JSON reales: `before,afterRejection,
afterReservation,afterRestart` y `afterSuccess` en éxito. El episodio conserva los nombres
del schema: `choiceQueries,retryReservations,status,unitKey,selectionFingerprint`.
Rechazo/reserva preservan todos los campos fuera de modelRecovery. Éxito de Agent/task-planner
cambia design→tasks y awaitingApproval=true; ejecución avanza taskIndex una vez.
Éxito exige además `artifact:{path,sha256}`, bytes no vacíos y episodio resolved.
Interrupción exige `hookAfterRestart`, captura del hook real que bloquea la reserva,
y estado idéntico a afterReservation. El lector no ejecuta recuperación ni reemplaza
la revisión del artefacto realizada por el coordinador.

Estos archivos prueban coherencia de la captura, no autentican por sí solos quién la produjo
ni disponibilidad comercial. Las pruebas unitarias crean fixtures con guided=false y
shellReplay=true; nunca se presentan como integración guiada. Capturas históricas sin estos
campos quedan incompletas y deben renovarse, no darse por aprobadas.
