#!/bin/sh
# RepoSweep — fetch-and-normalize seam (GitHub adapter).
#
# The ONE tracker-specific script. Lists all open issues and PRs via `gh` and
# emits normalized items (one JSON object per line) to the run's items.jsonl.
# No age gate on fetch — sweep all open items. PR size and mergeability come
# from the per-PR fields `gh` fetches. To port to another tracker, replace the
# two `gh` calls; the normalize.jq shape and everything downstream are unchanged.
#
# Usage: fetch-normalize.sh RUN_DIR [LIMIT]
set -eu

HERE=$(CDPATH= cd "$(dirname "$0")" && pwd)
RUN_DIR=${1:?usage: fetch-normalize.sh RUN_DIR [LIMIT]}
LIMIT=${2:-1000}
OUT="$RUN_DIR/items.jsonl"

: > "$OUT"

gh issue list --state open --limit "$LIMIT" \
  --json number,title,url,state,author,createdAt,updatedAt,labels \
  | jq -c --arg kind issue -f "$HERE/normalize.jq" >> "$OUT"

gh pr list --state open --limit "$LIMIT" \
  --json number,title,url,state,author,createdAt,updatedAt,labels,isDraft,additions,deletions,changedFiles,mergeStateStatus \
  | jq -c --arg kind pr -f "$HERE/normalize.jq" >> "$OUT"

printf '%s\n' "$OUT"
