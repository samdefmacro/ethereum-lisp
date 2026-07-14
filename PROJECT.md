# Project Contract

Last updated: 2026-07-14

## Goal

Build a usable Common Lisp Ethereum execution-layer client whose consensus
behavior can be checked against official fixtures and reference clients. The
project should progress from deterministic execution and local Engine/RPC
operation toward durable storage, staged synchronization, and real client
interoperability.

The project is not claiming production mainnet readiness. Correctness,
recoverability, and explicit capability boundaries take priority over API
breadth or superficial compatibility.

## Source Of Truth

The repository does not maintain a static roadmap or task backlog. Current
direction is derived from, in order:

1. executable behavior and deterministic tests;
2. the architecture and dependency rules in `docs/architecture.md`;
3. this project contract;
4. the verified snapshot and active objective in `docs/status.md`;
5. Git history for completed implementation detail.

Historical plans are not current requirements merely because they remain in
Git history.

## Phase State

- **Verifiable import:** closed for the pinned post-Merge Shanghai
  `engine_newPayloadV2` profile. The closure gate covers atomic execution and
  commitment validation, sender recovery, retained state, canonical reorgs,
  and pinned fixture replay.
- **Local Engine/RPC devnet:** closed for the repository-local process profile.
  The client can start split authenticated Engine and public HTTP listeners,
  execute the local payload lifecycle, operate its transaction pool, restore a
  development database, and survive bounded reorg/restart scenarios. This does
  not claim validation by the external Ethereum Hive test harness.
- **Durability and synchronization:** active. The immediate goal is to replace
  snapshot-only publication with record-scoped durable chain/state commits.
  Engine candidates, consensus-selected forkchoice transitions, and local
  dev-period seals now commit before publication; the next boundary is an
  explicit database/journal authority contract, followed by persisted sync
  progress and unwind behavior before real peer-to-peer synchronization.

## Priority Order

When choosing work, prefer the highest item that has a concrete unmet behavior
and a deterministic acceptance test:

1. consensus or state-transition correctness regressions;
2. executable end-to-end client behavior;
3. incremental persistence, crash consistency, and durable state/trie access;
4. staged import, persisted progress, and unwind/reorg behavior;
5. external Hive and reference-client interoperability;
6. devp2p, discovery, RLPx, and `eth`/`snap` synchronization;
7. operational hardening and performance;
8. additional RPC surface or convenience tooling.

Fixture widening, malformed-input matrices, and refactors are selected only
when they expose a real correctness risk, unblock a higher priority, or make an
active implementation slice safely testable.

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

For each implementation round, the agent:

1. inspects the clean Git state, recent changes, current architecture, and test
   baseline;
2. ranks at least two concrete candidate slices by project value, dependency,
   risk, and validation cost;
3. implements one coherent vertical behavior with explicit non-goals;
4. runs focused tests while iterating and the risk-appropriate gates from
   `docs/validation.md`; on macOS, every SBCL build or test process runs only
   inside the repository's Docker test environment;
5. obtains an independent diff review for production changes;
6. updates `docs/status.md` only when the verified capability, gap, objective,
   or test baseline changes;
7. commits the accepted phase as one intentional Git change and pushes the
   current work branch. A publish failure is reported as a blocker instead of
   silently leaving an accepted phase only in the worktree.

Completed micro-steps belong in Git history, not an append-only planning file.

## Decision Boundary

The agent may autonomously choose and implement slices that advance the active
project goal while preserving this contract. User direction is required before
changing the project target, supported baseline fork, consensus invariants,
public compatibility commitment, or adopting a major external runtime or
storage dependency.
