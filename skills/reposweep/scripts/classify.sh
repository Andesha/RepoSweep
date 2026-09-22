#!/bin/sh
# Deterministic, offline classification. Never overwrite reviewed verdicts.
set -eu
HERE=$(CDPATH='' cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
RUN_DIR=${1:?usage: classify.sh RUN_DIR}
lock_run "$RUN_DIR"
[ ! -e "$RUN_DIR/verdicts.jsonl" ] || { echo 'classify: verdicts already exist; start a new run' >&2; exit 1; }
jq -c -s -L "$HERE" --slurpfile meta "$RUN_DIR/meta.json" -f "$HERE/classify.jq" \
  "$RUN_DIR/items.jsonl" > "$lock/verdicts.jsonl"
mv "$lock/verdicts.jsonl" "$RUN_DIR/verdicts.jsonl"
printf '%s\n' "$RUN_DIR/verdicts.jsonl"
