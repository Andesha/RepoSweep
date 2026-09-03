#!/bin/sh
# RepoSweep test suite. Plain POSIX sh assertions (no bats) — the skill is
# shell, and a dependency-free runner earns its keep here. Only jq is required.
#
# Tests assert behaviour at the seam: feed a fixture, check the emitted
# artifact. No test reaches into how a script computes a value, and none touches
# the network (gh) or the LLM. Run: sh tests/run-tests.sh
set -u

SKILL_DIR=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
SCRIPTS="$SKILL_DIR/scripts"
FIX="$SKILL_DIR/tests/fixtures"
. "$SCRIPTS/lib.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }
assert_eq() { # desc expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi
}

# --- resolve one key from a resolved KEY=VALUE block -------------------------
val_of() { # key <<lines
  awk -F= -v k="$1" '$1==k{print $2}'
}

# ============================================================================
# Config resolution (issue #13)
# ============================================================================
config_tests() {
  work=$(mktemp -d)

  # zero-config: no reposweep.env, no env overrides -> shipped defaults
  resolved=$(resolve_config "$SKILL_DIR" "$work")
  assert_eq "zero-config STALE_DAYS = default 60" 60 "$(printf '%s\n' "$resolved" | val_of STALE_DAYS)"
  assert_eq "zero-config NEEDS_INFO_DAYS = default 7" 7 "$(printf '%s\n' "$resolved" | val_of NEEDS_INFO_DAYS)"
  assert_eq "zero-config DEDUP_MAX_PARTNERS = default 5" 5 "$(printf '%s\n' "$resolved" | val_of DEDUP_MAX_PARTNERS)"
  # every key present
  assert_eq "zero-config emits all 9 keys" 9 "$(printf '%s\n' "$resolved" | grep -c '=')"

  # reposweep.env overrides a default; unspecified keys stay at default (partial)
  printf 'STALE_DAYS=30\n' > "$work/reposweep.env"
  resolved=$(resolve_config "$SKILL_DIR" "$work")
  assert_eq "reposweep.env overrides STALE_DAYS -> 30" 30 "$(printf '%s\n' "$resolved" | val_of STALE_DAYS)"
  assert_eq "partial reposweep.env leaves NEEDS_INFO_DAYS at default 7" 7 "$(printf '%s\n' "$resolved" | val_of NEEDS_INFO_DAYS)"

  # environment variable beats reposweep.env (defaults < reposweep.env < env)
  resolved=$(STALE_DAYS=15 resolve_config "$SKILL_DIR" "$work")
  assert_eq "env STALE_DAYS=15 beats reposweep.env STALE_DAYS=30" 15 "$(printf '%s\n' "$resolved" | val_of STALE_DAYS)"

  # env override with NO reposweep.env still beats the default
  rm -f "$work/reposweep.env"
  resolved=$(NEEDS_INFO_DAYS=3 resolve_config "$SKILL_DIR" "$work")
  assert_eq "env NEEDS_INFO_DAYS=3 beats default 7" 3 "$(printf '%s\n' "$resolved" | val_of NEEDS_INFO_DAYS)"
  assert_eq "env override leaves other keys at default" 60 "$(printf '%s\n' "$resolved" | val_of STALE_DAYS)"

  rm -rf "$work"
}

# ============================================================================
# Run scaffolding + meta.json (issue #13)
# ============================================================================
run_tests() {
  work=$(mktemp -d)
  base="$work/.reposweep/runs"
  mkdir -p "$base"

  rid=$(REPOSWEEP_NOW=1700000000 run_id)
  sa=$(REPOSWEEP_NOW=1700000000 swept_at)
  rundir=$(create_run "$base" "$rid")
  resolve_config "$SKILL_DIR" "$work" | write_meta "$rundir" "$sa" "owner/repo"
  update_latest "$base" "$rid"

  assert_eq "run directory created" 1 "$([ -d "$rundir" ] && echo 1 || echo 0)"
  assert_eq "meta.json created" 1 "$([ -f "$rundir/meta.json" ] && echo 1 || echo 0)"
  assert_eq "meta records swept_at" "$sa" "$(jq -r .swept_at "$rundir/meta.json")"
  assert_eq "meta records resolved STALE_DAYS as number" 60 "$(jq -r .thresholds.STALE_DAYS "$rundir/meta.json")"
  assert_eq "meta thresholds STALE_DAYS is a JSON number" number "$(jq -r '.thresholds.STALE_DAYS|type' "$rundir/meta.json")"
  assert_eq "meta records all 9 thresholds" 9 "$(jq -r '.thresholds|length' "$rundir/meta.json")"

  # latest points to the newest run
  latest_target=$( (cd "$base" && { readlink latest 2>/dev/null || cat latest; }) )
  assert_eq "latest points to the run" "$rid" "$latest_target"

  # a second, later run repoints latest
  rid2=$(REPOSWEEP_NOW=1700000060 run_id)
  create_run "$base" "$rid2" >/dev/null
  update_latest "$base" "$rid2"
  latest_target=$( (cd "$base" && { readlink latest 2>/dev/null || cat latest; }) )
  assert_eq "latest repoints to the newest run" "$rid2" "$latest_target"

  rm -rf "$work"
}

# ============================================================================
# Mechanical classification pipeline (issue #12) — the one automated seam.
# Feed the fixture items + resolved defaults, assert verdicts.jsonl.
# ============================================================================
classify_tests() {
  work=$(mktemp -d)
  run="$work/run"
  mkdir -p "$run"
  cp "$FIX/items.jsonl" "$run/items.jsonl"
  # resolve zero-config defaults, freeze swept_at at the fixture's reference instant
  resolve_config "$SKILL_DIR" "$work" | write_meta "$run" "2026-01-01T00:00:00Z" "owner/repo"
  sh "$SCRIPTS/classify.sh" "$run" >/dev/null
  V="$run/verdicts.jsonl"

  # bin_of NUMBER; dup_of NUMBER; field NUMBER FILTER
  bin_of() { jq -r --argjson n "$1" 'select(.item.number==$n)|.bin' "$V"; }
  dup_of() { jq -r --argjson n "$1" 'select(.item.number==$n)|.duplicate_of' "$V"; }
  field()  { jq -r --argjson n "$1" 'select(.item.number==$n)|'"$2" "$V"; }

  # -- issue ladder rungs --
  assert_eq "issue wontfix label -> wontfix"                 wontfix          "$(bin_of 101)"
  assert_eq "needs-info within window -> needs-info"         needs-info       "$(bin_of 102)"
  assert_eq "needs-info past NEEDS_INFO_DAYS -> close-as-stale (fast-stale)" close-as-stale "$(bin_of 103)"
  assert_eq "idle unqueued issue -> close-as-stale"          close-as-stale   "$(bin_of 104)"
  assert_eq "queued ready-for-agent exempt from staleness"   ready-for-agent  "$(bin_of 105)"
  assert_eq "queued ready-for-human"                          ready-for-human  "$(bin_of 106)"
  assert_eq "fallthrough issue -> needs-triage"              needs-triage     "$(bin_of 107)"
  assert_eq "needs-triage seeds needs_agent"                 true             "$(field 107 .needs_agent)"

  # -- flags --
  assert_eq "good-first-issue surfaces as a flag"            true "$(field 108 '(.flags|any(.=="good-first-issue"))')"
  assert_eq "question-shaped title surfaces as a flag"       true "$(field 102 '(.flags|any(.=="question-shaped"))')"

  # -- duplicate nomination: lower number is canonical --
  assert_eq "dedup: newer item -> possible-duplicate"        possible-duplicate "$(bin_of 110)"
  assert_eq "dedup: newer points at lower (canonical) number" 109              "$(dup_of 110)"
  assert_eq "dedup: canonical item keeps duplicate_of null"  null             "$(dup_of 109)"
  assert_eq "dedup nomination seeds needs_agent"             true             "$(field 110 .needs_agent)"

  # -- PR ladder rungs --
  assert_eq "small clean idle PR -> close-as-stale"          close-as-stale   "$(bin_of 201)"
  assert_eq "large conflicted old PR -> flag-for-review (never closed)" flag-for-review "$(bin_of 202)"
  assert_eq "fresh conflicted PR -> needs-rebase"            needs-rebase     "$(bin_of 203)"
  assert_eq "recent clean small PR -> needs-triage"          needs-triage     "$(bin_of 204)"
  assert_eq "healthy PR carries healthy flag"                true "$(field 204 '(.flags|any(.=="healthy"))')"
  assert_eq "large fresh draft PR -> needs-triage (draft is a facet, not a bin)" needs-triage "$(bin_of 205)"
  assert_eq "dedup PR: newer -> possible-duplicate"          possible-duplicate "$(bin_of 207)"
  assert_eq "dedup PR: canonical is lower number"            206              "$(dup_of 207)"
  # PR staleness uses STALE_DAYS, never the needs-info fast-stale window:
  # a needs-info PR idle 12d (> NEEDS_INFO_DAYS, < STALE_DAYS) is NOT closed.
  assert_eq "needs-info PR past 7d but under STALE_DAYS -> not close-as-stale" needs-triage "$(bin_of 209)"

  # -- derived facets --
  assert_eq "PR size bucketing: small"                       small            "$(field 201 .item.size_bucket)"
  assert_eq "PR size bucketing: large"                       large            "$(field 202 .item.size_bucket)"
  assert_eq "PR size bucketing: medium"                      medium           "$(field 203 .item.size_bucket)"
  assert_eq "PR long_lived derived from age"                 true             "$(field 202 .item.long_lived)"
  assert_eq "PR conflicted derived from mergeable_state"     true             "$(field 203 .item.conflicted)"

  # -- normalized item passes through intact (facets never dropped) --
  assert_eq "draft facet preserved on embedded item"         true             "$(field 205 .item.is_draft)"
  assert_eq "bot facet preserved on embedded item"           true             "$(field 208 .item.is_bot)"

  # -- items.jsonl is left carrying the full Normalized item shape --
  assert_eq "items.jsonl carries derived size_bucket" small \
    "$(jq -r 'select(.number==201)|.size_bucket' "$run/items.jsonl")"
  assert_eq "items.jsonl carries derived long_lived" true \
    "$(jq -r 'select(.number==202)|.long_lived' "$run/items.jsonl")"

  # -- propose-only: every line is a verdict, one per item, nothing else --
  assert_eq "one verdict per fixture item"                   19               "$(wc -l < "$V" | tr -d ' ')"

  rm -rf "$work"
}

# ============================================================================
# Fetch-and-normalize transform (the tracker seam) against a recorded sample.
# The gh network call is out of scope for automation; the pure normalize
# transform is not.
# ============================================================================
normalize_tests() {
  ni=$(jq -c --arg kind issue -f "$SCRIPTS/normalize.jq" "$FIX/gh-issues.sample.json")
  np=$(jq -c --arg kind pr    -f "$SCRIPTS/normalize.jq" "$FIX/gh-prs.sample.json")
  nfield() { printf '%s\n' "$1" | jq -r --argjson n "$2" 'select(.number==$n)|'"$3"; }

  assert_eq "normalize issue: kind"          issue "$(nfield "$ni" 501 .kind)"
  assert_eq "normalize issue: author login"  rgomez "$(nfield "$ni" 501 .author)"
  assert_eq "normalize issue: state lowered" open  "$(nfield "$ni" 501 .state)"
  assert_eq "normalize issue: carried_labels raw strings" "type:bug needs-info" "$(nfield "$ni" 501 '(.carried_labels|join(" "))')"
  assert_eq "normalize issue: type from bug label"     bug     "$(nfield "$ni" 501 .type)"
  assert_eq "normalize issue: type from enhancement"   feature "$(nfield "$ni" 502 .type)"

  assert_eq "normalize pr: kind"                 pr    "$(nfield "$np" 610 .kind)"
  assert_eq "normalize pr: is_bot passthrough"   true  "$(nfield "$np" 610 .is_bot)"
  assert_eq "normalize pr: mergeable_state kept raw" DIRTY "$(nfield "$np" 611 .mergeable_state)"
  assert_eq "normalize pr: changed_files mapped" 14    "$(nfield "$np" 611 .changed_files)"
  assert_eq "normalize pr: isDraft mapped"       true  "$(nfield "$np" 611 .is_draft)"
}

# ============================================================================
# Report rendering — light structural check (self-contained + carries the data).
# Presentation is verified by eye against the prototype; this guards the
# self-contained / no-CDN lock and the data round-trip.
# ============================================================================
report_tests() {
  work=$(mktemp -d)
  run="$work/run"
  mkdir -p "$run"
  cp "$FIX/items.jsonl" "$run/items.jsonl"
  resolve_config "$SKILL_DIR" "$work" | write_meta "$run" "2026-01-01T00:00:00Z" "owner/repo"
  sh "$SCRIPTS/classify.sh" "$run" >/dev/null
  sh "$SCRIPTS/report.sh" "$run" >/dev/null
  R="$run/report.html"

  assert_eq "report.html generated"            1 "$([ -f "$R" ] && echo 1 || echo 0)"
  assert_eq "no injection markers remain"      0 "$(grep -c '__REPOSWEEP_' "$R" || true)"
  assert_eq "no external scripts/styles (self-contained, no CDN)" 0 \
    "$(grep -Eic '<script[^>]*src=|<link[[:space:]]' "$R" || true)"
  data_line=$(awk '/^const DATA =$/{getline; print; exit}' "$R")
  assert_eq "DATA carries one entry per item"  19 "$(printf '%s' "$data_line" | jq 'length')"
  assert_eq "DATA preserves bin verdicts"      possible-duplicate \
    "$(printf '%s' "$data_line" | jq -r '.[]|select(.number==110)|.bin')"

  rm -rf "$work"
}

config_tests
run_tests
classify_tests
normalize_tests
report_tests

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
