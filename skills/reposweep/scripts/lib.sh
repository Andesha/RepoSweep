# RepoSweep shared shell library. POSIX sh; sourced by the other scripts.
# No side effects on source beyond defining functions and REPOSWEEP_KEYS.

# The complete set of resolvable threshold keys (the only override surface).
# Order here is the order they are emitted into meta.json.
REPOSWEEP_KEYS="STALE_DAYS NEEDS_INFO_DAYS PR_LONG_LIVED_DAYS SIZE_SMALL_LINES SIZE_SMALL_FILES SIZE_LARGE_LINES SIZE_LARGE_FILES DEDUP_MIN_SHARED_TOKENS DEDUP_MAX_PARTNERS"

# resolve_config SKILL_DIR REPO_ROOT
# Resolves the threshold config across three layers, low -> high precedence:
#   1. shipped defaults.env (in SKILL_DIR)
#   2. optional repo-root reposweep.env (partial)
#   3. environment variables of the same name
# Emits resolved "KEY=VALUE" lines on stdout, one per known key, in REPOSWEEP_KEYS
# order. Runs entirely in a subshell so the caller's environment is untouched.
resolve_config() {
  rc_skill_dir=$1
  rc_repo_root=$2
  (
    # 1. Capture environment-provided overrides *before* sourcing any file.
    for k in $REPOSWEEP_KEYS; do
      eval "__set_$k=\${$k+set}"
      eval "__val_$k=\${$k-}"
    done
    # 2. Defaults layer (the canonical opinion). Required.
    . "$rc_skill_dir/defaults.env"
    # 3. Repo-root reposweep.env (partial; only names the keys it changes).
    if [ -f "$rc_repo_root/reposweep.env" ]; then
      . "$rc_repo_root/reposweep.env"
    fi
    # 4. Re-apply environment overrides on top (highest precedence).
    for k in $REPOSWEEP_KEYS; do
      eval "was=\$__set_$k"
      if [ "$was" = set ]; then
        eval "$k=\$__val_$k"
      fi
    done
    # 5. Emit resolved values.
    for k in $REPOSWEEP_KEYS; do
      eval "v=\${$k-}"
      printf '%s=%s\n' "$k" "$v"
    done
  )
}

# kv_to_json  (stdin: KEY=VALUE lines) -> JSON object on stdout.
# Numeric values become JSON numbers; anything else stays a string.
kv_to_json() {
  jq -Rn '
    [ inputs
      | select(length > 0)
      | capture("^(?<k>[^=]+)=(?<v>.*)$")
      | { (.k): (.v | tonumber? // .) }
    ] | add // {}'
}

# _utc FORMAT -> UTC `date` in FORMAT, honoring REPOSWEEP_NOW (epoch seconds)
# for reproducible/test runs. GNU (-d @sec) with a BSD (-r sec) fallback.
_utc() {
  if [ -n "${REPOSWEEP_NOW:-}" ]; then
    date -u -d "@$REPOSWEEP_NOW" "+$1" 2>/dev/null || date -u -r "$REPOSWEEP_NOW" "+$1"
  else
    date -u "+$1"
  fi
}

# run_id   -> a fresh UTC run identifier (e.g. 20260903T142207Z).
run_id()   { _utc %Y%m%dT%H%M%SZ; }

# swept_at -> the ISO-8601 UTC instant of the sweep.
swept_at() { _utc %Y-%m-%dT%H:%M:%SZ; }

# create_run RUNS_BASE RUN_ID -> creates the run directory, prints its path.
create_run() {
  cr_base=$1
  cr_id=$2
  cr_dir="$cr_base/$cr_id"
  mkdir -p "$cr_dir"
  printf '%s\n' "$cr_dir"
}

# update_latest RUNS_BASE RUN_ID -> repoints the `latest` pointer at RUN_ID.
# Uses a symlink; falls back to a plain file naming the run if symlinks fail.
update_latest() {
  ul_base=$1
  ul_id=$2
  ( cd "$ul_base" || exit 1
    rm -f latest
    ln -s "$ul_id" latest 2>/dev/null || printf '%s\n' "$ul_id" > latest
  )
}

# write_meta RUN_DIR SWEPT_AT REPO  (stdin: resolved KEY=VALUE lines)
# Writes the run's meta.json: swept_at, repo, and the resolved thresholds.
write_meta() {
  wm_dir=$1
  wm_swept_at=$2
  wm_repo=${3:-}
  wm_thresholds=$(kv_to_json)
  jq -n \
    --arg swept_at "$wm_swept_at" \
    --arg repo "$wm_repo" \
    --arg run_id "$(basename "$wm_dir")" \
    --argjson thresholds "$wm_thresholds" \
    '{ run_id: $run_id, swept_at: $swept_at, repo: $repo, thresholds: $thresholds }' \
    > "$wm_dir/meta.json"
}
