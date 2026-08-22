# Runtime security profiles

`docker-26.1.4-io-uring-seccomp.json` starts from Moby's Apache-2.0 licensed
[`v26.1.4/profiles/seccomp/default.json`](https://github.com/moby/moby/blob/v26.1.4/profiles/seccomp/default.json),
whose upstream SHA-256 is
`9c1025c88ccaa517b648da571961838744ea2137f176bfe6a48b21294cae9c76`.
Its only semantic delta is to add `io_uring_enter`, `io_uring_register`, and
`io_uring_setup` to the first `SCMP_ACT_ALLOW` syscall list.

The Hoodi live-gate broker pins the derived file's SHA-256, refuses a Docker
server version other than 26.1.4, uploads the profile with the runtime artifact,
and keeps the container non-root, read-only, capability-free, and under
`no-new-privileges`. Do not replace this profile with `seccomp=unconfined`.
Before a live cutover, the broker executes the runtime image's bounded
`ethereum-lisp-io-uring-probe` without a network and requires creation of the
same 256-entry ring used by RocksDB.
