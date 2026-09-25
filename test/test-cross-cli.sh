#!/usr/bin/env bash
# test-cross-cli.sh — Validate spec artifact portability across CLIs
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"

PASS=0
FAIL=0

ok() {
  PASS=$((PASS + 1))
  echo "  OK: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
}

# Canonicalize: on macOS mktemp -d returns a /var symlink path, while the
# resolver reports the physical /private/var path it resolves to.
TMP_DIR="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP_DIR"' EXIT

SPEC_DIR="$TMP_DIR/P999-cross-cli/spec"
mkdir -p "$SPEC_DIR"
STAMP="2026-03-28T00:00:00Z"

cat >"$SPEC_DIR/idea.md" <<EOF
---
spec: "P999-cross-cli"
phase: idea
created: "$STAMP"
---

# Idea: P999-cross-cli

## Vision

Create a small plugin that produces plain Markdown artifacts another CLI can continue from.

## Constraints

- Markdown only
- No proprietary state required to read artifacts
EOF

cat >"$SPEC_DIR/research.md" <<EOF
---
spec: "P999-cross-cli"
phase: research
created: "$STAMP"
---

# Research: P999-cross-cli

## Executive Summary

- Plain Markdown is portable across CLIs.
- YAML frontmatter should stay minimal and generic.

## External Research

- No external dependencies required for artifact readability.

## Codebase Analysis

- Existing prompts already write Markdown files.

## Feasibility Assessment

- Feasible with low risk.

## Open Questions

- Whether a bundle export is needed later.
EOF

cat >"$SPEC_DIR/requirements.md" <<EOF
---
spec: "P999-cross-cli"
phase: requirements
created: "$STAMP"
---

# Requirements: P999-cross-cli

## User Stories

#### US-1: Portable artifacts
**As a** developer
**I want to** read project artifacts in any CLI
**So that** work can continue without hidden session state

**Acceptance Criteria:**
- [ ] AC-1.1: Artifacts are plain Markdown files
- [ ] AC-1.2: Frontmatter uses generic YAML key/value pairs

## Functional Requirements

| ID | Description | Priority | Verification |
|----|-------------|----------|--------------|
| FR-1 | Output plain Markdown artifacts | High | Manual file inspection |

## Non-Functional Requirements

- Artifacts remain readable with basic text tools.

## Out of Scope

- Runtime-specific APIs

## Glossary

- Cross-CLI: readable by multiple coding CLIs
EOF

cat >"$SPEC_DIR/design.md" <<EOF
---
spec: "P999-cross-cli"
phase: design
created: "$STAMP"
---

# Design: P999-cross-cli

## Architecture Overview

Artifacts are written as standalone Markdown files with simple YAML frontmatter.

## Components

- Artifact writer
- Artifact reader

## Data Flow

Idea feeds research, research feeds requirements, requirements feed design and tasks.

## Technical Decisions

- Use plain Markdown for maximum portability.

## Error Handling

- If a file is missing, the next CLI reports the missing artifact explicitly.
EOF

cat >"$SPEC_DIR/tasks.md" <<EOF
---
spec: "P999-cross-cli"
phase: tasks
created: "$STAMP"
---

# Tasks: P999-cross-cli

## Phase 1: Make It Work (POC)

- [ ] 1.1 Write artifact files

## Phase 2: Refactoring

- [ ] 2.1 Normalize headings

## Phase 3: Testing

- [ ] 3.1 Verify Markdown portability

## Phase 4: Quality Gates

- [ ] 4.1 Run cross-CLI validation
EOF

FILES=(idea.md research.md requirements.md design.md tasks.md)

echo "=== Spec-Drive Cross-CLI Artifact Test ==="
echo "-- Generated sample spec at $SPEC_DIR"

echo "-- Plain text / Markdown checks..."
for f in "${FILES[@]}"; do
  MIME="$(file --mime-type -b "$SPEC_DIR/$f" || true)"
  case "$MIME" in
    text/*) ok "$f is text ($MIME)" ;;
    *) fail "$f is not text ($MIME)" ;;
  esac
done

echo "-- YAML frontmatter checks..."
for f in "${FILES[@]}"; do
  FILE="$SPEC_DIR/$f"
  FIRST="$(head -1 "$FILE")"
  SECOND_DELIM_COUNT="$(grep -c '^---$' "$FILE")"
  if [ "$FIRST" = "---" ] && [ "$SECOND_DELIM_COUNT" -ge 2 ]; then
    ok "$f has frontmatter delimiters"
  else
    fail "$f frontmatter delimiters invalid"
    continue
  fi

  FRONTMATTER="$(sed -n '2,/^---$/p' "$FILE" | sed '$d')"
  if echo "$FRONTMATTER" | grep -q '^spec:' && \
     echo "$FRONTMATTER" | grep -q '^phase:' && \
     echo "$FRONTMATTER" | grep -q '^created:'; then
    ok "$f frontmatter has spec/phase/created"
  else
    fail "$f frontmatter missing required keys"
  fi
done

echo "-- Template variable checks..."
if grep -rn '{{.\+}}' "$SPEC_DIR" >/dev/null 2>&1; then
  fail "rendered sample still contains template variables"
else
  ok "no template variables remain in rendered artifacts"
fi

echo "-- Self-contained readability checks..."
for f in "${FILES[@]}"; do
  FILE="$SPEC_DIR/$f"
  # Check file has a heading AND at least one line of body content (not just frontmatter/headings/table dividers)
  if grep -q '^# ' "$FILE" && grep -Evq '^\s*(<!--|---|spec:|phase:|created:|#|##|\|[- ]*$)' "$FILE"; then
    ok "$f has readable body content"
  else
    fail "$f lacks readable body content"
  fi

  if grep -nE 'hidden context|as discussed above|see chat|tool state' "$FILE" >/dev/null 2>&1; then
    fail "$f references hidden context"
  else
    ok "$f does not depend on hidden context"
  fi
done

# Candidate resolver portability matrix, sharing the fixture with test-smoke.
echo "-- Resolver candidate C1/C2 matrix..."
RESOLVER_SCRIPT="$PLUGIN_ROOT/hooks/scripts/resolve-model.sh"
RESOLVER_CASES="$PLUGIN_ROOT/test/fixtures/model-recovery/resolver-cases.json"
RESOLVER_XDG="$TMP_DIR/resolver-xdg"
mkdir -p "$RESOLVER_XDG/spec-drive"
RESOLVER_PROFILE="$RESOLVER_XDG/spec-drive/profiles.local.json"
jq -n --slurpfile cases "$RESOLVER_CASES" '
  ($cases[0]) as $c |
  {profiles:{
    codex:{light:$c.scenarios.codex},
    "claude-code":{light:$c.scenarios["claude-code"]},
    coda:{light:$c.scenarios.coda}
  }}' > "$RESOLVER_PROFILE"

for resolver_cli in $(jq -r '.clis[]' "$RESOLVER_CASES"); do
  resolver_model="$(jq -r --arg cli "$resolver_cli" '.scenarios[$cli].model' "$RESOLVER_CASES")"
  resolver_mechanism="$(jq -r --arg cli "$resolver_cli" '.scenarios[$cli].mechanism' "$RESOLVER_CASES")"
  resolver_err="$TMP_DIR/resolver-$resolver_cli.stderr"
  resolver_out="$(XDG_CONFIG_HOME="$RESOLVER_XDG" bash "$RESOLVER_SCRIPT" light "$resolver_cli" 2>"$resolver_err")"
  if printf '%s\n' "$resolver_out" | grep -Fqx "cli=$resolver_cli" && \
     printf '%s\n' "$resolver_out" | grep -Fqx "model=$resolver_model" && \
     printf '%s\n' "$resolver_out" | grep -Fqx "mechanism=$resolver_mechanism" && \
     [ ! -s "$resolver_err" ]; then
    ok "$resolver_cli explicit CLI selection uses its fixture profile"
  else
    fail "$resolver_cli explicit CLI selection did not match the fixture"
  fi
done

# Exercise legacy global warning and scoped-over-legacy precedence, then partial
# inheritance and explicit stubs/inherit behavior without commercial model IDs.
jq --arg model "$(jq -r '.models.beta' "$RESOLVER_CASES")" \
  '. + {light:{mechanism:"unsupported",model:$model}}' "$RESOLVER_PROFILE" > "$RESOLVER_PROFILE.next"
mv "$RESOLVER_PROFILE.next" "$RESOLVER_PROFILE"
legacy_out="$(XDG_CONFIG_HOME="$RESOLVER_XDG" bash "$RESOLVER_SCRIPT" light codex 2>"$TMP_DIR/resolver-legacy.stderr")"
if printf '%s\n' "$legacy_out" | grep -Fqx "model=$(jq -r '.models.alpha' "$RESOLVER_CASES")" && \
   grep -q '^warning=legacy_global_override$' "$TMP_DIR/resolver-legacy.stderr" && \
   ! grep -q 'fixture-model-' "$TMP_DIR/resolver-legacy.stderr"; then
  ok "global legacy warning is sanitized while scoped profile keeps precedence"
else
  fail "legacy warning or scoped precedence regression"
fi

jq -n --slurpfile cases "$RESOLVER_CASES" '
  ($cases[0]) as $c |
  {profiles:{($c.partial.cli):{($c.partial.tier):{model:$c.partial.model}}},
   ($c.partial.tier):$c.partial.base}' > "$RESOLVER_PROFILE"
partial_out="$(XDG_CONFIG_HOME="$RESOLVER_XDG" bash "$RESOLVER_SCRIPT" \
  "$(jq -r '.partial.tier' "$RESOLVER_CASES")" "$(jq -r '.partial.cli' "$RESOLVER_CASES")" 2>"$TMP_DIR/resolver-partial.stderr")"
if printf '%s\n' "$partial_out" | grep -Fqx "cmd=$(jq -r '.partial.expectedCmd' "$RESOLVER_CASES")" && \
   printf '%s\n' "$partial_out" | grep -Fqx "model=$(jq -r '.partial.model' "$RESOLVER_CASES")" && \
   grep -q '^warning=legacy_global_override$' "$TMP_DIR/resolver-partial.stderr" && \
   ! grep -q 'fixture-model-' "$TMP_DIR/resolver-partial.stderr"; then
  ok "partial model override inherits compatible command base"
else
  fail "partial override did not preserve its compatible command base"
fi

# Shipped Coda profiles are stubs and remain unresolved; explicit inherit is
# honored, and malformed CLI path inputs cannot escape the profile directory.
set +e
stub_out="$(bash "$RESOLVER_SCRIPT" light coda 2>"$TMP_DIR/resolver-stub.stderr")"
stub_status=$?
set -e
jq -n '{profiles:{codex:{advanced:{mechanism:"inherit"}}}}' > "$RESOLVER_PROFILE"
inherit_out="$(XDG_CONFIG_HOME="$RESOLVER_XDG" bash "$RESOLVER_SCRIPT" advanced codex 2>"$TMP_DIR/resolver-inherit.stderr")"
if [ "$stub_status" -ne 0 ] && grep -q '^error=invalid_profile$' "$TMP_DIR/resolver-stub.stderr" && \
   grep -Fq 'requires an explicit model' "$TMP_DIR/resolver-stub.stderr" && \
   [ -z "$stub_out" ] && printf '%s\n' "$inherit_out" | grep -Fqx 'mechanism=inherit' && \
   [ ! -s "$TMP_DIR/resolver-inherit.stderr" ]; then
  ok "shipped Coda stub fails closed and explicit inherit is supported"
else
  fail "stub or explicit inherit compatibility changed"
fi

resolver_sentinel="$TMP_DIR/$(jq -r '.sentinel' "$RESOLVER_CASES")"
for unsafe_cli in $(jq -r '.unsafeCliIds[]' "$RESOLVER_CASES"); do
  set +e
  hostile_out="$(XDG_CONFIG_HOME="$RESOLVER_XDG" bash "$RESOLVER_SCRIPT" light "$unsafe_cli" 2>"$TMP_DIR/resolver-hostile-cli.stderr")"
  hostile_status=$?
  set -e
  if [ "$hostile_status" -eq 1 ] && [ -z "$hostile_out" ] && [ ! -e "$resolver_sentinel" ]; then
    ok "hostile CLI path is rejected without filesystem effects"
  else
    fail "hostile CLI path caused output or filesystem effects"
  fi
done

echo ""
echo "Passed: $PASS | Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "PASS"
exit 0
