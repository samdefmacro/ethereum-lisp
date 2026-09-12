# Pinned replacement for Hive dde4f59d04ff0ff8b6585670b08cea1b6c8ab65c's
# simulators/devp2p/Dockerfile. The upstream file clones moving go-ethereum
# master, so an otherwise pinned Hive run changes its test binary and testchain.

# Build the exact devp2p tool and testchain source observed by the first complete
# Section 5 baseline.
FROM golang:1-alpine@sha256:cf6fca6641884b8433441b2b0652976f975e1d0fdd26d177eaaf8596087f3125 AS geth-builder
ARG GOPROXY
ARG GETH_COMMIT
ENV GOPROXY=${GOPROXY}
RUN apk add --update git gcc musl-dev linux-headers
RUN test -n "${GETH_COMMIT}" \
    && git init /go-ethereum \
    && git -C /go-ethereum remote add origin https://github.com/ethereum/go-ethereum.git \
    && git -C /go-ethereum fetch --depth 1 origin "${GETH_COMMIT}" \
    && git -C /go-ethereum checkout --detach FETCH_HEAD \
    && test "$(git -C /go-ethereum rev-parse HEAD)" = "${GETH_COMMIT}"
WORKDIR /go-ethereum
RUN go build -v ./cmd/devp2p

# Build the simulator executable from the pinned Hive checkout.
FROM golang:1-alpine@sha256:cf6fca6641884b8433441b2b0652976f975e1d0fdd26d177eaaf8596087f3125 AS sim-builder
ARG GOPROXY
ENV GOPROXY=${GOPROXY}
RUN apk add --update git gcc musl-dev linux-headers
WORKDIR /source
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -v -o devp2p-simulator

# Build the simulation run container.
FROM alpine:latest@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b
ADD . /source
WORKDIR /source
COPY --from=geth-builder /go-ethereum/devp2p ./devp2p
COPY --from=geth-builder /go-ethereum/cmd/devp2p/internal/ethtest/testdata /testchain
COPY --from=sim-builder /source/devp2p-simulator .
ENTRYPOINT ["./devp2p-simulator"]
