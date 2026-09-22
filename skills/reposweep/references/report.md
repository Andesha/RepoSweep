# Report delivery

For a complete snapshot, wait until `review.sh next` returns `complete`, then
regenerate the report:

```sh
sh <skill-dir>/scripts/report.sh <run>
```

Check that the item count matches `meta.json`, no judgments or pairs remain
pending, duplicate links point to older same-kind canonicals, and representative
rationales cite evidence. Open the HTML when browser tooling is available and
check filters, links, warnings, and duplicate groups. Report only what you
verified.

Snapshot completeness and review completeness are separate. Read
`meta.json.snapshot` before delivery. A complete snapshot has `complete: true`
and matching `included` and `listed` counts. An incomplete snapshot has
`complete: false`, both counts when known, and a reason.

For an explicitly recovered subset, normalize and classify the recovered items,
then mark the run before rendering:

```sh
sh <skill-dir>/scripts/mark-partial.sh <run> <listed-count> '<reason>'
sh <skill-dir>/scripts/report.sh <run>
```

The renderer reads this metadata and preserves a prominent incomplete-snapshot
warning across regeneration. The warning states the included and listed counts,
the reason, and that finishing review does not complete the backlog. Statistics
in a partial report describe only the included subset.

Return the report path and a short summary of proposed actions. Name any partial
snapshot, pending review, or unavailable evidence. The output is self-contained
and makes no network requests when opened.

To provide publishing instructions:

```sh
sh <skill-dir>/scripts/report.sh --publish <run> <target-repo-directory>
```

This command only prints commands. The maintainer reviews the report for private
information, chooses the publishing branch, and runs them. The report embeds all
normalized verdicts, including items hidden by filters. GitHub Pages must already
serve the target repository's `docs/` directory. RepoSweep never stages, commits,
pushes, configures Pages, or changes the tracker.
