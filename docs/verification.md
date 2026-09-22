# Verification and issue coverage

Checked on 2026-09-06, on `cleanup/presentation-ready`. These are implementation
and verification notes, not claims that the GitHub issues have been closed.

## Issue coverage

| Issue | Delivered |
| --- | --- |
| [#1](https://github.com/Andesha/RepoSweep/issues/1), [#12](https://github.com/Andesha/RepoSweep/issues/12) | Portable skill, local mechanical pass, bounded agent review, and offline report. The README explains the complete workflow rather than presenting the shell command as a finished agent sweep. |
| [#13](https://github.com/Andesha/RepoSweep/issues/13) | Zero-config run creation, partial overrides, environment precedence, frozen thresholds and label mapping, collision-safe run directories, and `latest` after a successful mechanical run. |
| [#14](https://github.com/Andesha/RepoSweep/issues/14) | All-page GitHub issue/PR listing; per-PR REST GET; recorded responses and bodies; normalized kind-specific fields, bot/draft status, dates, size, and conflict state. |
| [#15](https://github.com/Andesha/RepoSweep/issues/15) | Shared rule derivations, both ladders, shorter needs-info window, queued-work exemption, conservative PR closure, same-kind title nominations, and caps on both endpoints. Offline artifact checks cover the rules. |
| [#16](https://github.com/Andesha/RepoSweep/issues/16) | Issue/PR judgment references and `review.sh next/apply`. Batches are bounded to 20; writes are locked, validated, and atomic. Completed item judgments are skipped. |
| [#17](https://github.com/Andesha/RepoSweep/issues/17) | Separate pair review with both bodies. Rejections preserve the bin; confirmations use the oldest canonical, flatten groups, and respect wontfix. Both outcomes are checkpointed. |
| [#18](https://github.com/Andesha/RepoSweep/issues/18) | Offline faceted queue, live filter counts, search, native keyboard-accessible accordions, canonical links, frozen-threshold health summary, pending-review status, mobile layout, and print-only publishing instructions. |
| [#23](https://github.com/Andesha/RepoSweep/issues/23) | Duplicate nomination drops generic title words and tokens common within each kind, retains same-kind endpoint caps, and exposes overlap scores and shared-token evidence. Focused fixtures cover useful matches, generic false positives, caps, and cross-kind rejection. |
| [#24](https://github.com/Andesha/RepoSweep/issues/24) | Reports call mechanically selected stale items closure candidates, state that maintainers must inspect and confirm closure, and retain rationale showing inactivity, threshold, and queued-work status. No additional semantic-review stage was added. |

Issues #2–#11 supplied the design decisions. The selected queue layout from
[the prototype](https://github.com/Andesha/RepoSweep/blob/prototype/report-8/prototypes/report.prototype.html)
is retained; its mock-data mistakes are not carried into classification.

## Checks performed

- `sh skills/reposweep/tests/run-tests.sh`: 14 grouped artifact assertions plus
  config precedence, label mapping, overwrite refusal, invalid/repeated batch
  rejection, and resume checks. No network or LLM.
- ShellCheck passed for scripts, tests, and demo generation. Dynamic source
  paths were supplied; SC2016 was excluded for literal jq programs and intentional
  shell-injection test strings. POSIX shell syntax checks passed.
- A real read-only sweep of `Andesha/RepoSweep` fetched all six open issues.
  The agent reviewed the design-map issue and rejected the #16/#17 duplicate
  nomination because they implement distinct stages. `review.sh next` returned
  `complete`. The repository had no open PRs during this sweep.
- A [recorded GitHub sample](../examples/github-sample.jsonl) from public
  `jqlang/jq` issue [#3597](https://github.com/jqlang/jq/issues/3597) and PR
  [#3627](https://github.com/jqlang/jq/pull/3627) exercised REST normalization.
  The file retains the consumed response fields and bodies, not every API field.
- An adapter smoke check replayed recorded data as 1,001 issue records and one
  per-PR response across 11 pages. All 1,002 normalized items and counts survived.
  A simulated failing `gh` process left no published snapshot and released its lock.
  This validates adapter behavior, not a live 1,002-item GitHub sweep.
- Chrome/Playwright checks passed at desktop and 390px mobile widths: action
  groups, live counts, search, combined human/non-draft PR filters, reset,
  keyboard accordion operation, canonical links and reasoning, unknown issue
  types, PR-only conflict filters, and expand/collapse.
- Empty and 1,000-item reports rendered without JavaScript errors. A hostile
  title containing closing script tags and an image event handler remained text;
  `javascript:` item URLs were not clickable. The reports made no external requests.
- A 1,000-item classification with deliberately similar titles took about six
  seconds and 312 MiB peak memory on this machine. Pair nomination is quadratic;
  this is not a claim of suitability for arbitrarily large backlogs.

Browser and adapter smoke checks were run during development, not added as a
new dependency-heavy test framework. The checked-in demo can be regenerated:

```sh
sh examples/generate-demo.sh
```

To replay normalization of the recorded sample with a run's frozen metadata:

```sh
jq -c -L skills/reposweep/scripts \
  --slurpfile meta /path/to/run/meta.json \
  -f skills/reposweep/scripts/normalize.jq examples/github-sample.jsonl
```

## Loris trial and partial recovery

A separate saved Pi session ran the skill against `aces/Loris` on 2026-09-06,
using `openai-codex/gpt-6-astra` with reasoning `low`. It used the existing
checkout, without source, Git, or tracker changes.

The initial repository query reported 559 issues and 140 PRs; the subsequent
paginated listing contained 697 items. Those were separate live reads, not one
atomic count. The child agent set a **200-second shell-tool timeout**, and the
fetch did not finish within it. This was a trial-execution limit, not evidence
that GitHub returned an error or that the adapter could not complete.

The interrupted run retained 313 complete raw records in its lock directory.
At the user's request, the parent session copied those records to a separate
partial run, normalized and mechanically classified them, and rendered HTML.
The interrupted run was preserved. No new fetch or model session was launched
for this recovery.

| Recovered subset | Count |
| --- | ---: |
| Included items / listed items | 313 / 697 |
| Issues / PRs included | 210 / 103 |
| Close-as-stale proposals | 55 |
| Flag-for-review proposals | 11 |
| Needs-rebase proposals | 9 |
| Needs-triage | 238 |
| Item judgments still pending | 237 |
| Duplicate pairs still pending | 329 |

No item judgment or duplicate confirmation was completed on Loris. Its proposals
are mechanical and the subset is not representative. Chrome rendered all 313
records without page errors, and the generated report visibly warns that the
snapshot is incomplete and unreviewed.

Recovery added a `meta.partial` object and an explicit HTML warning **by hand**.
The current renderer does not interpret `meta.partial`; rerendering that run
would remove the warning. No supported partial-fetch resume/recovery command
was implemented. Follow-up work should address this rather than treating the
one-off recovery as a completed feature.

The Pi process exited with status 0 after reporting the blocker. That is not
sweep completion. Its original `result.md` predates the recovered report. See
[the handoff](handoff.md#first-external-trial-acesloris) for local session, log,
and report paths. The trial remains incomplete; a full external-backlog agent
review and its usage cost have not been validated.

## Final review

Separate standards and spec reviews read supplied source snapshots. Their
accepted findings were repaired and rechecked: incoming-edge duplicate-group
merges now cite actual pair evidence rather than retain an obsolete rationale;
unknown issue types are filterable; duplicate groups include the canonical's
proposal and reasoning. A reported conflict-filter concern was a false positive:
the predicate already restricted matches to PRs, and a browser check confirmed it.

## Deliberate corrections to the old implementation/spec wording

- Config is numeric data, not sourced shell. The precedence and file format
  remain, but executable expressions are rejected. Unknown keys are ignored.
- A verdict file is an atomically replaced checkpoint, not an append-only log.
  The old spec used both descriptions despite requiring in-place updates and
  exactly one verdict per item.
- `duplicate_candidates` holds nomination scores and nullable confirmation
  decisions on the newer row. `duplicate_of` remains null until confirmation.
  Rejected-pair state is retained to prevent repeated review on resume.
- `needs_agent` tracks item judgment; unfinished pair confirmations are counted
  separately. A report is complete only when both queues are empty.
- Unknown issue type remains null instead of fabricating a category. Agent
  inference lives in `inferred_type`; the fetched item remains unchanged.
- Fresh unknown/blocked PRs get a judgment request rather than an unsupported
  healthy flag. A needs-info PR uses the shorter idle window but still must be
  small and explicitly clean before receiving a close proposal.

## Boundaries

No tracker changes, issue closures, Git writes, Pages configuration, model
service, or hosted bot are part of RepoSweep's runtime. An agent still supplies
semantic judgments; offline fixture tests cannot prove their quality. GitHub
pagination can observe changes while a fetch is in progress. Local run artifacts
may contain private issue text and should not be published wholesale.
