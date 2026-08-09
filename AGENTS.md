# ethereum-lisp agent entry point

`PROJECT.md` is the agent-neutral working contract and authority. Read it before
substantive work, then follow `docs/style.md`, `docs/architecture.md`, and
`docs/validation.md` for the affected area.

Use `cl-workbench` and the documented `scripts/dev.sh` container brokers for
every application build, eval, test, documentation run, generated-code step,
and deployable process. Never invoke an application interpreter/compiler on
the host, and never fall back when Docker or a declared Workbench capability
is unavailable.
Do not inspect, delete, import, or commit raw `.dev-runtime` data or
`.cl-workbench/state` event spools.
