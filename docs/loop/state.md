# Loop State

Last updated: 2026-07-06

## Project State

- The repository target is a usable Common Lisp Ethereum execution-layer
  client.
- Phase A's bounded in-repo chain-import smoke path is documented as closed for
  the current Shanghai fixture set.
- Current highest strategic priority is Phase B local devnet, Engine/public RPC
  process behavior, Hive/process-runner readiness, and txpool/chain-store
  correctness that affects executable client behavior.
- Official execution-spec-tests v5.4.0 stable fixtures are expected at
  `.cache/eest-v5.4.0/root/fixtures` with archive SHA256
  `92cf1b47ad12fb27163261fc3c1cea5df72439cab507983d06b56c94f8741909`.

## Current Dirty Work

No intended dirty implementation work should remain after the current validated
batch is committed and pushed. The latest completed slice is the live
non-KZG hidden `engine_getBlobsV1` listener proof on top of the existing
fail-closed Engine-method gate that keeps KZG-backed methods hidden unless
both verifier hooks are installed. The next run spec should pivot to the
sibling non-KZG hidden-method rejection for `engine_getBlobsV2` instead of
revisiting already-proven V3/V4/V5/V6 payload envelopes, by-hash/by-range
payload-body probes, malformed-object KZG opt-in proofs, quantity/object
rejection matrices, or direct positive-path blob/cell-proof lookup.

Closed behavior from the latest slice:

- The engine-only `kzgOptIn` smoke child now seeds an Amsterdam-era version-6
  prepared payload alongside the existing imported V5 payload in its temporary
  database instead of stopping at blob bundle proof.
- That seeded V6 payload carries a non-empty execution request list, a
  non-empty block-access-list encoding, and the existing full-size blob bundle
  through the same verifier opt-in runner path.
- The focused engine-only smoke now performs a live `engine_getPayloadV6`
  request, requires the returned block number, slot number, execution request
  bytes, block-access-list bytes, and blob-bundle evidence to match the seeded
  V6 payload, and fails clearly when those Amsterdam-era fields are missing or
  malformed.
- The nested `kzgOptIn` report now records `engine_getPayloadV6` capability
  advertisement plus the V6 payload id, block number, slot number, execution
  request count/bytes, block-access-list bytes, blob prefix/count, commitment,
  proof count, and the expanded ten-request Engine connection contract.
- KV prepared-payload import now retains a prepared payload when the same block
  hash is already known and the full block body matches, while still dropping
  mismatched known/prepared collisions.
- The engine-only `kzgOptIn` smoke now seeds that same Amsterdam-era V6 block
  as both a known block and a prepared payload, then proves live
  `engine_getPayloadBodiesByHashV2` returns the expected empty
  transactions/withdrawals arrays plus the Amsterdam `blockAccessList`.
- The nested `kzgOptIn` report now records `preparedPayloadV6BlockHash`,
  `preparedPayloadBodiesByHashV2Count`,
  `preparedPayloadBodiesByHashV2TransactionCount`,
  `preparedPayloadBodiesByHashV2WithdrawalCount`, and
  `preparedPayloadBodiesByHashV2BlockAccessList`, and the nested KZG
  connection/shutdown contract expanded from ten to eleven Engine requests.
- The same engine-only `kzgOptIn` smoke now requests
  `engine_getPayloadBodiesByRangeV2` from block `0x9` with count `0x2`,
  proving a sparse mixed-hit response where the leading missing slot remains
  `null` while the later Amsterdam V6 slot still returns the expected empty
  `transactions` / `withdrawals` arrays plus `blockAccessList`.
- The nested `kzgOptIn` report now records
  `preparedPayloadBodiesByRangeV2StartBlockNumber = 0x9`,
  `preparedPayloadBodiesByRangeV2Count = 2`,
  `preparedPayloadBodiesByRangeV2LeadingNull = true`, and
  `preparedPayloadBodiesByRangeV2HitIndex = 1`, so sparse ordering regressions
  are visible at the runner boundary without changing the thirteen-request KZG
  connection contract.
- The same engine-only `kzgOptIn` smoke now also sends a live oversized
  `engine_getPayloadBodiesByRangeV2` request with `count = 0x401`, proving the
  existing `-38004` / "The number of requested bodies must not exceed 1024"
  contract through the real listener path instead of only in-process tests.
- The nested `kzgOptIn` report now records
  `preparedPayloadBodiesByRangeV2OversizedErrorCode = -38004` and
  `preparedPayloadBodiesByRangeV2OversizedErrorMessage`, and the nested KZG
  connection/shutdown contract expands from thirteen to fourteen Engine
  requests so the extra boundary probe is accounted for explicitly.
- The same engine-only `kzgOptIn` smoke now also sends live zero-start and
  zero-count `engine_getPayloadBodiesByRangeV2` requests, proving the existing
  `-32602` / "start and count must be positive numbers" contract through the
  real listener path instead of only in-process tests.
- The nested `kzgOptIn` report now records
  `preparedPayloadBodiesByRangeV2ZeroStartErrorCode = -32602`,
  `preparedPayloadBodiesByRangeV2ZeroStartErrorMessage`,
  `preparedPayloadBodiesByRangeV2ZeroCountErrorCode = -32602`, and
  `preparedPayloadBodiesByRangeV2ZeroCountErrorMessage`, and the nested KZG
  connection/shutdown contract expands from fourteen to sixteen Engine
  requests so both positive-number boundary probes are accounted for
  explicitly.
- The same engine-only `kzgOptIn` smoke now also sends a live malformed-start
  `engine_getPayloadBodiesByRangeV2` request with `start = "0xzz"`, proving
  the existing `-32602` / "start must be a non-negative quantity" envelope
  through the real listener path instead of only in-process validation.
- The nested `kzgOptIn` report now records
  `preparedPayloadBodiesByRangeV2MalformedStartErrorCode = -32602` and
  `preparedPayloadBodiesByRangeV2MalformedStartErrorMessage`, and the nested
  KZG connection/shutdown contract expands from sixteen to seventeen Engine
  requests, including the child `--max-connections` cap and shutdown telemetry
  checks.
- The same engine-only `kzgOptIn` smoke now also sends a live malformed-count
  `engine_getPayloadBodiesByRangeV2` request with `count = "0xzz"`, proving
  the existing `-32602` / "count must be a non-negative quantity" envelope
  through the real listener path instead of only in-process validation.
- The nested `kzgOptIn` report now records
  `preparedPayloadBodiesByRangeV2MalformedCountErrorCode = -32602` and
  `preparedPayloadBodiesByRangeV2MalformedCountErrorMessage`, and the nested
  KZG connection/shutdown contract expands from seventeen to eighteen Engine
  requests, including the child `--max-connections` cap and shutdown
  telemetry checks.
- The same engine-only `kzgOptIn` smoke now also sends a live one-element
  `engine_getPayloadBodiesByRangeV2` params array, proving the existing
  invalid-params `-32602` /
  "engine_getPayloadBodiesByRangeV2 param count is missing" envelope through
  the real listener path instead of only in-process validation.
- The nested `kzgOptIn` report now records
  `preparedPayloadBodiesByRangeV2ParamsEnvelopeErrorCode = -32602` and
  `preparedPayloadBodiesByRangeV2ParamsEnvelopeErrorMessage`, and the nested
  KZG connection/shutdown contract expands from eighteen to nineteen Engine
  requests, including the child `--max-connections` cap and shutdown
  telemetry checks.
- The same engine-only `kzgOptIn` smoke now also sends a live scalar non-array
  `engine_getPayloadBodiesByRangeV2` `params` request, proving the generic
  JSON-RPC invalid-request `-32600` / `"Invalid Request"` envelope through
  the real listener path instead of only in-process validation.
- The nested `kzgOptIn` report now records
  `preparedPayloadBodiesByRangeV2InvalidRequestErrorCode` and
  `preparedPayloadBodiesByRangeV2InvalidRequestErrorMessage`, and the nested
  KZG connection/shutdown contract expands from nineteen to twenty Engine
  requests, including the child `--max-connections` cap and shutdown
  telemetry checks.
- The same engine-only `kzgOptIn` smoke now also sends a live `params:null`
  `engine_getPayloadBodiesByRangeV2` request, proving the existing
  invalid-params `-32602` /
  `"engine_getPayloadBodiesByRangeV2 params must include start and count"`
  envelope through the real listener path instead of the stale generic
  invalid-request assumption.
- The nested `kzgOptIn` report now records
  `preparedPayloadBodiesByRangeV2NullParamsErrorCode` and
  `preparedPayloadBodiesByRangeV2NullParamsErrorMessage`, and the nested KZG
  connection/shutdown contract expands from twenty to twenty-one Engine
  requests, including the child `--max-connections` cap and shutdown
  telemetry checks.
- The same engine-only `kzgOptIn` smoke now also sends a live non-empty
  object-valued `engine_getPayloadBodiesByRangeV2` `params` request such as
  `{"start":"0x1","count":"0x1"}`, proving the existing invalid-params
  `-32602` / `"start must be a non-negative quantity"` envelope through the
  real listener path instead of only through in-process validation.
- The nested `kzgOptIn` report now records
  `preparedPayloadBodiesByRangeV2ObjectParamsErrorCode` and
  `preparedPayloadBodiesByRangeV2ObjectParamsErrorMessage`, and the nested
  KZG connection/shutdown contract expands from twenty-one to twenty-two
  Engine requests, including the child `--max-connections` cap and shutdown
  telemetry checks.
- The same engine-only `kzgOptIn` smoke now also sends a live empty-object
  `engine_getPayloadBodiesByRangeV2` `params` request such as `{}`, proving
  the existing invalid-params `-32602` /
  `"engine_getPayloadBodiesByRangeV2 params must include start and count"`
  envelope through the real listener path instead of only through in-process
  validation.
- The nested `kzgOptIn` report now records
  `preparedPayloadBodiesByRangeV2EmptyObjectParamsErrorCode` and
  `preparedPayloadBodiesByRangeV2EmptyObjectParamsErrorMessage`, and the
  nested KZG connection/shutdown contract expands from twenty-two to
  twenty-three Engine requests, including the child `--max-connections` cap
  and shutdown telemetry checks.
- The same engine-only `kzgOptIn` smoke now also sends a live single-key
  object-valued `engine_getPayloadBodiesByRangeV2` `params` request such as
  `{"count":"0x1"}`, proving the existing invalid-params `-32602` /
  `"start must be a non-negative quantity"` envelope through the real
  listener path instead of only through in-process validation.
- The nested `kzgOptIn` report now records
  `preparedPayloadBodiesByRangeV2MissingStartObjectParamsErrorCode` and
  `preparedPayloadBodiesByRangeV2MissingStartObjectParamsErrorMessage`, and
  the nested KZG connection/shutdown contract expands from twenty-three to
  twenty-four Engine requests, including the child `--max-connections` cap
  and shutdown telemetry checks.
- The same engine-only `kzgOptIn` smoke now also sends a live single-key
  object-valued `engine_getPayloadBodiesByRangeV2` `params` request such as
  `{"start":"0x1"}`, proving the current live and in-process invalid-params
  `-32602` / `"start must be a non-negative quantity"` envelope through the
  real listener path instead of assuming a separate missing-count message.
- The nested `kzgOptIn` report now records
  `preparedPayloadBodiesByRangeV2MissingCountObjectParamsErrorCode` and
  `preparedPayloadBodiesByRangeV2MissingCountObjectParamsErrorMessage`, and
  the nested KZG connection/shutdown contract expands from twenty-four to
  twenty-five Engine requests, including the child `--max-connections` cap
  and shutdown telemetry checks.
- The same engine-only `kzgOptIn` smoke now also sends a live unexpected-key
  object-valued `engine_getPayloadBodiesByRangeV2` `params` request such as
  `{"foo":"0x1"}`, proving the current live and in-process invalid-params
  `-32602` / "start must be a non-negative quantity" envelope through the
  real listener path instead of assuming object-valued drift only affects
  named keys.
- The nested `kzgOptIn` report now records
  `preparedPayloadBodiesByRangeV2UnexpectedKeyObjectParamsErrorCode` and
  `preparedPayloadBodiesByRangeV2UnexpectedKeyObjectParamsErrorMessage`, and
  the nested KZG connection/shutdown contract expands from twenty-five to
  twenty-six Engine requests, including the child `--max-connections` cap and
  shutdown telemetry checks.
- Positive `--dev.period DURATION` parses through the shared geth-style
  duration path and rejects malformed or negative values.
- Devnet summaries, readiness data, and lifecycle telemetry report
  `devPeriodSeconds`.
- Long-running devnet serve mode starts a shutdown-aware background dev-period
  tick when the configured period is positive.
- The deterministic tick path can seal currently pending, recoverable public
  txpool transactions into a local child block on top of the current devnet
  head.
- The sealed block uses the existing signed-block execution and commit path,
  advances public latest-head state, indexes included transaction/receipt
  lookups, and removes mined transactions from pending txpool visibility.
- The standalone devnet smoke gate txpool-rejournal helper now waits for the
  full expected journal record count before reporting, removing a race between
  "target record observed" and "all expected records flushed".
- The geth-style mining/archive/metrics CLI flag test now creates a readable
  temporary TOML config instead of depending on a fixed `/tmp` file.
- The standalone devnet smoke gate now runs an independent `--dev.period=1s`
  listener-boundary probe that submits a public raw transaction, waits for the
  background period tick to seal it, and reports mined transaction, receipt,
  block, and txpool cleanup evidence.
- The dev-period smoke probe uses a stable one-transfer fixture independent of
  the surrounding all-fixtures payload case, so the runner-boundary period tick
  contract is not coupled to unrelated fixture transaction shapes.
- The local dev-period tick now selects a deterministic prefix of recoverable
  public txpool transactions whose cumulative gas limit fits the child block
  gas limit, enters block execution only when at least one transaction fits,
  and leaves non-selected pending transactions visible for later blocks.
- The local dev-period selector is now sender-aware: when one sender's next
  nonce-safe transaction would exceed the remaining child block gas, that
  sender is skipped for the rest of the current block while later independent
  sender heads may still be selected if they fit.
- The shared local mining selector now lives in core and is reused by both the
  dev-period block-production path and Engine prepared-payload construction.
- Engine `engine_forkchoiceUpdated*` prepared payloads now select recoverable
  public pending txpool transactions with the deterministic, gas-limited,
  sender-aware policy.
- Non-empty prepared payloads execute the selected signed transactions against
  parent state to materialize payload block commitments without committing the
  block or removing txpool entries.
- Non-empty prepared payload ids include the selected transaction root, so a
  repeated same-head/same-attributes `engine_forkchoiceUpdated*` call after
  txpool changes gets a distinct cache key instead of reusing stale empty
  payloads.
- `engine_getPayloadV1` returns selected transaction bytes for prepared local
  payloads, while selected and non-selected txpool entries remain
  public-visible before import/forkchoice.
- The standalone devnet smoke gate now proves txpool-backed prepared-payload
  selection across the real authenticated Engine/public listener boundary. It
  admits public txpool transactions, prepares a second payload through
  authenticated `engine_forkchoiceUpdatedV2`, retrieves it through
  authenticated `engine_getPayloadV2`, reports the selected transaction
  raw bytes/hash, and runs a post-preparation public `txpool_contentFrom`
  query proving the selected pending transaction and non-selected basefee /
  nonce-gapped queued transactions remain public-visible before
  import/forkchoice.
- The standalone devnet smoke gate now imports that retrieved txpool-backed
  prepared payload through authenticated `engine_newPayloadV2`, canonicalizes it
  through `engine_forkchoiceUpdatedV2`, verifies public canonical transaction,
  receipt, raw transaction, and block visibility for the selected transaction,
  and verifies txpool cleanup removes the mined transaction while non-selected
  basefee and nonce-gapped entries remain queued.
- Focused in-process Engine RPC coverage now proves same-head/same-attributes
  prepared-payload cache refresh when a valid same-sender/same-nonce public
  txpool replacement changes the selected transaction without changing the
  selected transaction count. The second payload id is distinct,
  `engine_getPayloadV1` returns only the replacement raw transaction, and
  `txpool_contentFrom` exposes only the replacement at that sender/nonce before
  import.
- The standalone devnet smoke gate now promotes that same-sender/same-nonce
  replacement-cache boundary to the real split Engine/public listener path.
  It prepares and retrieves a txpool-backed payload, admits a valid
  replacement before import, repeats the same-head/same-attributes Engine
  preparation to prove the second payload id changes, and reports replacement
  raw transaction/hash evidence.
- The standalone replacement smoke now proves public `txpool_contentFrom` at
  the sender/nonce exposes only the replacement transaction before import even
  though the original prepared payload was already cached.
- The same standalone smoke now imports and canonicalizes the replacement
  prepared payload and proves the restored canonical transaction/receipt/raw
  transaction evidence follows the replacement transaction while non-selected
  basefee and queued entries remain queued.
- The standalone all-fixtures devnet smoke suite now reuses that replacement
  workflow for every current pinned Shanghai runner case, preserving the
  original and replacement payload-id evidence plus replacement-only
  public/canonical transaction evidence per case while keeping the aggregate
  suite connection contract coherent at `engineConnections=161`,
  `publicConnections=378`, and `totalConnections=539`.
- The engine-only `scripts/devnet-smoke-gate.lisp -- --engine-only-serve`
  `kzgOptIn` child no longer stops at `engine_exchangeCapabilities`: with the
  repo-local verifier configured, it now sends authenticated
  `engine_forkchoiceUpdatedV3` / `engine_forkchoiceUpdatedV4` requests and
  retrieves the resulting payloads through `engine_getPayloadV3` /
  `engine_getPayloadV4`.
- The same KZG opt-in smoke report now records V3/V4 payload ids, parent hash,
  block number, V4 slot number, zero-blob bundle counts, and the expanded
  five-request Engine connection contract, making blob-era prepared-payload
  envelope regressions visible at the process boundary.
- The same engine-only `kzgOptIn` child now seeds a temporary database with a
  non-empty version-5 prepared payload and retrieves it through live
  `engine_getPayloadV5`, proving blob-carrying `blobsBundle` process-boundary
  retrieval under verifier opt-in without adding a production-only hook.
- The KZG opt-in smoke report now also records the imported V5 payload id,
  block number, blob prefix/count, commitment, proof count, and the expanded
  six-request Engine connection contract, so blob-carrying runner regressions
  are visible even when V3/V4 prepared payloads remain empty.
- The same engine-only `kzgOptIn` child now seeds that blob sidecar into the
  direct versioned-hash store, upgrades the shared runner HTTP reader to
  buffered reads for large blob JSON bodies, and proves live
  `engine_getBlobsV1` retrieval under verifier opt-in.
- The KZG opt-in smoke report now also records the direct lookup versioned
  hash, blob/proof prefixes and hex lengths, and the expanded seven-request
  Engine connection contract, so direct blob lookup regressions are visible at
  the process boundary instead of only through payload-envelope retrieval.
- The same engine-only `kzgOptIn` child now seeds a full cell-proof sidecar
  shape and proves live `engine_getBlobsV2` / `engine_getBlobsV3` retrieval
  under verifier opt-in without widening production code.
- The KZG opt-in smoke report now also records direct cell-proof lookup
  counts, full proof cardinality, representative first/last proof bytes, and
  the expanded nine-request Engine connection contract, so Cancun cell-proof
  regressions are visible at the process boundary instead of only through V1
  blob lookup.
- The negative engine-only capability contract now explicitly keeps
  `engine_getBlobsV2` / `engine_getBlobsV3` hidden when no verifier is
  configured, so shape-only nodes cannot silently advertise cell-proof lookup.

Closed validation:

- Focused escalated standalone smoke for the blob-era prepared-payload runner
  path passed:
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`.
  The nested `kzgOptIn` report now includes live
  `engine_forkchoiceUpdatedV3` / `engine_forkchoiceUpdatedV4` and
  `engine_getPayloadV3` / `engine_getPayloadV4` evidence, including payload
  ids, parent hashes, block numbers, slot number, and blob-bundle field
  presence.
- `git diff --check` passed.
- The escalated `sbcl --script tests/run-tests.lisp` run passed with
  `894 tests passed, 5 skipped` before the final smoke-only assertion
  tightening that requires explicit `blobsBundle` child fields.
- After that verifier-driven assertion tightening, the focused escalated
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`
  rerun still passed on the final tree.
- Verifier review returned `PASS` after tightening the new smoke assertions so
  missing `blobsBundle` child fields cannot silently pass through `nil`/empty
  counts. Residual risk: the live runner boundary now proves empty V3/V4
  blob-era envelopes, but not yet blob-carrying bundle retrieval.
- Focused escalated standalone smoke for the blob-carrying runner path passed:
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`.
  The nested `kzgOptIn` report now includes imported non-empty
  `engine_getPayloadV5` evidence with payload id, block number, blob prefix,
  blob count, commitment, proof count, and six Engine connections.
- `git diff --check` passed.
- The escalated `sbcl --script tests/run-tests.lisp` rerun passed with
  `894 tests passed, 5 skipped` after fixing the new smoke assertion to match
  the seeded V5 payload block number.
- After verifier review flagged the synthetic V5 bundle proof cardinality, the
  seeded payload was tightened to a one-blob, one-commitment, one-proof shape
  and the focused escalated
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`
  rerun still passed on the final tree.
- Independent verifier review returned `PASS` on the final one-proof V5 smoke
  shape. Residual risk is now narrowed to direct
  `engine_getBlobsV1`/`V2`/`V3` runner proof and the shared HTTP reader's
  ability to handle full blob-response bodies.
- Focused escalated standalone smoke for the direct blob lookup runner path
  passed: `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`.
  The nested `kzgOptIn` report now includes the requested versioned hash plus
  direct live `engine_getBlobsV1` blob/proof evidence with prefixes, full
  blob/proof hex lengths, and seven Engine connections.
- `git diff --check` passed.
- Independent verifier review returned `PASS` after the direct-lookup smoke
  tightened both keyed-hit and unknown-hash-miss assertions plus the full
  report contract checks. Residual risk is now limited to direct
  `engine_getBlobsV2` / `engine_getBlobsV3` cell-proof runner proof.
- Focused escalated standalone smoke for the direct cell-proof lookup runner
  path passed: `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`.
  The nested `kzgOptIn` report now includes live `engine_getBlobsV2` /
  `engine_getBlobsV3` evidence with 128 returned cell proofs, representative
  first/last proof bytes, unknown-hash miss handling, and nine Engine
  connections.
- `git diff --check` passed.
- Independent verifier review returned `PASS`; residual risk is now limited to
  imported non-empty `engine_getPayloadV6` runner proof and other still-missing
  blob-era envelope variants beyond direct lookup.
- Focused escalated standalone smoke for the imported non-empty V6 runner path
  passed: `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`.
  The nested `kzgOptIn` report now includes live `engine_getPayloadV6`
  evidence with the imported payload id, block number, slot number, execution
  request count/bytes, block-access-list bytes, blob prefix/count,
  commitment, proof count, and the expanded ten-request Engine connection
  contract.
- `git diff --check` passed.
- Independent verifier review returned `PASS`; residual risk is now limited to
  blob-era payload-body retrieval at the process boundary, especially live
  `engine_getPayloadBodiesByHashV2` and `engine_getPayloadBodiesByRangeV2`
  proof for Amsterdam block-access-list responses.
- Focused escalated standalone smoke for the Amsterdam by-hash payload-body
  runner path passed:
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`.
  The nested `kzgOptIn` report now includes live
  `engine_getPayloadBodiesByHashV2` evidence for the same imported V6 block
  already proven through `engine_getPayloadV6`.
- `git diff --check` passed.
- The final escalated `sbcl --script tests/run-tests.lisp` run passed with
  `895 tests passed, 5 skipped`.
- Independent verifier review returned `PASS`; residual risk is now limited to
  live `engine_getPayloadBodiesByRangeV2` runner proof and any broader
  Amsterdam payload-body range assertions beyond the current by-hash contract.
- Focused escalated standalone smoke for the Amsterdam by-range payload-body
  runner path passed:
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`.
  The nested `kzgOptIn` report now includes live
  `engine_forkchoiceUpdatedV2` selection plus `engine_getPayloadBodiesByRangeV2`
  evidence for the same imported V6 block already proven through
  `engine_getPayloadV6` and `engine_getPayloadBodiesByHashV2`.
- Focused engine-only CLI coverage for
  `DEVNET-SMOKE-GATE-SCRIPT-ENGINE-ONLY-SERVE-MODE` passed after the smoke
  report assertions and non-KZG capability guards were updated for
  `engine_getPayloadBodiesByRangeV2`.
- `git diff --check` passed.
- Independent verifier review returned `PASS`; residual risk is now limited to
  broader Amsterdam payload-body range/null assertions beyond the current
  single-hit V6 proof.
- Focused escalated standalone smoke for the sparse Amsterdam by-range
  payload-body runner path passed:
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`.
  The nested `kzgOptIn` report now includes a two-slot
  `engine_getPayloadBodiesByRangeV2` response with a leading `null`
  placeholder for block `0x9` and the expected Amsterdam V6 body at `0xa`.
- Focused engine-only CLI coverage for
  `DEVNET-SMOKE-GATE-SCRIPT-ENGINE-ONLY-SERVE-MODE` passed after the sparse
  range report assertions were tightened to require
  `preparedPayloadBodiesByRangeV2LeadingNull` and
  `preparedPayloadBodiesByRangeV2HitIndex`.
- `git diff --check` passed.
- Independent verifier review returned `PASS`; residual risk is now limited to
  invalid/oversized runner-bound `engine_getPayloadBodiesByRangeV2` requests
  and fixture-shape drift that would remove the current `0x9` to `0xa`
  sparse hole.
- Focused core coverage passed for the tightened non-KZG filter:
  `ENGINE-RPC-EXCHANGE-CAPABILITIES-ADVERTISES-SUPPORTED-METHODS` now proves
  hidden `engine_getPayloadBodiesByRangeV2` and
  `engine_getPayloadBodiesByHashV2` both reject with JSON-RPC `-32601` /
  `"Method not found"` when verifier opt-in is absent.
- Focused escalated standalone smoke for the non-KZG hidden by-range runner
  path passed:
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --engine-only-serve --json`.
  The engine-only report now records `hiddenPayloadBodiesByRangeV2Status`,
  `hiddenPayloadBodiesByRangeV2ErrorCode`, and
  `hiddenPayloadBodiesByRangeV2ErrorMessage`, and the engine-only connection
  contract for that probe increased from seven to eight Engine requests.
- Focused CLI and Phase A process coverage passed after the engine-only report
  assertions were updated:
  `DEVNET-SMOKE-GATE-SCRIPT-ENGINE-ONLY-SERVE-MODE`,
  `PHASE-A-SMOKE-GATE-SCRIPT-CAN-INCLUDE-DEVNET-SUITE`, and
  `PHASE-A-SELECTOR-SCRIPTS-ACCEPT-ROOT-OPTION`.
- The first escalated full-suite rerun exposed one stale
  `ETHEREUM-LISP-SCRIPT-SERVE-MODE-HONORS-HTTP-FALSE-ENGINE-ONLY` shutdown
  assertion that had incorrectly inherited the new eight-connection contract.
  The `--http=false` no-probe path was corrected back to the existing
  seven-connection expectation and its focused rerun passed.
- `git diff --check` passed.
- The final escalated `sbcl --script tests/run-tests.lisp` run passed with
  `895 tests passed, 5 skipped`.
- Independent verifier review returned `PASS`; residual risk is now limited to
  sibling listener-boundary hidden-method proofs such as live non-KZG
  `engine_getPayloadBodiesByHashV2` rejection and any later choice to widen
  that same boundary to additional hidden KZG-backed methods.

- Focused dev-period coverage passed inside the full suite:
  `DEVNET-CLI-DEV-PERIOD-PARSES-AND-REPORTS-DURATION` and
  `DEVNET-CLI-DEV-PERIOD-TICK-SEALS-PUBLIC-TXPOOL-TRANSACTION`,
  plus `DEVNET-CLI-DEV-PERIOD-TICK-CARRIES-ACTIVE-FORK-BODIES` for
  fork-active Cancun/Prague/Amsterdam empty body/header fields.
- The focused escalated standalone smoke gate passed:
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --json`.
- `git diff --check` passed.
- The first escalated `sbcl --script tests/run-tests.lisp` run failed in
  `DEVNET-SMOKE-GATE-SCRIPT-RUNS-ALL-PINNED-FIXTURES` because the new
  dev-period probe was mistakenly coupled to each payload fixture's txpool
  transaction shape.
- After changing the probe to use a stable one-transfer fixture, the focused
  escalated all-fixtures smoke command passed:
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --json --all-fixtures ...`.
- The final escalated `sbcl --script tests/run-tests.lisp` run passed with
  `886 tests passed, 5 skipped`.
- Independent verifier review returned `PASS`; residual risk is limited to the
  intentional stable Shanghai one-transfer probe fixture, which proves the
  runner-boundary period tick contract but does not claim per-fixture mining
  semantics.
- Focused direct CLI coverage for
  `DEVNET-CLI-DEV-PERIOD-TICK-BOUNDS-TRANSACTIONS-BY-GAS-LIMIT` passed during
  the current run.
- `git diff --check` passed.
- The escalated `sbcl --script tests/run-tests.lisp` run passed with
  `887 tests passed, 5 skipped`.
- Independent verifier review returned `PASS`. Residual risks: the no-fitting
  first-transaction edge is covered by the selector shape but does not yet have
  focused coverage, and receipt visibility for the multi-transaction bounded
  case relies on the existing single-transaction dev-period receipt coverage.
- Focused direct CLI coverage for
  `DEVNET-CLI-DEV-PERIOD-TICK-SELECTS-FITTING-SECOND-SENDER` and
  `DEVNET-CLI-DEV-PERIOD-TICK-BOUNDS-TRANSACTIONS-BY-GAS-LIMIT` passed during
  the current run.
- `git diff --check` passed.
- The escalated `sbcl --script tests/run-tests.lisp` run passed with
  `888 tests passed, 5 skipped`.
- Independent verifier review returned `PASS`. Residual risks: the case where
  the first sorted sender head does not fit but a later sender head does is
  covered by the sender-aware selector structure but not yet by a dedicated
  focused test, and no explicit third same-sender nonce fixture asserts blocked
  sender tails beyond the currently non-fitting nonce.
- Focused direct Engine RPC coverage for
  `ENGINE-RPC-FORKCHOICE-UPDATED-V1-SELECTS-PENDING-TXPOOL-TRANSACTIONS`
  and
  `ENGINE-RPC-FORKCHOICE-UPDATED-V1-PAYLOAD-ID-TRACKS-TXPOOL-SELECTION`
  passed during the current run.
- `git diff --check` passed.
- The first sandbox `sbcl --script tests/run-tests.lisp` run reached the new
  focused prepared-payload test but failed at the local socket/devnet Phase A
  smoke gate under sandbox restrictions.
- The escalated `sbcl --script tests/run-tests.lisp` run passed with
  `890 tests passed, 5 skipped`.
- Independent verifier review returned `PASS` after the prepared-payload cache
  key was changed to include the selected transaction root for non-empty
  txpool-backed payloads. Residual risks: replacement churn preserving
  transaction count and V2/V3 prepared-payload txpool variants remain useful
  follow-up coverage, but are not blocking this slice.
- Focused escalated standalone smoke for
  `DEVNET-RUNNER-SMOKE-PREPARED-PAYLOAD-TXPOOL-SELECTION` passed:
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --json`.
- `git diff --check` passed.
- The first escalated `sbcl --script tests/run-tests.lisp` run failed because
  `tests/cli-tests.lisp` still hard-coded the old standalone smoke connection
  contract (`engineWorkflowConnections=12`, `publicTxpoolConnections=19`).
- After updating the connection-contract assertions to the new
  `engineWorkflowConnections=14`, `publicTxpoolConnections=20`, single-case
  `engineConnections=19`, `publicConnections=46`, and `totalConnections=65`,
  the escalated `sbcl --script tests/run-tests.lisp` run passed with
  `890 tests passed, 5 skipped`.
- The first independent verifier review for
  `DEVNET-RUNNER-SMOKE-PREPARED-PAYLOAD-TXPOOL-SELECTION` returned `FAIL`
  because the runtime smoke report emitted txpool-backed prepared-payload JSON
  evidence, but `tests/cli-tests.lisp` only asserted the new connection counts.
- `tests/cli-tests.lisp` now asserts `preparedTxpoolPayloadId`,
  `engineGetPayloadV2TxpoolParentHash`,
  `engineGetPayloadV2TxpoolBlockNumber`,
  `engineGetPayloadV2TxpoolTransactionCount`,
  `engineGetPayloadV2TxpoolSelectedTransactionRaw`,
  `engineGetPayloadV2TxpoolSelectedTransactionHash`,
  `engineGetPayloadV2TxpoolSelectedStillPending`,
  `engineGetPayloadV2TxpoolNonSelectedBasefeeStillQueued`, and
  `engineGetPayloadV2TxpoolNonSelectedQueuedStillQueued` against the
  corresponding prepared payload and public txpool fields.
- After the JSON evidence assertions were added, the escalated
  `sbcl --script tests/run-tests.lisp` run passed with
  `890 tests passed, 5 skipped`.
- The second independent verifier review returned `PASS`: the verifier found
  the smoke report evidence and CLI JSON field assertions sufficient for the
  selected runner-boundary slice.
- Focused escalated standalone smoke for
  `DEVNET-RUNNER-SMOKE-PREPARED-PAYLOAD-TXPOOL-IMPORT` passed:
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --json`. Key report fields
  include `engineNewPayloadV2TxpoolImportStatus=VALID`,
  `engineForkchoiceUpdatedV2TxpoolImportStatus=VALID`,
  `txpoolImportTxpoolStatusPending=0x0`,
  `txpoolImportTxpoolStatusQueued=0x2`, and
  `txpoolImportSelectedStillPending=false`.
- A fresh escalated all-fixtures devnet smoke command passed after the suite
  head assertions were updated to expect the imported txpool payload as the
  restored canonical head:
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --json --all-fixtures ...`.
- Final pre-commit validation passed:
  `git diff --check` and `sbcl --script tests/run-tests.lisp`
  (`890 tests passed, 5 skipped`).
- Independent verifier review returned `PASS`. Residual risks: coverage is
  still the V2 Shanghai-style prepared-payload path; V3/V4 prepared-payload
  variants and same-sender replacement-cache churn remain follow-up scope.
- Focused direct Engine RPC coverage for
  `ENGINE-RPC-FORKCHOICE-UPDATED-V1-REFRESHES-TXPOOL-REPLACEMENT-PAYLOAD-ID`
  passed during the current run.
- `git diff --check` passed.
- The first sandbox `sbcl --script tests/run-tests.lisp` run failed in
  `PHASE-A-SMOKE-GATE-SCRIPT-CAN-INCLUDE-DEVNET-SUITE`, consistent with the
  local socket/devnet smoke-gate sandbox restriction.
- The escalated `sbcl --script tests/run-tests.lisp` run passed with
  `891 tests passed, 5 skipped`.
- Independent verifier review returned `PASS`. Residual risk: coverage is
  intentionally in-process and V1-only; the split public/Engine listener and
  V2 smoke boundary is documented as the next run.
- Focused escalated standalone smoke for
  `DEVNET-RUNNER-SMOKE-PREPARED-PAYLOAD-TXPOOL-REPLACEMENT` passed:
  `sbcl --script scripts/devnet-smoke-gate.lisp -- --json`. Key report fields
  include distinct `preparedTxpoolPayloadId` and
  `preparedReplacementTxpoolPayloadId`, replacement-only
  `engine_getPayloadV2` transaction evidence, replacement-only
  `txpool_contentFrom` sender/nonce visibility before import, and stable
  import/canonicalization evidence for the replacement transaction.
- `git diff --check` passed.
- The stale `BLOCKED_EXTERNAL` KZG run contract was incorrect for this
  checkout. The repository already had the local trusted setup source and Go
  backend material needed to finish the real verifier slice, so the loop
  consumed that pending contract as implementer work instead of emitting a new
  blocker.
- Real KZG proof verification is now repo-local and pinned through
  `tools/kzg-verifier/` plus `scripts/kzg-verifier.sh`. The helper vendors the
  required Go modules, embeds the trusted setup JSON, checks its SHA-256
  (`f8e44a31ebf0a6d0734dcb301b0716e2c77f3ae18ed0cab0870fbcc2ca55616f`), and
  exits nonzero on helper faults so infrastructure errors no longer collapse
  into false proof results.
- Focused KZG coverage passed after the helper changes:
  `KZG-GO-ETHEREUM-COMMAND-VERIFIER-REPLAYS-CANONICAL-VECTORS`,
  `BLOB-SIDECAR-FIELD-VALIDATION-REPLAYS-REAL-KZG-VECTOR`, and
  `EVM-CALL-KZG-POINT-EVALUATION-REPLAYS-REAL-KZG-VECTOR`.
- `git diff --check` passed, and independent verifier review returned `PASS`
  after confirming the helper no longer depends on ignored checkouts or
  machine-local absolute module-cache paths. Residual note: the helper still
  requires a visible local Go toolchain because it runs `go run -mod=vendor`,
  but that prerequisite is now explicit rather than hidden.
- The final escalated `sbcl --script tests/run-tests.lisp` run passed with
  `894 tests passed, 5 skipped`.

## Current Loop Migration

The old fixed heartbeat prompt is being replaced by a loop v2 process:

- fixed rules live in `docs/loop/runbook.md`;
- project memory lives in this file;
- validation requirements live in `docs/loop/validation.md`;
- one-run task contracts are generated from
  `docs/loop/next-run-template.md` into `docs/loop/next-run.md`.
- validation now uses explicit gate tiers so test-only regressions and docs-only
  loop changes do not pay the full-suite cost by default; full-suite runs are
  reserved for broad production-code, consensus, persistence, or process-boundary
  changes, plus a separate low-frequency verifier automation.

## Next Recommended Orchestrator Decision

The next highest-value repository slice is to reuse the same engine-only
listener coverage and prove the sibling hidden-without-KZG negative request
contract for `engine_getBlobsV2`. The best bounded follow-up is to send one
live non-KZG engine-only request for that method, require the same
disabled-path JSON-RPC `-32601` / `"Method not found"` envelope now proven
for `engine_getBlobsV1`, and record the result before widening into
`engine_getBlobsV3` or unrelated Phase B runner work.
