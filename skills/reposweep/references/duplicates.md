# Duplicate review

`review.sh next` supplies same-kind candidate pairs, including both titles,
recorded bodies, overlap score, and the significant shared title tokens. Pairs
are ordered by descending score; numbers are ordered `[older, newer]`. Read both
items, even if the titles are identical. Shared components or words are not
semantic sameness.

Confirm only when they describe the same underlying failure or requested
change. Different reproduction conditions, expected behavior, or intended
solutions may distinguish them. Labels are weak supporting evidence; ignore
reporter identity. Issue-to-PR implementation links are outside duplicate scope.

```json
{"stage":"duplicates","decisions":[
  {"numbers":[41,57],"confirmed":true,"reason":"Both reproduce the same crash when the config file is absent."},
  {"numbers":[63,70],"confirmed":false,"reason":"One exports CSV; the other changes the JSON response format."}
]}
```

Submit through `review.sh apply`. Rejections retain the original bin and null
pointer. Confirmations set the newer item's bin to `possible-duplicate`, unless
`wontfix` has precedence. Connected confirmations share the lowest-numbered
canonical; there is no cluster ID. If either endpoint already belongs to a
cluster, inspect its canonical before adding another edge. Do not connect
clusters whose members represent distinct requests.

Every reviewed pair stays checkpointed, including rejected nominations, so
resume skips completed comparisons. Existing pair decisions are immutable in a
run; start a new sweep to reconsider them. These remain proposals for a
maintainer to verify before closing anything.
