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

# Quicklisp plus MGL-PAX, for scripts/docs-check.lisp. Fetched at build time so
# the transcript check still runs in a container with --network none.
RUN curl -fsSL https://beta.quicklisp.org/quicklisp.lisp -o /tmp/quicklisp.lisp \
    && sbcl --non-interactive \
            --load /tmp/quicklisp.lisp \
            --eval '(quicklisp-quickstart:install)' \
            --eval '(ql:quickload "mgl-pax/full" :silent t)' \
    && rm -f /tmp/quicklisp.lisp

WORKDIR /workspace
