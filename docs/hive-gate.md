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
| execution-specs EELS and fixtures | `tests@v20.0.2`, `abbe05777ab83fb94ce18c425daaa7ab79e779c1`, fixture SHA-256 `1280540950a4c3470a421416b6f35458a9b635827265c29e5aef1ae839ae1788` |
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
full-suite inventories (403 Engine tests and 234 rpc-compat tests). Bumping the
Hive pin means re-reading its
`docs/clients.md` for contract changes, re-diffing `tools/hive/mapper.jq`
against `clients/go-ethereum/mapper.jq`, and deliberately updating those
inventory counts.

The two EELS consume suites also fail closed instead of using their Dockerfiles'
moving default branch and `stable@latest` fixture download. Set
`HIVE_EELS_FIXTURE_ARCHIVE` to the pinned `tests@v20.0.2` `fixtures.tar.gz`.
The runner verifies its SHA-256, hard-links it temporarily into the selected
simulator context without duplicating the multi-gigabyte archive, and passes
both the exact execution-specs commit and `/fixtures` build arguments. The
temporary context link is removed on exit; the source archive is never changed.

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
  `mapper.jq` (genesis translation), `genesis.json` (Hive's pinned standard
  fallback for discovery cases that upload none), `enode.sh`, `hive.yaml`.
  Simulator uploads replace the fallback path before startup. The adapter
  explicitly selects `--db.engine rocksdb`: the fsync-per-record file backend
  is a small crash-safety oracle, whereas Hive's concurrent Engine/devp2p
  workloads require the production incremental backend used by public-network
  runs.
- **`scripts/hive-run.sh`** — materializes the pinned Hive checkout, installs
  `tools/hive` as `clients/ethereum-lisp`, writes the client file, runs a suite,
  and validates a nonzero fresh result/count manifest even when Hive reports
  test failures. `HIVE_EXPECTED_TESTS` pins a diagnostic subset explicitly;
  full Engine and rpc-compat runs select their known inventories automatically.
  For `devp2p`, it stages `scripts/hive-devp2p.Dockerfile` and passes the exact
  observed go-ethereum revision because pinned Hive otherwise clones moving
  master while building that simulator.
- **`scripts/hive-runtime-smoke.sh`** — starts the runtime image and asserts
  over the wire that it answers `eth_chainId`, refuses an unauthenticated
  `engine_*` call with 401, and answers a JWT-signed one. It also builds a
  `--hoodi` genesis, which is the only check that the packaged allocation files
  still resolve from inside a saved image.
- **`scripts/hive-adapter-smoke.sh`** — starts the adapter both as discovery
  cases do (no uploaded genesis) and as the other Hive cases do (uploaded
  `/genesis.json`, `HIVE_*` in the environment, no arguments). It checks that
  the bundled fallback starts, an upload replaces it and reaches the client,
  Hive's fixed JWT secret authenticates, each refused variable exits naming
  itself, and `enode.sh` returns the same routable bridge address as
  `admin_nodeInfo`. It also fails if the adapter does not select RocksDB.
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

Hive itself does not run on macOS: it dials each client container's bridge
address for its liveness check, which is not routable from a macOS host into the
Docker Desktop VM. `scripts/hive-run.sh` prepares everything and stops with that
explanation; `--prepare-only` makes that the intended outcome. Linux, and CI,
run the suite for real. A Linux release runner without a host Go toolchain may
set `HIVE_PREBUILT_BINARY_SHA256` to the exact checksum of an executable
`$HIVE_WORKDIR/hive/hive`; the runner still verifies the pinned checkout and
fails if either the binary or checksum is absent or mismatched. This permits a
binary built by a bounded reviewed Go container without silently trusting a
different executable.

### Remote runs: `scripts/hoodi-hive-gate.sh`

The Section 5 gates run on the Linux Hoodi host, each inside a fresh bounded
"outer runner" container that has its own nested Docker daemon. The external
supervisor that started the r19/r29/r54 runners is no longer on the control
plane. `scripts/hoodi-hive-gate.sh` (remote half in
`scripts/hoodi-hive-gate-remote.sh`) is the checked-in broker that replaces
it. It follows `scripts/hoodi-live-gate.sh`: `HOODI_GATE_HOST` (default
`test-ethereum-sophon2-symbiosis`), every path below `/data/hoodi-sec5-hive`,
runner label `agent=codex-sec5-live-gate`, and nothing is ever deleted.

```sh
S="--sim rpc-compat --run N --stamp YYYYMMDDTHHMMSSZ"   # or engine, devp2p
scripts/hoodi-hive-gate.sh inspect            # read-only: free -b, df, containers, images, staging
HOODI_GATE_ALLOW_MUTATION=1 scripts/hoodi-hive-gate.sh upload       # source + runtime tar, sha256 both ends
HOODI_GATE_ALLOW_MUTATION=1 HOODI_HIVE_NESTED_DOCKER_PRIVILEGED=1 \
  scripts/hoodi-hive-gate.sh prepare $S       # fresh evidence root, nested load, --prepare-only
HOODI_GATE_ALLOW_MUTATION=1 HOODI_HIVE_NESTED_DOCKER_PRIVILEGED=1 \
  scripts/hoodi-hive-gate.sh run $S           # detached outer runner
scripts/hoodi-hive-gate.sh status $S          # runner exit/OOMKilled/restarts, Hive summary line
scripts/hoodi-hive-gate.sh logs $S
scripts/hoodi-hive-gate.sh collect $S         # results + logs to /private/tmp/sec5-hive-evidence/<run>, counts, manifest
```

Mutating actions require `HOODI_GATE_ALLOW_MUTATION=1`, a clean checkout, and
the live gate's revision fence: `HOODI_HIVE_REVISION` (default `HEAD`) must be
`HEAD`, or an ancestor with no runtime-sensitive change since. `upload`
builds `/private/tmp/ethereum-lisp-source-<rev8>.tar` with
`git archive --format=tar <rev>` and checks that an existing one matches.

`upload` normally reads the runtime image's revision and platform from the
local Docker daemon. When that daemon is down (a Docker Desktop outage on the
control plane), an archive already exported by `scripts/dev.sh
runtime-export` can be staged instead:

```sh
HOODI_GATE_ALLOW_MUTATION=1 \
HOODI_HIVE_IMAGE_TAR=/private/tmp/ethereum-lisp-runtime-sec5-<rev8>-amd64.tar \
HOODI_HIVE_IMAGE_SHA256=<the sha256 runtime-export printed> \
  scripts/hoodi-hive-gate.sh upload
```

The archive's SHA-256 must equal the pin (`prepare` checks it again when the
variables are set), and its single image's `RepoTags` must include
`ethereum-lisp-runtime:sec5-<rev8>-amd64` and its configuration must carry
exactly one `org.opencontainers.image.revision` label equal to the revision
and the platform `linux/amd64`, read from `manifest.json` and the
configuration blob with `tar`, `grep` and `sed`. The revision fence runs
before any of this and is unchanged, and the nested runner still checks the
loaded image's revision, platform and user at load time.

Refusal matrix, each checked before any change:

| Condition | Refused actions |
|---|---|
| mutation flag missing, dirty checkout | upload, prepare, run |
| revision not an ancestor of HEAD | all |
| runtime-sensitive change since the revision | upload, prepare, run |
| `HOODI_HIVE_NESTED_DOCKER_PRIVILEGED` not 1 | prepare, run |
| runner or prepare container already exists | prepare, run |
| `/data` available below 12,884,901,888 bytes (r40) | prepare, run |
| MemAvailable below 4.5 GiB (prepare, rpc-compat) or 8 GiB (engine, devp2p) | prepare, run |
| a live-gate EL is running (`agent=codex-sec5-live-gate` + gate-revision label) | run engine, run devp2p |
| another Hive runner is running | prepare, run |
| runner image absent; staged archive, source, or Hive binary checksum mismatch | prepare |
| evidence root not freshly prepared, results non-empty, runner script changed | run |
| runner still running, no `hive-status.txt`, local directory exists | collect |
| `HOODI_HIVE_IMAGE_TAR` without `HOODI_HIVE_IMAGE_SHA256` (or the reverse), a pin that is not 64 lowercase hex digits, or an archive other than `HOODI_HIVE_RUNTIME_ARTIFACT` | all |
| archive checksum differs from the pin | upload, prepare |
| archive is not one `docker image save` image, lacks the `sec5-<rev8>-amd64` tag, or carries another revision or platform | upload |

Transcribed from the records: runner bounds 2 CPU, 3g/3584m for rpc-compat
(r19, `docs/evidence/gates.md`, row 6e3e9b1d) and 8g/10g for Engine (r29,
`docs/evidence/gates.md`, row 694667f9) and devp2p (r54,
`docs/evidence/gates.md`, row 03957929), 1,024 PIDs, read-only root, no published
port, not on the Hoodi networks, binds limited to the evidence root and the
nested-Docker path, bounded tmpfs. The runtime archive is loaded into the
runner's nested daemon, not the host's (r35/r43,
`docs/evidence/gates.md`, rows 4097bbd4 and b147ade6).
The inner call comes from the 3305307d records: `RUNTIME_PREBUILT=1`,
`HIVE_WORKDIR=/evidence/hive-gate`, `HIVE_RESULTS=/evidence/results`, the
pinned Hive binary `cff9f5c0…` via `HIVE_PREBUILT_BINARY_SHA256`,
`HIVE_EXPECTED_TESTS=48` for devp2p only (234 and 403 come from
`hive-run.sh`), no `HIVE_EXTRA_ARGS`. The runner exits 0 with Hive's own
status in `hive-status.txt` (r54).

**Inferred, not in any record — review before the first run:**

1. `--privileged` on the outer runner. A nested Docker daemon needs it, but no
   record names the flag, so `prepare`/`run` require
   `HOODI_HIVE_NESTED_DOCKER_PRIVILEGED=1` as an explicit acknowledgement.
2. The runner image `ethereum-lisp-sec5-hive-runner:docker27-amd64` contains
   `dockerd`, `docker`, `bash`, `git`, `jq`, `sha256sum`, `tar`. The runner
   script checks them and uses `/bin/sh` as entrypoint; `inspect` prints the
   image configuration.
3. The host path of the pinned Hive binary (default
   `/data/hoodi-sec5-hive/staging/hive-dde4f59d`, `HOODI_HIVE_BINARY`).
4. tmpfs sizes (`/run`, `/var/run` 64 MiB; `/tmp` 1 GiB).
5. No run timeout: r39's 2 h bound would cut off r29's roughly 2 h 06 min
   Engine run.

`scripts/hoodi-hive-gate-selftest.sh` runs the broker against stubbed
`ssh`/`scp`/`docker`/`git`/`free`/`df` (the ssh stub runs the remote half
locally). It covers argument parsing and every refusal above except the
staging-checksum and runner-script ones, each with a positive control, and
the archive upload with the local daemon stubbed down (70 checks). It runs
as the integration test `HOODI-HIVE-GATE-SELFTEST-COVERS-REFUSALS`
(`tests/control-plane-broker-tests.lisp`). `scripts/hoodi-fleet-status.sh`
calls `status` for the newest run of each suite, identified from the
runner's labels.

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
| `HIVE_DISCV5` | **refused** — the CLI currently starts discv4 only |
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
| `ethereum/rpc-compat` | wired, `continue-on-error`; exact revision `6e3e9b1d` passes the full pinned 234-case inventory |
| `ethereum/eels/consume-engine` | not wired |
| `ethereum/eels/consume-rlp` | not wired — requires a suite-specific current-fork review |
| `devp2p` | wired, `continue-on-error`; first complete baseline passed 1/33, with local RED/GREEN repairs for fork-ID mapping and discv4 fallback startup awaiting a pinned rerun; discv5 is now explicitly refused rather than silently running discv4 |
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
  the runtime image, starts both with the bundled discovery fallback and an
  uploaded simulator genesis, preserves source fork configuration when Hive
  supplies no override, authenticates Hive's fixed JWT secret, and refuses each
  unsupported variable by name. `enode.sh` returns the same non-loopback bridge
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

The exact Section 5 client revision `92982442` selected all 403 pinned Engine
cases and passed 401. One failure is ethereum/hive#1351's known harness race:
the detail log removes ethereum-lisp before the Modified Geth payload producer
fails to include the transaction that the test setup needs. The other is a
client-visible Cancun blob-ordering failure (`expected 6 blob, got 5`). Both
remain failures in the source record listed at `docs/evidence/gates.md`, row 92982442.

The first rpc-compat run that actually supplied the pinned Execution APIs
commit selected 234 cases, not the older 243-case moving-main baseline. It
passed 125 and failed 109. The immutable discovery evidence is archived in
the source record listed at `docs/evidence/gates.md`, row 92982442; the runner now pins 234
and requires a fresh confirmation result rather than retroactively treating the
discovery run as a passing inventory check.

The reviewed exact-revision rerun at `6e3e9b1d` selected the same 234 unique
cases and passed 234/234 with no failure or passed-to-failed regression. All
four `testing_buildBlockV1` cases passed. Artifact identities, resource bounds,
result/log hashes, and the preserved remote evidence path are archived in
the source record listed at `docs/evidence/gates.md`, row 6e3e9b1d. This closes rpc-compat only;
the Engine, EELS, devp2p, full-sync, snap, and live/soak gates retain their
independent status above.

The first complete devp2p discovery run at exact client revision `b7bdb6da`
executed 33 entries and passed 1. Twenty-four eth and six snap entries shared
one fork-ID mismatch: the uploaded genesis contained `osakaTime=180`, while the
simulator's forkenv omitted `HIVE_OSAKA_TIMESTAMP` and the client mapper
discarded the source activation. The mapper now retains supported source
time-fork values unless Hive overrides them, and the local adapter RED/GREEN
smoke passes. The adapter now also bundles Hive's pinned standard minimal
genesis for discovery entries that upload none; a second RED/GREEN control
proves fallback startup without weakening uploaded-genesis handling. Because
the CLI currently serves discv4 only, `HIVE_DISCV5` is explicitly refused
rather than silently starting the wrong protocol.
The retained simulator build used geth
`101035a1049c7dc468bfe973478b579d9883d7b6`. The runner now replaces Hive's
moving-master simulator Dockerfile with a reviewed template that fetches and
verifies that exact commit, and passes the same value through
`--sim.buildarg`. See
`docs/evidence/sec5-b7bdb6da-hive-devp2p-discovery.txt` and
`docs/evidence/sec5-0ba3a950-hive-discovery-genesis.txt` plus
`docs/evidence/sec5-f19ee8d5-hive-devp2p-geth-pin.txt`. Exact revision
`7b3e9d3590a774d37db32faa9400f323d6c1c3f0` now has a verified linux/amd64
runtime archive (SHA-256
`84111e9e69e7d09ee3d04d171fc5c80bb46a73c5d9db39efe770e8b1b614c54a`)
and matching source archive ready for the rerun; see
the source record listed at `docs/evidence/gates.md`, row 7b3e9d35. No local repair or artifact
build closes the devp2p gate before a fresh pinned Linux rerun.

Revision `63408ce2` repaired the remaining pinned `eth_config/get-config`
fork-ID mismatch by including `mergeNetsplitBlock` in the EIP-2124 activation
schedule. Its focused run passed the mandatory launch plus exact `eth_config`
case 2/2. A fresh full pinned run then passed 137/234; the 97 remaining
failures are `eth_simulateV1` (91), `testing_buildBlockV1` (4), and the two
genesis-tracing cases. Every other selected group passed. The immutable result
paths, hashes, runtime identity, local gates, and validation caveat are in
`docs/evidence/sec5-63408ce2-rpc-config-fork-id.txt`.
