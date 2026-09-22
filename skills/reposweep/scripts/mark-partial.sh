#!/bin/sh
# Mark an explicitly recovered subset; never changes fetched items or verdicts.
set -eu
HERE=$(CDPATH='' cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
RUN_DIR=${1:?usage: mark-partial.sh RUN_DIR LISTED_COUNT REASON}
listed=${2:?missing listed count}
reason=${3:?missing reason}
case $listed in *[!0-9]*|'') echo 'listed count must be a nonnegative integer' >&2; exit 1;; esac
[ -s "$RUN_DIR/items.jsonl" ] && [ -f "$RUN_DIR/verdicts.jsonl" ] || { echo 'recovered items and verdicts required' >&2; exit 1; }
lock_run "$RUN_DIR"
jq --argjson listed "$listed" --arg reason "$reason" --slurpfile items "$RUN_DIR/items.jsonl" '
  ($items|length) as $included
  | if $listed < $included then error("listed count is below included count") else . end
  | .snapshot = {complete: false, included: $included, listed: $listed, reason: $reason}
' "$RUN_DIR/meta.json" > "$lock/meta.json"
mv "$lock/meta.json" "$RUN_DIR/meta.json"
