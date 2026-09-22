#!/bin/sh
# GitHub adapter. Durable sequential fetches can be resumed after interruption.
set -eu
HERE=$(CDPATH='' cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
RUN_DIR=${1:?usage: fetch-normalize.sh RUN_DIR}
lock_run "$RUN_DIR"
[ ! -e "$RUN_DIR/items.jsonl" ] || { echo 'fetch: snapshot already exists; start a new run' >&2; exit 1; }
repo=$(jq -er '.repo | select(length > 0)' "$RUN_DIR/meta.json")
fetch="$RUN_DIR/fetch"
records="$fetch/records"
mkdir -p "$records"

# Publish the listing atomically. A truncated listing is never resume input.
if [ ! -f "$fetch/list.jsonl" ]; then
  printf 'reposweep: listing open items\n' >&2
  rm -f "$fetch/pages.tmp" "$fetch/list.tmp"
  gh api --method GET --paginate "repos/$repo/issues?state=open&per_page=100" > "$fetch/pages.tmp"
  jq -ce '.[]' "$fetch/pages.tmp" > "$fetch/list.tmp"
  mv "$fetch/pages.tmp" "$fetch/pages.json"
  mv "$fetch/list.tmp" "$fetch/list.jsonl"
fi

total=$(wc -l < "$fetch/list.jsonl" | awk '{print $1}')
completed=0
while IFS= read -r item; do
  number=$(printf '%s\n' "$item" | jq -er '.number')
  record="$records/$number.json"
  if [ -s "$record" ] && jq -e . "$record" >/dev/null 2>&1; then
    completed=$((completed + 1))
    continue
  fi
  rm -f "$fetch/record.tmp"
  if printf '%s\n' "$item" | jq -e 'has("pull_request")' >/dev/null; then
    gh api --method GET "repos/$repo/pulls/$number" > "$fetch/record.tmp"
    # GitHub may compute mergeability asynchronously. Retry once, then retain unknown.
    if jq -e '.mergeable_state == "unknown" or .mergeable_state == null' "$fetch/record.tmp" >/dev/null; then
      sleep "${REPOSWEEP_RETRY_DELAY:-1}"
      gh api --method GET "repos/$repo/pulls/$number" > "$fetch/record.tmp"
    fi
  else
    printf '%s\n' "$item" > "$fetch/record.tmp"
  fi
  jq -ce . "$fetch/record.tmp" > "$fetch/record.valid"
  mv "$fetch/record.valid" "$record"
  rm -f "$fetch/record.tmp"
  completed=$((completed + 1))
  printf 'reposweep: fetched %s/%s (#%s)\n' "$completed" "$total" "$number" >&2
done < "$fetch/list.jsonl"
printf 'reposweep: fetched %s/%s items\n' "$completed" "$total" >&2

: > "$lock/github-items.jsonl"
while IFS= read -r item; do
  number=$(printf '%s\n' "$item" | jq -er '.number')
  [ -s "$records/$number.json" ] || { echo "fetch: missing completed record for #$number" >&2; exit 1; }
  cat "$records/$number.json" >> "$lock/github-items.jsonl"
done < "$fetch/list.jsonl"
jq -c -L "$HERE" --slurpfile meta "$RUN_DIR/meta.json" -f "$HERE/normalize.jq" \
  "$lock/github-items.jsonl" > "$lock/items.jsonl"
jq -s -e 'map(.number) | length == (unique | length)' "$lock/items.jsonl" >/dev/null
jq --arg snapshot_at "$(swept_at)" --slurpfile items "$lock/items.jsonl" \
  '.snapshot_at = $snapshot_at | .counts = {items: ($items|length), issues: ([$items[]|select(.kind=="issue")]|length), prs: ([$items[]|select(.kind=="pr")]|length)} | .snapshot = {complete: true, included: ($items|length), listed: ($items|length), reason: null}' \
  "$RUN_DIR/meta.json" > "$lock/meta.json"
mv "$lock/github-items.jsonl" "$RUN_DIR/github-items.jsonl"
mv "$lock/meta.json" "$RUN_DIR/meta.json"
mv "$lock/items.jsonl" "$RUN_DIR/items.jsonl"
printf '%s\n' "$RUN_DIR/items.jsonl"
