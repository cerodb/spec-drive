# Spec-Drive 1.4.2: rama para revisión

Estado al 2026-09-26: candidato en desarrollo, sin release, tag, merge, cambio de marketplace ni instalación. Base v1.4.1 (`36196778d93e6c889d2123ba53f350f719f9ca1d`). Código verificado: `ca4b0c771eb964864a09aabc5bcb5becf84afc5b`.

## Qué cambia

- Separa el modelo del template de comando y permite overrides parciales por CLI.
- Conserva compatibilidad con configuración global legacy, con diagnóstico de conversión.
- Unifica delegaciones Agent/Task y vuelve a resolver el modelo antes de cada despacho.
- Acota recuperación a rechazo confirmado anterior al trabajo, con un único reintento y reserva persistida.
- Conserva los ajustes de contexto pertinente de ejecución y suma pruebas de regresión.

El adaptador Codex se mantiene fuera del repositorio de producto. [Su protocolo candidato](codex-adapter-protocol-es.md) se incluye como material de revisión; no cambia la instalación existente.

## Verificación

La suite completa `npm test` terminó con exit 0 sobre el commit de código indicado. El checkpoint de calidad volvió a comprobar identidad del candidato, log original completo, exit, documentación y hashes entre fuente y staging. Entre los resultados: hooks 46/46, commands 155/155, schema 63/63, cross-CLI 36/36, smoke 63/63 y pathing 10 + 10 con raíz symlinked.

Límite pendiente: la suite depende de `../release-staging` y del adaptador externo en `../adapter-codex/SKILL.md`. Es evidencia del entorno preparado; la reproducibilidad de `npm test` desde un clon limpio todavía debe resolverse. La CI remota no se ha ejecutado para este candidato. Esta rama no coincide con los filtros push de CI (`main`, `feat/**`).

Las pruebas con stubs acreditan lógica de resolución/recuperación, no acceso real a proveedores. La ejecución local previa acreditó Luna/High para tareas; no prueba todos los defaults distribuibles.

## Selección de modelos para discutir

Propuesta equilibrada para Codex, pendiente de decisión y smoke de cuenta antes de modificar perfiles:

| Nivel | Modelo propuesto | Razonamiento propuesto |
|---|---|---|
| light | gpt-6-luna | high |
| standard | gpt-6-sol | medium |
| advanced | gpt-6-sol | high |
| frontier | gpt-6-astra | high |

La elección combina los roles del catálogo local con la [guía oficial de GPT-6](https://developers.openai.com/api/docs/guides/latest-model): Luna para trabajo acotado, Sol para programación y Astra para tareas de mayor exigencia. Los esfuerzos son una propuesta del proyecto, no un benchmark comparativo. El perfil de producto conserva por ahora sus valores anteriores; no ejecutar sus defaults Codex sin revisar la selección. No repetir el modelo histórico rechazado.

Claude Code: conservar aliases haiku/sonnet/opus como punto de partida; revisar el ID fijo del nivel frontier y verificarlo en su runtime antes de afirmar disponibilidad. Coda conserva el stub inactivo. No se acreditó disponibilidad de esos proveedores.

## Foco de la revisión

1. Precedencia y compatibilidad del resolver; entradas inválidas y comandos opacos.
2. Clasificación de rechazo, persistencia de reserva y comportamiento al retomar.
3. Contrato del adaptador externo y su distribución futura.
4. Autonomía de las pruebas en un clon limpio y ejecución de CI.
5. Defaults finales y evidencia real de cada selección.

La publicación e instalación quedan diferidas por decisión del responsable. Se comparte esta rama para revisar mientras se completan los pendientes.
