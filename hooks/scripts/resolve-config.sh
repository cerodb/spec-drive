#!/bin/bash
# Shared config resolution for Spec-Drive hooks and docs.
# Resolution order is per key:
# 1. nearest ancestor config with explicit scope: project
# 2. nearest ancestor config with explicit scope: workspace, or legacy unscoped
# 3. legacy XDG config at ${XDG_CONFIG_HOME:-$HOME/.config}/spec-drive/config.json

set -euo pipefail

# portable_realpath — resolve absolute canonical path without GNU readlink -f.
# Works on Linux (GNU coreutils), macOS (BSD), and any system with python3.
# Falls back to cd/pwd -P for pure-shell resolution.
portable_realpath() {
    local path="$1"
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import os, sys; print(os.path.realpath(sys.argv[1]))" "$path"
    elif command -v realpath >/dev/null 2>&1; then
        realpath "$path"
    elif [ -d "$path" ]; then
        (cd "$path" && pwd -P)
    else
        local dir base
        dir="$(dirname "$path")"
        base="$(basename "$path")"
        if [ -d "$dir" ]; then
            echo "$(cd "$dir" && pwd -P)/$base"
        else
            printf '%s\n' "$path"
        fi
    fi
}

spec_drive_expand_path() {
    local raw="$1"
    case "$raw" in
        "~") printf '%s\n' "$HOME" ;;
        "~/"*) printf '%s/%s\n' "$HOME" "${raw#~/}" ;;
        *) printf '%s\n' "$raw" ;;
    esac
}

spec_drive_path_from_config_dir() {
    local raw="$1"
    local config_file="$2"
    local expanded

    expanded="$(spec_drive_expand_path "$raw")"
    if [[ "$expanded" = /* ]]; then
        printf '%s\n' "$expanded"
    else
        printf '%s\n' "$(dirname "$config_file")/$expanded"
    fi
}

spec_drive_config_error() {
    local path="$1"
    local reason="$2"
    printf 'Invalid Spec-Drive config: %s: %s\n' "$path" "$reason" >&2
}

spec_drive_json_has_key() {
    local file="$1"
    local key="$2"
    jq -e --arg key "$key" 'has($key)' "$file" >/dev/null 2>&1
}

spec_drive_json_value() {
    local file="$1"
    local key="$2"
    jq -r --arg key "$key" '.[$key] // empty' "$file"
}

spec_drive_validate_config_file() {
    local path="$1"
    local scope project_slug workspace_root projects_path project_root container

    if ! jq empty "$path" >/dev/null 2>&1; then
        spec_drive_config_error "$path" "invalid JSON"
        return 3
    fi

    scope="$(jq -r '.scope // empty' "$path")"
    case "$scope" in
        project)
            project_slug="$(jq -r '.projectSlug // empty' "$path")"
            if [ -z "$project_slug" ]; then
                spec_drive_config_error "$path" "scope project requires projectSlug"
                return 3
            fi
            case "$project_slug" in
                "."|".."|*/*|*\\*|"")
                    spec_drive_config_error "$path" "projectSlug must be a safe path segment"
                    return 3
                    ;;
            esac
            if spec_drive_json_has_key "$path" "workspaceRoot" || spec_drive_json_has_key "$path" "projectsPath" || spec_drive_json_has_key "$path" "projectRoot"; then
                spec_drive_config_error "$path" "scope project cannot declare workspaceRoot, projectsPath, or projectRoot"
                return 3
            fi
            ;;
        workspace)
            workspace_root="$(jq -r '.workspaceRoot // empty' "$path")"
            projects_path="$(jq -r '.projectsPath // empty' "$path")"
            if [ -z "$workspace_root" ]; then
                spec_drive_config_error "$path" "scope workspace requires workspaceRoot"
                return 3
            fi
            if [ -z "$projects_path" ]; then
                spec_drive_config_error "$path" "scope workspace requires projectsPath"
                return 3
            fi
            case "$projects_path" in
                /*)
                    spec_drive_config_error "$path" "projectsPath must be relative"
                    return 3
                    ;;
            esac
            if spec_drive_json_has_key "$path" "projectSlug" || spec_drive_json_has_key "$path" "projectRoot"; then
                spec_drive_config_error "$path" "scope workspace cannot declare projectSlug or projectRoot"
                return 3
            fi
            workspace_root="$(spec_drive_path_from_config_dir "$workspace_root" "$path")"
            container="$(portable_realpath "$workspace_root/$projects_path")"
            case "$container" in
                "$(portable_realpath "$workspace_root")"| "$(portable_realpath "$workspace_root")"/*) ;;
                *)
                    spec_drive_config_error "$path" "projectsPath must not escape workspaceRoot"
                    return 3
                    ;;
            esac
            ;;
        "")
            if spec_drive_json_has_key "$path" "projectRoot"; then
                project_root="$(jq -r '.projectRoot // empty' "$path")"
                if [ -z "$project_root" ]; then
                    spec_drive_config_error "$path" "legacy projectRoot cannot be empty"
                    return 3
                fi
            fi
            ;;
        *)
            spec_drive_config_error "$path" "unsupported scope '$scope'"
            return 3
            ;;
    esac

    return 0
}

spec_drive_start_dir() {
    local start_dir="${1:-$PWD}"
    if [ -z "$start_dir" ]; then
        start_dir="$PWD"
    fi
    if [ -f "$start_dir" ]; then
        start_dir="$(dirname "$start_dir")"
    fi
    if [ ! -d "$start_dir" ]; then
        start_dir="$PWD"
    fi
    portable_realpath "$start_dir"
}

spec_drive_xdg_config_path() {
    printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/spec-drive/config.json"
}

spec_drive_validate_discovered_configs() {
    local start_dir="$1"
    local dir candidate xdg_config

    dir="$(spec_drive_start_dir "$start_dir")"
    while :; do
        candidate="$dir/.spec-drive-config.json"
        if [ -f "$candidate" ]; then
            spec_drive_validate_config_file "$candidate" || return $?
        fi
        [ "$dir" = "/" ] && break
        dir="$(dirname "$dir")"
    done

    xdg_config="$(spec_drive_xdg_config_path)"
    if [ -f "$xdg_config" ]; then
        spec_drive_validate_config_file "$xdg_config" || return $?
    fi

    return 0
}

spec_drive_find_scoped_config() {
    local wanted_scope="$1"
    local start_dir="$2"
    local dir candidate scope

    dir="$(spec_drive_start_dir "$start_dir")"
    while :; do
        candidate="$dir/.spec-drive-config.json"
        if [ -f "$candidate" ]; then
            scope="$(jq -r '.scope // empty' "$candidate")"
            if [ "$wanted_scope" = "workspace" ] && { [ "$scope" = "workspace" ] || [ -z "$scope" ]; }; then
                printf '%s\n' "$candidate"
                return 0
            fi
            if [ "$wanted_scope" = "project" ] && [ "$scope" = "project" ]; then
                printf '%s\n' "$candidate"
                return 0
            fi
        fi
        [ "$dir" = "/" ] && break
        dir="$(dirname "$dir")"
    done

    return 1
}

spec_drive_resolve_config_file() {
    local start_dir="${1:-$PWD}"
    local config_file

    spec_drive_validate_discovered_configs "$start_dir" || return $?

    for scope in project workspace; do
        if config_file="$(spec_drive_find_scoped_config "$scope" "$start_dir")"; then
            printf '%s\n' "$config_file"
            return 0
        fi
    done

    config_file="$(spec_drive_xdg_config_path)"
    if [ -f "$config_file" ]; then
        printf '%s\n' "$config_file"
        return 0
    fi

    return 1
}

spec_drive_resolve_value() {
    local key="$1"
    local start_dir="${2:-$PWD}"
    local config_file scope

    case "$key" in
        projectRoot|projectsContainer)
            if [ "$key" = "projectRoot" ]; then
                spec_drive_resolve_context "$start_dir" | jq -r '.projectRoot // .projectsContainer'
            else
                spec_drive_resolve_projects_container "$start_dir"
            fi
            return 0
            ;;
    esac

    spec_drive_validate_discovered_configs "$start_dir" || return $?

    for scope in project workspace; do
        if config_file="$(spec_drive_find_scoped_config "$scope" "$start_dir")" && spec_drive_json_has_key "$config_file" "$key"; then
            spec_drive_json_value "$config_file" "$key"
            return 0
        fi
    done

    config_file="$(spec_drive_xdg_config_path)"
    if [ -f "$config_file" ] && spec_drive_json_has_key "$config_file" "$key"; then
        spec_drive_json_value "$config_file" "$key"
        return 0
    fi

    return 1
}

spec_drive_resolve_context() {
    local start_dir="${1:-$PWD}"
    local project_config="" workspace_config="" xdg_config=""
    local workspace_root="" projects_path="" projects_container=""
    local project_slug="" project_root="" cli=""
    local raw config_dir project_config_root

    spec_drive_validate_discovered_configs "$start_dir" || return $?

    project_config="$(spec_drive_find_scoped_config project "$start_dir" || true)"
    workspace_config="$(spec_drive_find_scoped_config workspace "$start_dir" || true)"
    xdg_config="$(spec_drive_xdg_config_path)"
    [ -f "$xdg_config" ] || xdg_config=""

    if [ -n "$workspace_config" ]; then
        case "$(jq -r '.scope // empty' "$workspace_config")" in
            workspace)
                raw="$(spec_drive_json_value "$workspace_config" "workspaceRoot")"
                workspace_root="$(spec_drive_path_from_config_dir "$raw" "$workspace_config")"
                projects_path="$(spec_drive_json_value "$workspace_config" "projectsPath")"
                projects_container="$(portable_realpath "$workspace_root/$projects_path")"
                workspace_root="$(portable_realpath "$workspace_root")"
                ;;
            "")
                raw="$(spec_drive_json_value "$workspace_config" "projectRoot")"
                if [ -n "$raw" ]; then
                    projects_container="$(portable_realpath "$(spec_drive_path_from_config_dir "$raw" "$workspace_config")")"
                fi
                ;;
        esac
    fi

    if [ -z "$projects_container" ] && [ -n "$xdg_config" ]; then
        raw="$(spec_drive_json_value "$xdg_config" "projectRoot")"
        if [ -n "$raw" ]; then
            projects_container="$(portable_realpath "$(spec_drive_path_from_config_dir "$raw" "$xdg_config")")"
        fi
    fi

    if [ -z "$projects_container" ]; then
        projects_container="$HOME/spec-drive-projects"
    fi
    projects_container="$(portable_realpath "$projects_container")"

    if [ -z "$workspace_root" ]; then
        workspace_root="$(dirname "$projects_container")"
    fi
    if [ -z "$projects_path" ]; then
        projects_path="$(basename "$projects_container")"
    fi

    if [ -n "$project_config" ]; then
        project_slug="$(spec_drive_json_value "$project_config" "projectSlug")"
        project_root="$(portable_realpath "$projects_container/$project_slug")"
        project_config_root="$(portable_realpath "$(dirname "$project_config")")"
        if [ "$project_config_root" != "$project_root" ]; then
            spec_drive_config_error "$project_config" "projectSlug does not match resolved project path"
            return 3
        fi
    fi

    cli="$(spec_drive_resolve_value cli "$start_dir" 2>/dev/null || true)"

    jq -n \
        --arg projectConfig "$project_config" \
        --arg workspaceConfig "$workspace_config" \
        --arg xdgConfig "$xdg_config" \
        --arg workspaceRoot "$workspace_root" \
        --arg projectsPath "$projects_path" \
        --arg projectsContainer "$projects_container" \
        --arg projectSlug "$project_slug" \
        --arg projectRoot "$project_root" \
        --arg cli "$cli" \
        '{
            workspaceRoot: $workspaceRoot,
            projectsPath: $projectsPath,
            projectsContainer: $projectsContainer
        }
        + (if $projectConfig != "" then {projectConfig: $projectConfig} else {} end)
        + (if $workspaceConfig != "" then {workspaceConfig: $workspaceConfig} else {} end)
        + (if $xdgConfig != "" then {xdgConfig: $xdgConfig} else {} end)
        + (if $projectSlug != "" then {projectSlug: $projectSlug} else {} end)
        + (if $projectRoot != "" then {projectRoot: $projectRoot} else {} end)
        + (if $cli != "" then {cli: $cli} else {} end)'
}

spec_drive_resolve_projects_container() {
    local start_dir="${1:-$PWD}"
    spec_drive_resolve_context "$start_dir" | jq -r '.projectsContainer'
}

spec_drive_workspace_root() {
    local start_dir="${1:-$PWD}"
    spec_drive_resolve_context "$start_dir" | jq -r '.workspaceRoot'
}

spec_drive_resolve_project_root() {
    local start_dir="${1:-$PWD}"
    spec_drive_resolve_projects_container "$start_dir"
}
