# CLAUDE.md — ethereum-lisp

A Common Lisp Ethereum execution-layer client. **PROJECT.md is the working
contract and the authority** on goals, correctness principles, and how to work
in this repo — read it before substantive work. Style rules live in
docs/style.md; layering and package ownership in docs/architecture.md;
validation policy in docs/validation.md.

## Operating constraints

**Commit identity.** Author AND committer must be `samdefmacro
<samnewstart2026@outlook.com>`; prior identities must appear nowhere in this
repo. History was rewritten on 2026-07-26 to remove them. The repo-local git
config is correct, but this machine's GLOBAL config still carries an old
identity, so a fresh clone or a new worktree can pick up the wrong one.
`git log -1 --format='%an <%ae>'` after committing is the cheap guard.

**No tool attribution in commits.** Do not add `Co-Authored-By` or
generated-with trailers naming Claude, Cursor, or any other agent, and do not
name a tool in the subject or body. Some earlier commits carry such trailers;
new ones must not.

**Push and merge are pre-authorized.** Push branches and merge to `main`
without asking, once the change is verified at the layer it actually touches —
a CLI/option change means running e2e too, not just unit and integration.
Prefer fast-forward when the branch is a linear descendant. This does not
extend to deleting remote branches, force-pushing, or rewriting published
history; ask for those.

**Completed development branches must land on `main`.** After verified work on
a temporary or development branch is finished, merge it into local `main`
(fast-forward when possible), push `main` to `origin`, and delete the local
development branch. Do not leave completed work published only on a
development branch. Keep the remote development branch unless its deletion is
explicitly requested.

**Docker-isolated builds and tests are pre-authorized.** Run ordinary in-scope
`cl-workbench` and `scripts/dev.sh` container-broker commands without asking
for a separate go-ahead. Other agents run their own builds and containers on
this machine, so keep this checkout's containers and caches isolated and obey
the never-kill / never-clear rules below. This authorization does not extend to
destructive shared-Docker cleanup or to running an interpreter on the host.

**No application toolchains on the host, ever.** Not SBCL, Python, Go, Node, or
scratch scripting — builds, tests, evals, deployable processes, and generated
code run in a reviewed container. Plain control-plane tools such as `git`, `rg`,
`curl`, and Docker are fine. `make test-*` and inner test scripts fail closed
outside the project image. This rule outranks any checked-in doc that appears to
sanction a host path; when one conflicts, fix the doc.

## The development loop (warm image, not cold sbcl runs)

**Application code never runs on the macOS host** (PROJECT.md; the machine is
shared with other agents). Common Lisp Workbench is the public development
entry point. Its project adapter delegates to `scripts/dev.sh`, whose warm
image keeps Swank on container loopback; no port is published to the host.

At the start of each substantive session that will execute application tooling,
run `cl-workbench doctor --strict` from the repository root before the first
such operation. Stop and report if it fails; never use a host or portable
fallback. Read-only and file-only tasks are exempt. The exact preflight and
rerun conditions live in `docs/validation.md`.

```
cl-workbench doctor --strict             # contract + Docker/container boundary
cl-workbench repl start                  # project + tests loaded, Swank inside
cl-workbench repl eval '(+ 1 2)'         # canonical client streamed into container
cl-workbench test trie-fixture-vectors   # one warm-image test by name
cl-workbench test                        # full suite in the warm image
cl-workbench docs verify                 # verify PAX doc transcripts
cl-workbench repl status / stop          # owned checkout lifecycle
scripts/dev.sh logs / shell              # low-level container inspection only
scripts/dev.sh cold-test unit|integration|e2e|all
scripts/dev.sh cold-docs                  # cold final verification
```

The dev image tag derives from pinned Docker build inputs and is deliberately
separate from `DOCKER_TEST_IMAGE`; identical inputs may share an immutable
image. The container and session IDs derive from the physical checkout, so two
worktrees run side by side without manual names. Ownership labels prevent a
checkout from reusing or deleting another checkout's container. The rootfs and
workspace are read-only, capabilities are dropped, `no-new-privileges` is set,
the Docker socket is absent, and tmpfs supplies the only writable runtime paths.

Workflow discipline (in order):
1. **Ground before writing**: check that symbols/APIs actually exist —
   `cl-workbench repl eval '(describe (quote some:symbol))'`, `(apropos "enr")`. Do not
   guess APIs.
2. **Develop in small evals** against the warm image.
3. **Edit files, then re-load and verify**:
   `cl-workbench repl eval '(load "src/...")'`
   or reload the affected system, then re-run the relevant test by name.
   Reload is YOUR job — the image does not watch files.
4. `defstruct`/`defconstant` layout changes cannot be hot-patched: restart
   (`cl-workbench repl stop && cl-workbench repl start`).
5. Finish with `scripts/dev.sh cold-test LAYER` — the warm image is a
   development convenience, not the verification of record.

Eval contract (`repl.eval.container.v1`): exit 0 ok / 1 Lisp error (with
backtrace frames) / 2 local preflight or connection error / 3 timed out and
interrupted (image survived) / 4 hard hang. The sole eval client belongs to
Common Lisp Workbench and is streamed into the owned container; the project
does not carry a copy. Workbench records payload-free operation outcomes under
`.cl-workbench/state/`. Historical raw `.dev-runtime` metrics remain private:
do not read, delete, import, or commit them.

The PostToolUse hook calls `cl-workbench hook claude-code parens`; its lexical
checker runs in the Workbench tool container and feeds delimiter errors straight
back. Fix them in the same turn.

## Verification traps

- **Never edit `src/` while a suite is running in the warm image.** Some tests
  parse the source tree from disk and compare it against the packages the image
  loaded at startup (`PROJECT-PACKAGE-DEPENDENCY-GRAPH-IS-ACYCLIC` and
  `...-INCLUDES-SOURCE-REFERENCES`), so an edited-but-not-reloaded tree fails
  them spuriously. Finish edits, reload, then run. When a warm-image failure
  looks surprising, re-check it cold before investigating it as real.
- **Never pipe a verification run through `tail` or `grep`.** It destroys the
  record of which tests failed, and it masks the exit code — the pipeline
  reports `tail`'s status, so a run that exited 2 looks like a 0. Redirect,
  then grep the file: `scripts/dev.sh cold-test all > log 2>&1; echo "EXIT=$?";
  grep -E "^not ok|tests passed" log`
- **Every `sb-thread:make-thread` body must wrap its work in a `handler-case`.**
  The node and the whole suite run as `sbcl --script`, which implies
  `--disable-debugger`, so an unhandled condition in ANY thread exits the whole
  process with code 1. It does not fail a test — it kills the run with no
  result. A regression test for this goes red by killing the run rather than by
  reporting a failure, so say that in the test comment.
- **A compile-time STYLE-WARNING is a test failure, not cosmetic noise.**
  Several tests launch a fresh `sbcl --script` and assert on its stdout — one
  expects it EMPTY, another parses it as JSON — and warnings emitted while the
  script loads land in that stdout. Never mix `&optional` and `&key` in one
  lambda list; use `loop repeat n` rather than a `dotimes` variable declared
  ignored. Only warnings under a `/workspace/src/...` filename are ours.

## Documentation is verified (PAX transcripts)

docs/*.lisp hold MGL-PAX sections whose ```cl-transcript examples are
re-executed and compared by `dev.sh docs-check` — a drifted example is a red
build. When you change behavior a transcript shows, update the transcript in
the same change; when adding a manual, add its section to *CHECKED-SECTIONS*
in scripts/docs-check.lisp. Authoring rules are in the header of
docs/rlp-manual.lisp (package-qualify transcript symbols; prefer `=>`/`..`
over `==>`; COPY-TREE around macroexpansions). The deliberately broken
@DOCS-CHECK-SELFTEST section must stay broken — it proves checking is on.
Per PROJECT.md, this workflow-infrastructure work is a legitimate standalone
objective; keep it additive and out of consensus paths.

## Conventions that bite

- Custom test harness (tests/test-framework.lisp): `deftest` with layer
  metadata, `is`/`signals`; runners are `tests/run-tests.lisp --layer ...`.
  In the warm image use `(cl-user::run-ethereum-lisp-test "name")`.
- Consensus behavior is validated against pinned EEST fixtures and reference
  clients — see PROJECT.md invariants; parity claims must name exact
  versions/commits.
- BLS (blst) and KZG (c-kzg-4844) are CFFI bindings, not subprocesses: the
  Dockerfile builds `tools/bls-ffi/shim.c` and `tools/ckzg-ffi/shim.c` into
  `libethbls.so` / `libethckzg.so` and the image dlopens them at runtime. Both
  are the CLI default, and each degrades gracefully when its library is absent.
  `.dockerignore` must un-ignore every new `shim.c`.
- Shared-machine rules (multiple agents): never kill sbcl processes you did
  not start; never clear the shared host FASL cache.
