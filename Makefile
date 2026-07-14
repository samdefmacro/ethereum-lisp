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
DOCKER_EEST_ARGS =
ifneq ($(strip $(ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT)),)
DOCKER_EEST_ARGS = \
	--mount "type=bind,source=$(abspath $(ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT)),target=$(DOCKER_EEST_ROOT),readonly" \
	--env ETHEREUM_LISP_EXECUTION_SPEC_TESTS_ROOT="$(DOCKER_EEST_ROOT)"
endif
DOCKER_TEST_RUN = $(DOCKER) run --rm --init --network none \
	--volume "$(CURDIR):$(DOCKER_TEST_WORKDIR):ro" \
	--tmpfs "$(DOCKER_TEST_WORKDIR)/.cache:exec,mode=1777" \
	--tmpfs "/private/tmp:exec,mode=1777" \
	--workdir "$(DOCKER_TEST_WORKDIR)" \
	--env E2E_JOBS="$(DOCKER_E2E_JOBS)" \
	--env E2E_WORKER_TIMEOUT="$(E2E_WORKER_TIMEOUT)" \
	--env XDG_CACHE_HOME=/tmp/ethereum-lisp-asdf-cache \
	$(DOCKER_EEST_ARGS) $(DOCKER_TEST_IMAGE)

.PHONY: test-unit test-integration test-e2e test-all \
	docker-test-image docker-test-unit docker-test-integration \
	docker-test-e2e docker-test-all docker-sbcl

test-unit:
	$(SBCL) --script tests/run-tests.lisp --layer unit

test-integration:
	$(SBCL) --script tests/run-tests.lisp --layer integration

test-e2e:
	$(SBCL) --script tests/run-tests.lisp --layer e2e --jobs $(E2E_JOBS) --worker-timeout $(E2E_WORKER_TIMEOUT)

test-all:
	SBCL="$(SBCL)" E2E_JOBS="$(E2E_JOBS)" scripts/run-test-layers.sh

docker-test-image:
	$(DOCKER) build --file Dockerfile --tag "$(DOCKER_TEST_IMAGE)" .

docker-test-unit: docker-test-image
	$(DOCKER_TEST_RUN) sh scripts/docker-test.sh unit $(DOCKER_TEST_ARGS)

docker-test-integration: docker-test-image
	$(DOCKER_TEST_RUN) sh scripts/docker-test.sh integration $(DOCKER_TEST_ARGS)

docker-test-e2e: docker-test-image
	$(DOCKER_TEST_RUN) sh scripts/docker-test.sh e2e $(DOCKER_TEST_ARGS)

docker-test-all: docker-test-image
	$(DOCKER_TEST_RUN) sh scripts/docker-test.sh all

docker-sbcl: docker-test-image
	$(if $(strip $(DOCKER_SBCL_ARGS)),,$(error DOCKER_SBCL_ARGS is required))
	$(DOCKER_TEST_RUN) sbcl $(DOCKER_SBCL_ARGS)
