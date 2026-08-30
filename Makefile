SBCL ?= sbcl
E2E_JOBS ?= 4
E2E_WORKER_TIMEOUT ?= 900
DOCKER_E2E_JOBS ?= 2
DOCKER_TEST_ARGS ?=
DOCKER_SBCL_ARGS ?=
DOCKER ?= docker
DOCKER_TEST_IMAGE ?= ethereum-lisp-sbcl-test:go1.24-bookworm
DOCKER_TEST_WORKDIR ?= /workspace
DOCKER_EEST_ROOT ?= /fixtures/execution-spec-tests
EEST_FIXTURE_DIR ?= .eest-fixtures
DOCKER_EEST_ARGS =
ifneq ($(strip $(ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT)),)
DOCKER_EEST_ARGS = \
	--mount "type=bind,source=$(abspath $(ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT)),target=$(DOCKER_EEST_ROOT),readonly" \
	--env ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT="$(DOCKER_EEST_ROOT)"
endif
# THE FIXTURE ROOT ALONE SELECTS NOTHING. The state-test and blockchain-replay
# cases each need a selector list too, and without one they report themselves
# SKIPPED in the same words they use when no corpus exists at all -- so a run
# that mounts 4.2 GB and executes zero vectors goes green. Forwarded only when
# set, so an unset selector stays unset inside the container instead of becoming
# an empty string, which the classifier would read as a selector.
DOCKER_SELECTOR_ARGS =
ifneq ($(strip $(ETHEREUM_LISP_PHASE_A_STATE_TEST_SELECTORS)),)
DOCKER_SELECTOR_ARGS += \
	--env ETHEREUM_LISP_PHASE_A_STATE_TEST_SELECTORS="$(ETHEREUM_LISP_PHASE_A_STATE_TEST_SELECTORS)"
endif
ifneq ($(strip $(ETHEREUM_LISP_PHASE_A_STATE_TEST_FORKS)),)
DOCKER_SELECTOR_ARGS += \
	--env ETHEREUM_LISP_PHASE_A_STATE_TEST_FORKS="$(ETHEREUM_LISP_PHASE_A_STATE_TEST_FORKS)"
endif
ifneq ($(strip $(ETHEREUM_LISP_PHASE_A_BLOCKCHAIN_REPLAY_SELECTORS)),)
DOCKER_SELECTOR_ARGS += \
	--env ETHEREUM_LISP_PHASE_A_BLOCKCHAIN_REPLAY_SELECTORS="$(ETHEREUM_LISP_PHASE_A_BLOCKCHAIN_REPLAY_SELECTORS)"
endif
# Blockchain replay defaults to Shanghai only; this widens the materializable
# network set the same way STATE_TEST_FORKS widens state-test discovery. Left
# unset it stays unset in the container, so the default gate is unchanged.
ifneq ($(strip $(ETHEREUM_LISP_PHASE_A_BLOCKCHAIN_REPLAY_FORKS)),)
DOCKER_SELECTOR_ARGS += \
	--env ETHEREUM_LISP_PHASE_A_BLOCKCHAIN_REPLAY_FORKS="$(ETHEREUM_LISP_PHASE_A_BLOCKCHAIN_REPLAY_FORKS)"
endif

DOCKER_TEST_RUN = $(DOCKER) run --rm --init --network none \
	--read-only \
	--cap-drop ALL \
	--security-opt no-new-privileges \
	--pids-limit 4096 \
	--volume "$(CURDIR):$(DOCKER_TEST_WORKDIR):ro" \
	--tmpfs "$(DOCKER_TEST_WORKDIR)/.cache:exec,mode=1777" \
	--tmpfs "/tmp:exec,mode=1777" \
	--tmpfs "/private/tmp:exec,mode=1777" \
	--workdir "$(DOCKER_TEST_WORKDIR)" \
	--env E2E_JOBS="$(DOCKER_E2E_JOBS)" \
	--env E2E_WORKER_TIMEOUT="$(E2E_WORKER_TIMEOUT)" \
	--env XDG_CACHE_HOME=/tmp/ethereum-lisp-asdf-cache \
	$(DOCKER_EEST_ARGS) $(DOCKER_SELECTOR_ARGS) $(DOCKER_TEST_IMAGE)

# Set DOCKER_TEST_IMAGE_PREBUILT=1 when the image was built by other means and
# must be used as-is. CI builds it with buildx against a shared layer cache, and
# a plain `docker build` there would rebuild every layer instead of reusing it.
DOCKER_TEST_IMAGE_DEP = docker-test-image
ifneq ($(strip $(DOCKER_TEST_IMAGE_PREBUILT)),)
DOCKER_TEST_IMAGE_DEP =
endif

.PHONY: require-container-runtime test-unit test-integration test-e2e test-all \
	docker-test-image docker-test-unit docker-test-integration \
	docker-test-e2e docker-test-all docker-docs-check docker-sbcl \
	docker-direct-store-scale \
	eest-fixtures eest-fixtures-stable eest-fixtures-amsterdam

require-container-runtime:
	@test "$${ETHEREUM_LISP_CONTAINER_RUNTIME:-}" = 1 || { \
		echo "ERROR: direct host toolchain targets are forbidden; use scripts/dev.sh cold-test" >&2; \
		exit 2; \
	}

test-unit: require-container-runtime
	$(SBCL) --script tests/run-tests.lisp --layer unit

test-integration: require-container-runtime
	$(SBCL) --script tests/run-tests.lisp --layer integration

test-e2e: require-container-runtime
	$(SBCL) --script tests/run-tests.lisp --layer e2e --jobs $(E2E_JOBS) --worker-timeout $(E2E_WORKER_TIMEOUT)

test-all: require-container-runtime
	SBCL="$(SBCL)" E2E_JOBS="$(E2E_JOBS)" scripts/run-test-layers.sh

# Fetch a pinned execution-spec-tests corpus and print the root to export as
# ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT. Idempotent: a corpus already
# extracted at the pinned release is reused rather than re-downloaded. Each
# baseline extracts to its own release-named subdirectory of EEST_FIXTURE_DIR,
# so the three can coexist. The checksum in the script is what makes reuse safe.
eest-fixtures:
	@scripts/fetch-eest-fixtures.sh $(EEST_FIXTURE_DIR)

# Current stable execution corpus (tests@v20.0.2); the Cancun/Prague/Osaka
# blocking surface lives here.
eest-fixtures-stable:
	@EEST_BASELINE=stable-v20.0.2 scripts/fetch-eest-fixtures.sh $(EEST_FIXTURE_DIR)

# Amsterdam feature corpus (tests-glamsterdam-devnet@v7.2.1). Staged for the
# Amsterdam burn-down (plan section 8); the current gates do not execute it.
eest-fixtures-amsterdam:
	@EEST_BASELINE=amsterdam-v7.2.1 scripts/fetch-eest-fixtures.sh $(EEST_FIXTURE_DIR)

docker-test-image:
	$(DOCKER) build --file Dockerfile --tag "$(DOCKER_TEST_IMAGE)" .

docker-test-unit: $(DOCKER_TEST_IMAGE_DEP)
	$(DOCKER_TEST_RUN) sh scripts/docker-test.sh unit $(DOCKER_TEST_ARGS)

docker-test-integration: $(DOCKER_TEST_IMAGE_DEP)
	$(DOCKER_TEST_RUN) sh scripts/docker-test.sh integration $(DOCKER_TEST_ARGS)

docker-test-e2e: $(DOCKER_TEST_IMAGE_DEP)
	$(DOCKER_TEST_RUN) sh scripts/docker-test.sh e2e $(DOCKER_TEST_ARGS)

docker-test-all: $(DOCKER_TEST_IMAGE_DEP)
	$(DOCKER_TEST_RUN) sh scripts/docker-test.sh all

# The cl-transcript examples in docs/*.lisp are re-executed and compared against
# what they claim, so a drifted transcript is a red build -- but only where this
# runs, and until now that was solely `scripts/dev.sh docs-check` on a developer
# machine. Same container shape as the test layers above (read-only workspace,
# tmpfs caches, --network none: mgl-pax/full is baked into the image, so
# quickload needs no network). scripts/docs-check.lisp carries its own RED gate
# -- the deliberately wrong @DOCS-CHECK-SELFTEST section must FAIL -- so this
# target proves the checker is switched on, not merely quiet.
docker-docs-check: $(DOCKER_TEST_IMAGE_DEP)
	$(DOCKER_TEST_RUN) sbcl --non-interactive --load scripts/docs-check.lisp

docker-sbcl: $(DOCKER_TEST_IMAGE_DEP)
	$(if $(strip $(DOCKER_SBCL_ARGS)),,$(error DOCKER_SBCL_ARGS is required))
	$(DOCKER_TEST_RUN) sbcl $(DOCKER_SBCL_ARGS)

# Section 3 production-store acceptance gate.  An unconstrained preparation
# container cold-compiles the current source into an ephemeral Docker volume;
# compiler peak memory is not part of the datastore-runtime claim. A fresh
# 384 MiB-limited container then streams a 512 MiB incompressible RocksDB and a
# fresh SBCL process opens it through the direct provider. The asserted 256 MiB
# RSS bound and 30-second whole-process restart bound leave the dataset larger
# than both the effective RAM limit and the accepted resident working set.
docker-direct-store-scale: $(DOCKER_TEST_IMAGE_DEP)
	@scale_cache="ethereum-lisp-direct-store-scale-cache-$$$$"; \
	cleanup() { $(DOCKER) volume rm "$$scale_cache" >/dev/null 2>&1 || true; }; \
	trap cleanup EXIT HUP INT TERM; \
	$(DOCKER) volume create "$$scale_cache" >/dev/null; \
	$(DOCKER) run --rm --init --network none \
		--volume "$(CURDIR):$(DOCKER_TEST_WORKDIR):ro" \
		--mount "type=volume,source=$$scale_cache,target=/tmp/ethereum-lisp-asdf-cache" \
		--workdir "$(DOCKER_TEST_WORKDIR)" \
		--env XDG_CACHE_HOME=/tmp/ethereum-lisp-asdf-cache \
		$(DOCKER_TEST_IMAGE) sbcl --non-interactive \
		--eval '(require :asdf)' \
		--eval '(asdf:load-asd #P"/workspace/ethereum-lisp.asd")' \
		--eval '(asdf:load-system :ethereum-lisp)'; \
	$(DOCKER) run --rm --init --network none \
		--memory 384m --memory-swap 384m \
		--volume "$(CURDIR):$(DOCKER_TEST_WORKDIR):ro" \
		--mount "type=volume,source=$$scale_cache,target=/tmp/ethereum-lisp-asdf-cache" \
		--workdir "$(DOCKER_TEST_WORKDIR)" \
		--env XDG_CACHE_HOME=/tmp/ethereum-lisp-asdf-cache \
		$(DOCKER_TEST_IMAGE) sh scripts/direct-store-scale-gate.sh
