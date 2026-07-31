# Validation Commands

These commands are available when a change needs verification. During feature
development, run the smallest check that directly covers the changed behavior.
The full suite is for an explicit user request, release/CI work, or a genuinely
broad high-risk change; it is not a routine prerequisite for implementing a
feature.

Local SBCL builds and tests run inside Docker on macOS so compiler caches,
temporary artifacts, child processes, and loopback listeners remain isolated.

## Test Layers

```sh
make docker-test-unit
make docker-test-integration
make docker-test-e2e
make docker-test-all
```

- `unit` covers process-free domain behavior.
- `integration` covers persistence, sockets, fixture adapters, and the KZG CFFI
  verifier.
- `e2e` covers standalone CLI, restart, signals, and devnet processes.
- `all` composes every layer and is intentionally the most expensive option.

Focused selection is available through `DOCKER_TEST_ARGS`, for example:

```sh
make docker-test-unit DOCKER_TEST_ARGS="--match TRANSACTION"
```

Optional official fixtures use `ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT`. A
missing optional fixture root produces a skip and is not evidence that external
fixture validation passed.

The root alone selects nothing. The state-test and blockchain-replay cases also
need `ETHEREUM_LISP_PHASE_A_STATE_TEST_SELECTORS` and
`ETHEREUM_LISP_PHASE_A_BLOCKCHAIN_REPLAY_SELECTORS` (`auto` takes every case the
classifier finds), and without them they report the same skip they report with no
corpus at all — so a run can mount the whole corpus, execute zero vectors, and
still look like a pass. The Docker targets bind-mount the root and forward all
three when they are set. State-test auto-discovery defaults to London and
Shanghai; set `ETHEREUM_LISP_PHASE_A_STATE_TEST_FORKS` to a comma-separated
fork list such as `Cancun,Prague,Osaka` to opt into later-fork vectors.

What the pinned corpus cannot cover: EEST `v5.4.0` contains no `amsterdam/`
directory, and its Osaka vectors predate Amsterdam activation, so they carry
Prague post-state rules. Amsterdam execution is therefore pinned only by the
in-tree fork matrix and unit tests, not by fixtures anyone else wrote. Nothing
in this tree has been checked against a running reference client either; every
parity claim rests on source comparison against the versions named in
`docs/reference-map.md`.

`DOCKER_TEST_IMAGE_PREBUILT=1` runs the layers against an existing image instead
of rebuilding it. CI sets it because it builds the image with buildx against a
shared layer cache that a plain `docker build` would not reuse.

Verification should not expand into unrelated coverage work, documentation
maintenance, repeated baselines, or a second development objective. Report an
unrelated failure separately and continue the requested feature when it is safe
to do so.

## Historical proof-of-work scope

Pre-Merge blocks are validated rather than refused. The Merge boundary is taken
from the chain configuration instead of from a header's difficulty field, so a
header below that boundary is checked against the fork-specific
Frontier-through-Gray-Glacier difficulty formula and its Ethash seal is
verified. Ommer lists are checked against the two-ommer cap, the six-block depth
window, duplicate and canonical-ancestor rejection, and full header validation
of each ommer against the supplied recent ancestry; block and ommer rewards are
paid. The DAO fork's ten-block extra-data rule and its drain-list balance
transition are applied.

Seal verification runs through `*ethash-seal-verifier*`, which defaults to an
in-tree light backend: it reconstructs the dataset items a header touches from
an epoch cache rather than materializing the multi-gigabyte DAG. Keccak-512 and
Hashimoto are pinned against the official `ethereum/tests` proof-of-work vector
at commit `c67e485ff8b5be9abc8ad15345ec21aa22e290d9`. The hook is replaceable by
an accelerated backend, and validation fails closed when no backend is
configured rather than accepting an unverified seal. Verifying a long pre-Merge
range is slow in proportion to the epochs it spans, and there is no mining or
full-DAG path.

Genesis parsing retains historical fork fields because they are part of public
network configurations and the EIP-2124 fork-id schedule.
