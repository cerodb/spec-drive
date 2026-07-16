#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"

FIXTURE_DIR="test/fixtures/routing"
PASS=0
FAIL=0
EXACT=0

tier_rank() {
  case "$1" in
    light) echo 0 ;;
    standard) echo 1 ;;
    advanced) echo 2 ;;
    frontier) echo 3 ;;
    *) echo -1 ;;
  esac
}

max_tier() {
  local left_rank right_rank
  left_rank="$(tier_rank "$1")"
  right_rank="$(tier_rank "$2")"
  if [ "$right_rank" -gt "$left_rank" ]; then
    echo "$2"
  else
    echo "$1"
  fi
}

matches_any() {
  local text="$1"
  shift
  local pattern
  for pattern in "$@"; do
    if printf '%s' "$text" | grep -Eq "$pattern"; then
      return 0
    fi
  done
  return 1
}

infer_surface() {
  local files_line="$1"
  local text="$2"
  local file_count
  file_count="$(printf '%s\n' "$files_line" | grep -o '`[^`]*`' | wc -l | tr -d ' ')"

  if matches_any "$text" 'public contract|public api|published task contract|downstream tools|multiple downstream|cross-repo'; then
    echo frontier
  elif [ "$file_count" -ge 4 ] || matches_any "$text" 'shared helper|multiple modules|cross-cutting|shared/cross-cutting'; then
    echo advanced
  elif [ "$file_count" -ge 2 ]; then
    echo standard
  else
    echo light
  fi
}

infer_logical() {
  local text="$1"
  if matches_any "$text" 'reconcile conflicting|breaking change|transition plan|without breaking active sessions|rollback strategy'; then
    echo frontier
  elif matches_any "$text" 'edge cases|backward compatibility|rollback-safe|migration|shared helper|duplicated fallback|regression test'; then
    echo advanced
  elif matches_any "$text" 'add (a )?validation test|assert|tighten parsing|extend the command smoke test|new .* flag'; then
    echo standard
  else
    echo light
  fi
}

infer_reversibility() {
  local text="$1"
  if matches_any "$text" 'breaking change|published task contract|live provider|stale credentials|active sessions'; then
    echo frontier
  elif matches_any "$text" 'rollback-safe|migration|persisted state|legacy|upgrade path'; then
    echo advanced
  else
    echo light
  fi
}

infer_external() {
  local text="$1"
  if matches_any "$text" 'oauth provider|live external provider|authentication|token exchange|stale credentials'; then
    echo frontier
  elif matches_any "$text" 'provider contract|third-party|external service|webhook'; then
    echo advanced
  else
    echo light
  fi
}

infer_ambiguity() {
  local text="$1"
  if matches_any "$text" 'reconcile conflicting|breaking change|transition plan'; then
    echo frontier
  elif matches_any "$text" 'rollback strategy|backward compatibility|legacy|choose'; then
    echo advanced
  elif matches_any "$text" 'small config field'; then
    echo standard
  else
    echo light
  fi
}

infer_criticality() {
  local text="$1"
  if matches_any "$text" 'live external provider|authentication|breaking change|active sessions|stale credentials'; then
    echo frontier
  elif matches_any "$text" 'rollback-safe|migration|backward compatibility|legacy'; then
    echo advanced
  else
    echo light
  fi
}

assign_tier() {
  local fixture="$1"
  local text files_line assigned signal

  text="$(tr '[:upper:]' '[:lower:]' < "$fixture")"
  files_line="$(grep -m1 '^[[:space:]]*- \*\*Files\*\*:' "$fixture" || true)"
  assigned="light"

  for signal in \
    "$(infer_logical "$text")" \
    "$(infer_surface "$files_line" "$text")" \
    "$(infer_reversibility "$text")" \
    "$(infer_external "$text")" \
    "$(infer_ambiguity "$text")" \
    "$(infer_criticality "$text")"
  do
    assigned="$(max_tier "$assigned" "$signal")"
  done

  echo "$assigned"
}

echo "=== Routing Fixture Test ==="

for fixture in "$FIXTURE_DIR"/*.md; do
  expected="$(sed -n 's/^expected_tier:[[:space:]]*//p' "$fixture" | head -n 1)"
  if [ -z "$expected" ]; then
    echo "  FAIL: $(basename "$fixture") missing expected_tier"
    FAIL=$((FAIL + 1))
    continue
  fi

  assigned="$(assign_tier "$fixture")"
  expected_rank="$(tier_rank "$expected")"
  assigned_rank="$(tier_rank "$assigned")"
  diff=$((expected_rank - assigned_rank))
  if [ "$diff" -lt 0 ]; then
    diff=$(( -diff ))
  fi

  if [ "$assigned" = "$expected" ]; then
    EXACT=$((EXACT + 1))
    PASS=$((PASS + 1))
    echo "  OK: $(basename "$fixture") expected=$expected assigned=$assigned"
  elif [ "$diff" -le 1 ]; then
    FAIL=$((FAIL + 1))
    echo "  WARN: $(basename "$fixture") expected=$expected assigned=$assigned diff=$diff"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $(basename "$fixture") expected=$expected assigned=$assigned diff=$diff"
  fi
done

TOTAL=$((PASS + FAIL))

echo ""
echo "Fixtures: $TOTAL | Exact: $EXACT | Non-exact: $((TOTAL - EXACT))"

if [ "$TOTAL" -lt 8 ]; then
  echo "FAIL: expected at least 8 fixtures"
  exit 1
fi

if [ "$EXACT" -lt 6 ]; then
  echo "FAIL: exact match threshold not met (need >= 6)"
  exit 1
fi

for fixture in "$FIXTURE_DIR"/*.md; do
  expected="$(sed -n 's/^expected_tier:[[:space:]]*//p' "$fixture" | head -n 1)"
  assigned="$(assign_tier "$fixture")"
  expected_rank="$(tier_rank "$expected")"
  assigned_rank="$(tier_rank "$assigned")"
  diff=$((expected_rank - assigned_rank))
  if [ "$diff" -lt 0 ]; then
    diff=$(( -diff ))
  fi
  if [ "$diff" -gt 1 ]; then
    echo "FAIL: fixture $(basename "$fixture") is off by more than one tier"
    exit 1
  fi
done

echo "PASS"
