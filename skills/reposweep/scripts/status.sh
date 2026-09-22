#!/bin/sh
# Report fetch, classification, and review state as JSON.
set -eu
RUN_DIR=${1:?usage: status.sh RUN_DIR}
[ -f "$RUN_DIR/meta.json" ] || { echo "status: missing $RUN_DIR/meta.json" >&2; exit 1; }
listed=0
completed=0
if [ -f "$RUN_DIR/fetch/list.jsonl" ]; then listed=$(wc -l < "$RUN_DIR/fetch/list.jsonl" | awk '{print $1}'); fi
if [ -d "$RUN_DIR/fetch/records" ]; then
  completed=$(find "$RUN_DIR/fetch/records" -type f -name '*.json' -size +0c | wc -l | awk '{print $1}')
fi
snapshot=$(jq -c '.snapshot // null' "$RUN_DIR/meta.json")
if [ -f "$RUN_DIR/items.jsonl" ]; then
  if jq -e '.snapshot.complete == true' "$RUN_DIR/meta.json" >/dev/null; then fetch_state=complete
  else fetch_state=partial
  fi
  if [ "$listed" -eq 0 ]; then
    completed=$(jq -r '.snapshot.included // .counts.items // 0' "$RUN_DIR/meta.json")
    listed=$(jq -r '.snapshot.listed // .counts.items // 0' "$RUN_DIR/meta.json")
  fi
elif [ "$listed" -gt 0 ]; then fetch_state=interrupted
else fetch_state=not-started
fi
if [ -f "$RUN_DIR/verdicts.jsonl" ]; then
  classification=complete
  review=$(jq -sc '{item_pending: ([.[] | select(.needs_agent)] | length), duplicate_pending: ([.[].duplicate_candidates[]? | select(.confirmed == null)] | length)}' "$RUN_DIR/verdicts.jsonl")
else
  classification=not-started
  review='{"item_pending":null,"duplicate_pending":null}'
fi
jq -n --arg fetch_state "$fetch_state" --argjson completed "$completed" --argjson listed "$listed" \
  --argjson snapshot "$snapshot" --arg classification "$classification" --argjson review "$review" \
  '{fetch:{state:$fetch_state,completed:$completed,total:(if $listed > 0 then $listed else null end)},snapshot:$snapshot,classification:{state:$classification},review:$review}'
