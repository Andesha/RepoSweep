# Issue judgment

Judge only rows returned by `review.sh next`. The mechanical pass has already
handled maintainer labels and inactivity. Its first-match ladder is
`wontfix → possible-duplicate → needs-info → close-as-stale → ready-for-agent → ready-for-human → needs-triage`.
The separate duplicate pass handles the second rung.

Read the title and body, then any linked requirements or discussion needed to
choose an action. Decide the first supported outcome:

- `wontfix`: explicit maintainer rejection or a documented scope exclusion.
  Age, difficulty, or your own roadmap preference is not rejection evidence.
- `needs-info`: a missing reproduction, environment, expected result, or scope
  prevents work. Name the missing information in the rationale. A question mark
  in a title is not sufficient evidence.
- `ready-for-agent`: bounded implementation, clear expected behavior, and enough
  context to work without a maintainer decision. A good-first-issue label alone
  does not establish readiness.
- `ready-for-human`: an actionable request needs a maintainer's design, policy,
  access, or prioritization decision. Name that decision.
- `needs-triage`: the evidence supports none of these. Explain what remains
  uncertain rather than inventing scope or obsolescence.

Optionally propose `type: "bug"`, `"feature"`, or `"docs"`; use null or omit it
when the request is not classifiable. A finalized `needs-triage` is a legitimate
judgment. An unread item is still pending.
