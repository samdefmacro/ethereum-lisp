#!/bin/sh
# Fetch a pinned execution-spec-tests fixture corpus.
#
# The suite already knows how to run these corpora and already names the release
# it expects (tests/test-framework.lisp: +phase-a-eest-release+ and friends).
# What was missing is anything that fetches them, so CI ran with the corpus
# absent and the fixture tests reported themselves skipped -- which reads, in a
# green build, exactly like passing.
#
# THE PIN IS A CHECKSUM, NOT A URL. A release tag can be moved and a release
# asset can be replaced; a sha256 cannot. Consensus conformance measured against
# a corpus that might have changed underneath us is not a measurement, so a
# mismatch here is a hard failure rather than a warning.
#
# Three baselines are pinned, selected with EEST_BASELINE:
#   legacy-v5.4.0    the corpus the London/Shanghai gate ran against (default,
#                    so `make eest-fixtures` keeps working unchanged).
#   stable-v20.0.2   the current stable execution corpus (tests@v20.0.2); the
#                    late-fork Cancun/Prague/Osaka surface lives here.
#   amsterdam-v7.2.1 the Amsterdam feature corpus (tests-glamsterdam-devnet
#                    @v7.2.1); NOT executed by the current gates, staged for the
#                    Amsterdam burn-down (plan section 8).
#
# Usage: EEST_BASELINE=<baseline> scripts/fetch-eest-fixtures.sh [destination]
# Prints the path to export as ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT.

set -eu

EEST_BASELINE="${EEST_BASELINE:-legacy-v5.4.0}"

case "${EEST_BASELINE}" in
    legacy-v5.4.0)
        EEST_RELEASE="v5.4.0"
        EEST_ARCHIVE="fixtures_stable.tar.gz"
        EEST_SHA256="92cf1b47ad12fb27163261fc3c1cea5df72439cab507983d06b56c94f8741909"
        EEST_URL="https://github.com/ethereum/execution-spec-tests/releases/download/${EEST_RELEASE}/${EEST_ARCHIVE}"
        EEST_EXTRACT_DIR="v5.4.0"
        ;;
    stable-v20.0.2)
        EEST_RELEASE="tests@v20.0.2"
        EEST_ARCHIVE="fixtures.tar.gz"
        EEST_SHA256="1280540950a4c3470a421416b6f35458a9b635827265c29e5aef1ae839ae1788"
        EEST_URL="https://github.com/ethereum/execution-specs/releases/download/tests%40v20.0.2/fixtures.tar.gz"
        EEST_EXTRACT_DIR="tests-v20.0.2"
        ;;
    amsterdam-v7.2.1)
        EEST_RELEASE="tests-glamsterdam-devnet@v7.2.1"
        EEST_ARCHIVE="fixtures_glamsterdam-devnet.tar.gz"
        EEST_SHA256="02e3eca2ede5b424f4dbf2461caf592e6b43b56d55bbd64213dd01f63af9a583"
        EEST_URL="https://github.com/ethereum/execution-specs/releases/download/tests-glamsterdam-devnet%40v7.2.1/fixtures_glamsterdam-devnet.tar.gz"
        EEST_EXTRACT_DIR="tests-glamsterdam-devnet-v7.2.1"
        ;;
    *)
        echo "fetch-eest-fixtures: unknown EEST_BASELINE ${EEST_BASELINE}" >&2
        echo "  expected one of: legacy-v5.4.0, stable-v20.0.2, amsterdam-v7.2.1" >&2
        exit 1
        ;;
esac

destination="${1:-.eest-fixtures}"
archive="${destination}/${EEST_ARCHIVE}"
extracted="${destination}/${EEST_EXTRACT_DIR}"

verify_checksum() {
    # sha256sum on Linux, shasum on macOS. Neither is guaranteed, so refusing
    # to continue without one is deliberate: an unverified multi-hundred-MiB
    # download is exactly what the pin exists to prevent.
    if command -v sha256sum >/dev/null 2>&1; then
        echo "${EEST_SHA256}  $1" | sha256sum -c - >/dev/null 2>&1
    elif command -v shasum >/dev/null 2>&1; then
        echo "${EEST_SHA256}  $1" | shasum -a 256 -c - >/dev/null 2>&1
    else
        echo "fetch-eest-fixtures: no sha256sum or shasum available" >&2
        exit 1
    fi
}

mkdir -p "${destination}"

if [ -d "${extracted}/fixtures" ]; then
    echo "${extracted}"
    exit 0
fi

if [ ! -f "${archive}" ] || ! verify_checksum "${archive}"; then
    echo "fetch-eest-fixtures: downloading ${EEST_BASELINE} (${EEST_RELEASE} ${EEST_ARCHIVE})" >&2
    curl -fsSL --retry 3 --retry-delay 5 -o "${archive}.partial" "${EEST_URL}"
    mv "${archive}.partial" "${archive}"
fi

if ! verify_checksum "${archive}"; then
    echo "fetch-eest-fixtures: checksum mismatch for ${archive}" >&2
    echo "  expected ${EEST_SHA256}" >&2
    exit 1
fi

# Extract to a release-named directory, so a later pin bump does not silently
# reuse the previous corpus and two baselines never collide in one destination.
mkdir -p "${extracted}"
tar xzf "${archive}" -C "${extracted}"

if [ ! -d "${extracted}/fixtures" ]; then
    echo "fetch-eest-fixtures: archive did not contain a fixtures/ directory" >&2
    exit 1
fi

echo "${extracted}"
