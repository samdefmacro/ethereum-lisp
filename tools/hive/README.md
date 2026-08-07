# Hive client definition for ethereum-lisp

A [Hive](https://github.com/ethereum/hive) client directory, pinned to Hive
`dde4f59d04ff0ff8b6585670b08cea1b6c8ab65c`. `scripts/hive-run.sh` copies it into
a pinned Hive checkout as `clients/ethereum-lisp/` and runs a suite; Hive then
builds this `Dockerfile` with this directory as the build context, which is why
every file the image needs lives here rather than elsewhere in the repository.

| File | Role |
|---|---|
| `Dockerfile` | layers `jq`/`curl` and the scripts onto `ethereum-lisp-runtime` |
| `ethereum-lisp.sh` | entry point: `HIVE_*` variables to CLI flags |
| `mapper.jq` | `/genesis.json` to the chain config this client parses |
| `enode.sh` | `/hive-bin/enode.sh`, the enode retriever Hive calls |
| `hive.yaml` | roles: `eth1` only |

The client binary is not built here — it comes from `Dockerfile.runtime` at the
repository root, following the same prebuilt-base convention as Hive's own
go-ethereum definition.

Which suites this is wired into, which it is not, and the client gaps behind
each: `docs/hive-gate.md`. Read it before adding a suite.
