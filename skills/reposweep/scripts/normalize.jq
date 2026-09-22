include "rules";

def issue_type:
  [.labels[].name | ascii_downcase] as $labels
  | if any($labels[]; . == "bug" or . == "type:bug" or . == "type: bug" or . == "kind/bug") then "bug"
    elif any($labels[]; . == "feature" or . == "enhancement" or . == "type:feature" or . == "type: feature" or . == "kind/feature") then "feature"
    elif any($labels[]; . == "documentation" or . == "docs" or . == "type:docs" or . == "type: docs" or . == "kind/documentation") then "docs"
    else null end;

# Input is recorded GitHub REST issue records and full per-PR GET records.
. as $raw
| {
    number, url: .html_url, title, state,
    kind: (if has("mergeable_state") then "pr" else "issue" end),
    author: (.user.login // "ghost"),
    is_bot: (.user.type == "Bot" or ((.user.login // "") | endswith("[bot]"))),
    created_at, updated_at, carried_labels: [.labels[].name]
  }
| if .kind == "issue" then . + {type: ($raw | issue_type)}
  else . + {
    is_draft: $raw.draft,
    additions: $raw.additions, deletions: $raw.deletions, changed_files: $raw.changed_files,
    mergeable_state: ($raw.mergeable_state // "unknown")
  } end
| derive($meta[0])
