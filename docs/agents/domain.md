# Domain docs

Read the repo-root `CONTEXT.md` before changing domain behavior. It is a glossary,
not an implementation spec or session log. Use its terms when naming fields,
writing instructions, or describing proposed actions.

Read relevant `docs/adr/` entries if that directory exists. An absent ADR
directory is not missing work. Surface conflicts with recorded decisions rather
than silently changing them.

Keep the document boundaries clear:

- `CONTEXT.md`: concise definitions of domain terms.
- `skills/reposweep/`: the portable agent procedure and its implementation.
- `docs/verification.md`: issue coverage, checks performed, and their limits.
- `docs/handoff.md`: the current development checkpoint and unresolved follow-ups.

If a concept changes, update its glossary definition and the affected behavior.
A run may contain a partial snapshot; review completion and fetch completeness
must remain distinct. Avoid inventing a new term for an existing concept.
