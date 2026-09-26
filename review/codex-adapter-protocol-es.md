# Protocolo candidato del adaptador Codex

Extracto del companion distribuido por separado en `review/adapter-codex/SKILL.md`.
No se instala automáticamente desde esta carpeta. El companion selecciona core con
`SPEC_DRIVE_TEST_CORE` para pruebas o `SPEC_DRIVE_DIR` para instalación; sólo admite
el layout relativo anterior como fallback validado si no hay ruta explícita.
Una ruta inválida detiene la ejecución, sin seleccionar versiones desde caches.

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
4. Resolvé el tier explícito; definición sin tier usa standard, tarea sin tier usa cadena vacía
   (inherit), y VERIFY conserva tier de sesión o cadena vacía. Corré:
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
5. Conservá la plantilla efectiva anterior a sustituir `{MODEL}` desde la entrada/base
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
    los mismos; argumentos idénticos salvo el ID sustituido. El cmd expandido cambia con el ID.
    Otro cambio bloquea. Reserva el único reintento antes de invocar;
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
proceso, capturas, artefacto y unidad; informá qué se ejecutó y qué sigue incierto.
Un éxito acreditado se registra bajo lock y avanza una sola vez sin cambiar modelo.
Sin evidencia suficiente, conservá la reserva y pedí autorización explícita antes de ejecutar.

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
