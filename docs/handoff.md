# Development handoff

Updated 2026-09-22 after the large-backlog hardening work in issues #20–#24.
The implementation is on `main`. Check Git status and recent commits before
relying on this checkpoint.

## Current state

RepoSweep remains a propose-only portable skill. Its runtime dependencies are
POSIX shell, jq, gh, and Git. It writes local run artifacts and never changes the
tracker. The driving agent supplies semantic judgments through validated batches.

The following large-run improvements are implemented:

- Every completed snapshot records stable completeness metadata in `meta.json`.
- The report keeps incomplete-snapshot warnings across regeneration.
- Fetch listings and per-item responses survive interruption under `fetch/`.
- `reposweep resume RUN_DIR` skips valid completed records.
- `reposweep status RUN_DIR` reports fetch, classification, and review progress.
- Review workload is shown as item, pair, and batch counts before judgment.
- Duplicate nominations omit common title tokens and expose overlap evidence.
- Stale results are described as closure candidates that require inspection.

The focused test suite covers classification, checkpoint integrity, partial
report regeneration, workload calculation, and interrupted fetch recovery with
a fake GitHub adapter. Keep the suite focused. Do not add an application
framework or a mock-heavy test system.

## Entry points

- `skills/reposweep/SKILL.md`: complete agent procedure.
- `skills/reposweep/scripts/reposweep`: start, resume, and status commands.
- `fetch-normalize.sh`: durable GitHub fetch and normalization.
- `mark-partial.sh`: mark an explicitly recovered subset as incomplete.
- `review.sh`: workload, bounded review batches, and checkpoint application.
- `report.sh`: offline report rendering and print-only publishing instructions.
- `docs/verification.md`: recorded checks, trials, and remaining limits.

## Loris evidence

The Loris checkout now lives at `/home/tk11br/Documents/neuro/Loris`.

The first run at `.reposweep/runs/20260906T042243Z/` was interrupted by a
caller-imposed 200-second timeout. A manual recovery produced the 313-item
`20260906T042243Z-partial` run from 697 listed items. That run predates durable
fetch state and cannot use the new resume command.

A later run at `.reposweep/runs/20260907T000242Z/` fetched all 697 listed items.
Its agent session completed all 237 item judgments before hitting the provider
usage limit during duplicate review. Of 855 nominated pairs, 7 were confirmed,
323 rejected, and 525 remain pending. Exit status was 1. Do not call this review
complete and do not restart it without the user's approval.

A local replay of the new duplicate nomination code used copies of the saved
normalized items and metadata. It made no tracker or Loris run changes:

| Saved snapshot | Old pairs | New pairs | Change | Runtime | Peak memory |
| --- | ---: | ---: | ---: | ---: | ---: |
| 313-item partial subset | 329 | 292 | -37 | 0.40s | 5.4 MiB |
| 697-item complete snapshot | 855 | 833 | -22 | 1.91s | 8.1 MiB |

On the complete snapshot, the new nomination set retained all 7 confirmed pairs
and all 323 rejected pairs. It removed 28 old pairs and added 6 because removing
common-token edges freed endpoint capacity. The reduction is real but modest.
Treat #23 as a noise reduction, not a scalability fix. Pair generation remains
quadratic and the complete saved run would still have a large review queue.

The user selected this saved-subset replay instead of a fresh live recovery
trial. Durable resume therefore has automated fake-adapter coverage, but no
medium-sized live interruption and resume trial yet.

## Remaining limits

- GitHub pagination is a live read rather than an atomic snapshot.
- Each PR still needs a detail request and may need one merge-state retry.
- Duplicate nomination remains quadratic.
- Old runs without `fetch/` cannot use fetch resume.
- The driving model determines semantic judgment quality and usage cost.
- Run artifacts can contain private issue text and should not be published
  without review.

## Checks

```sh
sh skills/reposweep/tests/run-tests.sh
sh examples/generate-demo.sh
```

ShellCheck is useful when installed. Browser checks remain manual development
checks rather than an installed runtime dependency.
