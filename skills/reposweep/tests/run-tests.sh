#!/bin/sh
# Offline artifact checks: classification/config, and the new checkpoint boundary.
set -eu
SKILL=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
SCRIPTS="$SKILL/scripts"
. "$SCRIPTS/lib.sh"
for key in $REPOSWEEP_KEYS; do unset "$key"; done
work=$(mktemp -d)
trap 'rm -rf "$work"' 0
trap 'exit 1' HUP INT TERM
run="$work/run"
mkdir "$run"
cp "$SKILL/tests/fixtures/items.jsonl" "$run/items.jsonl"
config=$(resolve_config "$SKILL" "$work")
printf '%s\n' "$config" | write_meta "$run" '2026-01-01T00:00:00Z' 'example/repo'
sh "$SCRIPTS/classify.sh" "$run" >/dev/null
V="$run/verdicts.jsonl"
checks=0
check() {
  jq -es "$2" "$V" >/dev/null || { echo "FAIL: $1" >&2; exit 1; }
  checks=$((checks+1)); printf 'ok - %s\n' "$1"
}
check 'issue ladder, including queued-work exemptions' '
  map(select(.item.kind=="issue") | [.item.number,.bin]) ==
  [[101,"wontfix"],[102,"needs-info"],[103,"close-as-stale"],[104,"close-as-stale"],
   [105,"ready-for-agent"],[106,"ready-for-human"],[107,"needs-triage"],[108,"ready-for-agent"],
   [109,"needs-triage"],[110,"needs-triage"]]'
check 'PR ladder, including the shorter needs-info window' '
  map(select(.item.kind=="pr") | [.item.number,.bin]) ==
  [[201,"close-as-stale"],[202,"flag-for-review"],[203,"needs-rebase"],[204,"needs-triage"],
   [205,"needs-triage"],[206,"needs-triage"],[207,"needs-triage"],[208,"needs-triage"],[209,"close-as-stale"]]'
check 'nomination is not confirmation and preserves the mechanical bin' '
  all(.[]; .duplicate_of == null) and
  ([.[] | select(.item.number==110) | .duplicate_candidates[] | [.number,.confirmed]] == [[109,null]])'
check 'kinds retain only their own fields, and sizing/long-lived facets are derived' '
  all(.[] | select(.item.kind=="issue"); (.item|has("size_bucket")|not)) and
  ([.[]|select(.item.number==201 or .item.number==202 or .item.number==203)|.item.size_bucket] == ["small","large","medium"]) and
  any(.[]; .item.number==202 and .item.long_lived)'
check 'rule provenance and judgment flags are meaningful' '
  all(.[]; (.matched_rule|length)>0) and ([.[]|select(.needs_agent)|.item.number] == [107,109,110])'
check 'stale candidate reasons state inactivity, threshold, and queue status' '
  all(.[] | select(.bin=="close-as-stale");
    (.reason | test("[Ii]dle [0-9]+d") and test("beyond the [0-9]+d window") and test("not queued")))'
cp "$V" "$work/first.jsonl"
# Refuse an accidental restart that would wipe agent work.
if sh "$SCRIPTS/classify.sh" "$run" >/dev/null 2>&1; then echo 'FAIL: overwrote verdicts' >&2; exit 1; fi
cmp "$V" "$work/first.jsonl"

# Read-only configuration, with a partial repo override and env taking precedence.
printf 'STALE_DAYS=12\nDEDUP_MAX_PARTNERS=1\n' > "$work/reposweep.env"
config=$(STALE_DAYS=25 resolve_config "$SKILL" "$work")
printf '%s\n' "$config" | write_meta "$run" '2026-01-01T00:00:00Z' 'example/repo'
jq -e '.thresholds.STALE_DAYS==25 and .thresholds.DEDUP_MAX_PARTNERS==1 and .thresholds.NEEDS_INFO_DAYS==7' "$run/meta.json" >/dev/null
if STALE_DAYS='$(touch bad)' resolve_config "$SKILL" "$work" >/dev/null 2>&1; then echo 'FAIL: accepted nonnumeric config' >&2; exit 1; fi
printf '| `needs-info` | `waiting` | Waiting |\n' > "$work/labels.md"
labels=$(resolve_labels "$work/labels.md")
jq --argjson labels "$labels" '.labels=$labels' "$run/meta.json" > "$work/meta.json"
mv "$work/meta.json" "$run/meta.json"

# Exercise safety boundaries and a dense duplicate graph in one small input.
jq -s '
  . as $items | ($items[]|select(.number==201)) as $pr | ($items[]|select(.number==109)) as $issue
  | [($pr + {number:1,title:"Unknown merge state",mergeable_state:"unknown"}),
     ($pr + {number:2,title:"Blocked checks",mergeable_state:"blocked"}),
     ($pr + {number:3,title:"Large old request",additions:600,mergeable_state:"clean"}),
     ($pr + {number:4,title:"Queued old request",carried_labels:["ready-for-agent"]}),
     ($pr + {number:5,title:"Waiting old conflict",carried_labels:["waiting"],updated_at:"2025-12-20T00:00:00Z",mergeable_state:"dirty"}),
     ($issue + {number:6,title:"Exact stale boundary",updated_at:"2025-12-07T00:00:00Z"}),
     ($issue + {number:7,title:"Exact waiting boundary",carried_labels:["waiting"],updated_at:"2025-12-25T00:00:00Z"}),
     ($pr + {number:8,title:$issue.title,updated_at:"2025-12-28T00:00:00Z"}),
     ($issue + {number:9,title:"Alpha beta gamma delta"}),
     ($issue + {number:10,title:"Alpha beta epsilon zeta"}),
     ($issue + {number:11,title:"Gamma delta eta theta"}),
     ($issue + {number:12,title:"Epsilon zeta eta theta"}),
     ($issue + {number:13,title:"Update documentation request"}),
     ($issue + {number:14,title:"Documentation update request"}),
     ($issue + {number:15,title:"Request documentation update"}),
     ($issue + {number:16,title:"Tokenizer crashes on malformed unicode input"}),
     ($issue + {number:17,title:"Malformed unicode input crashes tokenizer"})][]
' "$SKILL/tests/fixtures/items.jsonl" > "$run/items.jsonl"
rm "$V"
sh "$SCRIPTS/classify.sh" "$run" >/dev/null
check 'unknown, blocked, large, and conflicted stale PRs never become close proposals' '
  [.[]|select(.item.number==1 or .item.number==2 or .item.number==3 or .item.number==5)|.bin] == ["flag-for-review","flag-for-review","flag-for-review","flag-for-review"]'
check 'queued PR and exact idle boundaries do not go stale; label mapping applies' '
  [.[]|select(.item.number==4 or .item.number==6 or .item.number==7)|.bin] == ["needs-triage","needs-triage","needs-info"]'
check 'useful matches survive while common titles, cross-kind pairs, and excess partners do not' '
  [.[] as $v | $v.duplicate_candidates[] | [.number,$v.item.number]] as $pairs
  | ([$pairs[]|select(.[0]>=9 and .[0]<=12 and .[1]>=9 and .[1]<=12)]|length)==2
    and any($pairs[]; . == [16,17])
    and all($pairs[]; (.[0]<13 or .[0]>15) and (.[1]<13 or .[1]>15))
    and all($pairs[]; .[0]!=8 and .[1]!=8)
    and ($pairs|flatten|group_by(.)|all(.[];length<=1))'
check 'candidate ordering exposes score and shared-token evidence' '
  any(.[]; .item.number==17 and
    ([.duplicate_candidates[0] | .number,.score,.shared_tokens] ==
      [16,1,["crashes","input","malformed","tokenizer","unicode"]]))'

# Restore the normal run and review it in batches, preserving unrelated rows.
cp "$work/first.jsonl" "$V"
sh "$SCRIPTS/review.sh" workload "$run" 2 > "$work/workload.json"
jq -e '. == {batch_size:2,item_pending:3,item_batches:2,duplicate_pending:2,duplicate_batches:1,total_batches:3}' "$work/workload.json" >/dev/null
printf 'ok - workload reports pending counts and rounded-up stage batches\n'
sh "$SCRIPTS/review.sh" next "$run" 1 > "$work/next.json"
jq -e '.stage=="judgment" and (.items|length)==1 and .items[0].verdict.item.number==107' "$work/next.json" >/dev/null
printf '%s\n' '{"stage":"judgment","decisions":[{"number":107,"bin":"needs-info","reason":"Missing reproduction steps."}]}' > "$work/batch.json"
sh "$SCRIPTS/review.sh" apply "$run" "$work/batch.json"
check 'judgment checkpoint updates only the selected row' 'any(.[]; .item.number==107 and .bin=="needs-info" and .needs_agent==false) and any(.[]; .item.number==109 and .needs_agent)'
sh "$SCRIPTS/review.sh" workload "$run" 2 > "$work/workload.json"
jq -e '. == {batch_size:2,item_pending:2,item_batches:1,duplicate_pending:2,duplicate_batches:1,total_batches:2}' "$work/workload.json" >/dev/null
printf 'ok - workload reflects resumed checkpoints and exact batches\n'
cp "$V" "$work/checkpoint.jsonl"
if sh "$SCRIPTS/review.sh" apply "$run" "$work/batch.json" >/dev/null 2>&1; then echo 'FAIL: accepted repeated decision' >&2; exit 1; fi
cmp "$V" "$work/checkpoint.jsonl"
# An invalid second decision must not apply a valid first decision.
printf '%s\n' '{"stage":"judgment","decisions":[{"number":109,"bin":"ready-for-agent","reason":"Bounded reproduction."},{"number":110,"bin":"needs-rebase","reason":"Invalid issue bin."}]}' > "$work/batch.json"
if sh "$SCRIPTS/review.sh" apply "$run" "$work/batch.json" >/dev/null 2>&1; then echo 'FAIL: accepted invalid batch' >&2; exit 1; fi
cmp "$V" "$work/checkpoint.jsonl"
jq -s '{stage:"judgment",decisions:[.[]|select(.needs_agent)|{number:.item.number,bin:"ready-for-agent",reason:"Explicit reproduction and expected behavior."}]}' "$V" > "$work/batch.json"
sh "$SCRIPTS/review.sh" apply "$run" "$work/batch.json"
sh "$SCRIPTS/review.sh" next "$run" 2 > "$work/next.json"
jq -e '.stage=="duplicates" and all(.pairs[]; (.score|type)=="number" and (.shared_tokens|type)=="array")' "$work/next.json" >/dev/null
printf 'ok - duplicate review exposes nomination score and shared-token evidence\n'
printf '%s\n' '{"stage":"duplicates","decisions":[{"numbers":[109,110],"confirmed":true,"reason":"Same missing-config crash and reproduction."},{"numbers":[206,207],"confirmed":false,"reason":"Different export formats despite similar titles."}]}' > "$work/batch.json"
sh "$SCRIPTS/review.sh" apply "$run" "$work/batch.json"
check 'confirmed duplicate uses the older canonical; rejected nomination leaves bin and pointer unchanged' '
  any(.[]; .item.number==110 and .duplicate_of==109 and .bin=="possible-duplicate") and
  any(.[]; .item.number==207 and .duplicate_of==null and .bin=="needs-triage" and .matched_rule=="healthy")'
sh "$SCRIPTS/review.sh" next "$run" > "$work/next.json"
jq -e '.stage=="complete"' "$work/next.json" >/dev/null
sh "$SCRIPTS/review.sh" workload "$run" 15 > "$work/workload.json"
jq -e '. == {batch_size:15,item_pending:0,item_batches:0,duplicate_pending:0,duplicate_batches:0,total_batches:0}' "$work/workload.json" >/dev/null
printf 'ok - completed review has zero pending work and batches\n'
# Three-way union, including wontfix precedence.
jq -s 'map(select(.item.number==109 or .item.number==110)) | . + [.[1] | .item.number=111 | .bin="wontfix" | .duplicate_of=null | .duplicate_candidates=[{number:110,score:1,confirmed:null}]] | .[]' "$V" > "$work/cluster.jsonl"
cp "$work/cluster.jsonl" "$V"
printf '%s\n' '{"stage":"duplicates","decisions":[{"numbers":[110,111],"confirmed":true,"reason":"Third report of the same crash."}]}' > "$work/batch.json"
sh "$SCRIPTS/review.sh" apply "$run" "$work/batch.json"
check 'duplicate chains flatten to the oldest canonical without overriding wontfix' '
  any(.[]; .item.number==110 and .duplicate_of==109) and any(.[]; .item.number==111 and .duplicate_of==109 and .bin=="wontfix")'
# Bridge an existing group to an older canonical through an incoming edge.
jq -s '(. + [.[0] | .item.number=108 | .duplicate_candidates=[]])
  | map(if .item.number==110 then .duplicate_candidates += [{number:108,score:1,confirmed:null}] else . end)
  | sort_by(.item.number) | .[]' "$V" > "$work/bridge.jsonl"
cp "$work/bridge.jsonl" "$V"
printf '%s\n' '{"stage":"duplicates","decisions":[{"numbers":[108,110],"confirmed":true,"reason":"The older report describes the same missing-config crash."}]}' > "$work/batch.json"
sh "$SCRIPTS/review.sh" apply "$run" "$work/batch.json"
check 'merging groups replaces an incoming-only members original rationale with duplicate evidence' '
  any(.[]; .item.number==109 and .duplicate_of==108 and .bin=="possible-duplicate" and (.reason|contains("via #109/#110")))'
# Snapshot completeness is independent of item and pair review checkpoints.
included=$(jq -s length "$run/items.jsonl")
jq --argjson included "$included" '.snapshot={complete:true,included:$included,listed:$included,reason:null}' "$run/meta.json" > "$work/meta.json"
mv "$work/meta.json" "$run/meta.json"
sh "$SCRIPTS/report.sh" "$run" >/dev/null
jq -e '.snapshot.complete == true and .snapshot.included == .snapshot.listed' "$run/meta.json" >/dev/null
sh "$SCRIPTS/mark-partial.sh" "$run" 697 'Fetch interrupted during PR detail retrieval.'
jq -e --argjson included "$included" '.snapshot == {complete:false,included:$included,listed:697,reason:"Fetch interrupted during PR detail retrieval."}' "$run/meta.json" >/dev/null
sh "$SCRIPTS/report.sh" "$run" >/dev/null
grep -q 'Stale closure candidates' "$run/report.html"
grep -q 'a maintainer must' "$run/report.html"
cp "$run/report.html" "$work/partial.html"
sh "$SCRIPTS/report.sh" "$run" >/dev/null
cmp "$work/partial.html" "$run/report.html"
grep -q 'Incomplete snapshot' "$run/report.html"
if sh "$SCRIPTS/mark-partial.sh" "$run" 1 'Bad count' >/dev/null 2>&1; then echo 'FAIL: accepted undersized listed count' >&2; exit 1; fi
# A fake GitHub integration proves that interruption preserves records, resume skips
# completed PR details, and latest is published only after a complete snapshot.
mkdir -p "$work/bin" "$work/target"
printf '%s\n' '#!/bin/sh' \
  'printf "%s\\n" "$*" >> "$FAKE_GH_LOG"' \
  'if [ "$1 $2" = "repo view" ]; then printf "%s\\n" "example/repo"; exit 0; fi' \
  'url=${5:-${4:-${3:-}}}' \
  'case "$url" in' \
  '  *issues*) printf "%s\\n" '\''[{"number":1,"html_url":"https://example/1","title":"Issue one","state":"open","user":{"login":"human","type":"User"},"created_at":"2025-12-01T00:00:00Z","updated_at":"2025-12-31T00:00:00Z","labels":[]},{"number":2,"pull_request":{},"html_url":"https://example/2","title":"PR two","state":"open","user":{"login":"human","type":"User"},"created_at":"2025-12-01T00:00:00Z","updated_at":"2025-12-31T00:00:00Z","labels":[]},{"number":3,"pull_request":{},"html_url":"https://example/3","title":"PR three","state":"open","user":{"login":"human","type":"User"},"created_at":"2025-12-01T00:00:00Z","updated_at":"2025-12-31T00:00:00Z","labels":[]}]'\'';;' \
  '  *pulls/2) printf "%s\\n" '\''{"number":2,"html_url":"https://example/2","title":"PR two","state":"open","user":{"login":"human","type":"User"},"created_at":"2025-12-01T00:00:00Z","updated_at":"2025-12-31T00:00:00Z","labels":[],"draft":false,"additions":1,"deletions":0,"changed_files":1,"mergeable_state":"clean"}'\'';;' \
  '  *pulls/3) if [ ! -e "$FAKE_GH_STATE/interrupted" ]; then touch "$FAKE_GH_STATE/interrupted"; exit 1; fi; printf "%s\\n" '\''{"number":3,"html_url":"https://example/3","title":"PR three","state":"open","user":{"login":"human","type":"User"},"created_at":"2025-12-01T00:00:00Z","updated_at":"2025-12-31T00:00:00Z","labels":[],"draft":false,"additions":1,"deletions":0,"changed_files":1,"mergeable_state":"clean"}'\'';;' \
  '  *) echo "unexpected gh call: $*" >&2; exit 2;;' \
  'esac' > "$work/bin/gh"
chmod +x "$work/bin/gh"
git init -q "$work/target"
export FAKE_GH_LOG="$work/gh.log" FAKE_GH_STATE="$work"
if PATH="$work/bin:$PATH" REPOSWEEP_NOW=1767225600 sh "$SCRIPTS/reposweep" "$work/target" >/dev/null 2>&1; then
  echo 'FAIL: fake interrupted fetch succeeded' >&2; exit 1
fi
fake_run=$(find "$work/target/.reposweep/runs" -mindepth 1 -maxdepth 1 -type d | head -n 1)
[ ! -e "$work/target/.reposweep/runs/latest" ]
sh "$SCRIPTS/status.sh" "$fake_run" > "$work/status.json"
jq -e '.fetch == {state:"interrupted",completed:2,total:3} and .classification.state == "not-started"' "$work/status.json" >/dev/null
PATH="$work/bin:$PATH" REPOSWEEP_RETRY_DELAY=0 REPOSWEEP_REVIEW_BATCH_SIZE=2 sh "$SCRIPTS/reposweep" resume "$fake_run" >/dev/null 2>"$work/resume.err"
grep -q 'at batch size 2;' "$work/resume.err"
grep -q 'review batches total' "$work/resume.err"
[ -L "$work/target/.reposweep/runs/latest" ]
sh "$SCRIPTS/status.sh" "$fake_run" > "$work/status.json"
jq -e '.fetch == {state:"complete",completed:3,total:3} and .snapshot.complete and .classification.state == "complete"' "$work/status.json" >/dev/null
[ "$(grep -c 'pulls/2' "$work/gh.log")" -eq 1 ] || { echo 'FAIL: repeated completed PR detail request' >&2; exit 1; }
printf 'ok - interrupted fetch resumes without replacing latest or repeating completed PR details\n'

printf '\n%d artifact checks passed; config precedence, batch rejection, snapshot metadata, rerender, and fetch recovery checks passed.\n' "$checks"
