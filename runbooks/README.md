# runbooks/ — reviewed change packages for the production box

**The rule:** the box never receives anything that doesn't exist in this repo
first. Every production change ships as a *package* here: the exact artifacts
that will land on the machine (full files, never inline edits), plus a runbook
README with preconditions, verbatim steps, verification, and rollback.

Lifecycle of a package:

1. **Proposed** — artifacts + runbook authored here; `mirror/` still reflects
   the box as-is, so the reviewable diff is `diff mirror/... runbooks/<pkg>/...`.
2. **Reviewed** — a human reads the diff and the runbook and approves.
3. **Applied** — an authorized executor (human, or Claude with an explicitly
   user-granted scoped permission) runs the runbook *verbatim*. Artifacts are
   copied to the box byte-for-byte.
4. **Synced** — `mirror/` is updated from the applied artifacts, tickets are
   closed, and the package README is stamped `APPLIED <date>`.

Anonymization: packages follow the tree's resting state (`{{PLACEHOLDER}}`
tokens). Run `scripts/sanitize.sh --restore` before applying, re-run forward
after. Imperative hotfix steps (e.g. `docker update`) are allowed only when the
runbook records them explicitly as **debt** against the declarative end-state.

| Package | Covers | Status |
|---|---|---|
| `wave2-box-fixes/` | restart policies · image prune · Caddy hygiene · backup hardening | **Parked** (2026-07-18) — superseded by the new-box strategy: the successor box is *born* with these fixes via `docker/compose.prod.yaml`. Apply this package only if the legacy box must be fixed before cutover. |
