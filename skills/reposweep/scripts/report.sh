#!/bin/sh
# RepoSweep — render a run's verdicts into a single self-contained report.html.
#
# Reads verdicts.jsonl + meta.json from the run, flattens each verdict to the
# report's view shape, and injects DATA and META into report.template.html by
# replacing marker lines (getline, so JSON backslashes are never re-escaped).
# No CDN, no build step — the output is one file you can open offline or copy
# into docs/ to publish. Uses the run's RESOLVED thresholds (from meta.json).
#
# Usage: report.sh RUN_DIR
set -eu

HERE=$(CDPATH= cd "$(dirname "$0")" && pwd)
RUN_DIR=${1:?usage: report.sh RUN_DIR}
V="$RUN_DIR/verdicts.jsonl"
META="$RUN_DIR/meta.json"
OUT="$RUN_DIR/report.html"
TEMPLATE="$HERE/report.template.html"

[ -f "$V" ]    || { echo "report: no verdicts.jsonl in $RUN_DIR" >&2; exit 1; }
[ -f "$META" ] || { echo "report: no meta.json in $RUN_DIR" >&2; exit 1; }

DATA_F="$RUN_DIR/.report-data.json"
META_F="$RUN_DIR/.report-meta.json"

# Flatten verdicts to the compact view shape the template's JS expects.
jq -s -c '
  [ .[] | {
      number:   .item.number,
      kind:     .item.kind,
      title:    .item.title,
      url:      .item.url,
      author:   .item.author,
      is_bot:   (.item.is_bot // false),
      type:     (.item.type // null),
      is_draft: (.item.is_draft // false),
      conflicted: (.item.conflicted // false),
      long_lived: (.item.long_lived // false),
      size:     (.item.size_bucket // null),
      age:      (.item.age_days // null),
      idle:     (.item.idle_days // null),
      bin:      .bin,
      dup:      .duplicate_of,
      reason:   .reason,
      rule:     .matched_rule,
      flags:    (.flags // []),
      labels:   (.item.carried_labels // [])
    } ]
' "$V" > "$DATA_F"

jq -c . "$META" > "$META_F"

awk -v D="$DATA_F" -v M="$META_F" '
  /__REPOSWEEP_DATA__/ { while ((getline l < D) > 0) print l; next }
  /__REPOSWEEP_META__/ { while ((getline l < M) > 0) print l; next }
  { print }
' "$TEMPLATE" > "$OUT"

rm -f "$DATA_F" "$META_F"
printf '%s\n' "$OUT"
