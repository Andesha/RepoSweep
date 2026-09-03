#!/bin/sh
# RepoSweep tests. One focused seam: the mechanical classification ladder — the
# tool's deterministic opinion, and the only part where a wrong change is quiet
# and costly. Feed a fixture of Normalized items, run the mechanical pass, assert
# each verdict. No network (gh), no LLM. Run: sh tests/run-tests.sh
set -u

SKILL_DIR=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
SCRIPTS="$SKILL_DIR/scripts"
FIX="$SKILL_DIR/tests/fixtures"
. "$SCRIPTS/lib.sh"

PASS=0
FAIL=0
assert_eq() { # desc expected actual
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"
  else
    FAIL=$((FAIL + 1)); printf 'FAIL - %s\n        expected [%s] got [%s]\n' "$1" "$2" "$3"
  fi
}

# Build a run from the fixture items + zero-config defaults, then classify.
work=$(mktemp -d)
run="$work/run"
mkdir -p "$run"
cp "$FIX/items.jsonl" "$run/items.jsonl"
resolve_config "$SKILL_DIR" "$work" | write_meta "$run" "2026-01-01T00:00:00Z" "owner/repo"
sh "$SCRIPTS/classify.sh" "$run" >/dev/null
V="$run/verdicts.jsonl"

bin_of()  { jq -r --argjson n "$1" 'select(.item.number==$n)|.bin' "$V"; }
dup_of()  { jq -r --argjson n "$1" 'select(.item.number==$n)|.duplicate_of' "$V"; }
size_of() { jq -r --argjson n "$1" 'select(.item.number==$n)|.item.size_bucket' "$V"; }

# Issue ladder: wontfix -> possible-duplicate -> needs-info -> close-as-stale
#               -> ready-for-agent -> ready-for-human -> needs-triage
assert_eq "issue: wontfix label"                  wontfix         "$(bin_of 101)"
assert_eq "issue: needs-info within window"       needs-info      "$(bin_of 102)"
assert_eq "issue: needs-info past window stales"  close-as-stale  "$(bin_of 103)"
assert_eq "issue: idle unqueued stales"           close-as-stale  "$(bin_of 104)"
assert_eq "issue: queued ready-for-agent exempt"  ready-for-agent "$(bin_of 105)"
assert_eq "issue: fallthrough -> needs-triage"    needs-triage    "$(bin_of 107)"

# Duplicates: the lowest (oldest) number is canonical.
assert_eq "dedup: newer -> possible-duplicate"    possible-duplicate "$(bin_of 110)"
assert_eq "dedup: points at canonical"            109                "$(dup_of 110)"
assert_eq "dedup: canonical stays null"           null               "$(dup_of 109)"

# PR ladder + sizing. A large or conflicted-and-old PR is never silently closed.
assert_eq "pr: small clean idle -> close-as-stale"      close-as-stale  "$(bin_of 201)"
assert_eq "pr: large conflicted old -> flag-for-review" flag-for-review "$(bin_of 202)"
assert_eq "pr: fresh conflict -> needs-rebase"          needs-rebase    "$(bin_of 203)"
assert_eq "pr: healthy recent -> needs-triage"          needs-triage    "$(bin_of 204)"
assert_eq "pr size: small"  small  "$(size_of 201)"
assert_eq "pr size: large"  large  "$(size_of 202)"
assert_eq "pr size: medium" medium "$(size_of 203)"

rm -rf "$work"
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
