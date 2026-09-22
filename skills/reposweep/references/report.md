# Report delivery

For a normally fetched run, after `review.sh next` returns `complete`, regenerate:

```sh
sh <skill-dir>/scripts/report.sh <run>
```

Check that the item count matches `meta.json`, no judgments or pairs remain
pending, duplicate links point to older same-kind canonicals, and representative
rationales cite evidence rather than guesses. Open the HTML if browser tooling
is available; check filters, links, and duplicate clusters. Report what you
actually verified. A preliminary report is acceptable only when named as such.

For a manually recovered partial snapshot, check the run's recovery notes and
any `meta.partial` field first. Partial metadata is not yet a stable supported
contract: the current renderer ignores it, and regeneration can erase a manually
added warning. A partial report must visibly state the included versus listed
counts, the fetch limitation, and whether agent review occurred. Its statistics
apply only to the subset. Preserve that warning if the user requests regeneration;
do not describe a completed subset review as a complete backlog sweep.

Return the report path and a short summary of the proposed actions. Mention
snapshot limitations or unavailable evidence. The output is self-contained,
with no network requests or external assets when opened.

To provide publishing instructions:

```sh
sh <skill-dir>/scripts/report.sh --publish <run> <target-repo-directory>
```

This only prints two commands. The maintainer reviews the report for private
information, chooses the publishing branch, and runs them. The report embeds
all normalized verdicts, including items currently hidden by filters. GitHub
Pages must already serve the target repository's `docs/` directory. RepoSweep
never stages, commits, pushes, configures Pages, or changes the tracker.
