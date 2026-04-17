#!/usr/bin/env bash
# coordinator-score.sh — P291 v1 coordinator scoring function
#
# Pure shell implementation of the D1 observable activation heuristic from
# specs/p291-coordinator-mode-spec-drive/spec/04-Design.md. The spec-drive:coordinator
# agent invokes this script as the single source of truth for scoring, so the
# decision is reproducible across CLIs and testable without an LLM.
#
# Usage: coordinator-score.sh <basePath> <phase>
#   basePath — absolute path to the spec directory
#   phase    — "research" or "requirements"
#
# Output (key=value lines on stdout, one per line):
#   outcome=<continue_sequential|clarify_first|coordinate_research|block_and_escalate>
#   mode=<sequential|clarification|research>
#   reason=<stable string>
#   signals=<comma-separated IDs or "none">
#   score=<integer>
#
# Exit codes:
#   0 — scoring completed, outcome on stdout
#   2 — missing or unreadable input file
#   3 — bad arguments
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "usage: coordinator-score.sh <basePath> <phase>" >&2
  exit 3
fi

basePath="$1"
phase="$2"

case "$phase" in
  research|requirements) ;;
  *)
    echo "error: phase must be 'research' or 'requirements', got: $phase" >&2
    exit 3
    ;;
esac

if [ ! -d "$basePath" ]; then
  echo "error: basePath does not exist: $basePath" >&2
  exit 2
fi

idea_file="$basePath/idea.md"
research_file="$basePath/research.md"
state_file="$basePath/.spec-drive-state.json"

if [ ! -f "$idea_file" ]; then
  echo "error: idea.md not found at $idea_file" >&2
  exit 2
fi

# extract_section FILE SECTION_HEADER
# Prints content between "## SECTION_HEADER" and the next top-level "## " (or EOF).
extract_section() {
  local file="$1"
  local header="$2"
  awk -v header="## $header" '
    $0 == header { inside = 1; next }
    inside && /^## / { inside = 0 }
    inside { print }
  ' "$file"
}

# word_count_stdin — count words on stdin
word_count_stdin() {
  awk '{ for (i=1;i<=NF;i++) n++ } END { print n+0 }'
}

# ============================================================================
# Ambiguity signals (pre-requirements) — A1..A5
# ============================================================================
# These run when phase=requirements. They also inform the mutual-exclusion rule
# for phase=research: if A3 or A4 fire on idea.md alone, we override any fan-out
# decision with clarify_first because the idea itself is still unclear.

a_signals=""
a_count=0

has_conflicting=0

if [ "$phase" = "requirements" ] && [ -f "$research_file" ]; then
  # A1: ## Open Questions has at least one real question (bullet line or line containing ?).
  # "None identified." or "None" alone must NOT fire this signal.
  open_q_body="$(extract_section "$research_file" "Open Questions" || true)"
  exec_body="$(extract_section "$research_file" "Executive Summary" || true)"
  if [ -n "$open_q_body" ] && \
     printf '%s\n' "$open_q_body" | grep -qE '^[[:space:]]*-[[:space:]]|[?]'; then
    a_signals="${a_signals}A1,"
    a_count=$((a_count + 1))
  fi

  # A2: contains unresolved ambiguity markers in the sections that actually carry
  # current-state uncertainty. Avoid whole-file matching so quoted code/log text
  # (for example a literal string containing "blocked") does not trigger a false
  # escalation.
  ambiguity_scope="$exec_body"
  if [ -n "$open_q_body" ]; then
    ambiguity_scope="${ambiguity_scope}
$open_q_body"
  fi
  if printf '%s\n' "$ambiguity_scope" | grep -qiE '(TBD|\?\?\?|UNKNOWN|unclear|ambiguous|TODO)'; then
    a_signals="${a_signals}A2,"
    a_count=$((a_count + 1))
  fi
  if printf '%s\n' "$ambiguity_scope" | grep -qiE '(conflicting|contradictory|mutually exclusive|cannot both be true)'; then
    if [[ "$a_signals" != *"A2,"* ]]; then
      a_signals="${a_signals}A2,"
      a_count=$((a_count + 1))
    fi
    if printf '%s\n' "$ambiguity_scope" | grep -qiE '(conflicting|contradictory|mutually exclusive|cannot both be true)'; then
      has_conflicting=1
    fi
  fi

  # A5: ## Executive Summary contains feasibility-uncertain language
  if [ -n "$exec_body" ] && \
     printf '%s\n' "$exec_body" | grep -qiE '(feasibility unclear|depends on|depending on|requires decision|needs clarification)'; then
    a_signals="${a_signals}A5,"
    a_count=$((a_count + 1))
  fi
fi

# A3 and A4 run against idea.md regardless of phase (mutual exclusion rule)
vision_body="$(extract_section "$idea_file" "Vision" || true)"
vision_word_count=0
if [ -n "$vision_body" ]; then
  vision_word_count="$(printf '%s\n' "$vision_body" | word_count_stdin)"
fi

if [ "$vision_word_count" -lt 15 ]; then
  a_signals="${a_signals}A3,"
  a_count=$((a_count + 1))
fi

# A4: idea.md contains template placeholders or TBD/TODO
if grep -qE '(<[A-Za-z ]+>|TBD|TODO)' "$idea_file"; then
  a_signals="${a_signals}A4,"
  a_count=$((a_count + 1))
fi

# ============================================================================
# Fan-out signals (pre-research) — F1..F4
# ============================================================================

f_signals=""
f_count=0

if [ "$phase" = "research" ]; then
  # F1: Vision mentions 2+ distinct domains
  domains_hit=0
  for re in \
    '(backend|api|server)' \
    '(frontend|ui|client)' \
    '(cli|shell)' \
    '(mobile)' \
    '(ml|ai|model)' \
    '(infra|devops)'
  do
    if printf '%s\n' "$vision_body" | grep -qiE "$re"; then
      domains_hit=$((domains_hit + 1))
    fi
  done
  if [ "$domains_hit" -ge 2 ]; then
    f_signals="${f_signals}F1,"
    f_count=$((f_count + 1))
  fi

  # F2: Vision word count > 150
  if [ "$vision_word_count" -gt 150 ]; then
    f_signals="${f_signals}F2,"
    f_count=$((f_count + 1))
  fi

  # F3: 4+ consecutive list items in Vision or Constraints
  constraints_body="$(extract_section "$idea_file" "Constraints" || true)"
  max_run=0
  current_run=0
  while IFS= read -r line; do
    if printf '%s\n' "$line" | grep -qE '^- '; then
      current_run=$((current_run + 1))
      if [ "$current_run" -gt "$max_run" ]; then
        max_run=$current_run
      fi
    else
      current_run=0
    fi
  done <<EOF
$vision_body
$constraints_body
EOF
  if [ "$max_run" -ge 4 ]; then
    f_signals="${f_signals}F3,"
    f_count=$((f_count + 1))
  fi

  # F4: project name contains platform|suite|stack|system
  name=""
  if [ -f "$state_file" ] && command -v jq >/dev/null 2>&1; then
    name="$(jq -r '.name // ""' "$state_file")"
  fi
  if printf '%s\n' "$name" | grep -qiE '(platform|suite|stack|system)'; then
    f_signals="${f_signals}F4,"
    f_count=$((f_count + 1))
  fi
fi

# ============================================================================
# Decide outcome
# ============================================================================

outcome=""
mode=""
reason=""
final_signals="none"
final_score=0

if [ "$phase" = "requirements" ]; then
  final_score=$a_count
  final_signals="${a_signals%,}"
  [ -z "$final_signals" ] && final_signals="none"

  if [ "$a_count" -eq 0 ]; then
    outcome="continue_sequential"
    mode="sequential"
    reason="no_ambiguity_signals"
  elif [ "$has_conflicting" -eq 1 ] || [ "$a_count" -ge 3 ]; then
    outcome="block_and_escalate"
    mode="clarification"
    reason="high_ambiguity_or_conflict"
  else
    outcome="clarify_first"
    mode="clarification"
    reason="ambiguity_signals=${a_count}"
  fi
elif [ "$phase" = "research" ]; then
  # Mutual exclusion: if ambiguity signals A3/A4 fire on the idea alone,
  # suppress fan-out and emit clarify_first pointing at the idea.
  if printf '%s\n' "$a_signals" | grep -qE 'A3|A4'; then
    outcome="clarify_first"
    mode="clarification"
    reason="idea_too_ambiguous_for_fan_out"
    final_signals="${a_signals%,}"
    final_score=$a_count
  else
    final_score=$f_count
    final_signals="${f_signals%,}"
    [ -z "$final_signals" ] && final_signals="none"

    if [ "$f_count" -ge 2 ]; then
      outcome="coordinate_research"
      mode="research"
      reason="fan_out_signals=${f_count}"
    else
      outcome="continue_sequential"
      mode="sequential"
      reason="no_fan_out_signals"
    fi
  fi
fi

cat <<EOF
outcome=${outcome}
mode=${mode}
reason=${reason}
signals=${final_signals}
score=${final_score}
EOF
