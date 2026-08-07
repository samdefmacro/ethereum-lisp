# Hive Gate

What exists, what is pinned, and what each un-gated Hive suite is waiting on.

This covers plan section 2's "add a runtime client image and pinned Hive
adapter; gate Engine/auth, EELS consume-engine/consume-rlp, `rpc-compat`,
devp2p, full-sync, and snap suites in CI"
(`docs/gap-analysis/public-testnet-readiness-plan.md`). That is seven suites.
Two of them are wired and non-blocking; the other five are not wired at all,
for reasons that are client gaps rather than harness gaps. Both facts are
recorded here rather than implied by the presence of a YAML file.

## Pins

| Thing | Pin |
|---|---|
| `ethereum/hive` | `dde4f59d04ff0ff8b6585670b08cea1b6c8ab65c` |
| Execution APIs | `e5d1bb60e6c064e4b15080da07b4370d0baadf92` |
| devp2p specs | `51dc101fddd52b5d90e59a2d695a92e4d600cfaf` |
| Runtime base image | `debian:bookworm-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241` |
| c-kzg-4844 (with bundled blst) | tag `v2.1.1` |
| RocksDB | vendored `tools/rocksdb/rocksdb-11.1.2.tar.gz`, SHA-256 checked in the build |
| Quicklisp dist | `2026-01-01` |

`scripts/hive-run.sh` re-checks the Hive commit after fetching and refuses to
run if the tree is anything else, so a result can always name the commit it came
from. Bumping the Hive pin means re-reading its `docs/clients.md` for contract
changes and re-diffing `tools/hive/mapper.jq` against
`clients/go-ethereum/mapper.jq` at the new commit.

## Pieces

- **`Dockerfile.runtime`** — multi-stage, digest-pinned, non-root (uid 10001)
  image whose entrypoint is the client. The Lisp system is loaded once at build
  time and written out with `SAVE-LISP-AND-DIE :executable t`, so the shipped
  layer has no SBCL, no compiler, no Quicklisp and no test tree: one executable,
  `librocksdb`, `libethckzg`, `libethbls`, `libsecp256k1`, and the KZG trusted
  setup.
- **`tools/hive/`** — the Hive client definition: `Dockerfile` (layers `jq` and
  `curl` onto the runtime image), `ethereum-lisp.sh` (the `HIVE_*` contract),
  `mapper.jq` (genesis translation), `enode.sh`, `hive.yaml`.
- **`scripts/hive-run.sh`** — materializes the pinned Hive checkout, installs
  `tools/hive` as `clients/ethereum-lisp`, writes the client file, runs a suite.
- **`scripts/hive-runtime-smoke.sh`** — starts the runtime image and asserts
  over the wire that it answers `eth_chainId`, refuses an unauthenticated
  `engine_*` call with 401, and answers a JWT-signed one. It also builds a
  `--hoodi` genesis, which is the only check that the packaged allocation files
  still resolve from inside a saved image.
- **`scripts/hive-adapter-smoke.sh`** — starts the adapter the way Hive starts
  it (uploaded `/genesis.json`, `HIVE_*` in the environment, no arguments) and
  checks that the genesis translation reaches the client, that Hive's fixed JWT
  secret authenticates, and that each refused variable exits naming itself. It
  found gap 2 below.
- **`.github/workflows/hive.yml`** — a blocking `runtime-image` job running both
  smoke tests, and a non-blocking matrix of `ethereum/engine` and
  `ethereum/rpc-compat`.

The runtime image runs under `--read-only` provided the datadir is writable by
uid 10001; a `tmpfs` needs `tmpfs-mode=1777` and a bind mount needs to be owned
by that uid.

### Running it

```sh
docker build --file Dockerfile.runtime --tag ethereum-lisp-runtime:local .
scripts/hive-runtime-smoke.sh ethereum-lisp-runtime:local
RUNTIME_PREBUILT=1 RUNTIME_TAG=local scripts/hive-run.sh --sim ethereum/engine
```

Hive itself does not run on macOS: it needs a Go toolchain on the host and it
dials each client container's bridge address for its liveness check, which is
not routable from a macOS host into the Docker Desktop VM. `scripts/hive-run.sh`
prepares everything and stops with that explanation; `--prepare-only` makes that
the intended outcome. Linux, and CI, run the suite for real.

## The `HIVE_*` contract, as this client implements it

Commit `05ef79d5` made the CLI reject unknown options and behaviour-selecting
no-ops. That is what makes the table below trustworthy: an adapter that passed
a flag this client does not implement would fail at startup instead of running a
configuration nobody chose. Where a Hive variable has no honest destination, the
entrypoint exits with a message naming it.

| Variable | Handling |
|---|---|
| `HIVE_CHAIN_ID` | genesis `config.chainId` |
| `HIVE_NETWORK_ID` | `--networkid` (default 1337, as geth's adapter does) |
| `HIVE_FORK_*` (block-numbered forks) | genesis `config.*Block` |
| `HIVE_SHANGHAI/CANCUN/PRAGUE/OSAKA_TIMESTAMP` | genesis `config.*Time` |
| `HIVE_BPO{1..5}_TIMESTAMP` | genesis `config.bpo*Time` |
| `HIVE_*_BLOB_{TARGET,MAX,BASE_FEE_UPDATE_FRACTION}` | genesis `config.blobSchedule` |
| `HIVE_TERMINAL_TOTAL_DIFFICULTY` | genesis `config.terminalTotalDifficulty` |
| `HIVE_MERGE_BLOCK_ID` | genesis `config.mergeNetsplitBlock` |
| `HIVE_DEPOSIT_CONTRACT_ADDRESS` | genesis `config.depositContractAddress` |
| `HIVE_BOOTNODE` | `--bootnodes` |
| `HIVE_TARGET_GAS_LIMIT` | `--miner.gaslimit` |
| `HIVE_ALLOW_UNPROTECTED_TX` | `--rpc.allow-unprotected-txs` |
| `HIVE_NODETYPE=full`/`archive`/unset | accepted, no flag: full validation with no pruning is the only mode, and the CLI rejects `--syncmode` outright |
| `HIVE_NODETYPE=snap` | **refused** |
| `HIVE_CLIQUE_PERIOD`, `HIVE_CLIQUE_PRIVATEKEY` | **refused** — no consensus-engine selection exists |
| `HIVE_MINER`, `HIVE_MINER_EXTRA` | **refused** — no local sealing |
| `HIVE_GRAPHQL_ENABLED` | **refused** — `--graphql` is accepted by the CLI and does nothing |
| `HIVE_AMSTERDAM_TIMESTAMP` | **refused** — `AMSTERDAM-EXECUTION-AVAILABLE-P` is false |
| `HIVE_LOGLEVEL` | **ignored, with a note in the log** — see below |

The JWT secret is Hive's `globals.DefaultJwtTokenSecretBytes`, the 32 ASCII
bytes `secretsecretsecretsecretsecretse`, written as hex because
`DEVNET-CLI-READ-JWT-SECRET` parses hex. The `engine-auth` suite tests wrong and
stale tokens against exactly this value.

## Gaps this work found and did not fix

Each of these is a client gap. None is worked around in the adapter, because a
harness that papers over a client gap makes the gate report a readiness the
client does not have.

1. **No block import.** There is no `import` command and no code path that
   ingests `/chain.rlp` or `/blocks/`; `ethereum-lisp init` loads a genesis and
   nothing else (`src/app/cli/init.lisp`). Hive's `eth1` role requires the
   entry point to load both after genesis (`docs/clients.md`). The entrypoint
   prints a warning naming the uploaded file it is ignoring.
   *Blocks: `ethereum/rpc-compat`, `ethereum/eels/consume-rlp`, `devp2p`,
   `ethereum/sync`.*

2. **`admin_nodeInfo` always fails with `-32603`.** Found by
   `scripts/hive-adapter-smoke.sh`, reproducible against any node with
   `--http.api admin,…`. Both RPC services are built with
   `:request-guard-function store-guard-function` (`src/app/cli/devnet/node.lisp`),
   so a request already holds the node store guard when its handler runs; the
   `:node-info` closure in `DEVNET-NODE-ADMIN-BACKEND`
   (`src/app/cli/devnet/peer-table.lisp`) then calls
   `CALL-WITH-DEVNET-NODE-STORE-GUARD` to read the head number, and that mutex
   is not recursive (`sb-thread:with-mutex` in
   `MAKE-DEVNET-STORE-GUARD-FUNCTION`), so the second acquisition signals and
   the dispatcher reports an internal error. `admin_peers` is unaffected — it
   takes the separate peer-table mutex. Hive's `eth1` role requires
   `/hive-bin/enode.sh`, which reads `admin_nodeInfo`, so it returns `null`.
   *Blocks: `devp2p`, `ethereum/sync`.*

3. **`--nat` is parsed and then dropped.** `DEVNET-CLI-OPTIONS` parses
   `--nat=extip:IP` into `:nat-policy` and validates it, but
   `DEVNET-CLI-MAKE-NODE` (`src/app/cli/cli.lisp`) does not pass it to
   `MAKE-DEVNET-NODE`, which is the only consumer:
   `DEVNET-NODE-ADVERTISED-HOST` uses it to choose the enode address and
   otherwise falls back to loopback. The startup summary of a container running
   under Hive shows the consequence directly —
   `:ENODE "enode://…@127.0.0.1:30303"` — so even with gap 2 fixed, no other
   container could dial us. `--netrestrict` is dropped by the same omission.
   *Blocks: `devp2p`, `ethereum/sync`.*

4. **No log-level control.** `--verbosity` is in
   `*DEVNET-CLI-VALUE-OPTIONS*`, so it is consumed, recorded as ignored, and
   has no effect; the only logging control is `--log-file`, which selects a
   destination for structured events, not a level. `HIVE_LOGLEVEL` therefore
   cannot be honoured, and `--sim.loglevel` will not change what the client
   prints.

5. **Snap is not advertised.** `tools/hive/hive.yaml` claims only the `eth1`
   role. Claiming `eth1_snap` would enter this client into suites that need a
   `snap/1` server the live Hello does not advertise (plan section 5).

6. **Amsterdam is refused rather than mapped.** `mapper.jq` deliberately does
   not emit `amsterdamTime`, and the entrypoint exits if
   `HIVE_AMSTERDAM_TIMESTAMP` is set. Plan section 8 owns re-opening it.

Two smaller notes, not gaps: the client's WebSocket port is not exposed to Hive
because `--ws.api` is accepted and discarded, so the port could not honour a
namespace list; and `engine_getClientVersionV1` reports commit `0x00000000`
because that is a compile-time constant in
`src/api/engine/capabilities.lisp`, so `/version.txt` reports what the client
reports rather than a build-time git description the client would contradict.

## Status of each suite named in plan section 2

| Suite | State |
|---|---|
| `ethereum/engine` (incl. `engine-auth`) | wired, `continue-on-error` |
| `ethereum/rpc-compat` | wired, `continue-on-error`; expected to fail on gap 1 |
| `ethereum/eels/consume-engine` | not wired |
| `ethereum/eels/consume-rlp` | not wired — gap 1 |
| `devp2p` | not wired — gaps 1, 2 and 3 |
| `ethereum/sync` (full-sync) | not wired — gaps 1, 2 and 3, plus plan section 4 |
| snap | not wired — plan section 5 |

Live geth/Nethermind/Lighthouse interop smoke gates, also part of plan section
2, are not started. The runtime image is the prerequisite they were waiting on
and now exists; the remaining work is a compose topology pairing this image with
a pinned consensus client, which is a separate change.

## What has actually been run

At the time of writing, on a macOS development host:

- `Dockerfile.runtime` builds, and `scripts/hive-runtime-smoke.sh` passes
  against the resulting image — the client starts non-root under a read-only
  root filesystem, builds a `--hoodi` genesis, serves `eth_chainId` and
  `web3_clientVersion`, rejects an unauthenticated
  `engine_exchangeCapabilities` with 401, and answers
  `engine_exchangeCapabilities`, `engine_getClientVersionV1` and `eth_syncing`
  under a JWT.
- `scripts/hive-adapter-smoke.sh` passes — the client image builds on top of
  the runtime image and starts the way Hive starts it, the genesis translation
  reaches the client, Hive's fixed JWT secret authenticates, and each refused
  variable exits naming itself. `enode.sh` returns `null`, reported as gap 2.
- `scripts/hive-run.sh --prepare-only` checks out Hive
  `dde4f59d04ff0ff8b6585670b08cea1b6c8ab65c`, verifies the commit, and installs
  `clients/ethereum-lisp`.

**No Hive suite has been run.** Hive cannot run on this host for the reason
above, so nothing in this document or in any commit message says which Hive
tests pass. The first run will be the CI job, and its counts belong in this
section when it produces them.
