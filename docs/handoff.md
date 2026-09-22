# Development handoff

Updated 2026-09-06 after the cleanup and the first Loris trial. The user accepted
the cleanup and wants to continue with smaller tasks from inside this repo.
This is a checkpoint, not a standing task to repeat the rewrite.

## Working state

- Branch: `cleanup/presentation-ready`, based on
  `f056b33e00b24b2d70c9ad01971d6a9d949efee2`.
- The cleanup was committed on `cleanup/presentation-ready` after this checkpoint.
  `main` does not contain the cleanup as of this note. Check current Git status
  and branches before relying on this note.
- No PRs, issue comments, or issue closures were made during this work.
  Further Git writes and tracker changes require explicit user approval.
- GitHub issues #1 and #14–#18 remain open. #12 and #13 were already closed
  before the cleanup. Open issue status does not mean its implementation is
  missing; use [the coverage record](verification.md#issue-coverage).

## What to preserve

RepoSweep is a portable skill, not a standalone LLM application or hosted bot.
Its shell command fetches and classifies; the driving agent supplies semantic
judgments through bounded, validated batches. Runtime dependencies remain
`gh`, `jq`, Git, and POSIX shell utilities. Writes go to local run artifacts,
never the tracker. Publishing commands are printed for the maintainer to run.

The accepted implementation corrections are recorded in
[verification.md](verification.md#deliberate-corrections-to-the-old-implementationspec-wording).
In particular, config is numeric data rather than executable shell; nominations
are separate from confirmed duplicate proposals; item and pair review have
separate completion checks; and unknown issue types remain unknown.

The code has focused classification and checkpoint tests. Avoid turning these
into a large mock-heavy suite or introducing an application framework for the
next small task. The report remains one offline HTML file.

## Entry points

- `skills/reposweep/SKILL.md`: the procedure an agent follows, including its
  issue, PR, duplicate, and report references. The folder works independently
  of the parent repo's development docs.
- `skills/reposweep/scripts/reposweep`: new-run entry point.
- `rules.jq` in that scripts directory: shared derivations and first-match rules.
- `review.sh` and `review.jq`: bounded context and atomic checkpoint updates.
- `report.sh` and `report.template.html`: rendering and print-only publishing.
- `docs/demo/index.html`: fictional sample; `docs/demo/preview.png` is its screenshot.
- [Verification](verification.md): completed checks, evidence, and limitations.

## First external trial: aces/Loris

Read [the trial record](verification.md#loris-trial-and-partial-recovery) before
resuming it or making claims about large-backlog validation. Fetching timed out;
the complete backlog has **not** received agent review. The user then asked for
and received a mechanical report from the available subset.

Local artifacts are outside this repository:

- Checkout: `/home/tk11br/Documents/Loris`.
- Saved Pi session and logs: `<checkout>/.reposweep/pi-trial/`.
- Session file: `2026-09-06T04-22-23-086Z_01a074f4-006d-7536-9cd4-62a1616ea636.jsonl`.
- Interrupted run: `<checkout>/.reposweep/runs/20260906T042243Z/`.
- Recovered partial run and report:
  `<checkout>/.reposweep/runs/20260906T042243Z-partial/report.html`.

The child session's `result.md` describes its stop at the timeout. It predates
the parent session's partial recovery and is not the final status of the trial.
`exit-status` is `0`, which means the Pi process exited normally, not that the
sweep finished. No automatic desktop notification was configured. Treat `pid`
as historical; do not signal it without checking the current process identity.
The existing untracked `Loris/reports/` directory is unrelated and was left alone.

**Preserve the partial report warning.** Its `meta.partial` block and prominent
HTML warning were added manually during recovery. The shared renderer currently
ignores that metadata; regenerating the report will remove the warning. Partial
recovery is not yet a supported command or stable artifact contract.

## Candidate next tasks, not pre-authorized work

1. Fetch operation: useful progress, long-running harness execution without an
   arbitrary short timeout, and explicit interrupted-fetch recovery behavior.
2. Partial snapshots: supported completeness metadata and warnings that survive
   report regeneration. Review completion must not imply fetch completeness.
3. Usage-aware trials: show item/pair workload before launching costly review,
   allow a user-selected stopping point, and provide a completion notification
   or status command. No usage budget or notification policy has been decided.

The user was concerned about subscription usage. Do not automatically restart
the full Loris sweep or launch another model session merely because it remains
unfinished. Let the next requested small task set the scope.

## Checks for the next change

```sh
sh skills/reposweep/tests/run-tests.sh
sh examples/generate-demo.sh
```

The demo generator uses fixed defaults and fictional decisions. Browser and
adapter checks recorded in `verification.md` were also performed, but their
one-off development scripts lived in `/tmp`; they are not installed runtime
dependencies or a checked-in browser test suite.
