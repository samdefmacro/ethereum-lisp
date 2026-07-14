FROM golang:1.24-bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        make \
        procps \
        sbcl \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /private/tmp \
    && chmod 1777 /private/tmp

WORKDIR /workspace
