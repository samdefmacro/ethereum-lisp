FROM golang:1.24-bookworm@sha256:1a6d4452c65dea36aac2e2d606b01b4a029ec90cc1ae53890540ce6173ea77ac

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        make \
        procps \
        sbcl \
        cl-swank \
        curl \
        libsecp256k1-dev \
        libgflags-dev \
        libsnappy-dev \
        zlib1g-dev \
        libbz2-dev \
        liblz4-dev \
        libzstd-dev \
        liburing-dev \
        build-essential \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /private/tmp \
    && chmod 1777 /private/tmp

# RocksDB is vendored as a checksummed release archive so this layer can be
# rebuilt with Docker networking disabled. Keep the version synchronized with
# docs/storage-substrate.md and the CFFI backend.
COPY tools/rocksdb/rocksdb-11.1.2.tar.gz /opt/rocksdb-11.1.2.tar.gz
COPY tools/rocksdb/io-uring-kernel-compat.patch /opt/io-uring-kernel-compat.patch
RUN --network=none \
    echo "d5e78b69e0fb2960576fd5f21c9f3d1a02f635da61159b01942ff285e891c9c0  /opt/rocksdb-11.1.2.tar.gz" \
        | sha256sum -c - \
    && mkdir /opt/rocksdb \
    && tar -xzf /opt/rocksdb-11.1.2.tar.gz -C /opt/rocksdb --strip-components=1 \
    && patch -d /opt/rocksdb -p1 --fuzz=0 --input=/opt/io-uring-kernel-compat.patch \
    && make -C /opt/rocksdb -j2 shared_lib PORTABLE=1 DISABLE_WARNING_AS_ERROR=1 ROCKSDB_USE_IO_URING=1 \
    && cp -a /opt/rocksdb/librocksdb.so* /usr/local/lib/ \
    && readelf -d /usr/local/lib/librocksdb.so \
        | grep -F 'Shared library: [liburing.so.2]' \
    && ldconfig \
    && rm -rf /opt/rocksdb /opt/rocksdb-11.1.2.tar.gz \
        /opt/io-uring-kernel-compat.patch

COPY tools/rocksdb/io-uring-probe.c /opt/io-uring-probe.c
RUN mkdir -p /usr/local/libexec \
    && gcc -O2 -Wall -Wextra -Werror /opt/io-uring-probe.c \
        -o /usr/local/libexec/ethereum-lisp-io-uring-probe -luring \
    && rm /opt/io-uring-probe.c

# Every downloaded input from here on is checked against
# tools/build-inputs/inputs.lock before it is loaded, executed or compiled
# (plan section 10), exactly as in Dockerfile.runtime. Copied after the
# RocksDB layer so a lock-file change does not rebuild RocksDB.
COPY tools/build-inputs/inputs.lock tools/build-inputs/verify-inputs.sh /opt/build-inputs/

# SBCL came from the first apt layer; hold it to the pinned Debian version and
# per-architecture file digest here, after the expensive layers, so the check
# fails closed on drift without invalidating their cache.
RUN /opt/build-inputs/verify-inputs.sh deb sbcl sbcl

# Build c-kzg-4844 (with its bundled blst) as a shared library for the KZG CFFI
# binding, and stage its trusted setup. Cloned by tag and held to the pinned
# commits and tree digests before anything builds; the build has network,
# the runtime (--network none) only dlopens the result. shim.c wraps c-kzg in a
# stable byte-pointer ABI (see tools/ckzg-ffi/shim.c).
# c-kzg-4844 bundles blst as a submodule, so one clone provides both the KZG
# library and blst for the EIP-2537 BLS12-381 binding (tools/bls-ffi/shim.c).
COPY tools/ckzg-ffi/shim.c /opt/ckzg-shim.c
COPY tools/bls-ffi/shim.c /opt/bls-shim.c
RUN git clone --depth 1 --branch v2.1.1 --recurse-submodules \
        https://github.com/ethereum/c-kzg-4844.git /opt/c-kzg \
    && /opt/build-inputs/verify-inputs.sh \
        git c-kzg-4844 /opt/c-kzg \
        git blst /opt/c-kzg/blst \
    && cd /opt/c-kzg/blst && ./build.sh -fPIC \
    && cd /opt/c-kzg \
    && gcc -shared -fPIC -O2 -o /usr/local/lib/libethckzg.so \
        /opt/ckzg-shim.c src/ckzg.c -Isrc -Iblst/bindings blst/libblst.a \
    && gcc -shared -fPIC -O2 -o /usr/local/lib/libethbls.so \
        /opt/bls-shim.c -Iblst/bindings blst/libblst.a \
    && ldconfig \
    && mkdir -p /usr/local/share/eth-kzg \
    && cp src/trusted_setup.txt /usr/local/share/eth-kzg/trusted_setup.txt \
    && rm -rf /opt/c-kzg /opt/ckzg-shim.c /opt/bls-shim.c

# Quicklisp, for build-time Lisp dependencies fetched here so that everything
# still runs in a container with --network none:
#   - ironclad: the runtime crypto backend (Keccak/SHA-256/RIPEMD-160);
#   - cffi: the FFI layer for the libsecp256k1 binding;
#   - mgl-pax/full: used only by scripts/docs-check.lisp.
# A recent Ironclad from Quicklisp is markedly faster than Debian's cl-ironclad
# (0.57), so the Debian package is deliberately NOT installed.
#
# Nothing downloaded runs before it is verified (see Dockerfile.runtime for the
# same sequence): the pinned client over HTTPS, checked, laid out as
# quicklisp-quickstart:install would; then the pinned dist, and only a DOWNLOAD
# of the releases QUICKLOAD would load; every index and archive checked; and
# only then the QUICKLOADs, with networking disabled so they cannot fetch
# anything the check did not see.
RUN mkdir -p /root/quicklisp/dists \
    && curl -fsSL --proto '=https' --tlsv1.2 \
        https://beta.quicklisp.org/client/2021-02-13/quicklisp.tar -o /tmp/quicklisp.tar \
    && curl -fsSL --proto '=https' --tlsv1.2 \
        https://beta.quicklisp.org/client/2021-02-11/setup.lisp -o /root/quicklisp/setup.lisp \
    && curl -fsSL --proto '=https' --tlsv1.2 \
        https://beta.quicklisp.org/asdf/3.2.1/asdf.lisp -o /root/quicklisp/asdf.lisp \
    && /opt/build-inputs/verify-inputs.sh \
        file quicklisp-client /tmp/quicklisp.tar \
        file quicklisp-setup /root/quicklisp/setup.lisp \
        file quicklisp-asdf /root/quicklisp/asdf.lisp \
    && tar -xf /tmp/quicklisp.tar -C /root/quicklisp \
    && rm /tmp/quicklisp.tar \
    && sbcl --non-interactive \
            --load /root/quicklisp/setup.lisp \
            --eval '(ql-dist:install-dist "http://beta.quicklisp.org/dist/quicklisp/2026-01-01/distinfo.txt" :prompt nil)' \
            --eval '(dolist (system (list "ironclad" "cffi" "mgl-pax/full")) (map nil (function ql-dist:ensure-installed) (ql::quicklisp-releases (ql::compute-load-strategy system))))' \
    && /opt/build-inputs/verify-inputs.sh quicklisp-dist /root/quicklisp/dists/quicklisp
RUN --network=none sbcl --non-interactive \
            --load /root/quicklisp/setup.lisp \
            --eval '(ql:quickload :ironclad :silent t)' \
            --eval '(ql:quickload :cffi :silent t)' \
            --eval '(ql:quickload "mgl-pax/full" :silent t)'

# The cold-test path loads systems through plain ASDF and never loads Quicklisp,
# so expose the Quicklisp-fetched sources (ironclad + its deps) to ASDF. The
# trailing empty entry keeps ASDF's default registry (e.g. cl-swank) as well.
ENV CL_SOURCE_REGISTRY=/root/quicklisp/dists/quicklisp/software//:

WORKDIR /workspace

# Marker consumed by fail-closed project wrappers. Keep it after dependency
# layers so policy-only changes do not invalidate the expensive native build.
ENV ETHEREUM_LISP_CONTAINER_RUNTIME=1
