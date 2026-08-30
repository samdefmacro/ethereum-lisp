FROM golang:1.24-bookworm@sha256:1a6d4452c65dea36aac2e2d606b01b4a029ec90cc1ae53890540ce6173ea77ac AS test

WORKDIR /src
COPY go.mod main.go main_test.go ./
RUN --network=none files="$(gofmt -l .)" \
    && test -z "$files" \
    && go test ./...

FROM golang:1.24-bookworm@sha256:1a6d4452c65dea36aac2e2d606b01b4a029ec90cc1ae53890540ce6173ea77ac AS build

WORKDIR /src
COPY go.mod main.go ./
RUN --network=none CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o /out/shadow-engine-proxy .

FROM debian:bookworm-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241

ARG REVISION=unknown
LABEL org.opencontainers.image.title="ethereum-lisp-shadow-engine-proxy" \
      org.opencontainers.image.description="Bounded primary-authoritative Engine API shadow fan-out" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.revision="${REVISION}"

RUN groupadd --system --gid 10001 shadowproxy \
    && useradd --system --uid 10001 --gid 10001 --home-dir /nonexistent --shell /usr/sbin/nologin shadowproxy
COPY --from=build /out/shadow-engine-proxy /usr/local/bin/shadow-engine-proxy

USER shadowproxy:shadowproxy
EXPOSE 8551
ENTRYPOINT ["/usr/local/bin/shadow-engine-proxy"]
