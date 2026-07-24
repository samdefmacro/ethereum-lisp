# Project Contract

Last updated: 2026-07-24

## Goal

Build a usable Ethereum execution-layer client in Common Lisp. The client
executes blocks deterministically, serves the Engine and public JSON-RPC APIs,
stores chain and state durably, synchronizes with peers, and interoperates with
real consensus and execution clients.

Correctness comes first. Consensus behavior is checked against the official
Ethereum test fixtures (EEST) and cross-checked against mature reference
clients. The project does not claim production mainnet readiness — protocol
correctness, recoverability, and honest capability boundaries matter more than
API breadth or superficial compatibility.

## Reference clients

Common Lisp has no prior Ethereum client to copy, so when protocol behavior is
ambiguous, when consensus compatibility is at risk, or when a change makes an
explicit parity claim, read a mature client rather than guessing:

- **go-ethereum (geth)** — the primary reference.
- **Nethermind** and **Reth** — secondary references, useful for a second
  opinion and for their pool, sync, and storage architecture.

Source-comparison entry points are mapped in `docs/reference-map.md`. Ordinary
feature work does not need a multi-client report; reach for one when correctness
is genuinely in question.

Any claim of parity with geth, Nethermind, Reth, EEST, or Hive must name the
exact version or commit and the code path actually exercised. The pinned EEST
fixture set is release `v5.4.0` (tag target `88e9fb8`, archive
`fixtures_stable.tar.gz`, SHA-256
`92cf1b47ad12fb27163261fc3c1cea5df72439cab507983d06b56c94f8741909`).

## Correctness principles

These are the properties an execution client cannot get wrong. Preserve them:

- **Atomic import.** An imported block publishes state, receipts, indexes, and
  forkchoice effects together. A failed validation or durable write never
  exposes a partial chain view.
- **Real cryptography on real paths.** Signed import, admission, execution, and
  transaction-lookup paths recover senders for real under the configured chain,
  rather than trusting a sender field from input.
- **Derived, not trusted.** Receipt roots, cumulative gas, log order, bloom
  values, contract addresses, and post-execution header commitments are computed
  and validated, never taken from input.
- **Reorg safety.** Reorgs keep hash-addressed side-chain data while canonical
  number, transaction, receipt, state, safe, and finalized views follow the
  selected chain.
- **Layering.** Domain packages stay independent of transport and CLI. The
  package-ownership and acyclic-dependency rules in `docs/architecture.md` are
  enforced by tests.
- **Capability gating.** Later-fork and KZG-backed Engine methods stay gated
  when their verifier or execution semantics are unavailable, instead of
  silently returning wrong answers.

## Dependencies and cryptography

The tree is not required to be dependency-free; external Common Lisp libraries
(via Quicklisp/ASDF) are permitted.

Cryptographic primitives are chosen for maturity, robustness, and speed
together. Choose, in order: (1) a mature, well-reviewed Lisp implementation;
(2) failing that, a mature C library bound through CFFI. Among maintained
options prefer the faster one, and prefer a current release over a distro's
older package when the speed difference is material — crypto sits on the hottest
paths (Keccak runs per trie node). A hand-written implementation is a last
resort, justified only where it is small, fully covered by official vectors, and
no maintained alternative fits.

Any added dependency must keep the build reproducible and offline. The Docker
test image runs `--network none`, so Quicklisp systems are pre-fetched, native
libraries are installed at build time, and versions are pinned. The existing BLS
and KZG native helper binaries keep working and are not removed for their own
sake; new native crypto may use CFFI. Replacing a major runtime or storage
substrate — the storage engine, for example — is a direction-level decision, not
a routine dependency change.

## Common Lisp + AI development

This is an agent-driven codebase, and the workflow that makes it tractable is
itself a first-class objective — improving it is legitimate standalone work, not
a distraction from features:

- the warm-image development loop (`scripts/dev.sh`) and its eval hardening,
  metrics, and delimiter guard;
- agent-facing indexes (`CLAUDE.md`) that keep APIs discoverable;
- mechanically verified documentation — MGL-PAX sections whose `cl-transcript`
  examples are re-executed by `scripts/docs-check.lisp` (see
  `docs/rlp-manual.lisp`). These are verification artifacts that double as test
  vectors and teaching corpus for agents; a transcript that drifts from the code
  is a red build.

Keep this work additive and out of consensus paths. The day-to-day mechanics of
the dev loop live in `CLAUDE.md`; verification commands live in
`docs/validation.md`.

## How to work here

Implement the requested capability and the adjacent enabling work it needs, then
run the smallest verification that covers the change; reserve the full suite for
an explicit request, release/CI work, or a genuinely broad, high-risk change.
Update durable documentation when user-facing usage, a public contract, or an
architecture boundary actually changes.

Don't manufacture status snapshots, roadmaps, phase records, or test baselines
as a side effect of feature work, and don't turn an unrelated test failure or a
tempting refactor into a new workstream — report it and move on.
