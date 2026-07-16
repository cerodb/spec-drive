#!/usr/bin/env bash
# resolve-model.sh — tier -> {mechanism, model|cmd} resolver (FR-18, AC-3.5)
#
# Usage: resolve-model.sh <tier> [cli]
#   tier — light|standard|advanced|frontier. Any other value (unknown/absent)
#          resolves to mechanism=inherit (backward compat, AC-5.1/AC-5.2).
#   cli  — optional CLI id (claude-code|codex|coda|...). If omitted, the CLI
#          is detected from the resolved .spec-drive-config.json `cli` field
#          (see resolve-config.sh), else environment autodetection, else the
#          generic "default" profile.
#
# Resolution order per tier (FR-18):
#   ~/.config/spec-drive/profiles.local.json (XDG override, never committed)
#   -> profiles/<cli>.json                   (shipped per-CLI profile)
#   -> profiles/default.json                 (generic fallback)
#
# Output (key=value stdout, one per line):
#   mechanism=<agent|subprocess|inherit>
#   model=<id or empty>
#   cmd=<template or empty; subprocess templates must only leave {prompt} unresolved>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/resolve-config.sh"

# profiles/ ships two directories above hooks/scripts/ at the plugin/repo root.
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

tier="${1:-}"
cli_arg="${2:-}"

emit_inherit() {
    printf 'mechanism=inherit\n'
    printf 'model=\n'
    printf 'cmd=\n'
}

# emit_inherit_unresolved — tier was known but no profile (local/CLI/default) had
# an entry for it. Falls back to inherit per FR-18 / design "Error Handling",
# and records a note so callers can tell this apart from the plain
# unknown-tier backward-compat path (which never hard-fails a run).
emit_inherit_unresolved() {
    local t="$1"
    printf 'mechanism=inherit\n'
    printf 'model=\n'
    printf 'cmd=\n'
    printf 'note=model_used: inherit (unresolved:%s)\n' "$t"
}

case "$tier" in
    light|standard|advanced|frontier) ;;
    *)
        emit_inherit
        exit 0
        ;;
esac

# --- CLI detection -----------------------------------------------------
detect_cli() {
    # 1. Explicit arg wins.
    if [ -n "$cli_arg" ]; then
        printf '%s\n' "$cli_arg"
        return 0
    fi

    # 2. `cli` field in the resolved workspace/XDG spec-drive config.
    if command -v jq >/dev/null 2>&1; then
        local config_file configured_cli
        if config_file="$(spec_drive_resolve_config_file "$PWD" 2>/dev/null)"; then
            configured_cli="$(jq -r '.cli // empty' "$config_file" 2>/dev/null || true)"
            if [ -n "$configured_cli" ] && [ "$configured_cli" != "null" ]; then
                printf '%s\n' "$configured_cli"
                return 0
            fi
        fi
    fi

    # 3. Environment autodetection.
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || [ -n "${CLAUDECODE:-}" ]; then
        printf 'claude-code\n'
        return 0
    fi
    if [ -n "${CODEX_HOME:-}" ] || [ -n "${CODEX_SANDBOX:-}" ]; then
        printf 'codex\n'
        return 0
    fi

    # 4. Fallback — generic profile.
    printf 'default\n'
}

cli="$(detect_cli)"

# --- Profile lookup ------------------------------------------------------
local_profile="${XDG_CONFIG_HOME:-$HOME/.config}/spec-drive/profiles.local.json"
cli_profile="$PLUGIN_ROOT/profiles/$cli.json"
default_profile="$PLUGIN_ROOT/profiles/default.json"

lookup_tier() {
    local file="$1" t="$2"
    [ -f "$file" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    jq empty "$file" >/dev/null 2>&1 || return 1
    jq -e --arg t "$t" '.[$t] // empty' "$file" >/dev/null 2>&1 || return 1
    jq -c --arg t "$t" '.[$t]' "$file"
}

entry=""
for candidate in "$local_profile" "$cli_profile" "$default_profile"; do
    if entry="$(lookup_tier "$candidate" "$tier")"; then
        if [ -n "$entry" ] && [ "$entry" != "null" ]; then
            break
        fi
    fi
    entry=""
done

if [ -z "$entry" ]; then
    # Tier is a known tier name, but neither the local override, the CLI
    # profile, nor default.json has an entry for it. Never hard-fail a run
    # over routing (design "Error Handling") — fall back to inherit and note
    # why, distinct from the plain unknown-tier backward-compat path above.
    emit_inherit_unresolved "$tier"
    exit 0
fi

mechanism="$(printf '%s' "$entry" | jq -r '.mechanism // empty')"
model="$(printf '%s' "$entry" | jq -r '.model // empty')"
cmd="$(printf '%s' "$entry" | jq -r '.cmd // empty')"

if [ -z "$mechanism" ]; then
    emit_inherit
    exit 0
fi

# Subprocess mechanism requires a `{prompt}` placeholder in the cmd template
# so the dispatcher can substitute the actual task prompt. A template missing
# it is a config error, not a routing miss — fail fast per design "Error
# Handling" (env_error), rather than silently dispatching a broken command.
if [ "$mechanism" = "subprocess" ]; then
    case "$cmd" in
        *'{prompt}'*) ;;
        *)
            printf 'error=malformed_template\n' >&2
            printf 'reason=subprocess cmd template missing required {prompt} placeholder: %s\n' "$cmd" >&2
            exit 1
            ;;
    esac

    # Shipped non-Claude subprocess profiles are public stubs. They may contain
    # {MODEL}/{CMD} as documentation placeholders, but they are not executable
    # until a user replaces the whole cmd in profiles.local.json. Fail fast with
    # a clear config error instead of dispatching a literal placeholder to a CLI.
    case "$cmd" in
        *'{MODEL}'*|*'{CMD}'*)
            printf 'error=unresolved_placeholder\n' >&2
            printf 'reason=subprocess cmd template still contains {MODEL} or {CMD}; override this profile in profiles.local.json with a concrete command: %s\n' "$cmd" >&2
            exit 1
            ;;
    esac
fi

printf 'mechanism=%s\n' "$mechanism"
printf 'model=%s\n' "$model"
printf 'cmd=%s\n' "$cmd"
