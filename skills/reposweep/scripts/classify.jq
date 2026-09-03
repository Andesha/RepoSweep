# RepoSweep — mechanical classification pass.
#
# The one deterministic seam. Reads the run's normalized items (slurped as an
# array), plus the resolved thresholds and a fixed `now`, and emits one Verdict
# per item. It computes deterministic bins via both first-match ladders, sizes
# and ages PRs, nominates duplicate pairs by loose-lexical title overlap, and
# seeds `needs_agent` on the subset that needs LLM judgment. It writes NOTHING
# back to the tracker and never calls the network — pure data in, verdicts out.
#
# Invoked with --argjson for every threshold plus `now` (epoch seconds), e.g.
#   jq -s -f classify.jq --argjson now 1700000000 --argjson STALE_DAYS 60 ...
#
# Verdict shape (field names per issue #12): { bin, duplicate_of, reason,
# matched_rule, needs_agent, flags, item } where `item` is the enriched
# normalized item. (CONTEXT.md's glossary describes these in prose — the bin,
# the rationale, the provenance, the duplicate_of pointer.)

# --- helpers ----------------------------------------------------------------

def as_epoch: if . == null then null else (fromdateiso8601? // null) end;

def days_since($ts): ($ts | as_epoch) as $e
  | if $e == null then null else (($now - $e) / 86400 | floor) end;

# Significant title tokens: lowercased alphanumerics, >=3 chars, minus stopwords.
def stopwords: {
  "the":1,"and":1,"for":1,"with":1,"from":1,"this":1,"that":1,"there":1,
  "when":1,"what":1,"cannot":1,"does":1,"doesnt":1,"not":1,"add":1,"support":1,
  "using":1,"into":1,"onto":1,"are":1,"was":1,"has":1,"have":1,"will":1,"can":1,
  "should":1,"could":1,"would":1,"but":1,"all":1,"any":1,"our":1,"your":1
};
def tokens:
  (. // "") | ascii_downcase
  | [ scan("[a-z0-9]+") ]
  | map(select(length >= 3))
  | map(select(stopwords[.] | not))
  | unique;

def has_label($items; $name): (($items.carried_labels // []) | any(. == $name));
def intersect_count($a; $b): (($a - ($a - $b)) | length);

# --- enrichment -------------------------------------------------------------
# Derive age/idle/size/conflict facets from raw fields + resolved thresholds.

def enrich:
  . as $it
  | (days_since(.created_at)) as $age
  | (days_since(.updated_at)) as $idle
  | ((.additions // 0) + (.deletions // 0)) as $changes
  | (.changed_files // 0) as $files
  | (if .kind == "pr" then
       (if ($changes < $SIZE_SMALL_LINES and $files <= $SIZE_SMALL_FILES) then "small"
        elif ($changes >= $SIZE_LARGE_LINES or $files >= $SIZE_LARGE_FILES) then "large"
        else "medium" end)
     else null end) as $size
  | (if .kind == "pr" then ((.mergeable_state // "") | ascii_downcase | (. == "dirty" or . == "behind")) else false end) as $conflicted
  | (if .kind == "pr" and $age != null then ($age > $PR_LONG_LIVED_DAYS) else false end) as $long_lived
  | $it + {
      age_days: $age,
      idle_days: $idle,
      size_bucket: $size,
      conflicted: $conflicted,
      long_lived: $long_lived
    };

# --- duplicate nomination (mechanical stage) --------------------------------
# Loose-lexical: pairs sharing >= DEDUP_MIN_SHARED_TOKENS significant title
# tokens are candidates. An item with more than DEDUP_MAX_PARTNERS candidates is
# too generic — dropped from the graph. The canonical is the lowest (oldest)
# number; the newer item's verdict carries duplicate_of: <canonical>.

def dup_map($items):
  ($items | map({ number, t: (.title | tokens) })) as $tok
  | ($tok | map(
      .number as $n | .t as $tt
      | { number: $n,
          partners: [ $tok[] | select(.number != $n) | select(intersect_count($tt; .t) >= $DEDUP_MIN_SHARED_TOKENS) | .number ] }
    )) as $graph
  | [ $graph[] | select((.partners | length) <= $DEDUP_MAX_PARTNERS) | .number ] as $eligible
  | reduce $tok[] as $x ({};
      ($x.number) as $n
      | ($x.t) as $tt
      | (if ($eligible | index($n)) then
           [ $tok[]
             | select(.number < $n)
             | select(.number as $m | $eligible | index($m))
             | select(intersect_count($tt; .t) >= $DEDUP_MIN_SHARED_TOKENS)
             | .number ]
         else [] end) as $canon
      | if ($canon | length) > 0 then . + { ($n | tostring): ($canon | min) } else . end
    );

# --- soft flags -------------------------------------------------------------

def soft_flags($bin):
  [ (if has_label(.; "good-first-issue") then "good-first-issue" else empty end),
    (if (.kind == "issue" and ((.title // "") | test("\\?\\s*$"))) then "question-shaped" else empty end),
    (if (.kind == "pr" and $bin == "needs-triage") then "healthy" else empty end)
  ];

# --- ladders ----------------------------------------------------------------

def classify_issue($dup):
  . as $it
  | has_label($it; "wontfix") as $wontfix
  | has_label($it; "needs-info") as $needsinfo
  | has_label($it; "ready-for-agent") as $rfa
  | has_label($it; "ready-for-human") as $rfh
  | ($rfa or $rfh) as $queued
  | (if $needsinfo then $NEEDS_INFO_DAYS else $STALE_DAYS end) as $window
  | ((.idle_days // 0) > $window) as $stale
  | if $wontfix then
      { bin: "wontfix", matched_rule: "carried-label:wontfix",
        reason: "Carries a wontfix label; the maintainer has declined this.", needs_agent: false }
    elif $dup != null then
      { bin: "possible-duplicate", matched_rule: ("duplicate-of:" + ($dup | tostring)),
        reason: ("Title overlaps #" + ($dup | tostring) + " (loose-lexical nomination); agent confirms sameness."), needs_agent: true }
    elif ($needsinfo and (.idle_days // 0) <= $NEEDS_INFO_DAYS) then
      { bin: "needs-info", matched_rule: "carried-label:needs-info",
        reason: ("Waiting on the reporter; still within the " + ($NEEDS_INFO_DAYS | tostring) + "d needs-info window."), needs_agent: false }
    elif (($queued | not) and $stale) then
      { bin: "close-as-stale", matched_rule: "idle-past-stale",
        reason: ("Idle " + ((.idle_days // 0) | tostring) + "d, past the " + ($window | tostring) + "d window, and not queued."), needs_agent: false }
    elif $rfa then
      { bin: "ready-for-agent", matched_rule: "carried-label:ready-for-agent",
        reason: "Already queued for an AFK agent; exempt from staleness.", needs_agent: false }
    elif $rfh then
      { bin: "ready-for-human", matched_rule: "carried-label:ready-for-human",
        reason: "Already queued for a human; exempt from staleness.", needs_agent: false }
    else
      { bin: "needs-triage", matched_rule: "fallthrough",
        reason: "No mechanical rule fired; held in the triage pen for judgment.", needs_agent: true }
    end;

def classify_pr($dup):
  . as $it
  | has_label($it; "wontfix") as $wontfix
  | has_label($it; "needs-info") as $needsinfo
  | (.conflicted // false) as $conflicted
  | ((.idle_days // 0) > $STALE_DAYS) as $stale
  | ((.idle_days // 0) <= $STALE_DAYS) as $fresh
  | if $wontfix then
      { bin: "wontfix", matched_rule: "carried-label:wontfix",
        reason: "Carries a wontfix label; the maintainer has declined this.", needs_agent: false }
    elif $dup != null then
      { bin: "possible-duplicate", matched_rule: ("duplicate-of:" + ($dup | tostring)),
        reason: ("Overlaps #" + ($dup | tostring) + " in intent (loose-lexical nomination); agent confirms sameness."), needs_agent: true }
    elif ($needsinfo and (.idle_days // 0) <= $NEEDS_INFO_DAYS) then
      { bin: "needs-info", matched_rule: "carried-label:needs-info",
        reason: "No linked issue / description; ask the author what this fixes.", needs_agent: false }
    elif ($conflicted and $fresh) then
      { bin: "needs-rebase", matched_rule: "conflicted-fresh",
        reason: ("mergeable_state=" + (.mergeable_state // "?") + " but still fresh; ask the author to rebase."), needs_agent: false }
    elif ((.size_bucket == "small") and ($conflicted | not) and $stale) then
      { bin: "close-as-stale", matched_rule: "small-clean-idle",
        reason: ("Small, clean, and idle " + ((.idle_days // 0) | tostring) + "d past the " + ($STALE_DAYS | tostring) + "d stale window; low-cost to close."), needs_agent: false }
    elif $stale then
      { bin: "flag-for-review", matched_rule: "past-stale-not-closeable",
        reason: "Large or conflicted and past the stale window — never silently closed; flagged for a human.", needs_agent: false }
    else
      { bin: "needs-triage", matched_rule: "fallthrough",
        reason: "No rule fires; recent and healthy. A human decides the cadence.", needs_agent: false }
    end;

# --- driver -----------------------------------------------------------------

(map(enrich)) as $items
| dup_map($items) as $dups
| $items[]
| . as $it
| ($dups[($it.number | tostring)] // null) as $dup
| (if .kind == "pr" then classify_pr($dup) else classify_issue($dup) end) as $v
| {
    bin: $v.bin,
    duplicate_of: $dup,
    reason: $v.reason,
    matched_rule: $v.matched_rule,
    needs_agent: $v.needs_agent,
    flags: ($it | soft_flags($v.bin)),
    item: $it
  }
