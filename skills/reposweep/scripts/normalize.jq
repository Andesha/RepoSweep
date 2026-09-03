# RepoSweep — normalize a tracker payload into the Normalized item shape.
#
# This is the pure-transform half of the fetch-and-normalize seam — the ONE
# place that knows a specific tracker's field names. Porting RepoSweep to
# another tracker means writing an adapter that feeds this the same shape, or
# swapping this filter. Input: an array of raw gh issue/PR records. Output: one
# normalized item per line. Invoke with --arg kind "issue" | "pr".
#
# carried_labels are the raw label strings; the triage-labels.md indirection
# (role <-> actual string) is identity in this repo, so downstream matches the
# role strings directly.

def derive_type($labels):
  ($labels | map(ascii_downcase)) as $l
  | if   ($l | any(test("bug")))                 then "bug"
    elif ($l | any(test("feature|enhancement"))) then "feature"
    elif ($l | any(test("doc")))                 then "docs"
    else null end;

def base:
  {
    number, url, title,
    kind: $kind,
    state: ((.state // "OPEN") | ascii_downcase),
    author: (.author.login // "unknown"),
    is_bot: (.author.is_bot // false),
    created_at: .createdAt,
    updated_at: .updatedAt,
    carried_labels: [ (.labels // [])[].name ]
  };

.[] |
if $kind == "issue" then
  base + { type: derive_type([ (.labels // [])[].name ]) }
else
  base + {
    is_draft:        (.isDraft // false),
    additions:       (.additions // 0),
    deletions:       (.deletions // 0),
    changed_files:   (.changedFiles // 0),
    mergeable_state: (.mergeStateStatus // "UNKNOWN")
  }
end
