# Spec-Drive v1.3.0 Handoff

## Review status

This branch contains the Adaptive Model Router v1.3.0 work for review. Do not merge or tag until human review completes.

## Scope

- Out-of-box automatic routing is supported for Claude Code agent profiles.
- Codex, Coda, and default subprocess profiles are scaffolding stubs. They require a local `~/.config/spec-drive/profiles.local.json` override with concrete commands and model names.
- `hooks/scripts/resolve-model.sh` fails fast with `error=unresolved_placeholder` if a subprocess command still contains `{MODEL}` or `{CMD}`.
- Routing quality is LLM-driven. The fixtures are embedded as task-planner reference examples and checked for consistency; they are not a deterministic quality score for the LLM router.
- `claude -p --help` confirms `--effort` is accepted for the shipped Claude Code frontier subprocess command.

## Verification

Run before merge:

```bash
npm test
bash test/test-routing.sh
bash test/test-public-clean.sh
```
