ARG PROJECT_IMAGE=ethereum-lisp-sbcl-test:go1.24-bookworm
# The project's own test image (./Dockerfile, itself digest-pinned).
# pins-check: project-image
FROM ${PROJECT_IMAGE}

WORKDIR /opt/discv5-interop
COPY go.mod ./
COPY discv5_geth_test.go ./
RUN go mod tidy && go test ./...
