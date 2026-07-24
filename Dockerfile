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
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /private/tmp \
    && chmod 1777 /private/tmp

# Quicklisp, for two build-time dependencies fetched here so that everything
# still runs in a container with --network none:
#   - ironclad: the runtime crypto backend (Keccak etc.), a project dependency;
#   - mgl-pax/full: used only by scripts/docs-check.lisp.
# A recent Ironclad from Quicklisp is markedly faster than Debian's cl-ironclad
# (0.57), so the Debian package is deliberately NOT installed.
RUN curl -fsSL https://beta.quicklisp.org/quicklisp.lisp -o /tmp/quicklisp.lisp \
    && sbcl --non-interactive \
            --load /tmp/quicklisp.lisp \
            --eval '(quicklisp-quickstart:install)' \
            --eval '(ql-dist:install-dist "http://beta.quicklisp.org/dist/quicklisp/2026-01-01/distinfo.txt" :replace t :prompt nil)' \
            --eval '(ql:quickload :ironclad :silent t)' \
            --eval '(ql:quickload "mgl-pax/full" :silent t)' \
    && rm -f /tmp/quicklisp.lisp

# The cold-test path loads systems through plain ASDF and never loads Quicklisp,
# so expose the Quicklisp-fetched sources (ironclad + its deps) to ASDF. The
# trailing empty entry keeps ASDF's default registry (e.g. cl-swank) as well.
ENV CL_SOURCE_REGISTRY=/root/quicklisp/dists/quicklisp/software//:

WORKDIR /workspace
