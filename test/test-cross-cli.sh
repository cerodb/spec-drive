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

TMP_DIR="$(mktemp -d)"
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

  FRONTMATTER="$(sed -n '2,/^---$/p' "$FILE" | head -n -1)"
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

echo ""
echo "Passed: $PASS | Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "PASS"
exit 0
