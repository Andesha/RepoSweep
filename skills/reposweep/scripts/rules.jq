# Shared derivations. Every stage uses the frozen run metadata.
def role($m; $name):
  ($m.labels[$name] // $name) as $label | any(.carried_labels[]; . == $label);
def queued($m): role($m; "ready-for-agent") or role($m; "ready-for-human");
def declined($m): role($m; "wontfix") or any(.carried_labels[]; . == "invalid" or . == "as-designed");
def stale_window($m):
  if role($m; "needs-info") then $m.thresholds.NEEDS_INFO_DAYS else $m.thresholds.STALE_DAYS end;
def past_due($m): (queued($m) | not) and .idle_days > stale_window($m);
def derive($m):
  ($m.swept_at | fromdateiso8601) as $now
  | .age_days = ([0, (($now - (.created_at | fromdateiso8601)) / 86400 | floor)] | max)
  | .idle_days = ([0, (($now - (.updated_at | fromdateiso8601)) / 86400 | floor)] | max)
  | if .kind == "pr" then
      $m.thresholds as $t
      | .size_bucket = (if .additions + .deletions >= $t.SIZE_LARGE_LINES or .changed_files >= $t.SIZE_LARGE_FILES then "large"
          elif .additions + .deletions < $t.SIZE_SMALL_LINES and .changed_files <= $t.SIZE_SMALL_FILES then "small"
          else "medium" end)
      | .mergeable_state |= ascii_downcase
      | .conflicted = (.mergeable_state == "dirty" or .mergeable_state == "behind")
      | .long_lived = (.age_days > $t.PR_LONG_LIVED_DAYS)
    else del(.size_bucket, .mergeable_state, .conflicted, .long_lived, .is_draft, .additions, .deletions, .changed_files) end;
def verdict($bin; $rule; $reason; $pending):
  {bin: $bin, matched_rule: $rule, reason: $reason, needs_agent: $pending};
def classify($m):
  stale_window($m) as $window
  | if declined($m) then
      verdict("wontfix"; "carried-label:wontfix"; "Already marked as declined by the maintainer."; false)
    elif role($m; "needs-info") and (.idle_days <= $window or queued($m)) then
      verdict("needs-info"; "carried-label:needs-info"; "Marked as waiting for information; not past its applicable idle window."; false)
    elif .kind == "issue" then
      if past_due($m) then
        verdict("close-as-stale"; "idle-past-stale"; "Idle \(.idle_days)d, beyond the \($window)d window; not queued."; false)
      elif role($m; "ready-for-agent") then
        verdict("ready-for-agent"; "carried-label:ready-for-agent"; "Already queued for an agent; exempt from staleness."; false)
      elif role($m; "ready-for-human") then
        verdict("ready-for-human"; "carried-label:ready-for-human"; "Already queued for a human; exempt from staleness."; false)
      else verdict("needs-triage"; "fallthrough"; "Needs a reading of the issue before proposing an action."; true) end
    elif .conflicted and (past_due($m) | not) then
      verdict("needs-rebase"; "conflicted-fresh"; "Merge state is \(.mergeable_state); ask the author to update the branch."; false)
    elif past_due($m) and .size_bucket == "small" and .mergeable_state == "clean" then
      verdict("close-as-stale"; "small-clean-idle"; "Small, clean PR; idle \(.idle_days)d, beyond the \($window)d window."; false)
    elif past_due($m) then
      verdict("flag-for-review"; "past-stale-not-closeable"; "Idle \(.idle_days)d; size=\(.size_bucket), merge state=\(.mergeable_state). Needs a human keep-or-close decision."; false)
    elif .mergeable_state == "clean" then
      verdict("needs-triage"; "healthy"; "Clean and within the idle window; no mechanical action proposed."; false)
    else verdict("needs-triage"; "unresolved-merge-state"; "Merge state is \(.mergeable_state); inspect the PR before calling it healthy."; true) end;
