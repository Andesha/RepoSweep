#!/bin/sh
# next emits bounded context; apply atomically replaces one verdict checkpoint.
set -eu
HERE=$(CDPATH='' cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
usage='review.sh workload RUN_DIR [COUNT] | next RUN_DIR [COUNT] | apply RUN_DIR BATCH_JSON'
command=${1:?usage: $usage}
RUN_DIR=${2:?missing RUN_DIR}
case "$command" in
  workload|next)
    count=${3:-15}
    case "$count" in ''|*[!0-9]*) echo 'review: count must be 1-20' >&2; exit 1;; esac
    [ "$count" -ge 1 ] && [ "$count" -le 20 ] || { echo 'review: count must be 1-20' >&2; exit 1; }
    if [ "$command" = workload ]; then
      jq -s --argjson count "$count" '
        ([.[] | select(.needs_agent)] | length) as $items
        | ([.[].duplicate_candidates[]? | select(.confirmed == null)] | length) as $pairs
        | {batch_size: $count,
           item_pending: $items,
           item_batches: (($items + $count - 1) / $count | floor),
           duplicate_pending: $pairs,
           duplicate_batches: (($pairs + $count - 1) / $count | floor)}
        | .total_batches = (.item_batches + .duplicate_batches)
      ' "$RUN_DIR/verdicts.jsonl"
      exit 0
    fi
    raw="$RUN_DIR/github-items.jsonl"
    [ -f "$raw" ] || raw=/dev/null
    jq -s --slurpfile raw "$raw" --slurpfile meta "$RUN_DIR/meta.json" --argjson count "$count" '
      def context($v):
        ([$raw[] | select(.number == $v.item.number)][0]) as $source
        | {verdict: $v, body: (($source.body // "")[:12000]),
           body_truncated: (($source.body // "" | length) > 12000), body_available: ($source != null)};
      . as $rows
      | {repo: $meta[0].repo, thresholds: $meta[0].thresholds, labels: $meta[0].labels}
      + (if any($rows[]; .needs_agent) then
          {stage: "judgment", items: ([$rows[] | select(.needs_agent) | context(.)][:$count])}
        else
          [$rows[] as $v | $v.duplicate_candidates[] | select(.confirmed == null)
            | .number as $older | {numbers: [$older, $v.item.number], score,
                shared_tokens: (.shared_tokens // []),
                older: ([$rows[] | select(.item.number == $older)][0] | context(.)), newer: context($v)}]
          | sort_by(-(.score // 0), .numbers) as $pairs
          | if ($pairs|length) > 0 then {stage: "duplicates", pairs: $pairs[:$count]}
            else {stage: "complete", items: []} end
        end)' "$RUN_DIR/verdicts.jsonl";;
  apply)
    batch=${3:?missing BATCH_JSON}
    lock_run "$RUN_DIR"
    jq -cs --slurpfile batch "$batch" -f "$HERE/review.jq" "$RUN_DIR/verdicts.jsonl" > "$lock/verdicts.jsonl"
    mv "$lock/verdicts.jsonl" "$RUN_DIR/verdicts.jsonl"
    printf 'review: batch saved; rerun next to resume, report.sh to refresh HTML\n' >&2;;
  *) echo "usage: $usage" >&2; exit 1;;
esac
