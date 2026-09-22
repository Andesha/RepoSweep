#!/bin/sh
# Fictional sample using the same classifier, checkpoint writer, and renderer.
set -eu
ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
SKILL="$ROOT/skills/reposweep"
. "$SKILL/scripts/lib.sh"
for key in $REPOSWEEP_KEYS; do unset "$key"; done
work=$(mktemp -d)
trap 'rm -rf "$work"' 0
trap 'exit 1' HUP INT TERM
config=$(resolve_config "$SKILL" "$work")
printf '%s\n' "$config" | write_meta "$work" '2026-01-01T00:00:00Z' 'example/fieldnotes'
jq '.demo=true | .run_id="demo"' "$work/meta.json" > "$work/meta.tmp"
mv "$work/meta.tmp" "$work/meta.json"
jq -s '(. + [(.[]|select(.number==110)|.number=111|.title="Missing config file crashes startup")])[]
  | .url = ("https://example.com/fieldnotes/" + (if .kind=="pr" then "pull/" else "issues/" end) + (.number|tostring))' \
  "$SKILL/tests/fixtures/items.jsonl" > "$work/items.jsonl"
sh "$SKILL/scripts/classify.sh" "$work" >/dev/null
jq -s '{stage:"judgment",decisions:[.[]|select(.needs_agent)|
  if .item.number==107 then {number:.item.number,bin:"needs-info",reason:"The report does not include reproduction steps or the affected version."}
  else {number:.item.number,bin:"ready-for-agent",reason:"Reproduces a startup crash with an absent config; expected fallback behavior is specified."} end]}' \
  "$work/verdicts.jsonl" > "$work/batch.json"
sh "$SKILL/scripts/review.sh" apply "$work" "$work/batch.json"
jq -s '{stage:"duplicates",decisions:[.[] as $v|$v.duplicate_candidates[]|
  {numbers:[.number,$v.item.number],confirmed:($v.item.kind=="issue"),reason:
    (if $v.item.kind=="issue" then "Same missing-config startup crash, with identical reproduction and expected fallback."
     else "One PR provides the CSV writer; the other connects it to a new command. Related work, not duplicates." end)}]}' \
  "$work/verdicts.jsonl" > "$work/batch.json"
sh "$SKILL/scripts/review.sh" apply "$work" "$work/batch.json"
sh "$SKILL/scripts/report.sh" "$work" >/dev/null
out=${1:-"$ROOT/docs/demo/index.html"}
mkdir -p "$(dirname "$out")"
cp "$work/report.html" "$out"
printf '%s\n' "$out"
