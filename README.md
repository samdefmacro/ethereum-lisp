# ethereum-lisp

A Common Lisp implementation of the Ethereum execution layer.

This repository is intentionally being built in small, testable layers while
cross-checking behavior against:

- `references/go-ethereum` (`geth`)
- `references/nethermind` (`Nethermind`)

The reference repositories are local clones for reading and comparison only;
they are ignored by git.

## Current scope

The first milestone is the execution-layer substrate:

- byte and hex utilities
- Ethereum scalar/domain types
- RLP encoding and decoding
- Keccak-256
- Merkle Patricia Trie
- block, transaction, receipt, and account encodings
- state transition and EVM execution

The project currently ships a self-contained test runner so the initial layers
can run without Quicklisp.

Implemented so far:

- RLP, Keccak-256, and basic Ethereum domain types
- Merkle Patricia Trie encoding and root calculation
- account, transaction, receipt, bloom, and header encodings
- in-memory secure state root prototype
- early EVM interpreter skeleton with storage, logs, calldata, and basic gas
- minimal legacy transfer and recipient-code transaction execution paths
- top-level revert/error rollback for recipient-code execution

## Run tests

```sh
sbcl --script tests/run-tests.lisp
```

## Reference layout

See `docs/reference-map.md` for the source modules used as the main comparison
points, and `docs/roadmap.md` for the long-running implementation plan.
