# CLAUDE.md — ethereum-lisp

A Common Lisp Ethereum execution-layer client. **PROJECT.md is the working
contract and the authority** on goals, invariants, development method, and
decision boundaries — read it before substantive work. Style rules live in
docs/style.md; layering and package ownership in docs/architecture.md;
validation policy in docs/validation.md.

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
- Go helper binaries under tools/ (BLS, KZG) are built by scripts/*-backend
  scripts; missing binaries capability-gate the corresponding Engine paths.
- Shared-machine rules (multiple agents): never kill sbcl processes you did
  not start; never clear the shared host FASL cache.
