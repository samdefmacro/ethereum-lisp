SBCL ?= sbcl
E2E_JOBS ?= 4

.PHONY: test-unit test-integration test-e2e test-all

test-unit:
	$(SBCL) --script tests/run-tests.lisp --layer unit

test-integration:
	$(SBCL) --script tests/run-tests.lisp --layer integration

test-e2e:
	$(SBCL) --script tests/run-tests.lisp --layer e2e --jobs $(E2E_JOBS)

test-all:
	SBCL="$(SBCL)" E2E_JOBS="$(E2E_JOBS)" scripts/run-test-layers.sh
