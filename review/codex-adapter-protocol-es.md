# Protocolo candidato del adaptador Codex

Extracto para revisión del adaptador externo. No se instala desde esta carpeta. La resolución inicial del core sigue siendo responsabilidad del adaptador de cada entorno.

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
  usa `standard`; para tareas, no inventes un valor si falta. `model: inherit` del rol no
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
4. Resolvé el tier pedido (`light`/`standard`/`advanced`/`frontier`, o `standard` si el comando no
   especifica uno) corriendo:
   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/hooks/scripts/resolve-model.sh" "$TIER" codex
   ```
   Esto imprime `mechanism=subprocess`, el `model=` separado seleccionado y `cmd=` con el
   comando completo ya resuelto para Codex, sin placeholders que completar a mano (a diferencia del
   profile de Coda, este viene listo de fábrica: `codex exec -m <modelo-real> -s workspace-write
   -- < {promptfile}`).
5. Sustituí `{promptfile}` en el `cmd` resuelto por la ruta real del promptfile del paso 3.
   **Insertá `--skip-git-repo-check` en ese comando antes de correrlo** (ej. después de `exec`:
   `codex exec --skip-git-repo-check -m <modelo> -s workspace-write -- < {promptfile}`). El
   comando que trae `core/profiles/codex.json` no incluye esa flag, y `basePath` suele ser un
   proyecto de spec-drive recién creado (`create-project.sh` corre `git init`), que Codex no
   reconoce como directorio confiable todavía. Sin la flag, el subproceso corta antes de leer el
   prompt con `Not inside a trusted directory and --skip-git-repo-check was not specified.` y la
   delegación entera falla en silencio salvo por ese mensaje en stderr.
6. En el template Codex conocido, añadí `--skip-git-repo-check` y `--json` exactamente una
   vez cada uno. No reescribas un comando personalizado/legacy opaco: ejecutalo como fue
   resuelto y no infieras un modelo ni banderas para él. Escapá la ruta del promptfile como
   un único argumento shell; nunca interpolés el prompt en la orden.
7. Corré en foreground y capturá stdout JSONL, stderr y código de salida por separado,
   leyendo ambos streams hasta EOF. Conservá la secuencia JSONL completa y parseable; un
   stream truncado o mal formado es fallo, no éxito.
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
    incompatible. Re-resuelve y comprueba que CLI, tier, mecanismo, comando y proveedor sean
    los mismos. Un cambio en cualquiera bloquea. Reserva el único reintento antes de invocar;
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
consultar ni despachar otra vez.

La misma unidad y fingerprint reanudan el mismo episodio. Una invocación repetida, cambios de
configuración ajenos, estado corrupto, symlinks inesperados o conflicto concurrente no reinician
límites. El rechazo confirmado previo al trabajo preserva cursor, checks, contadores normales,
progreso e historial. Si un reintento inicia trabajo y luego falla, usa el conteo normal de
intentos y conserva efectos parciales. Avanzá sólo tras validar el artefacto de esa unidad.
Archivá el episodio agotado y abrí otro sólo si una corrección explícita cambia la selección
efectiva y el usuario solicita continuar; conservá el archivo y hacé la transición bajo el
mismo lock.

### Evidencia del POC `adapter-poc`

Para las dos ejecuciones guiadas del coordinador, guardá `work/evidence/adapter-poc.json`
con `schemaVersion: 1` y dos entradas `captures`: `planner-agent` y `task-task`. Cada
captura debe registrar `input` (`kind`, `role`, `tier`, `unitKey`, `historyModelUsed`),
`resolution` (`cli`, `tier`, `mechanism`, `model`, `source`), `dispatch` (`argv`, rutas
relativas al workspace de `stdoutJsonl` y `stderr`, `exitCode`), `received` (`role`,
`promptSha256`), y `historyAfterModelUsed` (igual a `input.historyModelUsed` para probar que el dato histórico
permanece inalterado), y `outcomes` con casos `valid_success`, `success_without_artifact` y
`failure_without_advance`. Cada caso registra `exitCode`, `stdoutJsonl`, `stderr`,
`artifactValid` y `advanced`; `valid_success` puede referenciar las capturas de `dispatch`.
El verificador lee cada JSONL hasta EOF y comprueba que ambos archivos de captura existen.
La captura exitosa debe tener artefacto válido; `success_without_artifact` debe registrar
exit 0 sin artefacto y sin avance; `failure_without_advance` debe registrar exit distinto
de cero y sin avance. No escribas contenido de prompts; registra hashes. El fixture
controlado crea el artefacto sólo en el caso válido.

El verificador `adapter-poc --implementation-only` comprueba contratos y estructura sin
reclamar que estas capturas ya se ejecutaron. El modo normal exige ambas capturas y valida
resolución vigente, historial preservado, argumentos, JSONL, stderr/exit y gates de avance.

No hace falta un `model-tiers.json` propio de este adapter, a diferencia del de Coda: el profile
`core/profiles/codex.json` ya trae modelos reales para las cuatro tiers. Sí hace falta la flag
`--skip-git-repo-check` del punto 5 arriba, que ese profile no trae – encontrado y corregido acá
(no en `core`, que es de Gab) en la primera prueba en vivo de delegación real (2026-08-28, PG185).
