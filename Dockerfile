FROM golang:1.24-bookworm

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
        build-essential \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /private/tmp \
    && chmod 1777 /private/tmp

# Build c-kzg-4844 (with its bundled blst) as a shared library for the KZG CFFI
# binding, and stage its trusted setup. Pinned to a tag; the build has network,
# the runtime (--network none) only dlopens the result. shim.c wraps c-kzg in a
# stable byte-pointer ABI (see tools/ckzg-ffi/shim.c).
# c-kzg-4844 bundles blst as a submodule, so one clone provides both the KZG
# library and blst for the EIP-2537 BLS12-381 binding (tools/bls-ffi/shim.c).
COPY tools/ckzg-ffi/shim.c /opt/ckzg-shim.c
COPY tools/bls-ffi/shim.c /opt/bls-shim.c
RUN git clone --depth 1 --branch v2.1.1 --recurse-submodules \
        https://github.com/ethereum/c-kzg-4844.git /opt/c-kzg \
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
RUN curl -fsSL https://beta.quicklisp.org/quicklisp.lisp -o /tmp/quicklisp.lisp \
    && sbcl --non-interactive \
            --load /tmp/quicklisp.lisp \
            --eval '(quicklisp-quickstart:install)' \
            --eval '(ql-dist:install-dist "http://beta.quicklisp.org/dist/quicklisp/2026-01-01/distinfo.txt" :replace t :prompt nil)' \
            --eval '(ql:quickload :ironclad :silent t)' \
            --eval '(ql:quickload :cffi :silent t)' \
            --eval '(ql:quickload "mgl-pax/full" :silent t)' \
    && rm -f /tmp/quicklisp.lisp

# The cold-test path loads systems through plain ASDF and never loads Quicklisp,
# so expose the Quicklisp-fetched sources (ironclad + its deps) to ASDF. The
# trailing empty entry keeps ASDF's default registry (e.g. cl-swank) as well.
ENV CL_SOURCE_REGISTRY=/root/quicklisp/dists/quicklisp/software//:

WORKDIR /workspace
