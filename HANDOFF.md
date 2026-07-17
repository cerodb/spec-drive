# Spec-Drive v1.3.1 Handoff

## Review status

This branch contains the Adaptive Model Router v1.3.1 cross-CLI subprocess work for review. Do not merge or tag until human review completes.

## Scope

- Out-of-box automatic routing is supported for Claude Code agent profiles.
- Codex subprocess routing now uses concrete Dell-verified model IDs (`gpt-5.4-mini`, `gpt-5.4`, `gpt-5.5`, `gpt-5.6-sol`).
- Subprocess dispatch uses `agents/executor-subprocess.md`; `agents/executor.md` remains Claude-Code-flavored and is not sent verbatim to other CLIs.
- Coda and default subprocess profiles remain scaffolding stubs. They require a local `~/.config/spec-drive/profiles.local.json` override with concrete commands and model names.
- `hooks/scripts/resolve-model.sh` fails fast with `error=unresolved_placeholder` if a subprocess command still contains `{MODEL}` or `{CMD}`.
- Routing quality is LLM-driven. The fixtures are embedded as task-planner reference examples and checked for consistency; they are not a deterministic quality score for the LLM router.
- Real probes confirm `codex exec -m <model> -s danger-full-access -- ...` works for all Codex tiers and `claude -p --model claude-opus-4-8 --effort high -- "..."` runs successfully.
- End-to-end canary tasks passed through both Codex and Claude frontier subprocesses and produced parseable final `TASK_COMPLETE` lines.

## Verification

Run before merge:

```bash
npm test
bash test/test-routing.sh
bash test/test-public-clean.sh
```
