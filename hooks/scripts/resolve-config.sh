#!/bin/bash
# Shared config resolution for Spec-Drive hooks and docs.
# Resolution order:
# 1. Workspace config at nearest git root (or cwd if no git root)
# 2. XDG config at ${XDG_CONFIG_HOME:-$HOME/.config}/spec-drive/config.json
# 3. Legacy home config at ~/.spec-drive-config.json

set -euo pipefail

spec_drive_expand_path() {
    local raw="$1"
    case "$raw" in
        "~") printf '%s\n' "$HOME" ;;
        "~/"*) printf '%s/%s\n' "$HOME" "${raw#~/}" ;;
        *) printf '%s\n' "$raw" ;;
    esac
}

spec_drive_workspace_root() {
    local start_dir="${1:-$PWD}"
    if [ -z "$start_dir" ] || [ ! -d "$start_dir" ]; then
        start_dir="$PWD"
    fi

    git -C "$start_dir" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$start_dir"
}

spec_drive_resolve_config_file() {
    local start_dir="${1:-$PWD}"
    local workspace_root workspace_config xdg_config legacy_config

    workspace_root="$(spec_drive_workspace_root "$start_dir")"
    workspace_config="$workspace_root/.spec-drive-config.json"
    xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}/spec-drive/config.json"
    legacy_config="$HOME/.spec-drive-config.json"

    if [ -f "$workspace_config" ] && jq empty "$workspace_config" >/dev/null 2>&1; then
        printf '%s\n' "$workspace_config"
        return 0
    fi

    if [ -f "$xdg_config" ] && jq empty "$xdg_config" >/dev/null 2>&1; then
        printf '%s\n' "$xdg_config"
        return 0
    fi

    if [ -f "$legacy_config" ] && jq empty "$legacy_config" >/dev/null 2>&1; then
        printf '%s\n' "$legacy_config"
        return 0
    fi

    return 1
}

spec_drive_resolve_project_root() {
    local start_dir="${1:-$PWD}"
    local default_root config_file raw_root config_dir expanded_root

    default_root="$HOME/spec-drive-projects"

    if ! config_file="$(spec_drive_resolve_config_file "$start_dir")"; then
        printf '%s\n' "$default_root"
        return 0
    fi

    raw_root="$(jq -r '.projectRoot // empty' "$config_file" 2>/dev/null || true)"
    if [ -z "$raw_root" ] || [ "$raw_root" = "null" ]; then
        printf '%s\n' "$default_root"
        return 0
    fi

    expanded_root="$(spec_drive_expand_path "$raw_root")"
    if [[ "$expanded_root" = /* ]]; then
        printf '%s\n' "$expanded_root"
        return 0
    fi

    config_dir="$(dirname "$config_file")"
    printf '%s\n' "$config_dir/$expanded_root"
}
