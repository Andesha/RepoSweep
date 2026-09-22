# RepoSweep

RepoSweep reviews a repository's open issues and pull requests and proposes
next actions. It does not apply those actions to the tracker.

## Language

**Run**: One backlog sweep, with its own snapshot, resolved thresholds,
verdicts, and report. A resumed run continues reviewing the same snapshot.

**Partial snapshot**: A known-incomplete subset of the listed backlog, such as
records recovered after an interrupted fetch. Its counts describe only that
subset, not the full repository or a representative sample.

**Preliminary report**: A report whose item judgments or duplicate comparisons
are still pending. This is separate from whether the snapshot itself is complete.

**Review complete**: All item judgments and nominated pair comparisons for a
snapshot have been decided. This says nothing about whether every open item
was fetched or whether a maintainer has accepted the proposals.

**Normalized item**: The tracker-neutral record for an open issue or PR.
Its kind distinguishes shared fields from issue-only and PR-only fields;
its number identifies it within the repository. Missing issue type means unknown.

**Verdict**: One item's proposed bin, evidence-based rationale, and provenance.
It includes the normalized item and may remain pending agent judgment.

**Bin**: The single proposed next-action group for an item. `needs-triage` is
the holding group when no other action is supported, including after review.

**Facet**: A filterable item attribute such as kind, draft status, bot status,
conflict state, or issue type. It does not create an action group.

**Flag**: A secondary signal such as `good-first-issue` or `healthy`, rather
than a bin or a hard item attribute.

**Duplicate nomination**: A same-kind pair selected by title overlap for
semantic review. A nomination is not a duplicate finding.

**Canonical**: The lowest-numbered item in a confirmed duplicate group.
Other members point directly to it, while the proposed action remains subject
to maintainer confirmation and `wontfix` precedence.

**Threshold config**: Numeric overrides for staleness, PR age and size, and
duplicate nomination limits. It does not alter the bin set or ladder order.

**Resolved thresholds**: The effective threshold values frozen at run start.
All subsequent stages use these values, even if repository configuration changes.

**Past due**: Idle beyond the applicable staleness window and not already
queued for work. This measures inactivity, not proof of obsolescence.
