# Apply one validated batch to the verdict checkpoint. No network or tracker writes.
def require($ok; $message): if $ok then . else error($message) end;
def one_line: type == "string" and (length > 0) and (test("[\r\n]") | not);
def root($parents; $n):
  if $parents[$n|tostring] == $n then $n else root($parents; $parents[$n|tostring]) end;
def clusters:
  . as $rows
  | (reduce .[] as $v ({}; .[$v.item.number|tostring] = $v.item.number)) as $parents
  | reduce (.[] | .item.number as $n | .duplicate_candidates[] | select(.confirmed == true) | [$n, .number]) as $edge
      ($parents; root(.; $edge[0]) as $a | root(.; $edge[1]) as $b | .[([$a,$b]|max)|tostring] = ([$a,$b]|min))
  | . as $parents
  | $rows | map(root($parents; .item.number) as $canonical
      | if $canonical == .item.number then . else
          .duplicate_of = $canonical
          | if .bin == "wontfix" then . else
              .bin = "possible-duplicate" | .matched_rule = "agent:duplicate"
              | .item.number as $number
              | ([$rows[] as $v | $v.duplicate_candidates[]
                    | select(.confirmed == true and ($v.item.number == $number or .number == $number))
                    | {older: .number, newer: $v.item.number, reason}][0]) as $evidence
              | .reason = "Confirmed group via #\($evidence.older)/#\($evidence.newer): \($evidence.reason)"
              | .flags -= ["healthy"]
            end
        end);

$batch[0] as $b
| require(($batch|length) == 1 and ($b|type) == "object"; "expected one batch object")
| require(($b|keys) == ["decisions","stage"]; "batch keys must be stage and decisions")
| require(($b.decisions|type) == "array"; "decisions must be an array")
| require(($b.decisions|length) > 0 and ($b.decisions|length) <= 20; "submit 1-20 decisions per batch")
| if $b.stage == "judgment" then
    require(($b.decisions|map(.number)|length) == ($b.decisions|map(.number)|unique|length); "duplicate judgment numbers")
    | reduce $b.decisions[] as $d (.;
        require(($d|keys) - ["number","bin","reason","type"] == []; "unknown judgment field")
        | require(($d.reason|one_line); "a one-line rationale is required")
        | ([.[] | select(.item.number == $d.number)]) as $found
        | require(($found|length) == 1 and $found[0].needs_agent; "item is missing or already decided")
        | $found[0] as $v
        | (if $v.item.kind == "issue" then ["ready-for-agent","ready-for-human","needs-info","wontfix","needs-triage"]
           else ["needs-info","wontfix","flag-for-review","needs-triage"] end) as $bins
        | require(($bins|index($d.bin)) != null; "invalid judgment bin for this kind or ladder position")
        | require(($d|has("type")|not) or ($v.item.kind == "issue" and ([null,"bug","feature","docs"]|index($d.type)) != null); "invalid inferred issue type")
        | map(if .item.number == $d.number then
            .bin = $d.bin | .reason = $d.reason | .matched_rule = "agent:judgment"
            | .needs_agent = false | .inferred_type = ($d.type // .inferred_type)
          else . end))
  elif $b.stage == "duplicates" then
    require(all(.[]; .needs_agent == false); "finish item judgments before duplicate review")
    | require(($b.decisions|map(.numbers)|length) == ($b.decisions|map(.numbers)|unique|length); "duplicate pair decisions")
    | reduce $b.decisions[] as $d (.;
        require(($d|keys) == ["confirmed","numbers","reason"]; "duplicate decision keys must be numbers, confirmed, reason")
        | require(($d.confirmed|type) == "boolean" and ($d.reason|one_line); "confirmation needs a boolean and one-line rationale")
        | require(($d.numbers|type) == "array" and ($d.numbers|length) == 2 and $d.numbers[0] < $d.numbers[1]; "pair must be [older, newer]")
        | ([.[] | select(.item.number == $d.numbers[1]) | .duplicate_candidates[]
            | select(.number == $d.numbers[0] and .confirmed == null)]) as $found
        | require(($found|length) == 1; "pair was not nominated or is already reviewed")
        | map(if .item.number == $d.numbers[1] then
            .duplicate_candidates |= map(if .number == $d.numbers[0] then .confirmed = $d.confirmed | .reason = $d.reason else . end)
          else . end))
    | clusters
  else error("stage must be judgment or duplicates") end
| .[]
