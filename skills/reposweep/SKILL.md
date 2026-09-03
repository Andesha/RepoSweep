---
name: reposweep
description: "Sweep a repo's open issues and PRs, classify each into an opinionated-but-overridable taxonomy, and emit one self-contained HTML report. Propose-only — writes nothing back to the tracker. Harness-neutral (gh/jq/sh). Use when a maintainer wants their backlog triaged into action-piles without any automated closing or relabelling."
---

# reposweep

A **propose-only** sweep of a repository's open issues and PRs. Every item is
classified into exactly one **bin** (an action-pile) with a one-line rationale,
and the whole backlog is rendered as a single self-contained HTML report the
maintainer can open offline or copy into `docs/` for GitHub Pages. RepoSweep
**writes nothing back** to the tracker: every classification is a proposal.

The domain vocabulary — **Run**, **Normalized item**, **Verdict**, **Bin**,
**Facet**, **Flag**, **Canonical**, **Threshold config**, **Resolved
thresholds** — is defined in `CONTEXT.md`. Read it first; this file uses those
terms verbatim.

## Requirements

- `gh` (authenticated for the target repo), `jq`, and a POSIX `sh`. Nothing else.
- Harness-neutral: no dependency on any particular agent harness.

## How a sweep works — two passes

1. **Mechanical pass (scripts, deterministic).** `scripts/reposweep` resolves the
   thresholds once, creates the run, fetches & normalizes every open item,
   computes a deterministic Verdict for each, nominates duplicate pairs by loose
   title overlap, **seeds `needs_agent`** on the subset that needs judgment, and
   renders a first-cut report. Reproducible; no LLM involved.
2. **Agent pass (you, the LLM).** Refine only the rows the mechanical pass
   flagged (`needs_agent == true`) and confirm the duplicate nominations, in
   small checkpointed batches. Then re-render the report.

### Run the mechanical pass

```sh
sh scripts/reposweep
```

This creates `.reposweep/runs/<utc-timestamp>/` under the repo root, containing
`meta.json` (the **resolved thresholds** + `swept_at`), `items.jsonl` (the
normalized items), `verdicts.jsonl` (one Verdict per item), and `report.html`.
A `latest` pointer names the newest run. It prints how many verdicts were seeded
`needs_agent` and how many duplicates were nominated.

### Do the agent pass

Work the flagged rows in **batches of ~10–20** so an interrupted sweep resumes
cleanly (resume = the rows still carrying `needs_agent: true`). For each batch:

1. Select flagged rows:
   `jq -c 'select(.needs_agent)' <run>/verdicts.jsonl` (take the next ~15).
2. For each, read `.item` (title, labels, type, age). Fetch the body only if you
   need it: `gh issue view <n> --json body` / `gh pr view <n> --json body`.
3. **Classify** by the item's ladder (below). Rewrite that item's line in
   `verdicts.jsonl` in place: set `bin`, set `matched_rule` to `"agent"`, write a
   one-line `reason`, and set `needs_agent: false`. Never delete a line; update by
   `number`.
4. **Confirm duplicates** (rows with `duplicate_of` set): compare the item's
   title+body against its **canonical** (the lower/oldest number). Labels are a
   tiebreak; ignore the reporter. If it is a true duplicate, keep
   `bin: "possible-duplicate"` and `duplicate_of`. If not, clear `duplicate_of`
   to `null` and reclassify by the ladder.
5. Checkpoint: after each batch, the updated `verdicts.jsonl` is the resume point.

When no `needs_agent: true` rows remain, re-render:

```sh
sh scripts/report.sh <run-dir>
```

## Bins and the first-match ladders (baked in — not configurable)

The suggested outcome **is** the bin. Assigned by the **first** rule that fires.

**Issues:** `wontfix` → `possible-duplicate` → `needs-info` → `close-as-stale`
→ `ready-for-agent` → `ready-for-human` → `needs-triage`.

**PRs:** `wontfix` → `possible-duplicate` → `needs-info` → `needs-rebase`
(fresh conflict) → `close-as-stale` (small **and** clean **and** idle past
`STALE_DAYS`) → `flag-for-review` (anything else past stale, *including* large
or conflicted-and-old — never silently closed) → `needs-triage` (carries a
`healthy` flag).

Notes that the mechanical pass already encodes, and you must preserve:

- A `duplicate_of` pointer forces `possible-duplicate` (2nd rung; only `wontfix`
  overrides). The **canonical** is the lowest (oldest) number.
- `needs-info` items use the shorter `NEEDS_INFO_DAYS` staleness window (they age
  out faster); past it they fall through to `close-as-stale`.
- **Queued** work (already `ready-for-agent` / `ready-for-human`) is **exempt**
  from staleness.
- **Facets** (kind, draft, bot, conflicted, issue type) never open a new bin;
  they are filters. **Flags** (`good-first-issue`, `healthy`, …) are soft signals
  and never a bin. `good-first-issue` is an input flag, not a label RepoSweep emits.

## Threshold config (the only override surface)

Flat scalar numbers, three layers, low → high precedence:

1. `defaults.env` (shipped here — the canonical opinion),
2. an optional repo-root `reposweep.env` (partial — name only the keys you change),
3. an environment variable of the same name (a single-run override).

Runs fully on **zero config**. The resolved values are frozen into the run's
`meta.json`; the scripts, you, and the report all read the resolved thresholds
from the run — never the layers directly. Keys: `STALE_DAYS`, `NEEDS_INFO_DAYS`,
`PR_LONG_LIVED_DAYS`, `SIZE_SMALL_LINES`, `SIZE_SMALL_FILES`, `SIZE_LARGE_LINES`,
`SIZE_LARGE_FILES`, `DEDUP_MIN_SHARED_TOKENS`, `DEDUP_MAX_PARTNERS`.

Label-string mappings live in `docs/agents/triage-labels.md`, **not** here.

## Publishing (propose-only — the skill never pushes)

To share on GitHub Pages, the maintainer copies one file (the skill prints these
exact lines after a sweep):

```sh
cp <run-dir>/report.html docs/reposweep/index.html
git add docs/reposweep/index.html && git commit -m 'reposweep report' && git push
```

Served at `https://andesha.github.io/RepoSweep/reposweep/` after a one-time
Pages → `main` / `docs` setup.

## Portability

Everything tracker-specific is confined to the **fetch-and-normalize** seam
(`scripts/fetch-normalize.sh` + `scripts/normalize.jq`). Porting to another
tracker means writing one adapter that emits the same Normalized item shape;
classification, dedup, the report, and config resolution are unchanged.

## Tests

```sh
sh tests/run-tests.sh
```

Dependency-free POSIX assertions. They cover the one automated seam — the
mechanical classification pipeline (both ladders, sizing, staleness incl.
`needs-info` fast-stale and queued-work exemption, duplicate nomination,
`needs_agent` seeding), config resolution/precedence, run scaffolding, the
normalize transform (against a recorded API sample), and a structural report
check. The LLM passes and report presentation are verified by eye.

## Out of scope

Applying changes back to the tracker; configuring the ladder/bin set (only the
scalar thresholds are tunable); label-string overrides in config; run-over-run
trends; charting libraries; heavy ML dedup; local-LLM privacy mode; a hosted
CI bot. See issue #12 for the full boundary.
