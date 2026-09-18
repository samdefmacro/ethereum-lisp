# Section 5 pause and agent handoff — 2026-09-18

Continues `docs/sec5-pause-handoff-20260913.md`. Read that one first: its
pause boundary, branch pointers, and remote paths still describe the
deployment substrate, and this document only records what changed since.

## Pause boundary

Development was paused at `2026-09-18T03:06Z` (`2026-09-18T11:06+08:00`) at
the user's request, to hand the work to a different agent.

- branch: `sec5-public-bootstrap-sync`
- HEAD: `05c13ad55dd573ea075d0237b6478f4690ebcb0d`
- `origin/sec5-public-bootstrap-sync` points at the same revision; the
  checkout was clean before this handoff was added.
- `origin/main`: `81c6efdab2b5b2f5ca9d1b6e327173f7943eaa38`. The branch is 605
  commits ahead of it and zero behind. Section 5 is not complete, so the
  branch deliberately stays unmerged.
- every other local branch is already merged into `main`; only
  `sec5-public-bootstrap-sync` carries unmerged work.
- the development branch pointers pushed at the 2026-09-13 handoff
  (`parallel/*`, `section5/*`) are unchanged on `origin`.

## What changed since 2026-09-13

Twelve commits after the handoff itself, all pushed. Six are evidence
archives. The five behavioral ones, oldest first:

- `c0cce53d` — defer proved subtrees regardless of frontier
  (evidence `docs/evidence/sec5-c0cce53d-heal-deferral-frontier.txt`);
- `83c5e3ce` — apply one pool deadline to every request kind
  (evidence `docs/evidence/sec5-83c5e3ce-pool-deadline.txt`);
- `646da589` — answer remote height from metadata, not block copies;
- `5c8a39c0` — trust closed storage subtrees during healing, advancing the
  closure epoch from five to six
  (evidence `docs/evidence/sec5-5c8a39c0-storage-closure-epoch.txt`);
- `05c13ad5` — heal an oversized storage plan in segments (HEAD, no evidence
  archived; see below).

`60d8050d` is operational only: `scripts/hoodi-live-gate.sh` now uploads with
`scp -O`, because the remote host's sftp-server closes immediately.

The arc these describe is one investigation. Closure epoch six made the
storage skip fire on the live chain — 6,822,712 skipped subtrees against
1,058,816 processed nodes — and healing still did not converge, because
`knownIncompleteNodes` (1,058,419) tracked `processedNodes` almost exactly:
the healer was walking marked account nodes.
`docs/evidence/sec5-heal-stale-marker-trace.txt` is the diagnosis that
followed. It measured where those markers come from (a completed flat import
leaves stale markers on complete content, proportional to page count and not
to any bound being exceeded), rejected four hypotheses with
measurements, and showed that the 8,192 deferred-storage bound cannot simply
be raised: one storage heal work encodes to 72 bytes, so the four-megabyte
checkpoint admits about 58,000, three orders of magnitude below a live plan
naming millions of storage roots. Its conclusion was that the fallback, not
the bound, is the defect. `05c13ad5` implements exactly that conclusion.

## The one item in flight

`05c13ad5` turns `+snap-sync-deferred-storage-max-works+` into the parameter
`*snap-sync-deferred-storage-max-works*`, adds
`SNAP-SYNC-DEFERRED-STORAGE-SEGMENT` plus a durable
`snap-heal-storage-plan-cursor-v1:` record, and makes the healer advance that
cursor across consecutive segments instead of abandoning an oversized plan for
a state-root walk. Completion waits until the plan is exhausted. Two tests
come with it: `snap-heal-storage-plan-is-healed-in-consecutive-segments`
(integration — same plan healed whole and in segments of two, requiring the
same completion and the same durable nodes, and no cursor left behind) and
`snap-heal-storage-plan-segment-resumes-past-its-cursor` (unit — the loader
alone delivers every root exactly once across segments).

**No evidence file is archived for this revision, and that is the gap.** The
stale-marker trace asked for a RED regression proving that a segmented run
reports completion only after the final segment, because this changes the same
completion semantics that produced the `03263d2f` and `b23c7d57` false
completions. The tests above exist; no recorded RED control for them does.
Also missing for `05c13ad5`: an archived cold-all record, a runtime image and
`runtime-smoke` result, and any live run. No
`ethereum-lisp-runtime-sec5-05c13ad5-*` artifact exists under `/private/tmp`.

A cold-all was run at this pause on the exact HEAD revision,
`cl-workbench validation run cold-all`, exit 0:

    1403 tests passed, 3 skipped.   (unit)
    572 tests passed, 9 skipped.    (integration)
    34 tests passed.                (e2e)
    31 tests passed.                (e2e)

No `not ok` line and no compile warning under `/workspace/src`. Against the
`5c8a39c0` record that is one more unit and one more integration test, which
is exactly the two tests `05c13ad5` adds.

That is a green-tree check, not Section 5 evidence. The next agent still owes
`05c13ad5` its evidence file in the format the neighbouring
`docs/evidence/sec5-*.txt` files use.

## Problems carried forward

1. **The account side of closure is unsolved.** Storage nodes may be skipped
   on presence under epoch six; account nodes may not, because an unmarked
   account subtree may still name code or storage that is not durable. The
   preserved live store holds only 537 account dependency proofs and 12,151
   account subtree proofs, so almost no account subtree can be skipped by
   proof either. Segmenting the storage plan lets healing start from deferred
   storage roots and skip the account walk; whether that is enough on the live
   chain is unmeasured.
2. **A reproducible SBCL memory fault on shutdown**, seen on both `0c6b51bf`
   and `646da589`, remains unexplained.
3. **Remote disk is the binding operational constraint.** At the last
   recorded run the data filesystem was at 87% with 90 GiB free, holding
   preserved datadirs `0c6b51bf` (52 GiB), `646da589` (51 GiB), `5c8a39c0`
   (~54 GiB) and the geth control (98 GiB). Plan disk before starting another
   fresh-datadir run.

## Environment at the pause

Verified in this session:

- `cl-workbench doctor --strict` passed; dev image
  `ethereum-lisp-dev:go1.24-bookworm-b8aaea74d911` present and ownership
  verified; dev container `ethereum-lisp-dev-46e5d9739ddd` stopped.
- A `bitcoin-lisp` container from another project is running on this machine.
  It is not ours; do not stop it. The shared-machine rules in `AGENTS.md` and
  `CLAUDE.md` apply.
- Worktrees: this checkout clean at `05c13ad5`;
  `/Users/sen/.codex/worktrees/8fd5/ethereum-lisp` clean, detached at
  `81c6efda`; `/Users/sen/.codex/worktrees/afc4/ethereum-lisp` on
  `codex/create-precondition-soft-failures` (`972d7d7e`, already merged into
  `main`) with uncommitted edits to `src/runtime/evm/interpreter/create.lisp`,
  `tests/evm-create-tests.lisp` and `tests/execution-block-basic-tests.lisp`.
  That is a different agent's unfinished CREATE-gas work, unrelated to
  Section 5, and it was deliberately left untouched.
- One stash survives: `stash@{0}`, "wave1 shared-checkout leftovers" on
  `feat/nonvacuous-conformance`. It predates this work.

**Not verified in this session: the remote Hoodi host.** No remote command was
run. The last recorded live state is in
`docs/evidence/sec5-5c8a39c0-storage-closure-epoch.txt`, where container
`hoodi-el-sec5-5c8a39c0` was stopped cleanly on 2026-09-15 with its datadir
preserved. Treat that as history, not as the current state. Establish the
truth with the read-only broker actions before doing anything else:
`scripts/hoodi-live-gate.sh inspect`, `status`, `logs`, `complete`. Mutating
actions (`upload`, `load`, `start`, `upgrade`, `restart`) require
`HOODI_GATE_ALLOW_MUTATION=1` and, per the 2026-09-13 handoff, a newly
generated and independently reviewed authorization request — the old one
(`20260913T151406Z-sec5-13cebe2a-hoodi-upgrade-r1`) was cancelled and its
preconditions are stale.

## Remaining Section 5 acceptance gates

`docs/gap-analysis/public-testnet-readiness-plan.md` (lines 1320–1330) is the
authority. Section 5 completion requires one continuous fresh-datadir run
that records `peer.snap.target_completed`, finishes the healer with
`completed=true` and an empty frontier, returns `eth_syncing=false`, and
executes the canonical EL head through the CL-authorized target. The same
revision must pass the selected current-fork EEST/fixture and required Hive
suites with zero unexpected skips before its seven-day shadow comparison can
count; the fourteen-day validator soak starts only after that shadow gate
passes.

The prerequisites the plan already marks closed — `tests@v20.0.2`, Hive
rpc-compat 234/234, the pinned Engine/auth zero-failure gate, and the required
Hive devp2p discv4/eth/snap surface at 47/47 — were closed for specific
revisions. Closed there does not mean closed for `05c13ad5`.

## Where to start

1. Read `PROJECT.md`, `AGENTS.md`, `docs/validation.md`,
   `docs/gap-analysis/public-testnet-readiness-plan.md`, the 2026-09-13
   handoff, and `docs/evidence/sec5-heal-stale-marker-trace.txt`. The trace is
   the one that explains why the current work is shaped the way it is.
2. Run `cl-workbench doctor --strict` before the first application tooling
   operation.
3. Give `05c13ad5` its evidence: a RED control for the segmentation
   regressions, cold-all, a `linux/amd64` runtime image, and `runtime-smoke`.
4. Only then consider a live run, through a newly reviewed request.

Do not resume the stopped Section 5 supervisor or either paused cron job
without the user asking for it.
