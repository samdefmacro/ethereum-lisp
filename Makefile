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
ifneq ($(strip $(ETHEREUM_LISP_PHASE_A_BLOCKCHAIN_REPLAY_SELECTORS)),)
DOCKER_SELECTOR_ARGS += \
	--env ETHEREUM_LISP_PHASE_A_BLOCKCHAIN_REPLAY_SELECTORS="$(ETHEREUM_LISP_PHASE_A_BLOCKCHAIN_REPLAY_SELECTORS)"
endif

DOCKER_TEST_RUN = $(DOCKER) run --rm --init --network none \
	--volume "$(CURDIR):$(DOCKER_TEST_WORKDIR):ro" \
	--tmpfs "$(DOCKER_TEST_WORKDIR)/.cache:exec,mode=1777" \
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

.PHONY: test-unit test-integration test-e2e test-all \
	docker-test-image docker-test-unit docker-test-integration \
	docker-test-e2e docker-test-all docker-sbcl eest-fixtures

test-unit:
	$(SBCL) --script tests/run-tests.lisp --layer unit

test-integration:
	$(SBCL) --script tests/run-tests.lisp --layer integration

test-e2e:
	$(SBCL) --script tests/run-tests.lisp --layer e2e --jobs $(E2E_JOBS) --worker-timeout $(E2E_WORKER_TIMEOUT)

test-all:
	SBCL="$(SBCL)" E2E_JOBS="$(E2E_JOBS)" scripts/run-test-layers.sh

# Fetch the pinned execution-spec-tests corpus and print the root to export as
# ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT. Idempotent: a corpus already
# extracted at the pinned release is reused rather than re-downloaded.
eest-fixtures:
	@scripts/fetch-eest-fixtures.sh $(EEST_FIXTURE_DIR)

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

docker-sbcl: $(DOCKER_TEST_IMAGE_DEP)
	$(if $(strip $(DOCKER_SBCL_ARGS)),,$(error DOCKER_SBCL_ARGS is required))
	$(DOCKER_TEST_RUN) sbcl $(DOCKER_SBCL_ARGS)
