# Next Run

## Run Metadata

- Date: 2026-07-05
- Orchestrator model: current loop driver
- Implementer model: implementation agent
- Verifier model: independent verifier agent
- Target branch: `main`
- Stop state: `BLOCKED_EXTERNAL`

## Orientation Summary

- Git state: replacement-fixture breadth is already validated on `main`; the
  next actionable repository task is the remaining unchecked KZG item.
- Recent commits reviewed: prepared-payload txpool selection/import work, the
  in-process replacement-cache slice, and the standalone replacement smoke
  slice are already on `main`; focused escalated
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --json --all-fixtures`
  also passed on current `main`.
- Relevant task/roadmap anchors: `DEVNET-RUNNER-SMOKE-PREPARED-PAYLOAD-TXPOOL-REPLACEMENT-FIXTURE-BREADTH`
  is now closed; the only remaining unchecked backlog item is `Integrate real
  KZG proof verification`.
- Relevant loop state: the repository already has pluggable point/blob KZG
  verifier hooks, CLI command-backed opt-in wiring, timeout-bounded subprocess
  adapters, and runner-facing KZG capability smoke coverage. The missing piece
  is external: no pinned trusted-setup-backed backend, trusted setup artifact
  path/checksum, or canonical vector source is present in the repo.

## Candidate Ranking

### Candidate A

- Objective: integrate a real trusted-setup-backed KZG verifier through the
  existing point/blob proof hooks, with pinned backend, trusted setup source,
  and canonical vectors.
- Value: highest; it is the only remaining unchecked backlog item and the
  prerequisite for claiming real blob-era proof verification.
- Risk: high; it crosses cryptographic backend pinning, setup artifact
  management, and consensus-facing vector replay.
- Required validation: KZG vector coverage, `git diff --check`, and
  `sbcl --script tests/run-tests.lisp`; add runner/devnet smoke only if the
  CLI capability opt-in path changes.
- Decision: selected but blocked.
- Reason: it is the correct next frontier, but the required backend/setup
  inputs are not present locally.

### Candidate B

- Objective: widen process-boundary smoke coverage for V3/V4 prepared-payload
  variants.
- Value: medium; useful later-fork runner confidence once real KZG proof
  verification exists.
- Risk: medium-high because blob/KZG-gated capability boundaries can widen
  scope or force shape-only exceptions.
- Required validation: focused devnet smoke and likely the full suite if
  production code changes.
- Decision: defer.
- Reason: far-fork runner expansion is lower value than unblocking real KZG
  verification and should not jump ahead of the remaining P0 task.

### Candidate C

- Objective: add replacement-path pending-filter or txpool-journal event
  propagation assertions.
- Value: low-medium; it would harden a known residual risk on an already green
  Phase B surface.
- Risk: medium because it adds more listener-boundary accounting without
  changing the top remaining project blocker.
- Required validation: focused devnet smoke and `git diff --check`.
- Decision: defer.
- Reason: it is lower value than unblocking real KZG verification and should
  not replace the final unchecked backlog item.

## Selected Objective

Unblock `Integrate real KZG proof verification` by pinning a concrete trusted
KZG backend, trusted setup artifact source/checksum, and canonical vector
source, then wiring those inputs through the existing verifier hooks.

## Scope

Allowed files/modules:

- `src/core.lisp`
- `src/evm.lisp`
- `src/cli.lisp`
- `tests/core-tests.lisp`
- `tests/evm-tests.lisp`
- `tests/cli-tests.lisp`
- vendored backend / setup metadata files if they are added to the repo
- `docs/tasks.md`
- `docs/roadmap.md`
- `docs/loop/state.md`
- `docs/loop/next-run.md`

Expected behavior changes:

- Blob sidecar verification and the point-evaluation precompile use a real
  trusted-setup-backed verifier instead of the current unavailable/stubbed
  boundary.
- The repository records the pinned backend source, trusted setup artifact
  path/checksum, and canonical vector source used for verification claims.
- KZG vector tests prove both point-proof and blob-proof success/failure
  behavior through the existing consensus call sites.

Non-goals:

- Do not add more shape-only blob-era capability or runner smoke surface as a
  substitute for real verification.
- Do not rewrite the existing verifier-hook call sites if a backend can be
  mounted behind them directly.
- Do not claim Cancun blob payload validity without both the pinned backend
  and canonical vector replay.

## Acceptance Criteria

- A pinned trusted-setup-backed verifier backend is present in or explicitly
  pinned for the repository, together with a pinned trusted setup artifact
  path/checksum and a canonical KZG vector source.
- Blob sidecar verification and the point-evaluation precompile both use that
  verifier through the existing point/blob proof hooks.
- Focused KZG vector coverage proves true and false verification outcomes for
  both point proofs and blob proofs.
- Independent verifier reviews the final diff before commit.

## Validation Plan

Gate tier:

- Tier 2 narrow implementation, but always run the full suite because the
  touched path is consensus-facing cryptographic verification.

Focused gates:

- focused KZG vector tests for the backend-bound point-proof and blob-proof
  paths

Required pre-commit gates:

- `git diff --check`
- `sbcl --script tests/run-tests.lisp`
- independent verifier `PASS`

Full-suite policy:

- Mandatory once before commit because real KZG verification changes shared
  cryptographic and consensus-facing behavior.

Escalation requirements:

- If vendoring or downloading a backend/setup artifact is required, request the
  necessary approval rather than inventing local substitutes.
- If the CLI capability opt-in path changes and needs runner smoke, request
  local socket/network escalation before the smoke gate.

## Commit And Push Policy

- Commit allowed: only after the backend/setup/vector inputs are present and
  all deterministic gates plus verifier review pass.
- Push allowed: yes, after commit if remote authentication is available.
- Commit message: `Integrate trusted KZG proof verification`

## Blockers

- The repository currently has no pinned trusted-setup-backed verifier backend.
- The repository currently has no pinned trusted setup artifact path plus
  checksum.
- The repository currently has no canonical KZG vector source recorded for
  replay through the existing verifier hooks.
- If those three inputs are still unavailable at the start of the run, stop as
  `BLOCKED_EXTERNAL` instead of widening unrelated runner work.

## Implementer Notes

- Reuse the existing point/blob verifier hooks, command-adapter shape, and
  CLI opt-in surface instead of adding a second KZG integration path.
- Treat backend pinning, trusted setup pinning, and canonical vector replay as
  one coherent slice; do not claim success after only adding another shim.
- If the backend cannot be vendored or pinned under current approvals, keep the
  run blocked and document the missing input precisely.

## Verifier Result

- Status: pending
- Findings: pending
- Residual risk: pending
