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

**Get a go-ahead before running Docker, SBCL, or make.** Other agents run their
own builds and containers on this machine, and concurrent runs race on compiler
caches, images, CPU and loopback ports. This is on top of the never-kill /
never-clear rules below: ask before `make docker-test-*` or any container run,
not only before touching a process someone else started.

**No interpreters on the host, ever.** Not sbcl, not python3, not scratch
scripting — anything that executes code runs in a container. Plain `git`, `rg`
and `curl` on the host are fine. This rule outranks any checked-in doc that
appears to sanction a host path; when one conflicts, fix the doc.

## The development loop (warm image, not cold sbcl runs)

**SBCL never runs on the macOS host** (PROJECT.md; the machine is shared with
other agents). `scripts/dev.sh` runs the warm image inside a container and
`docker exec`s each eval, so the Swank port is never published to the host.

```
scripts/dev.sh start                     # container w/ project + tests loaded, Swank inside (once)
scripts/dev.sh eval '(+ 1 2)'            # ~0.2s per eval against the warm image
scripts/dev.sh test trie-fixture-vectors # one test by name
scripts/dev.sh test-all                  # full suite in the warm image
scripts/dev.sh docs-check                # verify PAX doc transcripts
scripts/dev.sh logs / shell / status     # container output, a shell inside, state
make docker-test-unit / docker-test-integration / docker-test-e2e
                                         # cold layered runs — final verification
```

The dev image is tagged `ethereum-lisp-dev:go1.24-bookworm`, deliberately
separate from `DOCKER_TEST_IMAGE`, so rebuilding it never disturbs another
agent's `make docker-test-*`. Set `ETHEREUM_LISP_DEV_CONTAINER` to run two
warm images side by side. The workspace is mounted read-only with the same
tmpfs shape as the cold gates — edits land on the host and are visible
immediately; nothing in the container can write to your working tree.

Workflow discipline (in order):
1. **Ground before writing**: check that symbols/APIs actually exist —
   `dev.sh eval '(describe (quote some:symbol))'`, `(apropos "enr")`. Do not
   guess APIs.
2. **Develop in small evals** against the warm image.
3. **Edit files, then re-load and verify**: `dev.sh eval '(load "src/...")'`
   or reload the affected system, then re-run the relevant test by name.
   Reload is YOUR job — the image does not watch files.
4. `defstruct`/`defconstant` layout changes cannot be hot-patched: restart
   (`dev.sh stop && dev.sh start`).
5. Finish with the cold `make docker-test-*` layer runs — the warm image is a
   development convenience, not the verification of record.

Eval contract (scripts/dev-swank-eval.lisp): exit 0 ok / 1 lisp error (with
backtrace frames) / 2 connection error (image down — NOT your code; run
dev.sh start) / 3 timed out and interrupted (default 20s, image survived;
raise DEV_EVAL_TIMEOUT for long forms) / 4 hard hang (restart the image).
Output is capped at 10k chars with an explicit TRUNCATED marker. Every eval
is logged to .dev-runtime/swank-dev/eval-metrics.log — do not delete it; it
is the agent-productivity metric stream.

A PostToolUse hook (scripts/paren-hook.sh) checks delimiter balance on every
.lisp/.asd edit and feeds errors straight back — fix them in the same turn.

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
  then grep the file: `make docker-test-all > log 2>&1; echo "EXIT=$?";
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
