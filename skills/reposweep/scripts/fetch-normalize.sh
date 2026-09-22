#!/bin/sh
# GitHub adapter. Paginate every open item, then GET each PR for size/merge state.
set -eu
HERE=$(CDPATH='' cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
RUN_DIR=${1:?usage: fetch-normalize.sh RUN_DIR}
lock_run "$RUN_DIR"
[ ! -e "$RUN_DIR/items.jsonl" ] || { echo 'fetch: snapshot already exists; start a new run' >&2; exit 1; }
repo=$(jq -er '.repo | select(length > 0)' "$RUN_DIR/meta.json")

gh api --method GET --paginate "repos/$repo/issues?state=open&per_page=100" > "$lock/pages.json"
jq -c '.[]' "$lock/pages.json" > "$lock/list.jsonl"
: > "$lock/github-items.jsonl"
while IFS= read -r item; do
  if printf '%s\n' "$item" | jq -e 'has("pull_request")' >/dev/null; then
    number=$(printf '%s\n' "$item" | jq -r .number)
    gh api --method GET "repos/$repo/pulls/$number" > "$lock/pr.json"
    # GitHub may compute mergeability asynchronously. Retry once, then retain unknown.
    if jq -e '.mergeable_state == "unknown" or .mergeable_state == null' "$lock/pr.json" >/dev/null; then
      sleep 1
      gh api --method GET "repos/$repo/pulls/$number" > "$lock/pr.json"
    fi
    jq -c . "$lock/pr.json" >> "$lock/github-items.jsonl"
  else printf '%s\n' "$item" >> "$lock/github-items.jsonl"; fi
done < "$lock/list.jsonl"
jq -c -L "$HERE" --slurpfile meta "$RUN_DIR/meta.json" -f "$HERE/normalize.jq" \
  "$lock/github-items.jsonl" > "$lock/items.jsonl"
jq -s -e 'map(.number) | length == (unique | length)' "$lock/items.jsonl" >/dev/null
jq --arg snapshot_at "$(swept_at)" --slurpfile items "$lock/items.jsonl" \
  '.snapshot_at = $snapshot_at | .counts = {items: ($items|length), issues: ([$items[]|select(.kind=="issue")]|length), prs: ([$items[]|select(.kind=="pr")]|length)}' \
  "$RUN_DIR/meta.json" > "$lock/meta.json"
mv "$lock/github-items.jsonl" "$RUN_DIR/github-items.jsonl"
mv "$lock/meta.json" "$RUN_DIR/meta.json"
mv "$lock/items.jsonl" "$RUN_DIR/items.jsonl"
printf '%s\n' "$RUN_DIR/items.jsonl"
