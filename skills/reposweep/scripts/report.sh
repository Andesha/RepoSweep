#!/bin/sh
# Render one offline report. --publish only prints commands for a human to run.
set -eu
HERE=$(CDPATH='' cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
if [ "${1:-}" = --publish ]; then
  run=${2:?missing run directory} root=${3:?missing target repository root}
  src=$(jq -nr --arg p "$run/report.html" '$p|@sh')
  dst=$(jq -nr --arg p "$root/docs/reposweep" '$p|@sh')
  repo=$(jq -nr --arg p "$root" '$p|@sh')
  printf 'Review the report for private information before publishing. On your intended publishing branch, run:\n'
  printf 'mkdir -p %s && cp %s %s/index.html\n' "$dst" "$src" "$dst"
  printf "git -C %s add docs/reposweep/index.html && git -C %s commit -m 'Publish RepoSweep report' && git -C %s push\n" "$repo" "$repo" "$repo"
  exit 0
fi
RUN_DIR=${1:?usage: report.sh RUN_DIR}
lock_run "$RUN_DIR"
# Escape < in serialized JSON so tracker text cannot terminate the script tag.
jq -sr -L "$HERE" --slurpfile meta "$RUN_DIR/meta.json" '
  include "rules";
  map(. + {past_due: (.item | past_due($meta[0])), stale_window: (.item | stale_window($meta[0]))})
  | tojson | gsub("<"; "\\u003c")' "$RUN_DIR/verdicts.jsonl" > "$lock/data.json"
jq -r 'tojson | gsub("<"; "\\u003c")' "$RUN_DIR/meta.json" > "$lock/meta.json"
awk -v D="$lock/data.json" -v M="$lock/meta.json" '
  /__REPOSWEEP_DATA__/ {while ((getline line < D) > 0) print line; next}
  /__REPOSWEEP_META__/ {while ((getline line < M) > 0) print line; next}
  {print}
' "$HERE/report.template.html" > "$lock/report.html"
mv "$lock/report.html" "$RUN_DIR/report.html"
printf '%s\n' "$RUN_DIR/report.html"
