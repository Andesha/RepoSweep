# Shared POSIX shell helpers.
REPOSWEEP_KEYS="STALE_DAYS NEEDS_INFO_DAYS PR_LONG_LIVED_DAYS SIZE_SMALL_LINES SIZE_SMALL_FILES SIZE_LARGE_LINES SIZE_LARGE_FILES DEDUP_MIN_SHARED_TOKENS DEDUP_MAX_PARTNERS"

resolve_config() (
  skill=$1 root=$2
  set -- "$skill/defaults.env"
  if [ -f "$root/reposweep.env" ]; then set -- "$@" "$root/reposweep.env"; fi
  # Read assignments as data. Repository configuration must not execute code.
  for k in $REPOSWEEP_KEYS; do
    value=$(awk -v key="$k" '
      {sub(/#.*/, ""); separator=index($0, "=")}
      separator {
        name=substr($0, 1, separator-1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
        if (name==key) {value=substr($0, separator+1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)}
      }
      END {print value}' "$@")
    eval 'override=${'"$k"'+yes}'
    if [ "${override:-}" = yes ]; then eval 'value=${'"$k"'}'; fi
    case "$value" in ''|*[!0-9]*) echo "reposweep: $k must be a non-negative integer" >&2; exit 1;; esac
    printf '%s=%s\n' "$k" "$value"
  done
)

kv_to_json() {
  jq -Rn '[inputs | split("=") | {(.[0]): (.[1] | tonumber)}] | add'
}

# Read the target repository's existing Markdown mapping, or use role names.
resolve_labels() {
  file=$1
  if [ -f "$file" ]; then text=$(jq -Rs . "$file"); else text='""'; fi
  jq -n --argjson text "$text" '
    ["needs-triage", "needs-info", "ready-for-agent", "ready-for-human", "wontfix"] as $roles
    | (reduce $roles[] as $r ({}; .[$r] = $r))
    | reduce ($text | split("\n")[] | select(startswith("|"))
        | split("|") | map(gsub("^\\s+|\\s+$"; "") | gsub("`"; ""))
        | select(.[1] as $r | $roles | index($r))) as $row (.;
          if $row[2] == "" then error("empty triage label mapping") else .[$row[1]] = $row[2] end)'
}

swept_at() {
  if [ -n "${REPOSWEEP_NOW:-}" ]; then
    jq -nr --argjson now "$REPOSWEEP_NOW" '$now | todateiso8601'
  else date -u '+%Y-%m-%dT%H:%M:%SZ'; fi
}

write_meta() {
  dir=$1 time=$2 repo=$3
  thresholds=$(kv_to_json)
  jq -n --arg swept_at "$time" --arg repo "$repo" --arg run_id "$(basename "$dir")" \
    --argjson thresholds "$thresholds" \
    '{run_id: $run_id, swept_at: $swept_at, repo: $repo, thresholds: $thresholds}' > "$dir/meta.json"
}

# Scratch directory and lock live beside the artifacts; rename stays atomic.
# Locks are deliberately not auto-stolen after interruption.
lock_run() {
  RUN_DIR=$1
  lock="$RUN_DIR/.lock"
  mkdir "$lock" 2>/dev/null || { echo "reposweep: run is locked: $lock; confirm no writer is running before removing this lock" >&2; exit 1; }
  trap 'rm -rf "$lock"' 0
  trap 'exit 1' HUP INT TERM
}
