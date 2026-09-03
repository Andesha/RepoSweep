#!/bin/sh
# RepoSweep — run the mechanical classification pass over a run's items.
#
# Reads the RESOLVED thresholds and swept_at from the run's meta.json (never the
# config layers directly — the resolve-once contract), classifies every item in
# items.jsonl via classify.jq, and writes verdicts.jsonl into the run.
#
# Usage: classify.sh RUN_DIR
set -eu

HERE=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"

RUN_DIR=${1:?usage: classify.sh RUN_DIR}
META="$RUN_DIR/meta.json"
ITEMS="$RUN_DIR/items.jsonl"
OUT="$RUN_DIR/verdicts.jsonl"

[ -f "$META" ]  || { echo "classify: no meta.json in $RUN_DIR" >&2; exit 1; }
[ -f "$ITEMS" ] || { echo "classify: no items.jsonl in $RUN_DIR" >&2; exit 1; }

# `now` is the run's swept_at instant, so classification is reproducible.
now=$(jq '.swept_at | fromdateiso8601' "$META")

# Build the --argjson list from the resolved thresholds in meta.json.
set -- -s -f "$HERE/classify.jq" --argjson now "$now"
for k in $REPOSWEEP_KEYS; do
  v=$(jq ".thresholds.$k" "$META")
  set -- "$@" --argjson "$k" "$v"
done

jq "$@" "$ITEMS" \
  | jq -c . \
  > "$OUT"

# The verdict embeds the fully enriched Normalized item (age/idle/size/conflict
# facets, which need the resolved thresholds). Write those back so the run's
# items.jsonl carries the complete Normalized item shape, consistent with the
# item embedded in each verdict.
jq -c '.item' "$OUT" > "$ITEMS.tmp" && mv "$ITEMS.tmp" "$ITEMS"

printf '%s\n' "$OUT"
