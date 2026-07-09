(in-package #:ethereum-lisp.test)

(defparameter +trie-vector-fixture-path+
  "tests/fixtures/execution-spec-tests/trie-vectors.json")

(defparameter +trie-vector-fixture-format+
  "ethereum-lisp/trie-vectors-v1")

(defparameter +eest-trie-test-sample-path+
  "tests/fixtures/execution-spec-tests-root/fixtures/trie_tests/phase-a-trie-sample.json")

(defparameter +eest-trie-test-secure-sample-path+
  "tests/fixtures/execution-spec-tests-root/fixtures/trie_tests/phase-a-secureTrie.json")

(defparameter +empty-trie-root-hex+
  "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421")

(defparameter +phase-a-eest-trie-test-case-names+
  '("phase-a-secureTrie.json/phase-a-secure-branch"
    "phase-a-secureTrie.json/phase-a-secure-branch-child-branch"
    "phase-a-secureTrie.json/phase-a-secure-branch-child-extension"
    "phase-a-secureTrie.json/phase-a-secure-branch-update-keeps-branch"
    "phase-a-secureTrie.json/phase-a-secure-delete"
    "phase-a-secureTrie.json/phase-a-secure-delete-branch-child"
    "phase-a-secureTrie.json/phase-a-secure-delete-branch-child-keeps-branch"
    "phase-a-secureTrie.json/phase-a-secure-delete-branch-sibling-collapses-to-extension"
    "phase-a-secureTrie.json/phase-a-secure-delete-extension-child"
    "phase-a-secureTrie.json/phase-a-secure-duplicate-overwrite"
    "phase-a-secureTrie.json/phase-a-secure-extension"
    "phase-a-secureTrie.json/phase-a-secure-extension-update-keeps-extension"
    "phase-a-secureTrie.json/phase-a-secure-insert"
    "phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-1"
    "phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-2"
    "phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-3"
    "phase-a-secureTrie.json/phase-a-secure-zgeth-account-five-step"
    "phase-a-secureTrie.json/phase-a-secure-zgeth-delete-sequence"
    "phase-a-secureTrie.json/phase-a-secure-missing-delete-branch"
    "phase-a-secureTrie.json/phase-a-secure-missing-delete-extension"
    "phase-a-secureTrie.json/phase-a-secure-object-form-branch"
    "phase-a-secureTrie.json/phase-a-secure-object-form-empty-value-delete"
    "phase-a-secureTrie.json/phase-a-secure-object-form-missing-delete"
    "phase-a-secureTrie.json/phase-a-secure-object-form-value-hex-bytes"
    "phase-a-secureTrie.json/phase-a-secure-value-hex-byte-delete"
    "phase-a-trie-multi.json/alpha"
    "phase-a-trie-multi.json/geth-long-leaf-value"
    "phase-a-trie-multi.json/geth-large-value-branch"
    "phase-a-trie-multi.json/geth-tiny-account-step-1"
    "phase-a-trie-multi.json/geth-tiny-account-step-2"
    "phase-a-trie-multi.json/geth-tiny-account-step-3"
    "phase-a-trie-multi.json/geth-tiny-account-five-step"
    "phase-a-trie-multi.json/hex-byte-value-leaf"
    "phase-a-trie-multi.json/branch"
    "phase-a-trie-multi.json/branch-child-branch"
    "phase-a-trie-multi.json/branch-child-extension"
    "phase-a-trie-multi.json/object-form-branch"
    "phase-a-trie-multi.json/object-form-empty-value-delete"
    "phase-a-trie-multi.json/object-form-hex-byte-value-leaf"
    "phase-a-trie-multi.json/object-form-missing-delete"
    "phase-a-trie-multi.json/branch-value"
    "phase-a-trie-multi.json/branch-value-zero-child"
    "phase-a-trie-multi.json/delete-branch-child"
    "phase-a-trie-multi.json/delete-branch-child-no-value"
    "phase-a-trie-multi.json/delete-branch-child-keeps-branch"
    "phase-a-trie-multi.json/delete-branch-sibling-collapses-to-extension"
    "phase-a-trie-multi.json/delete-branch-value"
    "phase-a-trie-multi.json/delete-extension-child-collapses-to-leaf"
    "phase-a-trie-multi.json/delete-missing-branch-child"
    "phase-a-trie-multi.json/delete-missing-leaf"
    "phase-a-trie-multi.json/duplicate-overwrite"
    "phase-a-trie-multi.json/delete-collapse"
    "phase-a-trie-multi.json/delete-missing-extension-child"
    "phase-a-trie-multi.json/delete-nested-branch-value"
    "phase-a-trie-multi.json/delete-prefix-branch-value"
    "phase-a-trie-multi.json/embedded-extension"
    "phase-a-trie-multi.json/extension"
    "phase-a-trie-multi.json/geth-insert-shared-prefix"
    "phase-a-trie-multi.json/geth-delete-sequence"
    "phase-a-trie-multi.json/geth-empty-value-sequence"
    "phase-a-trie-multi.json/geth-replication-sequence"
    "phase-a-trie-multi.json/geth-random-cases-sequence"
    "phase-a-trie-multi.json/geth-stacktrie-extension-child-boundary"
    "phase-a-trie-multi.json/geth-stacktrie-short-branch-growth"
    "phase-a-trie-multi.json/geth-stacktrie-root-branch-short-long-growth"
    "phase-a-trie-multi.json/geth-stacktrie-extension-branch-short-long-growth"
    "phase-a-trie-multi.json/geth-stacktrie-sparse-root-branch-long-values"
    "phase-a-trie-multi.json/geth-stacktrie-root-branch-nested-right-branch"
    "phase-a-trie-multi.json/geth-stacktrie-root-branch-nested-left-branch"
    "phase-a-trie-multi.json/geth-stacktrie-root-branch-extension-child"
    "phase-a-trie-multi.json/geth-stacktrie-root-branch-left-extension-child"
    "phase-a-trie-multi.json/geth-stacktrie-deep-extension-branch"
    "phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-tail-fanout"
    "phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-shortens-to-three-nibbles"
    "phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-shortens-to-two-nibbles"
    "phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-shortens-to-one-nibble"
    "phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-splits-to-root-branch"
    "phase-a-trie-multi.json/geth-stacktrie-zero-prefix-extension-fanout"
    "phase-a-trie-multi.json/geth-stacktrie-f-prefix-nested-right-branch"
    "phase-a-trie-multi.json/geth-stacktrie-ff-prefix-nested-left-branch"
    "phase-a-trie-multi.json/geth-stacktrie-shared-prefix-tail-fanout"
    "phase-a-trie-multi.json/geth-stacktrie-shared-prefix-shortens-to-two-nibbles"
    "phase-a-trie-multi.json/geth-stacktrie-shared-prefix-shortens-to-one-nibble"
    "phase-a-trie-multi.json/geth-stacktrie-shared-prefix-splits-to-root-branch"
    "phase-a-trie-multi.json/mixed-branch-refs"
    "phase-a-trie-sample.json"))

(defparameter +trie-fixture-top-level-fields+
  '("format" "source" "executionSpecTests" "cases"))

(defparameter +trie-fixture-known-tags+
  '("leaf-root"
    "branch-root"
    "extension-root"
    "path-compression"
    "delete-collapse"
    "delete-to-empty"
    "embedded-child-reference"
    "hashed-child-reference"
    "branch-child-references"
    "branch-children"
    "branch-value"
    "missing-delete-noop"
    "duplicate-overwrite"
    "hex-key"
    "hex-value"
    "secure-key"
    "lookup-assertions"
    "empty-value-delete"
    "single-node-proof"
    "exact-proof-node-rlp"
    "proof-node-rlp"
    "delete-proof-node-rlp"
    "missing-proof-node-rlp"
    "entry-pair-replay"
    "entry-range"
    "intermediate-roots"))

(defparameter +trie-fixture-required-case-names+
  '("single-leaf"
    "geth-one-element-proof"
    "geth-long-leaf-value"
    "geth-large-value-branch"
    "geth-tiny-account-step-1"
    "geth-tiny-account-step-2"
    "geth-tiny-account-step-3"
    "geth-tiny-account-five-step"
    "hex-byte-value-leaf"
    "delete-missing-key-keeps-leaf"
    "duplicate-key-overwrites-leaf-value"
    "geth-insert-shared-prefix"
    "geth-delete-sequence"
    "geth-empty-value-sequence"
    "geth-replication-sequence"
    "geth-random-cases-sequence"
    "geth-stacktrie-extension-child-boundary"
    "geth-stacktrie-short-branch-growth"
    "geth-stacktrie-root-branch-short-long-growth"
    "geth-stacktrie-extension-branch-short-long-growth"
    "geth-stacktrie-sparse-root-branch-long-values"
    "geth-stacktrie-root-branch-nested-right-branch"
    "geth-stacktrie-root-branch-nested-left-branch"
    "geth-stacktrie-root-branch-extension-child"
    "geth-stacktrie-root-branch-left-extension-child"
    "geth-stacktrie-deep-extension-branch"
    "geth-stacktrie-zero-prefix-extension-fanout"
    "geth-stacktrie-f-prefix-nested-right-branch"
    "geth-stacktrie-ff-prefix-nested-left-branch"
    "geth-stacktrie-shared-prefix-tail-fanout"
    "geth-stacktrie-shared-prefix-shortens-to-two-nibbles"
    "geth-stacktrie-shared-prefix-shortens-to-one-nibble"
    "geth-stacktrie-shared-prefix-splits-to-root-branch"
    "geth-stacktrie-long-shared-prefix-tail-fanout"
    "geth-stacktrie-long-shared-prefix-shortens-to-three-nibbles"
    "geth-stacktrie-long-shared-prefix-shortens-to-two-nibbles"
    "geth-stacktrie-long-shared-prefix-shortens-to-one-nibble"
    "geth-stacktrie-long-shared-prefix-splits-to-root-branch"
    "nethermind-partial-path-proof-nodes"
    "branch-extension-shared-prefix"
    "branch-child-branch"
    "branch-child-extension"
    "extension-embedded-child-reference"
    "extension-hashed-child-reference"
    "delete-collapses-path"
    "delete-nested-branch-value-keeps-extension"
    "delete-prefix-branch-value-keeps-sibling-extension"
    "delete-extension-child-collapses-to-leaf"
    "delete-branch-sibling-collapses-to-extension"
    "delete-missing-extension-child-keeps-extension"
    "delete-last-entry-empty-root"
    "secure-branch-root"
    "secure-branch-child-branch"
    "secure-branch-child-extension"
    "secure-missing-delete-keeps-branch-root"
    "secure-extension-root"
    "secure-missing-delete-keeps-extension-root"
    "secure-delete-branch-child-collapses-to-leaf"
    "secure-delete-branch-child-keeps-branch"
    "secure-delete-branch-sibling-collapses-to-extension"
    "secure-delete-extension-child-collapses-to-leaf"
    "secure-duplicate-key-overwrites-leaf-value"
    "geth-secure-account-step-1"
    "geth-secure-account-step-2"
    "geth-secure-account-step-3"
    "geth-secure-account-five-step"
    "geth-secure-delete-sequence"
    "secure-single-leaf"
    "secure-delete-last-entry-empty-root"
    "root-branch-sparse-children"
    "root-branch-mixed-child-references"
    "delete-missing-branch-child-keeps-root-branch"
    "root-branch-value-for-prefix-key"
    "root-branch-value-with-zero-child"
    "delete-root-branch-value-collapses-to-leaf"
    "delete-root-branch-child-without-value-collapses-to-leaf"
    "delete-root-branch-child-without-value-keeps-branch"
    "delete-root-branch-child-collapses-to-root-value-leaf"
    "geth-general-range-iteration"))

(defparameter +trie-fixture-reference-case-requirements+
  '(("geth-one-element-proof" . :plain)
    ("geth-long-leaf-value" . :plain)
    ("geth-large-value-branch" . :plain)
    ("geth-general-range-iteration" . :plain)
    ("geth-tiny-account-step-1" . :plain)
    ("geth-tiny-account-step-2" . :plain)
    ("geth-tiny-account-step-3" . :plain)
    ("geth-tiny-account-five-step" . :plain)
    ("geth-insert-shared-prefix" . :plain)
    ("geth-delete-sequence" . :plain)
    ("geth-empty-value-sequence" . :plain)
    ("geth-replication-sequence" . :plain)
    ("geth-random-cases-sequence" . :plain)
    ("geth-stacktrie-extension-child-boundary" . :plain)
    ("geth-stacktrie-short-branch-growth" . :plain)
    ("geth-stacktrie-root-branch-short-long-growth" . :plain)
    ("geth-stacktrie-extension-branch-short-long-growth" . :plain)
    ("geth-stacktrie-sparse-root-branch-long-values" . :plain)
    ("geth-stacktrie-root-branch-nested-right-branch" . :plain)
    ("geth-stacktrie-root-branch-nested-left-branch" . :plain)
    ("geth-stacktrie-root-branch-extension-child" . :plain)
    ("geth-stacktrie-root-branch-left-extension-child" . :plain)
    ("geth-stacktrie-deep-extension-branch" . :plain)
    ("geth-stacktrie-zero-prefix-extension-fanout" . :plain)
    ("geth-stacktrie-f-prefix-nested-right-branch" . :plain)
    ("geth-stacktrie-ff-prefix-nested-left-branch" . :plain)
    ("geth-stacktrie-shared-prefix-tail-fanout" . :plain)
    ("geth-stacktrie-shared-prefix-shortens-to-two-nibbles" . :plain)
    ("geth-stacktrie-shared-prefix-shortens-to-one-nibble" . :plain)
    ("geth-stacktrie-shared-prefix-splits-to-root-branch" . :plain)
    ("geth-stacktrie-long-shared-prefix-tail-fanout" . :plain)
    ("geth-stacktrie-long-shared-prefix-shortens-to-three-nibbles" . :plain)
    ("geth-stacktrie-long-shared-prefix-shortens-to-two-nibbles" . :plain)
    ("geth-stacktrie-long-shared-prefix-shortens-to-one-nibble" . :plain)
    ("geth-stacktrie-long-shared-prefix-splits-to-root-branch" . :plain)
    ("nethermind-partial-path-proof-nodes" . :plain)
    ("geth-secure-account-step-1" . :secure)
    ("geth-secure-account-step-2" . :secure)
    ("geth-secure-account-step-3" . :secure)
    ("geth-secure-account-five-step" . :secure)
    ("geth-secure-delete-sequence" . :secure)))

(defparameter +trie-fixture-entry-pair-reference-case-names+
  '("geth-tiny-account-step-1"
    "geth-tiny-account-step-2"
    "geth-tiny-account-step-3"
    "geth-tiny-account-five-step"
    "geth-secure-account-step-1"
    "geth-secure-account-step-2"
    "geth-secure-account-step-3"
    "geth-secure-account-five-step"))

(defparameter +trie-fixture-account-proof-reference-case-names+
  '("geth-tiny-account-step-1"
    "geth-tiny-account-step-2"
    "geth-tiny-account-step-3"
    "geth-tiny-account-five-step"
    "geth-secure-account-step-1"
    "geth-secure-account-step-2"
    "geth-secure-account-step-3"
    "geth-secure-account-five-step"))

(defparameter +phase-a-eest-trie-reference-gates+
  '((:name :case-mode
     :validator validate-trie-reference-case-requirements
     :items (("phase-a-trie-multi.json/geth-long-leaf-value" . :plain)
             ("phase-a-trie-multi.json/geth-large-value-branch" . :plain)
             ("phase-a-trie-multi.json/geth-tiny-account-step-1" . :plain)
             ("phase-a-trie-multi.json/geth-tiny-account-step-2" . :plain)
             ("phase-a-trie-multi.json/geth-tiny-account-step-3" . :plain)
             ("phase-a-trie-multi.json/geth-tiny-account-five-step" . :plain)
             ("phase-a-trie-multi.json/geth-insert-shared-prefix" . :plain)
             ("phase-a-trie-multi.json/geth-delete-sequence" . :plain)
             ("phase-a-trie-multi.json/geth-empty-value-sequence" . :plain)
             ("phase-a-trie-multi.json/geth-replication-sequence" . :plain)
             ("phase-a-trie-multi.json/geth-random-cases-sequence" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-extension-child-boundary" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-short-branch-growth" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-root-branch-short-long-growth" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-extension-branch-short-long-growth" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-sparse-root-branch-long-values" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-root-branch-nested-right-branch" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-root-branch-nested-left-branch" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-root-branch-extension-child" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-root-branch-left-extension-child" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-deep-extension-branch" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-tail-fanout" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-shortens-to-three-nibbles" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-shortens-to-two-nibbles" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-shortens-to-one-nibble" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-splits-to-root-branch" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-zero-prefix-extension-fanout" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-f-prefix-nested-right-branch" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-ff-prefix-nested-left-branch" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-shared-prefix-tail-fanout" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-shared-prefix-shortens-to-two-nibbles" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-shared-prefix-shortens-to-one-nibble" . :plain)
             ("phase-a-trie-multi.json/geth-stacktrie-shared-prefix-splits-to-root-branch" . :plain)
             ("phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-1" . :secure)
             ("phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-2" . :secure)
             ("phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-3" . :secure)
             ("phase-a-secureTrie.json/phase-a-secure-zgeth-account-five-step" . :secure)
             ("phase-a-secureTrie.json/phase-a-secure-zgeth-delete-sequence" . :secure)))
    (:name :explicit-output
     :validator validate-trie-reference-explicit-output-requirements
     :items ("phase-a-trie-multi.json/geth-tiny-account-step-1"
             "phase-a-trie-multi.json/geth-tiny-account-step-2"
             "phase-a-trie-multi.json/geth-tiny-account-step-3"
             "phase-a-trie-multi.json/geth-tiny-account-five-step"
             "phase-a-trie-multi.json/geth-stacktrie-short-branch-growth"
             "phase-a-trie-multi.json/geth-stacktrie-root-branch-short-long-growth"
             "phase-a-trie-multi.json/geth-stacktrie-extension-branch-short-long-growth"
             "phase-a-trie-multi.json/geth-stacktrie-sparse-root-branch-long-values"
             "phase-a-trie-multi.json/geth-stacktrie-root-branch-nested-right-branch"
             "phase-a-trie-multi.json/geth-stacktrie-root-branch-nested-left-branch"
             "phase-a-trie-multi.json/geth-stacktrie-root-branch-extension-child"
             "phase-a-trie-multi.json/geth-stacktrie-root-branch-left-extension-child"
             "phase-a-trie-multi.json/geth-stacktrie-deep-extension-branch"
             "phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-tail-fanout"
             "phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-shortens-to-three-nibbles"
             "phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-shortens-to-two-nibbles"
             "phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-shortens-to-one-nibble"
             "phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-splits-to-root-branch"
             "phase-a-trie-multi.json/geth-stacktrie-zero-prefix-extension-fanout"
             "phase-a-trie-multi.json/geth-stacktrie-f-prefix-nested-right-branch"
             "phase-a-trie-multi.json/geth-stacktrie-ff-prefix-nested-left-branch"
             "phase-a-trie-multi.json/geth-stacktrie-shared-prefix-tail-fanout"
             "phase-a-trie-multi.json/geth-stacktrie-shared-prefix-shortens-to-two-nibbles"
             "phase-a-trie-multi.json/geth-stacktrie-shared-prefix-shortens-to-one-nibble"
             "phase-a-trie-multi.json/geth-stacktrie-shared-prefix-splits-to-root-branch"
             "phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-1"
             "phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-2"
             "phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-3"
             "phase-a-secureTrie.json/phase-a-secure-zgeth-account-five-step"))
    (:name :intermediate-roots
     :validator validate-trie-reference-intermediate-root-requirements
     :items ("phase-a-trie-multi.json/geth-stacktrie-short-branch-growth"
             "phase-a-trie-multi.json/geth-stacktrie-root-branch-short-long-growth"
             "phase-a-trie-multi.json/geth-stacktrie-extension-branch-short-long-growth"
             "phase-a-trie-multi.json/geth-stacktrie-sparse-root-branch-long-values"
             "phase-a-trie-multi.json/geth-stacktrie-root-branch-nested-right-branch"
             "phase-a-trie-multi.json/geth-stacktrie-root-branch-nested-left-branch"
             "phase-a-trie-multi.json/geth-stacktrie-root-branch-extension-child"
             "phase-a-trie-multi.json/geth-stacktrie-root-branch-left-extension-child"
             "phase-a-trie-multi.json/geth-stacktrie-deep-extension-branch"
             "phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-tail-fanout"
             "phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-shortens-to-three-nibbles"
             "phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-shortens-to-two-nibbles"
             "phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-shortens-to-one-nibble"
             "phase-a-trie-multi.json/geth-stacktrie-long-shared-prefix-splits-to-root-branch"
             "phase-a-trie-multi.json/geth-stacktrie-zero-prefix-extension-fanout"
             "phase-a-trie-multi.json/geth-stacktrie-f-prefix-nested-right-branch"
             "phase-a-trie-multi.json/geth-stacktrie-ff-prefix-nested-left-branch"
             "phase-a-trie-multi.json/geth-stacktrie-shared-prefix-tail-fanout"
             "phase-a-trie-multi.json/geth-stacktrie-shared-prefix-shortens-to-two-nibbles"
             "phase-a-trie-multi.json/geth-stacktrie-shared-prefix-shortens-to-one-nibble"
             "phase-a-trie-multi.json/geth-stacktrie-shared-prefix-splits-to-root-branch"))
    (:name :entry-pairs
     :validator validate-trie-reference-entry-pair-requirements
     :items ("phase-a-trie-multi.json/geth-tiny-account-step-1"
             "phase-a-trie-multi.json/geth-tiny-account-step-2"
             "phase-a-trie-multi.json/geth-tiny-account-step-3"
             "phase-a-trie-multi.json/geth-tiny-account-five-step"
             "phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-1"
             "phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-2"
             "phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-3"
             "phase-a-secureTrie.json/phase-a-secure-zgeth-account-five-step"))
    (:name :proofs
     :validator validate-trie-reference-proof-requirements
     :items ("phase-a-trie-multi.json/geth-large-value-branch"
             "phase-a-trie-multi.json/geth-tiny-account-step-1"
             "phase-a-trie-multi.json/geth-tiny-account-step-2"
             "phase-a-trie-multi.json/geth-tiny-account-step-3"
             "phase-a-trie-multi.json/geth-tiny-account-five-step"
             "phase-a-trie-multi.json/geth-delete-sequence"
             "phase-a-trie-multi.json/geth-empty-value-sequence"
             "phase-a-trie-multi.json/geth-replication-sequence"
             "phase-a-trie-multi.json/geth-random-cases-sequence"
             "phase-a-trie-multi.json/geth-stacktrie-extension-child-boundary"
             "phase-a-secureTrie.json/phase-a-secure-branch-child-branch"
             "phase-a-secureTrie.json/phase-a-secure-branch-child-extension"
             "phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-1"
             "phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-2"
             "phase-a-secureTrie.json/phase-a-secure-zgeth-account-step-3"
             "phase-a-secureTrie.json/phase-a-secure-zgeth-account-five-step"
             "phase-a-secureTrie.json/phase-a-secure-zgeth-delete-sequence"))
    (:name :ranges
     :validator validate-trie-reference-explicit-range-requirements
     :items ("phase-a-trie-multi.json/geth-tiny-account-five-step"
             "phase-a-secureTrie.json/phase-a-secure-zgeth-account-five-step"))))

(defun phase-a-eest-trie-reference-gate-items (name)
  (let ((gate (find name +phase-a-eest-trie-reference-gates+
                    :key (lambda (gate)
                           (getf gate :name)))))
    (unless gate
      (error "Unknown Phase A EEST trie reference gate ~A" name))
    (copy-tree (getf gate :items))))

(defparameter +trie-fixture-required-tags+
  '("leaf-root"
    "branch-root"
    "extension-root"
    "delete-collapse"
    "delete-to-empty"
    "embedded-child-reference"
    "hashed-child-reference"
    "branch-child-references"
    "branch-value"
    "missing-delete-noop"
    "duplicate-overwrite"
    "hex-key"
    "hex-value"
    "secure-key"
    "lookup-assertions"
    "empty-value-delete"
    "single-node-proof"
    "exact-proof-node-rlp"
    "proof-node-rlp"
    "delete-proof-node-rlp"
    "missing-proof-node-rlp"
    "entry-pair-replay"
    "entry-range"))

(defparameter +trie-fixture-root-shapes+
  '("empty" "leaf" "extension" "branch"))

(defparameter +trie-fixture-child-shapes+
  '("leaf" "extension" "branch"))

(defparameter +trie-fixture-child-reference-kinds+
  '("embedded" "hashed"))

(defparameter +trie-fixture-case-fields+
  '("name"
    "secure"
    "tags"
    "operations"
    "expectedIntermediateRoots"
    "expectedRoot"
    "expectedShape"
    "expectedChildReference"
    "expectedRootChildren"
    "expectedRootChildReferences"
    "expectedRootChildShapes"
    "expectedRootPathNibbles"
    "expectedRootValueAscii"
    "expectedRootValueHex"
    "expectedGets"
    "expectedMissing"
    "expectedEntryPairs"
    "expectedEntryRanges"
    "expectedProofPrefixes"))

(defparameter +trie-fixture-operation-fields+
  '("op" "keyHex" "keyAscii" "valueAscii" "valueHex"))

(defparameter +trie-fixture-expected-get-fields+
  '("keyHex" "keyAscii" "valueAscii" "valueHex"))

(defparameter +trie-fixture-expected-missing-fields+
  '("keyHex" "keyAscii"))

(defparameter +trie-fixture-expected-entry-pair-fields+
  '("keyHex" "keyAscii" "valueAscii" "valueHex"))

(defparameter +trie-fixture-expected-entry-range-fields+
  '("startKeyHex" "startKeyAscii" "endKeyHex" "endKeyAscii" "expectedKeys"))

(defparameter +trie-fixture-expected-entry-range-key-fields+
  '("keyHex" "keyAscii"))

(defparameter +trie-fixture-expected-proof-prefix-fields+
  '("keyHex" "keyAscii" "nodeRlps" "exactLength"))

(defparameter +eest-trie-test-case-fields+
  '("entryPairs" "in" "intermediateRoots" "out" "proofs" "ranges" "root" "secure"))

(defparameter +eest-trie-test-entry-pair-fields+
  '("key" "value"))

(defparameter +eest-trie-test-range-fields+
  '("start" "end" "keys"))

(defparameter +eest-trie-test-proof-fields+
  '("key" "nodeRlps" "exactLength"))

(defun validate-trie-fixture-object-fields (object allowed-fields label)
  (unless (listp object)
    (error "~A must be a JSON object" label))
  (let ((seen-fields (make-hash-table :test 'equal)))
    (dolist (field object)
      (let ((name (car field)))
        (unless (stringp name)
          (error "~A field name must be a string" label))
        (when (gethash name seen-fields)
          (error "~A has duplicate field ~A" label name))
        (setf (gethash name seen-fields) t)
        (unless (member name allowed-fields :test #'string=)
          (error "~A has unknown field ~A" label name))))))

(defun validate-trie-fixture-non-empty-string (value label)
  (unless (stringp value)
    (error "~A must be a string" label))
  (when (blank-string-p value)
    (error "~A must be present" label))
  value)

(defun validate-trie-fixture-hash-field (object field label)
  (let ((value (fixture-required-field object field)))
    (unless (stringp value)
      (error "~A ~A must be a hash hex string" label field))
    (let ((hash (hash32-from-hex value)))
      (unless (string= value (hash32-to-hex hash))
        (error "~A ~A must be canonical lowercase 0x-prefixed hash hex"
               label field)))))

(defun validate-trie-fixture-byte-field (value label)
  (unless (stringp value)
    (error "~A must be a hex string" label))
  (handler-case
      (let ((bytes (hex-to-bytes value)))
        (unless (string= value (bytes-to-hex bytes))
          (error "~A must be canonical lowercase 0x-prefixed hex" label)))
    (error (condition)
      (error "~A must be hex bytes: ~A" label condition))))

(defun validate-trie-fixture-value-fields (object label &key allow-empty)
  (let ((has-hex (fixture-field-present-p object "valueHex"))
        (has-ascii (fixture-field-present-p object "valueAscii")))
    (unless (or has-hex has-ascii)
      (error "~A must include valueAscii or valueHex" label))
    (when (and has-hex has-ascii)
      (error "~A must not include both valueAscii and valueHex" label))
    (when has-ascii
      (if allow-empty
          (unless (stringp (fixture-object-field object "valueAscii"))
            (error "~A valueAscii must be a string" label))
          (validate-trie-fixture-non-empty-string
           (fixture-object-field object "valueAscii")
           (format nil "~A valueAscii" label))))
    (when has-hex
      (let ((value (fixture-object-field object "valueHex")))
        (validate-trie-fixture-byte-field
         value
         (format nil "~A valueHex" label))
        (when (and (not allow-empty)
                   (zerop (length (hex-to-bytes value))))
          (error "~A valueHex must not be empty" label))))))

(defun validate-trie-fixture-metadata (fixture)
  (validate-trie-fixture-object-fields
   fixture
   +trie-fixture-top-level-fields+
   "Trie fixture")
  (validate-fixture-format fixture +trie-vector-fixture-format+)
  (validate-trie-fixture-non-empty-string
   (fixture-required-field fixture "source")
   "Trie fixture source")
  (validate-fixture-pinned-eest-source fixture))

(defun validate-trie-fixture-case-name (case seen-names)
  (let ((name (fixture-object-field case "name")))
    (validate-trie-fixture-non-empty-string
     name
     "Trie fixture case name")
    (let ((previous (gethash name seen-names)))
      (when previous
        (error "Duplicate trie fixture case name: ~A" name)))
    (setf (gethash name seen-names) t)))

(defun validate-trie-fixture-case-tags (case seen-tags)
  (let ((name (fixture-object-field case "name"))
        (tags (fixture-object-field case "tags")))
    (unless (and (listp tags) tags)
      (error "Trie fixture case ~A must include non-empty tags" name))
    (let ((case-tags (make-hash-table :test 'equal)))
      (dolist (tag tags)
        (when (gethash tag case-tags)
          (error "Trie fixture case ~A has duplicate tag ~A" name tag))
        (setf (gethash tag case-tags) t)
        (unless (and (stringp tag)
                     (member tag +trie-fixture-known-tags+
                             :test #'string=))
          (error "Trie fixture case ~A has unknown tag ~A" name tag))
        (setf (gethash tag seen-tags) t)))))

(defun validate-trie-fixture-key-fields (object label)
  (let ((has-hex (fixture-field-present-p object "keyHex"))
        (has-ascii (fixture-field-present-p object "keyAscii")))
    (unless (or has-hex has-ascii)
      (error "~A must include keyHex or keyAscii" label))
    (when (and has-hex has-ascii)
      (error "~A must not include both keyHex and keyAscii" label))
    (when has-hex
      (validate-trie-fixture-byte-field
       (fixture-object-field object "keyHex")
       (format nil "~A keyHex" label)))
    (when has-ascii
      (let ((key (fixture-object-field object "keyAscii")))
        (validate-trie-fixture-non-empty-string
         key
         (format nil "~A keyAscii" label))))))

(defun validate-trie-fixture-operation (operation case-name)
  (unless (listp operation)
    (error "Trie fixture case ~A operation must be a JSON object" case-name))
  (validate-trie-fixture-object-fields
   operation
   +trie-fixture-operation-fields+
   (format nil "Trie fixture case ~A operation" case-name))
  (validate-trie-fixture-key-fields operation
                                    (format nil "Trie fixture case ~A operation"
                                            case-name))
  (let ((op (fixture-object-field operation "op")))
    (unless (stringp op)
      (error "Trie fixture case ~A operation op must be a string" case-name))
    (cond
      ((string= op "put")
       (validate-trie-fixture-value-fields
        operation
        (format nil "Trie fixture case ~A put operation" case-name)
        :allow-empty t))
      ((string= op "delete")
       (when (fixture-field-present-p operation "valueAscii")
         (error "Trie fixture case ~A delete operation must not include valueAscii"
                case-name))
       (when (fixture-field-present-p operation "valueHex")
         (error "Trie fixture case ~A delete operation must not include valueHex"
                case-name)))
      (t (error "Unknown trie fixture operation in case ~A: ~A"
                case-name op)))))

(defun validate-trie-fixture-expected-lookup (expected case-name field)
  (unless (listp expected)
    (error "Trie fixture case ~A ~A entry must be a JSON object"
           case-name field))
  (validate-trie-fixture-object-fields
   expected
   (if (string= field "expectedGets")
       +trie-fixture-expected-get-fields+
       +trie-fixture-expected-missing-fields+)
   (format nil "Trie fixture case ~A ~A entry" case-name field))
  (validate-trie-fixture-key-fields expected
                                    (format nil "Trie fixture case ~A ~A entry"
                                            case-name field))
  (cond
    ((string= field "expectedGets")
     (validate-trie-fixture-value-fields
      expected
      (format nil "Trie fixture case ~A expectedGets entry" case-name)))
    ((string= field "expectedMissing")
     (when (fixture-field-present-p expected "valueAscii")
       (error "Trie fixture case ~A expectedMissing entry must not include valueAscii"
              case-name))
     (when (fixture-field-present-p expected "valueHex")
       (error "Trie fixture case ~A expectedMissing entry must not include valueHex"
              case-name)))))

(defun validate-trie-fixture-expected-proof-prefix (expected case-name)
  (unless (listp expected)
    (error "Trie fixture case ~A expectedProofPrefixes entry must be a JSON object"
           case-name))
  (validate-trie-fixture-object-fields
   expected
   +trie-fixture-expected-proof-prefix-fields+
   (format nil "Trie fixture case ~A expectedProofPrefixes entry" case-name))
  (validate-trie-fixture-key-fields
   expected
   (format nil "Trie fixture case ~A expectedProofPrefixes entry"
           case-name))
  (when (fixture-field-present-p expected "exactLength")
    (let ((exact-length (fixture-object-field expected "exactLength")))
      (unless (or (eq exact-length t) (null exact-length))
        (error "Trie fixture case ~A expectedProofPrefixes exactLength must be a boolean"
               case-name))))
  (let ((node-rlps (fixture-required-field expected "nodeRlps")))
    (unless (and (listp node-rlps) node-rlps)
      (error "Trie fixture case ~A expectedProofPrefixes nodeRlps must be a non-empty list"
             case-name))
    (dolist (node-rlp node-rlps)
      (validate-trie-fixture-byte-field
       node-rlp
       (format nil "Trie fixture case ~A expectedProofPrefixes nodeRlp"
               case-name))
      (when (zerop (length (hex-to-bytes node-rlp)))
        (error "Trie fixture case ~A expectedProofPrefixes nodeRlp must not be empty"
               case-name)))))

(defun validate-trie-fixture-expected-entry-pair (expected case-name)
  (unless (listp expected)
    (error "Trie fixture case ~A expectedEntryPairs entry must be a JSON object"
           case-name))
  (validate-trie-fixture-object-fields
   expected
   +trie-fixture-expected-entry-pair-fields+
   (format nil "Trie fixture case ~A expectedEntryPairs entry" case-name))
  (validate-trie-fixture-key-fields
   expected
   (format nil "Trie fixture case ~A expectedEntryPairs entry" case-name))
  (validate-trie-fixture-value-fields
   expected
   (format nil "Trie fixture case ~A expectedEntryPairs entry" case-name)))

(defun validate-trie-fixture-entry-range-bound (expected case-name prefix)
  (let* ((hex-field (format nil "~AKeyHex" prefix))
         (ascii-field (format nil "~AKeyAscii" prefix))
         (has-hex (fixture-field-present-p expected hex-field))
         (has-ascii (fixture-field-present-p expected ascii-field))
         (label (format nil "Trie fixture case ~A expectedEntryRanges ~A bound"
                        case-name
                        prefix)))
    (when (and has-hex has-ascii)
      (error "~A must not include both ~A and ~A"
             label hex-field ascii-field))
    (when has-hex
      (validate-trie-fixture-byte-field
       (fixture-object-field expected hex-field)
       (format nil "~A ~A" label hex-field)))
    (when has-ascii
      (let ((key (fixture-object-field expected ascii-field)))
        (validate-trie-fixture-non-empty-string
         key
         (format nil "~A ~A" label ascii-field))))))

(defun validate-trie-fixture-entry-range-key (expected case-name)
  (unless (listp expected)
    (error "Trie fixture case ~A expectedEntryRanges expectedKeys entry must be a JSON object"
           case-name))
  (validate-trie-fixture-object-fields
   expected
   +trie-fixture-expected-entry-range-key-fields+
   (format nil "Trie fixture case ~A expectedEntryRanges expectedKeys entry"
           case-name))
  (validate-trie-fixture-key-fields
   expected
   (format nil "Trie fixture case ~A expectedEntryRanges expectedKeys entry"
           case-name)))

(defun validate-trie-fixture-expected-entry-range (expected case-name)
  (unless (listp expected)
    (error "Trie fixture case ~A expectedEntryRanges entry must be a JSON object"
           case-name))
  (validate-trie-fixture-object-fields
   expected
   +trie-fixture-expected-entry-range-fields+
   (format nil "Trie fixture case ~A expectedEntryRanges entry" case-name))
  (validate-trie-fixture-entry-range-bound expected case-name "start")
  (validate-trie-fixture-entry-range-bound expected case-name "end")
  (let ((expected-keys (fixture-required-field expected "expectedKeys"))
        (seen-keys (make-hash-table :test 'equal)))
    (unless (listp expected-keys)
      (error "Trie fixture case ~A expectedEntryRanges expectedKeys must be a list"
             case-name))
    (dolist (key-entry expected-keys)
      (validate-trie-fixture-entry-range-key key-entry case-name)
      (let ((key (bytes-to-hex (trie-fixture-key key-entry))))
        (when (gethash key seen-keys)
          (error "Trie fixture case ~A expectedEntryRanges has duplicate expected key ~A"
                 case-name
                 key))
        (setf (gethash key seen-keys) t)))))

(defun validate-trie-fixture-expected-lookup-keys (case)
  (let ((seen-keys (make-hash-table :test 'equal))
        (case-name (fixture-object-field case "name")))
    (labels ((record-key (expected field)
               (let* ((key (bytes-to-hex (trie-fixture-key expected)))
                      (previous-field (gethash key seen-keys)))
                 (when previous-field
                   (error "Trie fixture case ~A has duplicate lookup key ~A in ~A and ~A"
                          case-name
                          key
                          previous-field
                          field))
                 (setf (gethash key seen-keys) field))))
      (dolist (expected (fixture-object-field case "expectedGets"))
        (record-key expected "expectedGets"))
      (dolist (expected (fixture-object-field case "expectedMissing"))
        (record-key expected "expectedMissing")))))

(defun trie-fixture-valid-child-reference-kind-p (kind)
  (member kind +trie-fixture-child-reference-kinds+ :test #'string=))

(defun validate-trie-fixture-expected-root (case)
  (validate-trie-fixture-hash-field
   case
   "expectedRoot"
   "Trie fixture case"))

(defun validate-trie-fixture-expected-intermediate-roots (case)
  (when (fixture-field-present-p case "expectedIntermediateRoots")
    (let ((roots (fixture-object-field case "expectedIntermediateRoots"))
          (operations (fixture-object-field case "operations"))
          (name (fixture-object-field case "name")))
      (unless (listp roots)
        (error "Trie fixture case ~A expectedIntermediateRoots must be a JSON array"
               name))
      (unless (= (length roots) (length operations))
        (error "Trie fixture case ~A expectedIntermediateRoots must match operation count"
               name))
      (loop for root in roots
            for index from 0
            do (validate-trie-fixture-byte-field
                root
                (format nil "Trie fixture case ~A expectedIntermediateRoots ~D"
                        name
                        index))
               (unless (= 32 (length (hex-to-bytes root)))
                 (error "Trie fixture case ~A expectedIntermediateRoots ~D must be a 32-byte hash"
                        name
                        index))))))

(defun validate-trie-fixture-expected-shape (case)
  (let ((shape (fixture-required-field case "expectedShape")))
    (unless (stringp shape)
      (error "Trie fixture case ~A expectedShape must be a string"
             (fixture-object-field case "name")))
    (unless (member shape +trie-fixture-root-shapes+ :test #'string=)
      (error "Trie fixture case ~A has unknown expectedShape ~A"
             (fixture-object-field case "name")
             shape))
    shape))

(defun validate-trie-fixture-nibble-list (case field &key allow-terminator)
  (when (fixture-field-present-p case field)
    (let ((nibbles (fixture-object-field case field)))
      (unless (listp nibbles)
        (error "Trie fixture case ~A ~A must be a JSON array"
               (fixture-object-field case "name")
               field))
      (dolist (nibble nibbles)
        (unless (and (integerp nibble)
                     (<= 0 nibble)
                     (if allow-terminator
                         (<= nibble 16)
                         (< nibble 16)))
          (error "Trie fixture case ~A has malformed ~A nibble ~A"
                 (fixture-object-field case "name")
                 field
                 nibble))))))

(defun validate-trie-fixture-root-children (case)
  (when (fixture-field-present-p case "expectedRootChildren")
    (let ((children (fixture-object-field case "expectedRootChildren"))
          (seen (make-hash-table)))
      (unless (listp children)
        (error "Trie fixture case ~A expectedRootChildren must be a JSON array"
               (fixture-object-field case "name")))
      (dolist (child children)
        (unless (and (integerp child) (<= 0 child 15))
          (error "Trie fixture case ~A has malformed root child index ~A"
                 (fixture-object-field case "name")
                 child))
        (when (gethash child seen)
          (error "Trie fixture case ~A has duplicate root child index ~A"
                 (fixture-object-field case "name")
                 child))
        (setf (gethash child seen) t)))))

(defun parse-trie-fixture-child-reference-index (case raw-index)
  (unless (stringp raw-index)
    (error "Trie fixture case ~A child reference index must be a string"
           (fixture-object-field case "name")))
  (multiple-value-bind (index position)
      (parse-integer raw-index :junk-allowed t)
    (unless (and index (= position (length raw-index)) (<= 0 index 15))
      (error "Trie fixture case ~A has malformed child reference index ~A"
             (fixture-object-field case "name")
             raw-index))
    index))

(defun validate-trie-fixture-root-child-references (case)
  (when (fixture-field-present-p case "expectedRootChildReferences")
    (let ((references
            (fixture-object-field case "expectedRootChildReferences"))
          (seen-indexes (make-hash-table)))
      (unless (listp references)
        (error "Trie fixture case ~A expectedRootChildReferences must be a JSON object"
               (fixture-object-field case "name")))
      (dolist (reference references)
        (let ((index (parse-trie-fixture-child-reference-index
                      case
                      (car reference)))
              (kind (cdr reference)))
          (when (gethash index seen-indexes)
            (error "Trie fixture case ~A has duplicate child reference index ~A"
                   (fixture-object-field case "name")
                   (car reference)))
          (setf (gethash index seen-indexes) t)
          (unless (stringp kind)
            (error "Trie fixture case ~A child reference kind must be a string"
                   (fixture-object-field case "name")))
          (unless (trie-fixture-valid-child-reference-kind-p kind)
            (error "Trie fixture case ~A has unknown child reference kind ~A"
                   (fixture-object-field case "name")
                   kind)))))))

(defun validate-trie-fixture-root-child-shapes (case)
  (when (fixture-field-present-p case "expectedRootChildShapes")
    (let ((shapes
            (fixture-object-field case "expectedRootChildShapes"))
          (seen-indexes (make-hash-table)))
      (unless (listp shapes)
        (error "Trie fixture case ~A expectedRootChildShapes must be a JSON object"
               (fixture-object-field case "name")))
      (dolist (shape-entry shapes)
        (let ((index (parse-trie-fixture-child-reference-index
                      case
                      (car shape-entry)))
              (shape (cdr shape-entry)))
          (when (gethash index seen-indexes)
            (error "Trie fixture case ~A has duplicate child shape index ~A"
                   (fixture-object-field case "name")
                   (car shape-entry)))
          (setf (gethash index seen-indexes) t)
          (unless (stringp shape)
            (error "Trie fixture case ~A child shape must be a string"
                   (fixture-object-field case "name")))
          (unless (member shape +trie-fixture-child-shapes+ :test #'string=)
            (error "Trie fixture case ~A has unknown child shape ~A"
                   (fixture-object-field case "name")
                   shape)))))))

(defun validate-trie-fixture-expected-fields (case)
  (let ((shape (validate-trie-fixture-expected-shape case)))
    (validate-trie-fixture-expected-root case)
    (validate-trie-fixture-expected-intermediate-roots case)
    (unless (or (not (fixture-field-present-p case "expectedChildReference"))
                (string= shape "extension"))
      (error "Trie fixture case ~A expectedChildReference requires an extension root"
             (fixture-object-field case "name")))
    (when (fixture-field-present-p case "expectedChildReference")
      (let ((kind (fixture-object-field case "expectedChildReference")))
        (unless (stringp kind)
          (error "Trie fixture case ~A expectedChildReference must be a string"
                 (fixture-object-field case "name")))
        (unless (trie-fixture-valid-child-reference-kind-p kind)
          (error "Trie fixture case ~A has unknown expectedChildReference ~A"
                 (fixture-object-field case "name")
                 kind))))
    (unless (or (not (fixture-field-present-p case "expectedRootChildren"))
                (string= shape "branch"))
      (error "Trie fixture case ~A expectedRootChildren requires a branch root"
             (fixture-object-field case "name")))
    (unless (or (not (fixture-field-present-p case "expectedRootChildReferences"))
                (string= shape "branch"))
      (error "Trie fixture case ~A expectedRootChildReferences requires a branch root"
             (fixture-object-field case "name")))
    (unless (or (not (fixture-field-present-p case "expectedRootChildShapes"))
                (string= shape "branch"))
      (error "Trie fixture case ~A expectedRootChildShapes requires a branch root"
             (fixture-object-field case "name")))
    (validate-trie-fixture-root-children case)
    (validate-trie-fixture-root-child-references case)
    (validate-trie-fixture-root-child-shapes case)
    (cond
      ((string= shape "leaf")
       (validate-trie-fixture-nibble-list
        case "expectedRootPathNibbles" :allow-terminator t))
      ((string= shape "extension")
       (validate-trie-fixture-nibble-list
        case "expectedRootPathNibbles"))
      ((fixture-field-present-p case "expectedRootPathNibbles")
       (error "Trie fixture case ~A expectedRootPathNibbles requires a leaf or extension root"
              (fixture-object-field case "name"))))
    (when (fixture-field-present-p case "expectedRootValueAscii")
      (validate-trie-fixture-non-empty-string
       (fixture-object-field case "expectedRootValueAscii")
       (format nil "Trie fixture case ~A expectedRootValueAscii"
               (fixture-object-field case "name"))))
    (when (and (fixture-field-present-p case "expectedRootValueAscii")
               (fixture-field-present-p case "expectedRootValueHex"))
      (error "Trie fixture case ~A must not include both expectedRootValueAscii and expectedRootValueHex"
             (fixture-object-field case "name")))
    (when (fixture-field-present-p case "expectedRootValueHex")
      (let ((value (fixture-object-field case "expectedRootValueHex")))
        (validate-trie-fixture-byte-field
         value
         (format nil "Trie fixture case ~A expectedRootValueHex"
                 (fixture-object-field case "name")))
        (when (zerop (length (hex-to-bytes value)))
          (error "Trie fixture case ~A expectedRootValueHex must not be empty"
                 (fixture-object-field case "name")))))))

(defun validate-trie-fixture-case-shape (case)
  (let ((name (fixture-object-field case "name"))
        (operations (fixture-object-field case "operations")))
    (validate-trie-fixture-object-fields
     case
     +trie-fixture-case-fields+
     (format nil "Trie fixture case ~A" name))
    (when (fixture-field-present-p case "secure")
      (let ((secure (fixture-object-field case "secure")))
        (unless (or (eq secure t) (null secure))
          (error "Trie fixture case ~A secure must be a boolean" name))))
    (unless (and (listp operations) operations)
      (error "Trie fixture case ~A must include non-empty operations" name))
    (validate-trie-fixture-expected-fields case)
    (dolist (operation operations)
      (validate-trie-fixture-operation operation name))
    (dolist (expected (fixture-object-field case "expectedGets"))
      (validate-trie-fixture-expected-lookup expected name "expectedGets"))
    (dolist (expected (fixture-object-field case "expectedMissing"))
      (validate-trie-fixture-expected-lookup expected name "expectedMissing"))
    (dolist (expected (fixture-object-field case "expectedEntryPairs"))
      (validate-trie-fixture-expected-entry-pair expected name))
    (dolist (expected (fixture-object-field case "expectedEntryRanges"))
      (validate-trie-fixture-expected-entry-range expected name))
    (dolist (expected (fixture-object-field case "expectedProofPrefixes"))
      (validate-trie-fixture-expected-proof-prefix expected name))
    (validate-trie-fixture-expected-lookup-keys case)))

(defun validate-trie-fixture-case-coverage (cases)
  (unless (and (listp cases) cases)
    (error "Trie fixture must include at least one case"))
  (let ((seen-names (make-hash-table :test #'equal))
        (seen-tags (make-hash-table :test #'equal))
        secure-leaf-root-p
        secure-delete-to-empty-p
        secure-branch-root-p
        secure-extension-root-p
        secure-entry-pair-replay-p
        entry-range-p
        exact-proof-node-rlp-p)
    (dolist (case cases)
      (unless (listp case)
        (error "Trie fixture case must be a JSON object"))
      (validate-trie-fixture-case-name case seen-names)
      (validate-trie-fixture-case-tags case seen-tags)
      (let ((secure-p (not (null (fixture-object-field case "secure"))))
            (shape (fixture-object-field case "expectedShape")))
        (when (and secure-p (stringp shape) (string= shape "branch"))
          (setf secure-branch-root-p t))
        (when (and secure-p (stringp shape) (string= shape "extension"))
          (setf secure-extension-root-p t))
        (when (and secure-p (stringp shape) (string= shape "leaf"))
          (setf secure-leaf-root-p t))
        (when (and secure-p
                   (member "entry-pair-replay"
                           (fixture-object-field case "tags")
                           :test #'string=))
          (setf secure-entry-pair-replay-p t))
        (when (and (member "entry-range"
                           (fixture-object-field case "tags")
                           :test #'string=)
                   (fixture-object-field case "expectedEntryRanges"))
          (setf entry-range-p t))
        (when (some (lambda (expected)
                      (fixture-object-field expected "exactLength"))
                    (fixture-object-field case "expectedProofPrefixes"))
          (setf exact-proof-node-rlp-p t))
        (when (and secure-p
                   (stringp shape)
                   (string= shape "empty")
                   (member "delete-to-empty"
                           (fixture-object-field case "tags")
                           :test #'string=))
          (setf secure-delete-to-empty-p t))))
    (dolist (tag +trie-fixture-required-tags+)
      (unless (gethash tag seen-tags)
        (error "Trie fixture is missing required coverage tag ~A" tag)))
    (unless secure-leaf-root-p
      (error "Trie fixture must include a secure leaf root case"))
    (unless secure-delete-to-empty-p
      (error "Trie fixture must include a secure delete-to-empty case"))
    (unless secure-branch-root-p
      (error "Trie fixture must include a secure branch root case"))
    (unless secure-extension-root-p
      (error "Trie fixture must include a secure extension root case"))
    (unless secure-entry-pair-replay-p
      (error "Trie fixture must include a secure entry-pair replay case"))
    (unless entry-range-p
      (error "Trie fixture must include entry-range coverage"))
    (unless exact-proof-node-rlp-p
      (error "Trie fixture must include exact proof-node RLP coverage"))))

(defun validate-trie-fixture-required-case-names (cases)
  (let ((case-by-name (make-hash-table :test #'equal))
        (seen-required-names (make-hash-table :test #'equal)))
    (dolist (case cases)
      (setf (gethash (fixture-required-field case "name") case-by-name)
            case))
    (dolist (name +trie-fixture-required-case-names+)
      (when (gethash name seen-required-names)
        (error "Trie fixture required case list has duplicate name ~A"
               name))
      (setf (gethash name seen-required-names) t)
      (unless (gethash name case-by-name)
        (error "Trie fixture is missing required seed case ~A"
               name)))))

(defun trie-reference-case-mode (case)
  (if (fixture-object-field case "secure")
      :secure
      :plain))

(defun validate-trie-reference-case-requirements
    (cases requirements label)
  (let ((case-by-name (make-hash-table :test #'equal))
        (seen-requirements (make-hash-table :test #'equal)))
    (dolist (case cases)
      (setf (gethash (fixture-required-field case "name") case-by-name)
            case))
    (dolist (requirement requirements)
      (destructuring-bind (name . expected-mode) requirement
        (unless (member expected-mode '(:plain :secure))
          (error "~A reference case ~A has unknown required mode ~A"
                 label
                 name
                 expected-mode))
        (when (gethash name seen-requirements)
          (error "~A reference case list has duplicate name ~A"
                 label
                 name))
        (setf (gethash name seen-requirements) t)
        (let ((case (gethash name case-by-name)))
          (unless case
            (error "~A is missing required reference-derived trie case ~A"
                   label
                   name))
          (let ((actual-mode (trie-reference-case-mode case)))
            (unless (eq actual-mode expected-mode)
              (error "~A reference-derived trie case ~A must be ~A, got ~A"
                     label
                     name
                     expected-mode
                     actual-mode))))))))

(defun validate-trie-reference-explicit-output-requirements
    (cases names label)
  (let ((case-by-name (make-hash-table :test #'equal))
        (seen-names (make-hash-table :test #'equal)))
    (dolist (case cases)
      (setf (gethash (fixture-required-field case "name") case-by-name)
            case))
    (dolist (name names)
      (when (gethash name seen-names)
        (error "~A explicit-output reference list has duplicate name ~A"
               label
               name))
      (setf (gethash name seen-names) t)
      (let ((case (gethash name case-by-name)))
        (unless case
          (error "~A is missing explicit-output reference case ~A"
                 label
                 name))
        (unless (fixture-field-present-p case "expectedOut")
          (error "~A reference-derived trie case ~A must include explicit out assertions"
                 label
                 name))
        (multiple-value-bind (present-count missing-count)
            (eest-trie-test-explicit-output-counts case)
          (unless (and (plusp present-count)
                       (plusp missing-count))
            (error "~A reference-derived trie case ~A explicit out must include present and missing keys"
                   label
                   name)))))))

(defun validate-trie-reference-intermediate-root-requirements
    (cases names label)
  (let ((case-by-name (make-hash-table :test #'equal))
        (seen-names (make-hash-table :test #'equal)))
    (dolist (case cases)
      (setf (gethash (fixture-required-field case "name") case-by-name)
            case))
    (dolist (name names)
      (when (gethash name seen-names)
        (error "~A intermediate-root reference list has duplicate name ~A"
               label
               name))
      (setf (gethash name seen-names) t)
      (let ((case (gethash name case-by-name)))
        (unless case
          (error "~A is missing intermediate-root reference case ~A"
                 label
                 name))
        (unless (fixture-field-present-p case "expectedIntermediateRoots")
          (error "~A reference-derived trie case ~A must include intermediate root assertions"
                 label
                 name))
        (unless (fixture-object-field case "expectedIntermediateRoots")
          (error "~A reference-derived trie case ~A intermediate roots must not be empty"
                 label
                 name))))))

(defun validate-trie-reference-entry-pair-requirements
    (cases names label)
  (let ((case-by-name (make-hash-table :test #'equal))
        (seen-names (make-hash-table :test #'equal)))
    (dolist (case cases)
      (setf (gethash (fixture-required-field case "name") case-by-name)
            case))
    (dolist (name names)
      (when (gethash name seen-names)
        (error "~A entry-pair reference list has duplicate name ~A"
               label
               name))
      (setf (gethash name seen-names) t)
      (let ((case (gethash name case-by-name)))
        (unless case
          (error "~A is missing entry-pair reference case ~A"
                 label
                 name))
        (unless (fixture-field-present-p case "expectedEntryPairs")
          (error "~A reference-derived trie case ~A must include explicit entry-pair assertions"
                 label
                 name))
        (unless (fixture-object-field case "expectedEntryPairs")
          (error "~A reference-derived trie case ~A explicit entry-pair assertions must not be empty"
                 label
                 name))))))

(defun validate-trie-reference-proof-requirements
    (cases names label)
  (let ((case-by-name (make-hash-table :test #'equal))
        (seen-names (make-hash-table :test #'equal)))
    (dolist (case cases)
      (setf (gethash (fixture-required-field case "name") case-by-name)
            case))
    (dolist (name names)
      (when (gethash name seen-names)
        (error "~A proof reference list has duplicate name ~A"
               label
               name))
      (setf (gethash name seen-names) t)
      (let ((case (gethash name case-by-name)))
        (unless case
          (error "~A is missing proof reference case ~A"
                 label
                 name))
        (unless (fixture-field-present-p case "expectedProofs")
          (error "~A reference-derived trie case ~A must include proof-node assertions"
                 label
                 name))
        (unless (fixture-object-field case "expectedProofs")
          (error "~A reference-derived trie case ~A proof-node assertions must not be empty"
                 label
                 name))))))

(defun validate-trie-reference-explicit-range-requirements
    (cases names label)
  (let ((case-by-name (make-hash-table :test #'equal))
        (seen-names (make-hash-table :test #'equal)))
    (dolist (case cases)
      (setf (gethash (fixture-required-field case "name") case-by-name)
            case))
    (dolist (name names)
      (when (gethash name seen-names)
        (error "~A explicit-range reference list has duplicate name ~A"
               label
               name))
      (setf (gethash name seen-names) t)
      (let ((case (gethash name case-by-name)))
        (unless case
          (error "~A is missing explicit-range reference case ~A"
                 label
                 name))
        (unless (fixture-field-present-p case "expectedRanges")
          (error "~A reference-derived trie case ~A must include explicit range assertions"
                 label
                 name))
        (unless (fixture-object-field case "expectedRanges")
          (error "~A reference-derived trie case ~A explicit ranges must not be empty"
                 label
                 name))))))

(defun validate-trie-reference-gates (cases gates label)
  (let ((seen-gates (make-hash-table :test #'eq)))
    (dolist (gate gates)
      (let ((name (getf gate :name))
            (validator (getf gate :validator))
            (items (getf gate :items)))
        (unless name
          (error "~A reference gate is missing a name" label))
        (when (gethash name seen-gates)
          (error "~A reference gate list has duplicate gate ~A"
                 label
                 name))
        (setf (gethash name seen-gates) t)
        (unless (and validator (fboundp validator))
          (error "~A reference gate ~A has unknown validator ~A"
                 label
                 name
                 validator))
        (unless items
          (error "~A reference gate ~A must include required items"
                 label
                 name))
        (funcall (symbol-function validator) cases items label)))))

(defun validate-trie-fixture-entry-pair-reference-cases
    (cases names label)
  (let ((case-by-name (make-hash-table :test #'equal))
        (seen-names (make-hash-table :test #'equal)))
    (dolist (case cases)
      (setf (gethash (fixture-required-field case "name") case-by-name)
            case))
    (dolist (name names)
      (when (gethash name seen-names)
        (error "~A entry-pair reference list has duplicate name ~A"
               label
               name))
      (setf (gethash name seen-names) t)
      (let ((case (gethash name case-by-name)))
        (unless case
          (error "~A is missing entry-pair reference case ~A"
                 label
                 name))
        (unless (member "entry-pair-replay"
                        (fixture-object-field case "tags")
                        :test #'string=)
          (error "~A reference-derived trie case ~A must include entry-pair replay"
                 label
                 name))
        (unless (fixture-object-field case "expectedEntryPairs")
          (error "~A reference-derived trie case ~A must include expectedEntryPairs"
                 label
                 name))))))

(defun validate-trie-fixture-account-proof-reference-cases
    (cases names label)
  (let ((case-by-name (make-hash-table :test #'equal))
        (seen-names (make-hash-table :test #'equal)))
    (dolist (case cases)
      (setf (gethash (fixture-required-field case "name") case-by-name)
            case))
    (dolist (name names)
      (when (gethash name seen-names)
        (error "~A account-proof reference list has duplicate name ~A"
               label
               name))
      (setf (gethash name seen-names) t)
      (let ((case (gethash name case-by-name)))
        (unless case
          (error "~A is missing account-proof reference case ~A"
                 label
                 name))
        (unless (member "exact-proof-node-rlp"
                        (fixture-object-field case "tags")
                        :test #'string=)
          (error "~A reference-derived trie case ~A must include exact proof-node RLP"
                 label
                 name))
        (unless (member "missing-proof-node-rlp"
                        (fixture-object-field case "tags")
                        :test #'string=)
          (error "~A reference-derived trie case ~A must include missing proof-node RLP"
                 label
                 name))
        (unless (fixture-object-field case "expectedMissing")
          (error "~A reference-derived trie case ~A must include missing-key proof assertions"
                 label
                 name))
        (let ((prefixes (fixture-object-field case "expectedProofPrefixes")))
          (unless prefixes
            (error "~A reference-derived trie case ~A must include expectedProofPrefixes"
                   label
                   name))
          (dolist (prefix prefixes)
            (unless (fixture-object-field prefix "exactLength")
              (error "~A reference-derived trie case ~A proof prefix must be exact-length"
                     label
                     name))))))))

(defun validate-trie-fixture-cases (cases)
  (validate-trie-fixture-case-coverage cases)
  (validate-trie-reference-case-requirements
   cases
   +trie-fixture-reference-case-requirements+
   "Seed trie fixture")
  (validate-trie-fixture-entry-pair-reference-cases
   cases
   +trie-fixture-entry-pair-reference-case-names+
   "Seed trie fixture")
  (validate-trie-fixture-account-proof-reference-cases
   cases
   +trie-fixture-account-proof-reference-case-names+
   "Seed trie fixture")
  (dolist (case cases)
    (validate-trie-fixture-case-shape case)))

