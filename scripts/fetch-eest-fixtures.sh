#!/bin/sh
# Fetch the pinned execution-spec-tests fixture corpus.
#
# The suite already knows how to run this corpus and already names the release
# it expects (tests/test-framework.lisp: +phase-a-eest-release+ and friends).
# What was missing is anything that fetches it, so CI ran with the corpus absent
# and the fixture tests reported themselves skipped -- which reads, in a green
# build, exactly like passing.
#
# THE PIN IS A CHECKSUM, NOT A URL. A release tag can be moved and a release
# asset can be replaced; a sha256 cannot. Consensus conformance measured against
# a corpus that might have changed underneath us is not a measurement, so a
# mismatch here is a hard failure rather than a warning.
#
# Usage: scripts/fetch-eest-fixtures.sh [destination]
# Prints the path to export as ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT.

set -eu

EEST_RELEASE="v5.4.0"
EEST_ARCHIVE="fixtures_stable.tar.gz"
EEST_SHA256="92cf1b47ad12fb27163261fc3c1cea5df72439cab507983d06b56c94f8741909"
EEST_URL="https://github.com/ethereum/execution-spec-tests/releases/download/${EEST_RELEASE}/${EEST_ARCHIVE}"

destination="${1:-.eest-fixtures}"
archive="${destination}/${EEST_ARCHIVE}"
extracted="${destination}/${EEST_RELEASE}"

verify_checksum() {
    # sha256sum on Linux, shasum on macOS. Neither is guaranteed, so refusing
    # to continue without one is deliberate: an unverified 245 MiB download is
    # exactly what the pin exists to prevent.
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
    echo "fetch-eest-fixtures: downloading ${EEST_RELEASE} ${EEST_ARCHIVE}" >&2
    curl -fsSL --retry 3 --retry-delay 5 -o "${archive}.partial" "${EEST_URL}"
    mv "${archive}.partial" "${archive}"
fi

if ! verify_checksum "${archive}"; then
    echo "fetch-eest-fixtures: checksum mismatch for ${archive}" >&2
    echo "  expected ${EEST_SHA256}" >&2
    exit 1
fi

# Extract to a release-named directory, so a later pin bump does not silently
# reuse the previous corpus.
mkdir -p "${extracted}"
tar xzf "${archive}" -C "${extracted}"

if [ ! -d "${extracted}/fixtures" ]; then
    echo "fetch-eest-fixtures: archive did not contain a fixtures/ directory" >&2
    exit 1
fi

echo "${extracted}"
