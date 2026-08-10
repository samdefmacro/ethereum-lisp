# ethereum-lisp agent entry point

`PROJECT.md` is the agent-neutral working contract and authority. Read it before
substantive work, then follow `docs/style.md`, `docs/architecture.md`, and
`docs/validation.md` for the affected area.

Before the first application build, eval, test, documentation verification,
generated-code step, dependency operation, or deployable process in each
substantive session, run `cl-workbench doctor --strict` from the repository
root. If it fails, stop and report the failure; never downgrade to a host or
portable fallback. A task limited to reading or editing files does not require
this preflight.

Use `cl-workbench` and the documented `scripts/dev.sh` container brokers for
every application build, eval, test, documentation run, generated-code step,
and deployable process. Never invoke an application interpreter/compiler on
the host, and never fall back when Docker or a declared Workbench capability
is unavailable.
Do not inspect, delete, import, or commit raw `.dev-runtime` data or
`.cl-workbench/state` event spools.
