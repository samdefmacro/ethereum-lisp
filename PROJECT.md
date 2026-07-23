# Project Contract

Last updated: 2026-07-14

## Goal

Build a usable Common Lisp Ethereum execution-layer client whose consensus
behavior can be checked against official fixtures and reference clients. The
project combines deterministic execution, local Engine/RPC operation, durable
storage, synchronization, and real client interoperability.

The project is not claiming production mainnet readiness. Correctness,
recoverability, and explicit capability boundaries take priority over API
breadth or superficial compatibility.

## Working Direction

The user's current request defines the development priority. When no feature is
specified, choose one coherent missing capability by its value to a usable,
interoperable client, not by how easy it is to test or document.

The current code and Git history describe completed work. The repository does
not maintain an active-objective, phase-status, roadmap, or test-baseline file.
Tests are verification tools; adding tests, widening fixtures, refactoring, or
editing prose documentation is not a standalone development objective unless
the user requests it or it directly unblocks a product capability or
correctness fix.

Exception: work that improves the Common Lisp + AI development workflow of
this repository IS a legitimate standalone objective — the warm-image dev
loop (scripts/dev.sh), eval hardening and metrics, the delimiter guard,
agent-facing indexes (CLAUDE.md), and mechanically verified documentation
(MGL-PAX transcripts checked by scripts/docs-check.lisp, which double as
test vectors and as in-context teaching corpus for agents). Such docs are
verification artifacts, not prose: a transcript that drifts from the code is
a red build. Keep this work additive and out of consensus paths.

## Invariants

- Imported blocks publish state, receipts, indexes, and forkchoice effects
  atomically. A failed validation or durable write must not expose a partial
  chain view.
- Signed import, admission, execution, and mined-transaction lookup paths use
  real sender recovery under the configured chain.
- Receipt roots, cumulative gas, log order, bloom values, contract addresses,
  and post-execution header commitments are derived and validated rather than
  trusted from input.
- Reorgs preserve hash-addressed side-chain data while canonical number,
  transaction, receipt, state, safe, and finalized views follow the selected
  chain.
- Domain packages remain independent from transport and CLI layers. Package
  ownership and the acyclic dependency graph described in
  `docs/architecture.md` are enforced by tests.
- Claims of parity with geth, Nethermind, Reth, EEST, or Hive name the exact
  version or commit and the path actually exercised.
- Later-fork and KZG-backed Engine methods remain capability-gated when their
  required verifier or execution semantics are unavailable.

The Phase A fixture pin remains EEST release `v5.4.0`, tag target `88e9fb8`,
archive `fixtures_stable.tar.gz`, archive SHA-256
`92cf1b47ad12fb27163261fc3c1cea5df72439cab507983d06b56c94f8741909`.

## Development Method

Feature implementation is the default use of development time:

1. identify the requested observable behavior and the production boundaries it
   touches;
2. implement a coherent functional slice, including adjacent enabling work when
   needed;
3. run the smallest relevant verification after implementation, proportional to
   the risk of the change; reserve the full suite for an explicit user request,
   release/CI work, or a genuinely broad high-risk change;
4. update durable documentation only when user-facing usage, a public contract,
   or an architecture boundary actually changes.

Do not create or maintain status snapshots, phase records, test baselines,
recurring plans, or generic progress reports as a side effect of feature work.
Unrelated test failures, coverage expansion, refactors, review exercises, and
documentation polish are reported rather than turned into blockers or new
workstreams. If an SBCL check is run on macOS, use the repository's Docker test
environment.

## Decision Boundary

The agent may autonomously implement the requested feature and adjacent enabling
work while preserving this contract. Completing a task is a terminal condition:
do not invent another development round from repository documents. User
direction is required before changing the project target, supported baseline
fork, consensus invariants, public compatibility commitment, or adopting a
major external runtime or storage dependency.
