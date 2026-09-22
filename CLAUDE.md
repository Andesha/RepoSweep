# RepoSweep

A propose-only skill for reviewing issue and PR backlogs. Keep the runtime
portable: POSIX shell, jq, gh, and Git. The driving agent supplies judgments;
RepoSweep writes local artifacts, never tracker changes.

## Continuing development

Before changing the project, read `docs/handoff.md` for the accepted cleanup,
uncommitted working state, Loris trial artifacts, and unresolved follow-ups.
Use `docs/verification.md` to distinguish implemented behavior from what has
actually been verified. Work on the user's selected small task, not another rewrite.

## Domain vocabulary

Read `CONTEXT.md` for the glossary. Keep implementation and session state out
of it. See `docs/agents/domain.md` when domain decisions change.

## Issue tracker and labels

Specs and issues live in GitHub Issues (`Andesha/RepoSweep`), accessed through
`gh`. See `docs/agents/issue-tracker.md` before tracker operations. Open status
may lag local implementation; check the handoff before rebuilding an issue.

`docs/agents/triage-labels.md` maps the five canonical roles to tracker labels.
Runtime sweeps read that mapping from the target repository, not this one.

Git writes and tracker changes require explicit user approval. Reading an issue
or testing the skill does not authorize claiming, commenting on, or closing it.
