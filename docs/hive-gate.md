# Hive Gate

What exists, what is pinned, and what each un-gated Hive suite is waiting on.

This covers plan section 2's "add a runtime client image and pinned Hive
adapter; gate Engine/auth, EELS consume-engine/consume-rlp, `rpc-compat`,
devp2p, full-sync, and snap suites in CI"
(`docs/gap-analysis/public-testnet-readiness-plan.md`). That is seven suites.
Three of them are wired and non-blocking; the other four are not wired at all,
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
| RocksDB | vendored `tools/rocksdb/rocksdb-11.1.2.tar.gz`, SHA-256 checked; narrow Linux 5.15 io_uring compatibility patch; io_uring linkage required by the build |
| Quicklisp dist | `2026-01-01` |

The remote Hoodi performance gate additionally pins Docker 26.1.4's default
seccomp profile and adds only `io_uring_setup`, `io_uring_enter`, and
`io_uring_register`; see `tools/runtime/README.md`. This live-gate policy is
host-side deployment metadata and is not embedded in the portable Hive image.

`scripts/hive-run.sh` re-checks the Hive commit after fetching and refuses to
run if the tree is anything else, so a result can always name the commit it came
from. For rpc-compat it also overrides the simulator Dockerfile's moving
`execution-apis/main` default with the reviewed
`e5d1bb60e6c064e4b15080da07b4370d0baadf92` commit. It requires a fresh result
directory, rejects missing or zero-test result manifests, and checks the pinned
full-suite inventories (403 Engine tests and 243 rpc-compat tests). Bumping the
Hive pin means re-reading its
`docs/clients.md` for contract changes, re-diffing `tools/hive/mapper.jq`
against `clients/go-ethereum/mapper.jq`, and deliberately updating those
inventory counts.

## Pieces

- **`Dockerfile.runtime`** — multi-stage, digest-pinned, non-root (uid 10001)
  image whose entrypoint is the client. The Lisp system is loaded once at build
  time and written out with `SAVE-LISP-AND-DIE :executable t`, so the shipped
  layer has no SBCL, no compiler, no Quicklisp and no test tree: the client
  executable, a tiny deployment-only io_uring availability probe,
  `librocksdb`, its `liburing` runtime, `libethckzg`, `libethbls`,
  `libsecp256k1`, and the KZG trusted
  setup. The saved executable reserves an explicit 6 GiB SBCL dynamic space:
  SBCL commits it on demand, while the operator's container limit remains the
  physical RSS authority. This is part of the runtime contract rather than a
  builder-default accident; a public three-source snap import exceeded the
  former default heap while the container itself was still below its limit.
- **`tools/hive/`** — the Hive client definition: `Dockerfile` (layers `jq` and
  `curl` onto the runtime image), `ethereum-lisp.sh` (the `HIVE_*` contract),
  `mapper.jq` (genesis translation), `enode.sh`, `hive.yaml`.
- **`scripts/hive-run.sh`** — materializes the pinned Hive checkout, installs
  `tools/hive` as `clients/ethereum-lisp`, writes the client file, runs a suite,
  and validates a nonzero fresh result/count manifest even when Hive reports
  test failures. `HIVE_EXPECTED_TESTS` pins a diagnostic subset explicitly;
  full Engine and rpc-compat runs select their known inventories automatically.
- **`scripts/hive-runtime-smoke.sh`** — starts the runtime image and asserts
  over the wire that it answers `eth_chainId`, refuses an unauthenticated
  `engine_*` call with 401, and answers a JWT-signed one. It also builds a
  `--hoodi` genesis, which is the only check that the packaged allocation files
  still resolve from inside a saved image.
- **`scripts/hive-adapter-smoke.sh`** — starts the adapter the way Hive starts
  it (uploaded `/genesis.json`, `HIVE_*` in the environment, no arguments) and
  checks that the genesis translation reaches the client, that Hive's fixed JWT
  secret authenticates, that each refused variable exits naming itself, and
  that `enode.sh` returns the same routable bridge address as `admin_nodeInfo`.
- **`.github/workflows/hive.yml`** — a blocking `runtime-image` job running both
  smoke tests, and a non-blocking matrix of `ethereum/engine`,
  `ethereum/rpc-compat`, and `devp2p`.

The runtime image runs under `--read-only` provided the datadir is writable by
uid 10001; a `tmpfs` needs `tmpfs-mode=1777` and a bind mount needs to be owned
by that uid.

### Running it

```sh
scripts/dev.sh runtime-build ethereum-lisp-runtime:local
cl-workbench validation run runtime-smoke ethereum-lisp-runtime:local
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

`/chain.rlp` and `/blocks/` are now passed to the CLI as explicit offline
imports. The former is decoded as Hive's concatenated RLP block stream and the
latter as direct `.rlp` files in Hive's numeric filename order. Each block must extend
the current canonical head and crosses the ordinary execution, publication, and
durability boundary before the next one begins. A validation failure retains
the durable valid prefix and starts the node from it; malformed paths and
storage failures fail startup. The pinned Hive fixtures intentionally use fake
historical PoW seals: the pinned geth client constructs `ethash.NewFaker`, and
Erigon passes `--fakepow`. The adapter therefore adds
`--import-chain-skip-pow` only when one of those offline fixture paths exists.
The CLI rejects that switch without an explicit offline import, dynamically
scopes it to that import call, and reports `pow-seals=skipped`; normal startup,
P2P, Engine, and default offline imports keep real Ethash verification. This is
an implemented adapter contract, not yet evidence that any Hive suite passes.

## Gaps this work found and did not fix

Each of these is a client gap. None is worked around in the adapter, because a
harness that papers over a client gap makes the gate report a readiness the
client does not have.

1. **No log-level control.** `--verbosity` is in
   `*DEVNET-CLI-VALUE-OPTIONS*`, so it is consumed, recorded as ignored, and
   has no effect; the only logging control is `--log-file`, which selects a
   destination for structured events, not a level. `HIVE_LOGLEVEL` therefore
   cannot be honoured, and `--sim.loglevel` will not change what the client
   prints.

2. **Hive snap mode is not selectable.** The live client now negotiates
   `snap/1`, but Hive's `HIVE_NODETYPE=snap` still maps to no explicit client
   strategy because `--syncmode` is deliberately rejected. Claiming
   `eth1_snap` before that selector is implemented would enter snap suites
   under a configuration the client did not honour.

3. **Amsterdam is refused rather than mapped.** `mapper.jq` deliberately does
   not emit `amsterdamTime`, and the entrypoint exits if
   `HIVE_AMSTERDAM_TIMESTAMP` is set. Plan section 8 owns re-opening it.

One smaller note, not a gap: the client's WebSocket port is not exposed to Hive
because `--ws.api` is accepted and discarded, so the port could not honour a
namespace list. The runtime build embeds the full Git object id while saving
the executable; `engine_getClientVersionV1`, `web3_clientVersion`, the CLI
version output, the OCI revision label, and Hive's `/version.txt` therefore
agree on the same eight-hex-digit client commit.

## Status of each suite named in plan section 2

| Suite | State |
|---|---|
| `ethereum/engine` (incl. `engine-auth`) | wired, `continue-on-error` |
| `ethereum/rpc-compat` | wired, `continue-on-error`; full pinned inventory executes, with the current failure set still under repair |
| `ethereum/eels/consume-engine` | not wired |
| `ethereum/eels/consume-rlp` | not wired — requires a suite-specific current-fork review |
| `devp2p` | wired, `continue-on-error`; the adapter's routable enode is asserted |
| `ethereum/sync` (full-sync) | not wired — plan section 4 remains the blocker |
| snap | not wired — plan section 5 |

Live geth/Nethermind/Lighthouse interop smoke gates, also part of plan section
2, are not started. The runtime image is the prerequisite they were waiting on
and now exists; the remaining work is a compose topology pairing this image with
a pinned consensus client, which is a separate change.

## What has actually been run

The container-only image and adapter smoke checks pass on the development
control plane:

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
  variable exits naming itself. `enode.sh` returns the same non-loopback bridge
  address reported by `admin_nodeInfo`.
- `scripts/hive-run.sh --prepare-only` checks out Hive
  `dde4f59d04ff0ff8b6585670b08cea1b6c8ab65c`, verifies the commit, and installs
  `clients/ethereum-lisp`.

Real Hive runs execute on the reviewed Linux runner `test-ethereum-server`, not
on macOS. The first full baseline at client revision `10d533fd` executed all
403 Engine cases and passed 307: engine-auth 8/8, exchange-capabilities 5/5,
withdrawals 30/35, Cancun 165/226, and engine-api 99/129. Its full rpc-compat
run passed 50/243. These are failure inventories, not readiness gates.

After repairing historical block execution, client revision `6543ad11` passed
the focused rpc-compat launch/head run 2/2 and its adapter imported all 54
fixture blocks without an offline-import stop. The full pinned rpc-compat run
then passed 96/243. The remaining 147 failures are still open; the largest
groups include `eth_simulateV1`, tracing, blob/set-code transaction and receipt
coverage, and exact RPC error/parameter semantics. No full Engine result has
yet been recorded for `6543ad11`, and none of these runs completes Section 5.
