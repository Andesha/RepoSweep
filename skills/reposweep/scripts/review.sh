#!/bin/sh
# next emits bounded context; apply atomically replaces one verdict checkpoint.
set -eu
HERE=$(CDPATH='' cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
command=${1:?usage: review.sh next RUN_DIR [COUNT] | apply RUN_DIR BATCH_JSON}
RUN_DIR=${2:?missing RUN_DIR}
case "$command" in
  next)
    count=${3:-15}
    case "$count" in ''|*[!0-9]*) echo 'review: count must be 1-20' >&2; exit 1;; esac
    [ "$count" -ge 1 ] && [ "$count" -le 20 ] || { echo 'review: count must be 1-20' >&2; exit 1; }
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
            | .number as $older | {numbers: [$older, $v.item.number],
                older: ([$rows[] | select(.item.number == $older)][0] | context(.)), newer: context($v)}] as $pairs
          | if ($pairs|length) > 0 then {stage: "duplicates", pairs: $pairs[:$count]}
            else {stage: "complete", items: []} end
        end)' "$RUN_DIR/verdicts.jsonl";;
  apply)
    batch=${3:?missing BATCH_JSON}
    lock_run "$RUN_DIR"
    jq -cs --slurpfile batch "$batch" -f "$HERE/review.jq" "$RUN_DIR/verdicts.jsonl" > "$lock/verdicts.jsonl"
    mv "$lock/verdicts.jsonl" "$RUN_DIR/verdicts.jsonl"
    printf 'review: batch saved; rerun next to resume, report.sh to refresh HTML\n' >&2;;
  *) echo 'usage: review.sh next RUN_DIR [COUNT] | apply RUN_DIR BATCH_JSON' >&2; exit 1;;
esac
