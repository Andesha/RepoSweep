# PR judgment

The mechanical ladder is
`wontfix → possible-duplicate → needs-info → needs-rebase → close-as-stale → flag-for-review → needs-triage`.
Only small, explicitly clean, unqueued PRs past their idle window can receive a
mechanical close proposal. Old large, medium, conflicted, blocked, and unknown
PRs go to review. Fresh conflicts need rebase. Fresh clean PRs stay in
`needs-triage` with a `healthy` flag. Draft and bot status are facets, not exclusions.
A mechanical `close-as-stale` result is only a closure candidate; it does not
prove obsolescence, and the maintainer must inspect and confirm closure.

You receive the unresolved subset, usually an unknown or blocked merge state.
Read the description and, as needed, comments or checks. Use the repository in
`meta.json` when calling `gh pr view NUMBER --repo OWNER/REPO --comments`.

Choose `needs-info` for an identified missing author response or description,
`flag-for-review` for a concrete review/check blocker, `wontfix` for explicit
maintainer rejection, or `needs-triage` when no supported action follows.
Explain the evidence in one line. An unknown merge state is not a clean merge,
a draft is not abandonment, and a PR implementing an issue is not its duplicate.

The judgment pass cannot invent a stale-close or rebase result contrary to the
snapshot. If the tracker changed after fetching, explain that limitation or ask
for a new sweep. Duplicate review is a separate stage.
