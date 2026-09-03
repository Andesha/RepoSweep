# RepoSweep — Context & Glossary

The ubiquitous language for RepoSweep, a propose-only skill that sweeps a repo's issue/PR backlog and classifies each item. Glossary only — no implementation detail.

## Glossary

### Run
One sweep of the backlog, captured under `.reposweep/runs/<utc-timestamp>/`. Self-contained and reproducible: it holds the normalized items, the verdicts, and a run-level `meta.json`. A `latest` pointer names the newest run.

### Normalized item
The tracker-neutral shape that fetch-and-normalize emits for one open backlog item — the seam between a specific tracker (GitHub, etc.) and everything downstream. One flat record for both issues and PRs, discriminated by **kind**; type-specific fields are present only for their kind. Identity is the item's tracker-local **number**.

### Verdict
The classification RepoSweep proposes for one item, written to `verdicts.jsonl`. Self-contained — it embeds the normalized item — so the report reads verdicts in one pass. Carries the **bin**, the rationale, provenance, and the **duplicate_of** pointer. RepoSweep is propose-only: a verdict is a proposal, never an applied change.

### Bin
The single action-pile a verdict sorts into, and the report's primary grouping. The suggested outcome *is* the bin. One of: `ready-for-agent`, `ready-for-human`, `needs-info`, `possible-duplicate`, `wontfix`, `close-as-stale` (issues + PRs), `needs-rebase`, `flag-for-review` (PR-only), and `needs-triage` (the fallthrough holding pen — a bin, but not an outcome). Assigned by the first-match rule ladder.

### Facet
A secondary attribute the report filters or columns *within* a bin, rather than sorting by. Kind (issue vs. PR), draft, bot, conflicted, and issue type are facets — they never open a new bin.

### Flag
A soft input signal on a verdict (`good-first-issue`, `has-repro`, `healthy`, …) that informs a judgment or the report but doesn't warrant its own named field. Distinct from a **facet**, which is a hard, filterable field on the item.

### Canonical (duplicate)
When two items are flagged as duplicates, the **canonical** one is the lowest (oldest) number; the newer item's verdict carries `duplicate_of: <canonical number>`. A cluster of three or more emerges naturally as several items pointing at the same canonical number — there is no separate cluster id.

### Threshold config
The only override surface: a flat set of scalar numbers (staleness windows, PR long-lived age, Prow size cutoffs, dedup guards) — the tunable knobs of the opinionated taxonomy. The classification logic itself (the ladder order, the bin set) is not configurable, and label strings are overridden elsewhere (`triage-labels.md`), not here. Three layers, low precedence to high: the shipped **`defaults.env`** (the canonical opinion), an optional repo-root **`reposweep.env`** (partial — names only the keys it changes), and environment variables. RepoSweep runs fully on zero config.

### Resolved thresholds
The effective numbers a **run** actually used, computed once from the threshold config at sweep start and frozen into the run's `meta.json`. The scripts, the agent, and the report all read the resolved thresholds from the run — never the config layers directly — so a run is reproducible and self-explaining, and no stage can drift from another.
