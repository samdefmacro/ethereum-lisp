(in-package #:ethereum-lisp.test)

(defparameter +state-root-fixture-path+
  "tests/fixtures/execution-spec-tests/state-roots.json")

(defparameter +state-proof-fixture-path+
  "tests/fixtures/execution-spec-tests/state-proofs.json")

(defparameter +state-proof-reference-fixture-path+
  "tests/fixtures/execution-spec-tests/state-proofs-reference.json")

(defparameter +state-root-fixture-format+
  "ethereum-lisp/state-root-fixture-v1")

(defparameter +state-proof-fixture-format+
  "ethereum-lisp/state-proof-fixture-v1")

(defparameter +state-proof-reference-fixture-format+
  "ethereum-lisp/reference-state-proof-fixture-v1")

(defparameter +state-root-fixture-top-level-fields+
  '("format" "source" "executionSpecTests" "cases"))

(defparameter +state-proof-fixture-top-level-fields+
  '("format" "source" "executionSpecTests" "cases"))

(defparameter +state-proof-reference-fixture-top-level-fields+
  '("format" "source" "references" "cases"))

(defparameter +state-root-fixture-case-fields+
  '("name"
    "tags"
    "operations"
    "expectedRoot"
    "expectedStorageRoots"
    "expectedAccounts"
    "expectedAccountRanges"
    "expectedStorageRanges"
    "expectedStorageTrieShapes"
    "expectedStateTrieShape"
    "expectedStateTrieRootPathNibbles"
    "expectedStateTrieChildReference"
    "expectedStateTrieRootChildren"
    "expectedStateTrieRootChildShapes"
    "expectedStateTrieRootChildReferences"))

(defparameter +state-proof-fixture-case-fields+
  '("name"
    "tags"
    "operations"
    "request"
    "expectedRoot"
    "expectedProof"))

(defparameter +state-proof-reference-fixture-case-fields+
  '("name" "reference" "expectedRoot" "expectedProof"))

(defparameter +state-proof-reference-fields+
  '("client" "commit" "path" "test"))

(defparameter +state-proof-fixture-request-fields+
  '("address" "storageKeys"))

(defparameter +state-proof-fixture-proof-fields+
  '("address"
    "accountProof"
    "balance"
    "codeHash"
    "nonce"
    "storageHash"
    "storageProof"))

(defparameter +state-proof-fixture-storage-proof-fields+
  '("key" "value" "proof"))

(defparameter +state-root-fixture-operation-fields+
  '("op" "address" "recipient" "nonce" "balance" "amount" "slot" "value"
    "code"))

(defparameter +state-root-fixture-storage-root-fields+
  '("address" "root"))

(defparameter +state-root-fixture-storage-trie-shape-fields+
  '("address"
    "shape"
    "rootPathNibbles"
    "childReference"
    "rootChildren"
    "rootChildShapes"
    "rootChildReferences"))

(defparameter +state-root-fixture-account-fields+
  '("address" "nonce" "balance" "storageRoot" "codeHash" "rlp"))

(defparameter +state-root-fixture-account-range-fields+
  '("startProofKey" "endProofKey" "expectedAccounts"))

(defparameter +state-root-fixture-account-range-account-fields+
  '("proofKey" "address" "rlp" "code" "storage"))

(defparameter +state-root-fixture-account-range-storage-fields+
  '("slot" "value"))

(defparameter +state-root-fixture-storage-range-fields+
  '("address" "startProofKey" "endProofKey" "expectedStorage"))

(defparameter +state-root-fixture-storage-range-entry-fields+
  '("proofKey" "slot" "value"))

(defparameter +state-root-fixture-known-tags+
  '("empty-state-root"
    "account-root"
    "storage-root"
    "storage-delete"
    "storage-prune"
    "storage-root-projection"
    "code-root"
    "code-delete"
    "code-prune"
    "code-update"
    "multi-account"
    "account-projection"
    "account-range"
    "storage-range"
    "account-update"
    "balance-update"
    "value-transfer"
    "account-prune"
    "account-clear-missing-noop"
    "storage-update"
    "storage-update-delete"
    "storage-delete-missing-noop"
    "state-trie-leaf"
    "state-trie-branch"
    "state-trie-branch-child-references"
    "state-trie-extension"
    "state-trie-extension-child-reference"
    "state-trie-branch-extension"
    "state-trie-delete-collapse"
    "storage-trie-leaf"
    "storage-trie-branch"
    "storage-trie-branch-child-shapes"
    "storage-trie-branch-child-references"
    "storage-trie-extension"
    "storage-trie-extension-child-reference"
    "storage-trie-delete-to-empty"
    "storage-trie-delete-collapse"))

(defparameter +state-root-fixture-required-case-names+
  '("empty-state-root"
    "storage-zero-write-missing-account-keeps-empty-root"
    "single-account-nonce-balance-root"
    "storage-zero-write-funded-empty-storage-keeps-account-root"
    "storage-zero-write-code-account-keeps-code-root"
    "explicit-empty-account-root"
    "explicit-empty-account-clear-prunes-to-empty-root"
    "account-update-overwrites-nonce-balance-root"
    "account-update-preserves-storage-root"
    "account-update-preserves-code-and-storage-root"
    "balance-add-creates-account-root"
    "balance-add-zero-missing-account-keeps-empty-root"
    "balance-add-zero-funded-account-keeps-account-root"
    "balance-add-preserves-code-and-storage-root"
    "value-transfer-creates-recipient-account-root"
    "value-transfer-preserves-code-and-storage-root"
    "value-transfer-zero-missing-recipient-keeps-root"
    "state-trie-branch-value-transfer-creates-recipient-root"
    "state-trie-extension-value-transfer-creates-recipient-root"
    "state-trie-branch-extension-value-transfer-creates-recipient-root"
    "state-trie-branch-balance-add-zero-missing-keeps-root"
    "state-trie-branch-balance-add-zero-existing-keeps-root"
    "state-trie-branch-balance-add-keeps-sibling-root"
    "state-trie-extension-balance-add-keeps-sibling-root"
    "state-trie-extension-balance-add-zero-missing-keeps-root"
    "state-trie-extension-balance-add-zero-existing-keeps-root"
    "state-trie-branch-extension-balance-add-keeps-sibling-root"
    "state-trie-branch-extension-balance-add-zero-missing-keeps-root"
    "state-trie-branch-extension-balance-add-zero-existing-keeps-root"
    "account-clear-prunes-to-empty-root"
    "account-clear-prunes-code-and-storage-root"
    "account-clear-preserves-sibling-account-root"
    "account-clear-missing-keeps-branch-root"
    "state-trie-branch-account-update-keeps-sibling-root"
    "state-trie-branch-account-update-preserves-code-storage-root"
    "state-trie-branch-code-update-keeps-sibling-root"
    "state-trie-branch-code-delete-keeps-sibling-root"
    "account-clear-missing-keeps-extension-root"
    "state-trie-extension-storage-delete-keeps-sibling-root"
    "state-trie-extension-account-update-keeps-sibling-root"
    "state-trie-extension-account-update-preserves-code-storage-root"
    "state-trie-extension-code-update-keeps-sibling-root"
    "state-trie-extension-code-delete-keeps-sibling-root"
    "account-clear-missing-keeps-branch-extension-root"
    "state-trie-branch-extension-storage-delete-keeps-sibling-root"
    "state-trie-branch-extension-account-update-keeps-sibling-root"
    "state-trie-branch-extension-account-update-preserves-code-storage-root"
    "state-trie-branch-extension-code-update-keeps-sibling-root"
    "state-trie-branch-extension-code-delete-keeps-sibling-root"
    "state-trie-branch-clear-code-storage-collapses-to-leaf-root"
    "state-trie-extension-clear-code-storage-collapses-to-leaf-root"
    "state-trie-branch-extension-clear-code-storage-collapses-to-extension-root"
    "single-account-storage-root"
    "storage-update-overwrites-slot-root"
    "storage-update-to-zero-prunes-slot-root"
    "storage-created-account-prunes-to-empty-root"
    "storage-delete-keeps-funded-account-root"
    "single-code-account-root"
    "code-update-overwrites-code-hash-root"
    "code-update-preserves-storage-root"
    "code-created-account-prunes-to-empty-root"
    "code-delete-keeps-funded-account-root"
    "multi-account-secure-state-root"
    "geth-secure-account-state-root-step-1"
    "geth-secure-account-state-root-step-2"
    "geth-secure-account-state-root"
    "nethermind-state-trie-leaf-root"
    "nethermind-state-trie-branch-root"
    "state-trie-branch-storage-delete-keeps-sibling-root"
    "nethermind-state-trie-extension-root"
    "nethermind-state-trie-branch-into-extension-root"
    "state-trie-branch-delete-collapses-to-leaf-root"
    "state-trie-extension-delete-collapses-to-leaf-root"
    "state-trie-branch-extension-delete-collapses-to-extension-root"
    "storage-trie-branch-root"
    "storage-trie-branch-missing-delete-keeps-root"
    "storage-trie-branch-update-keeps-sibling-slot-root"
    "storage-trie-branch-delete-preserves-branch-root"
    "storage-trie-extension-root"
    "storage-trie-extension-missing-delete-keeps-root"
    "storage-trie-extension-update-keeps-sibling-slot-root"
    "storage-trie-extension-delete-preserves-extension-root"
    "storage-trie-branch-delete-collapses-to-leaf-root"
    "storage-trie-extension-delete-collapses-to-leaf-root"))

(defparameter +state-root-fixture-required-tags+
  '("empty-state-root"
    "account-root"
    "storage-root"
    "storage-delete"
    "storage-prune"
    "storage-root-projection"
    "code-root"
    "code-delete"
    "code-prune"
    "code-update"
    "multi-account"
    "account-projection"
    "account-range"
    "storage-range"
    "account-update"
    "balance-update"
    "value-transfer"
    "account-prune"
    "account-clear-missing-noop"
    "storage-update"
    "storage-update-delete"
    "storage-delete-missing-noop"
    "state-trie-leaf"
    "state-trie-branch"
    "state-trie-branch-child-references"
    "state-trie-extension"
    "state-trie-extension-child-reference"
    "state-trie-branch-extension"
    "state-trie-delete-collapse"
    "storage-trie-leaf"
    "storage-trie-branch"
    "storage-trie-branch-child-shapes"
    "storage-trie-branch-child-references"
    "storage-trie-extension"
    "storage-trie-extension-child-reference"
    "storage-trie-delete-to-empty"
    "storage-trie-delete-collapse"))

(defparameter +state-root-fixture-trie-shapes+
  '("empty" "leaf" "extension" "branch"))

(defparameter +state-root-fixture-child-reference-kinds+
  '("embedded" "hashed"))

(defparameter +state-proof-fixture-known-tags+
  '("empty-state-proof"
    "present-account"
    "missing-account"
    "storage-present"
    "storage-missing"
    "no-storage-request"
    "prefixless-storage-key-request"
    "short-storage-key-request"
    "storage-deleted-missing"
    "storage-overwrite-proof"
    "storage-overwrite-delete-proof"
    "multi-storage-present"
    "storage-trie-branch-proof"
    "storage-trie-extension-proof"
    "storage-trie-update-proof"
    "storage-trie-delete-collapse-proof"
    "account-update-proof"
    "balance-update-proof"
    "value-transfer-proof"
    "code-update-proof"
    "code-delete-proof"
    "state-trie-leaf-proof"
    "state-trie-branch-proof"
    "state-trie-branch-missing-after-clear-proof"
    "state-trie-extension-proof"
    "state-trie-extension-missing-after-clear-proof"
    "state-trie-branch-extension-proof"
    "state-trie-branch-extension-missing-after-clear-proof"
    "state-trie-delete-collapse-proof"
    "geth-secure-account-proof"
    "geth-shaped-result"))

(defparameter +state-proof-fixture-required-case-names+
  '("empty-state-missing-account-proof"
    "present-account-with-present-and-missing-storage"
    "present-account-without-storage-key-request"
    "present-account-with-prefixless-storage-key-request"
    "present-account-with-short-storage-key-request"
    "storage-overwrite-final-value-proof"
    "storage-overwrite-to-zero-prunes-slot-proof"
    "missing-account-proof"
    "present-account-deleted-storage-proof"
    "storage-zero-write-missing-account-proof"
    "storage-zero-write-funded-empty-storage-proof"
    "storage-zero-write-code-account-proof"
    "code-update-overwrites-code-hash-proof"
    "code-update-preserves-storage-proof"
    "state-trie-branch-code-update-proof"
    "state-trie-extension-code-update-proof"
    "state-trie-branch-extension-code-update-proof"
    "code-created-account-delete-prunes-proof"
    "code-delete-funded-account-proof"
    "state-trie-branch-code-delete-proof"
    "state-trie-extension-code-delete-proof"
    "state-trie-branch-extension-code-delete-proof"
    "present-account-with-multiple-present-storage-proofs"
    "storage-trie-branch-storage-proof"
    "storage-trie-branch-update-keeps-sibling-slot-proof"
    "storage-trie-branch-delete-preserves-branch-proof"
    "storage-trie-extension-storage-proof"
    "storage-trie-extension-update-keeps-sibling-slot-proof"
    "storage-trie-extension-delete-preserves-extension-proof"
    "storage-trie-delete-collapse-storage-proof"
    "account-update-preserves-code-and-storage-proof"
    "balance-add-creates-account-proof"
    "balance-add-zero-missing-account-proof"
    "balance-add-zero-funded-account-proof"
    "balance-add-preserves-code-and-storage-proof"
    "value-transfer-recipient-proof"
    "state-trie-branch-value-transfer-sender-proof"
    "state-trie-branch-value-transfer-recipient-proof"
    "state-trie-extension-value-transfer-sender-proof"
    "state-trie-extension-value-transfer-recipient-proof"
    "state-trie-branch-extension-value-transfer-sender-proof"
    "state-trie-branch-extension-value-transfer-recipient-proof"
    "state-trie-branch-balance-add-zero-missing-proof"
    "state-trie-branch-balance-add-zero-existing-proof"
    "state-trie-extension-balance-add-zero-missing-proof"
    "state-trie-extension-balance-add-zero-existing-proof"
    "state-trie-branch-extension-balance-add-zero-missing-proof"
    "state-trie-branch-extension-balance-add-zero-existing-proof"
    "state-trie-branch-balance-add-proof"
    "state-trie-extension-balance-add-proof"
    "state-trie-branch-extension-balance-add-proof"
    "state-trie-branch-account-update-preserves-code-storage-proof"
    "state-trie-extension-account-update-preserves-code-storage-proof"
    "state-trie-branch-extension-account-update-preserves-code-storage-proof"
    "state-trie-branch-delete-collapse-survivor-proof"
    "state-trie-extension-delete-collapse-survivor-proof"
    "state-trie-branch-extension-delete-collapse-survivor-proof"
    "state-trie-branch-delete-collapse-deleted-account-proof"
    "state-trie-extension-delete-collapse-deleted-account-proof"
    "state-trie-branch-extension-delete-collapse-deleted-account-proof"
    "state-trie-branch-clear-code-storage-survivor-proof"
    "state-trie-extension-clear-code-storage-survivor-proof"
    "state-trie-branch-extension-clear-code-storage-survivor-proof"
    "state-trie-branch-clear-code-storage-deleted-account-proof"
    "state-trie-extension-clear-code-storage-deleted-account-proof"
    "state-trie-branch-extension-clear-code-storage-deleted-account-proof"
    "nethermind-state-trie-leaf-account-proof"
    "nethermind-state-trie-branch-account-proof"
    "state-trie-branch-missing-account-after-clear-proof"
    "nethermind-state-trie-extension-account-proof"
    "state-trie-extension-missing-account-after-clear-proof"
    "nethermind-state-trie-branch-extension-missing-account-proof"
    "state-trie-branch-extension-missing-account-after-clear-proof"
    "geth-secure-account-state-proof"
    "geth-secure-account-state-second-account-proof"
    "geth-secure-account-state-third-account-proof"))

(defparameter +state-proof-fixture-required-tags+
  '("empty-state-proof"
    "present-account"
    "missing-account"
    "storage-present"
    "storage-missing"
    "no-storage-request"
    "prefixless-storage-key-request"
    "short-storage-key-request"
    "storage-deleted-missing"
    "storage-overwrite-proof"
    "storage-overwrite-delete-proof"
    "multi-storage-present"
    "storage-trie-branch-proof"
    "storage-trie-extension-proof"
    "storage-trie-update-proof"
    "storage-trie-delete-collapse-proof"
    "account-update-proof"
    "balance-update-proof"
    "value-transfer-proof"
    "code-update-proof"
    "code-delete-proof"
    "state-trie-leaf-proof"
    "state-trie-branch-proof"
    "state-trie-branch-missing-after-clear-proof"
    "state-trie-extension-proof"
    "state-trie-extension-missing-after-clear-proof"
    "state-trie-branch-extension-proof"
    "state-trie-branch-extension-missing-after-clear-proof"
    "state-trie-delete-collapse-proof"
    "geth-secure-account-proof"
    "geth-shaped-result"))

