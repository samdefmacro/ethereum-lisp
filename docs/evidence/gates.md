# Gate results by revision

One row per revision that has a gate record: the amd64 runtime artifact and
its smoke, the pinned current-fork EEST gates, the pinned Hive suites, and the
Hoodi live run. Every value is copied from the record named for that revision
in [Revisions and source records](#revisions-and-source-records); "—" means
the record does not say. Rows run oldest first by the record's own UTC date.

Pins behind the columns, unchanged across every row: EEST `tests@v20.0.2`
(archive sha256 `1280540950a4c3470a421416b6f35458a9b635827265c29e5aef1ae839ae1788`,
upstream `abbe05777ab83fb94ce18c425daaa7ab79e779c1`); Hive
`dde4f59d04ff0ff8b6585670b08cea1b6c8ab65c`; Execution APIs
`e5d1bb60e6c064e4b15080da07b4370d0baadf92`; devp2p geth
`101035a1049c7dc468bfe973478b579d9883d7b6`. Hive counts are passed/selected.

- **EEST "8/8"**: the three non-vacuity manifest gates and the five fixture
  executors each passed one top-level test, with zero unexpected skips.
  "report" rows are `scripts/conformance-report.sh` outputs: they carry the
  count manifest, not per-gate results.
- **Hive engine 401/403** (92982442, d203fee6, aee866f7): one of the two
  failures is always an "Invalid Missing Ancestor Syncing ReOrg ... Invalid P9
  (Paris)" variant. That is the pinned Hive setup race
  [ethereum/hive#1351](https://github.com/ethereum/hive/issues/1351): the
  simulator's own geth builds the block to be corrupted with no transaction in
  it, and the test aborts before the client is asked. It is an expected
  failure (sec5-engine-regressions-d203fee6.txt,
  sec5-engine-regressions-aee866f7.txt). The other failure, "Blob Transaction
  Ordering, Multiple Clients (Cancun)", was a client defect each time.
- **Hive devp2p 47/48**: the one failure is discv5. The client does not
  implement discv5, and its Hive adapter refuses `HIVE_DISCV5` fail-closed.
  The readiness plan's required devp2p surface is discv4 16 + eth 25 + snap 6
  = 47/47.

| revision | date (UTC) | amd64 runtime tar sha256 + smoke | EEST v20.0.2 | Hive rpc-compat | Hive engine | Hive devp2p | Hoodi | notes |
|---|---|---|---|---|---|---|---|---|
| bb8fb8b3 | 2026-09-01 | — | report: selected 15,393 state / 11,382 replay / 10,257 RLP; 0 unexpected skips | — | — | — | — | first current-fork report; the gate fails on unexpected skips |
| 92982442 | 2026-09-01 | — (image id only) | report: selected Prague state 4,222 / Shanghai replay 2,093 / RLP 2,073; 0 unexpected skips | 125/234 (inventory discovery; confirmation run 125/234) | 401/403 | — | — | first exact-pin run; the inventory is 234, not 243; engine failures are hive#1351 and blob ordering (client) |
| d9e0e2dd | 2026-09-10 | — | 5 executors pass; the manifests came from an aggregate that was cut off (exit 143) | — | — | — | healer completed=T with empty frontier, then exited on a missing persisted trie descendant | marker-only storage closure distrusted; Hoodi outcome from the 694667f9 record (r27) |
| 6e3e9b1d | 2026-09-11 | `8e2d9f085e37` pass | — | 234/234 | — | — | — | geth default gas ceiling; closes the pinned rpc-compat gate (r19) |
| 694667f9 | 2026-09-11 | `d57ef9bbbdc7` — | — | — | 403/403 (r29) | — | — | blob proofs from cell sidecars; r25 399, r27 400, r28 401 moving connection resets under a 4 GiB runner; r29 at 8 GiB closes the Engine/auth gate |
| 0c6b51bf | 2026-09-11 | — | 8/8 | — | — | — | run r1 from 2026-09-11T15:51Z: still healing at 2026-09-13, frontier growing, block 0x0 | closure proofs wait for descendants; Hoodi outcome from the 13cebe2a / 16fe6962 records |
| 7b3e9d35 | 2026-09-12 | `84111e9e69e7` pass | — | — | — | — (artifacts for a rerun) | — | uploaded-genesis fork schedule, discv5 refusal, pinned devp2p geth |
| a6ce1c1c | 2026-09-12 | `a0a8033b75f9` pass | — | — | — | — (artifacts for a rerun) | — | discv4 expiration, compressed Disconnect, eth/70 receipt chunking |
| 4097bbd4 | 2026-09-12 | `464e330346ee` pass | — | — | — | r34 and r35 stopped before Hive (checksum transcription, image-ID comparator) | — | SNAP serving: empty bytecode, TrieNodes cardinality, slim AccountRange |
| f79f5b2e | 2026-09-12 | `4e576d4cfc06` — | — | — | — | r39: 30 of 36 enumerated passed, 2 h timeout, snap not reached | — | txpool account slots; r40 at 48e351a0 refused (disk below the 12 GiB precondition) |
| 81446d47 | 2026-09-12 | — | report: manifests identical to bb8fb8b3; 0 unexpected skips | — | — | — | — | exact current-fork rerun (docs commit) |
| e96a5cc8 | 2026-09-12 | `0aa4724119b1` pass | — | — | — | — | — | productive-healer repair and follow-ups; runtime tree identical to 81446d47 |
| c93389e7 | 2026-09-12 | `5b3c462575f9` pass | — | — | — | — | — | pooled announcement metadata and BlobViolations (8286eb7f) |
| 4cd40480 | 2026-09-12 | `338188a67dc8` pass | — | — | — | — | — | bad blob peers and invalid-Cells regression |
| dba597c9 | 2026-09-12 | `c68240d8c51c` pass | — | — | — | — | — | pinned-geth tx/blob regressions through TestGetCells |
| 970a04b0 | 2026-09-12 | `c22b41e3bb9e` pass | — | — | — | — | — | SNAP account byte-target record (docs commit) |
| b147ade6 | 2026-09-13 | `527924597b5e` pass | — | — | — | r43 stopped before Hive (compared a non-portable image ID) | — | ETH/72 pooled blob encoding aligned with geth |
| 03957929 | 2026-09-13 | `69f09e6deb0e` — | 8/8 | — | — | 47/48 (r54) | — | blob announcement network size; closes the required devp2p surface |
| 16fe6962 | 2026-09-13 | `99fc93388c1f` pass | — | — | — | — | — | SNAP target-tail completion guard (functional 40be2940) |
| f8aa7575 | 2026-09-13 | `5b0cf180dbed` pass | — | — | — | — | — | completed-SNAP scheduling (docs commit) |
| 13cebe2a | 2026-09-13 | `e696de80af5e` pass | — | — | — | — | — | superseded targets cleared on publication |
| a5039c3a | 2026-09-18 | `d9f859c3ba76` pass | — | — | — | — | — | storage-plan segmentation and range-plan promotion streaming merged |
| 3305307d | 2026-09-18 | `73a88be3d217` pass | 8/8 | not run | not run | not run | heal stalled for 4 days: promotedSubtrees 0, frontier growing, block 0x0 | live-gate fault reporting, iterator closes; Hoodi outcome from sec5-3305307d-hoodi-stall.txt |
| 75b0b7a7 | 2026-09-22 | `9de615d24fe3` pass | — | — | — | — | epoch-7 heal could not finish inside a pivot lifetime (read width 1, stale storage markers) | closure epoch seven |
| cceee42f | 2026-09-22 | `68510430ed37` pass | — | — | — | — | range phase dead: KV multi-get > 4096 keys | storage-root closure at cursor completion; heal read width |
| aac5f762 | 2026-09-23 | `132c9b023d3d` pass | — | — | — | — | heal converged 34 s; exit 1 on the batch importer's storage overlay | milestone: first live heal convergence |
| 8e95b990 | 2026-09-23 | `80a3bafb4e86` — | — | — | — | — | heal converged 36 s; exit 1 on a peer socket error, restarted; `complete` exit 1 (eth_syncing not false) | pending storage overlay; tar hash from the completion draft |
| d203fee6 | 2026-09-23 | `04b0c0f7397d` pass | 8/8 (at 9f8f336e, src identical) | 234/234 | 401/403 | 47/48 | heal converged 35 s, `complete` exit 0 | milestone: first `complete` exit 0 and first full Hive x3; blob ordering fixed in 747ca812 |
| aee866f7 | 2026-09-23 | `ab52095f1204` pass | 8/8 (at c04d7ab4, src identical) | 234/234 | 401/403 | 47/48 | heal converged 35 s, `complete` exit 0 | second release candidate; blob ordering fixed in b5161312 |
| 880319df | 2026-09-23 | `f5745af6372b` pass | — | — | — | — | — | third release candidate: Engine guard deferral, GC/guard telemetry |
| b5161312 | 2026-09-23 | `53b77bf3597b` pass | 8/8 (at 37e34068, src identical) | — | — | — | heal converged; Engine 30 s timeouts after 208 VALID payloads; `complete` exit 1; OOM-killed at 12 GiB | milestone R4: its telemetry drove the 2026-09-24 fleet |
| 709616fc | 2026-09-24 | `f1e023e09392` pass | — | — | — | — | — | Section 10 signed release set; release-verify PASS; src identical to a07c912e |
| 591f700e | 2026-09-24 | — | 8/8 | — | — | — | — | wave-1 merges (886afd05) plus a test-stub fix; latest EEST record |
| 04a3aff4 | 2026-09-24 | f192550ac742 + smoke PASS (SBOM, provenance, SHA256SUMS exported) | 8/8 | — | — | — | upgrade on datadir-b5161312 (12 GiB): forward sync refused at 3684027 (persisted INVALID), pivot rebased to 3684866, healed from retained state in ~90 s, tail 3684877-3684908 at ~0.7 s/block, RSS 788 MB; exit 1 at 05:00:49Z on "tail block 3684909 returned SYNCING" | wave 1 + F fcu-canonical-cost + N peer-session-holds; records sec5-b5161312-hoodi-run.txt (addenda), sec5-snap-tail-syncing.txt |
| cbfe2c63 | 2026-09-24 | — | 8/8 | — | — | — | — | evm-throughput branch (P2) on 886afd05: manifest lines identical to b5161312; merged as 5fee5219 |
| 70409b12 | 2026-09-24 | — | 8/8 | — | — | — | — | hoodi-gas-mismatch branch (X) on 04a3aff4: lazy-state slot lost on revert (Hoodi 3684027) and persisted INVALID verdicts; record sec5-hoodi-gas-mismatch.txt |

## Revisions and source records

Records marked † were deleted in `f0136810`, those marked ‡ in `f9100e98`. Read
one with
`git show f0136810^:docs/evidence/<file>` or
`git show f9100e98^:docs/evidence/<file>`.

| revision | full revision | source records |
|---|---|---|
| bb8fb8b3 | `bb8fb8b3bddb621aff7e67895d2b56f091bac510` | sec5-bb8fb8b3-eest-v20.0.2.txt † |
| 92982442 | `92982442f6a72e3bc73fa5e7487d537afdf51ea9` | sec5-92982442-eest-v20.0.2.txt †, sec5-92982442-hive-rpc-inventory.txt ‡, sec5-92982442-hive-engine.txt ‡ |
| d9e0e2dd | `d9e0e2dd74ced0baddc63a0e43881c53be302df6` | sec5-d9e0e2dd-eest-v20.0.2.txt ‡, sec5-694667f9-hive-engine-r25-r26.txt ‡ (Hoodi) |
| 6e3e9b1d | `6e3e9b1ddd3c890c98db04d2bd5f367ce2300bad` | sec5-6e3e9b1d-hive-rpc-compat.txt ‡ |
| 694667f9 | `694667f95727430baef2aaceec24c91c2c46bd91` | sec5-694667f9-hive-engine-r25-r26.txt ‡ |
| 0c6b51bf | `0c6b51bf6ea4852ddf2baf47147ce0ab24bbf4ae` | sec5-0c6b51bf-eest-v20.0.2.txt ‡, sec5-13cebe2a-amd64-runtime.txt † and sec5-16fe6962-amd64-runtime.txt ‡ (Hoodi) |
| 7b3e9d35 | `7b3e9d3590a774d37db32faa9400f323d6c1c3f0` | sec5-7b3e9d35-amd64-artifacts.txt ‡ |
| a6ce1c1c | `a6ce1c1cf53b1eb140f9a1b875f574ca45add82f` | sec5-a6ce1c1c-amd64-artifacts.txt † |
| 4097bbd4 | `4097bbd40843f76fbc8c0c402e39f85cce6708e6` | sec5-4097bbd4-amd64-artifacts.txt ‡ |
| f79f5b2e | `f79f5b2e8521fb6cb2ee20744572ff753e996a3e` | sec5-f79f5b2e-hive-devp2p-r39.txt ‡ |
| 81446d47 | `81446d476c9bb36db745cda202052cb61714ffb7` | sec5-81446d47-eest-v20.0.2.txt ‡ |
| e96a5cc8 | `e96a5cc8908214f7d769f41c959a691fa6517b89` | sec5-e96a5cc8-amd64-runtime.txt ‡ |
| c93389e7 | `c93389e762b9a4e32f2cbb0cf86ed2be5b892453` | sec5-c93389e7-amd64-runtime.txt ‡ |
| 4cd40480 | `4cd40480a2e30ba0b451bd9a9cb14a66bd738b80` | sec5-4cd40480-amd64-runtime.txt ‡ |
| dba597c9 | `dba597c98cb5e974fde2c8d2ba26ffe885bde0b6` | sec5-dba597c9-amd64-runtime.txt ‡ |
| 970a04b0 | `970a04b06c85b0e5f733103782da072821250829` | sec5-970a04b0-amd64-runtime.txt ‡ |
| b147ade6 | `b147ade6f2b506f67a86ec54cc82a9722c38789f` | sec5-b147ade6-amd64-runtime.txt ‡ |
| 03957929 | `0395792914fdcda41cf76c43ae292f261315f0d5` | sec5-03957929-eest-v20.0.2.txt ‡, sec5-03957929-hive-devp2p-r54.txt ‡ |
| 16fe6962 | `16fe6962837be612281e2659aa91ad100f85d9c1` | sec5-16fe6962-amd64-runtime.txt ‡ |
| f8aa7575 | `f8aa75752468d290fe1426900dbb488d9b106b54` | sec5-f8aa7575-amd64-runtime.txt ‡ |
| 13cebe2a | `13cebe2a06f65fde4bd827a1e280aa1210854c2a` | sec5-13cebe2a-amd64-runtime.txt † |
| a5039c3a | `a5039c3a8fff7ab224b107f3261729328df24e2a` | sec5-a5039c3a-amd64-runtime.txt † |
| 3305307d | `3305307d02918d797ad0037a93092451f0ab2b61` | sec5-3305307d-amd64-runtime.txt †, sec5-3305307d-eest-v20.0.2.txt ‡, sec5-3305307d-hive-rpc-compat.txt †, sec5-3305307d-hive-engine-auth.txt ‡, sec5-3305307d-hive-devp2p.txt †, sec5-3305307d-hoodi-start.txt ‡, sec5-3305307d-hoodi-stall.txt |
| 75b0b7a7 | `75b0b7a7554810274c3416da327e8aea7ed7fcb4` | sec5-75b0b7a7-amd64-runtime.txt †, sec5-75b0b7a7-hoodi-start.txt †, sec5-75b0b7a7-hoodi-heal.txt † |
| cceee42f | `cceee42f1631f235559bb19f67fd841ab3b1b4b5` | sec5-cceee42f-amd64-runtime.txt †, sec5-cceee42f-hoodi-run.txt † |
| aac5f762 | `aac5f762e0fe8b0c171b44375c0d9cf695727b94` | sec5-aac5f762-amd64-runtime.txt, sec5-aac5f762-hoodi-run.txt |
| 8e95b990 | `8e95b9904447b4cee9aac7aa88d92963d17db4c6` | sec5-8e95b990-hoodi-run.txt ‡, sec5-8e95b990-hoodi-complete.txt (draft), sec5-simulate-burndown-8e95b990.txt † |
| d203fee6 | `d203fee694ab44a362cc669a7f95e9e542acb85d` | sec5-d203fee6-amd64-runtime.txt, sec5-d203fee6-eest-v20.0.2.txt, sec5-d203fee6-hive-rpc-compat.txt, sec5-d203fee6-hive-engine.txt, sec5-d203fee6-hive-devp2p.txt, sec5-d203fee6-hoodi-complete.txt |
| aee866f7 | `aee866f7c7527f8da9f6e08a2311401006771eea` | sec5-aee866f7-amd64-runtime.txt †, sec5-aee866f7-eest-v20.0.2.txt †, sec5-aee866f7-hive.txt †, sec5-aee866f7-hoodi-complete.txt † |
| 880319df | `880319df5756fa0c591765fc4d998b88b8c9699e` | sec5-880319df-amd64-runtime.txt † |
| b5161312 | `b51613129ad17a6ef22513e06a80abda41a6dd08` | sec5-b5161312-amd64-runtime.txt, sec5-b5161312-eest-v20.0.2.txt, sec5-b5161312-hoodi-run.txt |
| 709616fc | `709616fc386d7abd0d8084e6bbd311a42c075a2a` | sec10-709616fc-amd64-runtime.txt ‡ |
| 591f700e | `591f700eb14346251d3b0f51e0a62b4d3e7bdcf0` | sec5-591f700e-eest-v20.0.2.txt |
| 04a3aff4 | `04a3aff4f1bf6e68856131e641e9ddcedeb3f6fa` | coordinator run logs (scratchpad eest-04a3aff4, r5b-runtime-*.log, r5b-gate-upgrade2.log); sec5-b5161312-hoodi-run.txt addendum 2 |
| cbfe2c63 | `cbfe2c633129d644b020e43cbdde0f9e52134296` | sec5-evm-throughput.txt |
| 70409b12 | `70409b12184b5577da44e158d5d819c5d533183d` | sec5-hoodi-gas-mismatch.txt |

Full revisions that the records give only in short form (d203fee6, aee866f7,
880319df, b5161312) were resolved with `git rev-parse` on this repository.
