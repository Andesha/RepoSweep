include "rules";

# Same-kind title overlap nominates pairs, never a duplicate verdict.
def tokens:
  ascii_downcase | [scan("[a-z0-9]{3,}")]
  | . - ["the","and","for","with","from","this","that","there","when","what",
         "cannot","does","doesnt","not","add","support","using","into","are",
         "was","has","have","will","can","should","could","would","but","all",
         "any","our","your","issue","request","please","bug","feature","fix",
         "proposal","task","update"] | unique;
def candidates($items; $t):
  if $t.DEDUP_MAX_PARTNERS == 0 then [] else
  ($items | map({number, kind, tokens: (.title | tokens)})) as $tokenized
  # Ignore tokens present in at least three titles and 10% of their kind. They
  # identify the backlog more often than a specific duplicate.
  | ($tokenized | group_by(.kind) | map(
      . as $kind_items
      | {key: .[0].kind,
         value: ([.[].tokens[]] | group_by(.)
           | map(select(length >= 3 and length * 10 >= ($kind_items | length)) | .[0]))})
      | from_entries) as $common
  | ($tokenized | map(.tokens -= $common[.kind])) as $tokens
  | [range(0; $tokens | length) as $i | $tokens[$i] as $a
      | $tokens[$i+1:][] as $b | select($a.kind == $b.kind)
      | ($a.tokens - ($a.tokens - $b.tokens)) as $shared
      | select(($shared | length) >= $t.DEDUP_MIN_SHARED_TOKENS)
      | {numbers: [$a.number, $b.number], shared_tokens: $shared,
         score: (($shared | length) / ([$a.tokens[], $b.tokens[]] | unique | length))}]
  | sort_by(-.score, .numbers)
  # Greedy top-scoring edges enforce the partner cap on BOTH endpoints.
  | reduce .[] as $pair ({counts: {}, pairs: []};
      ($pair.numbers[0] | tostring) as $a | ($pair.numbers[1] | tostring) as $b
      | if (.counts[$a] // 0) < $t.DEDUP_MAX_PARTNERS and (.counts[$b] // 0) < $t.DEDUP_MAX_PARTNERS then
          .counts[$a] = ((.counts[$a] // 0) + 1) | .counts[$b] = ((.counts[$b] // 0) + 1)
          | .pairs += [$pair]
        else . end) | .pairs end;

$meta[0] as $m
| sort_by(.number) | map(derive($m)) as $items
| candidates($items; $m.thresholds) as $pairs
| $items[] as $item
| ($item | classify($m)) as $v
| $v + {
    duplicate_of: null,
    duplicate_candidates: [$pairs[] | select(.numbers[1] == $item.number)
      | {number: .numbers[0], score, shared_tokens, confirmed: null}],
    inferred_type: null,
    flags: [
      (if any($item.carried_labels[]; . == "good-first-issue" or . == "good first issue") then "good-first-issue" else empty end),
      (if $item.kind == "issue" and ($item.title | test("\\?\\s*$")) then "question-shaped" else empty end),
      (if $v.matched_rule == "healthy" then "healthy" else empty end)
    ],
    item: $item
  }
