(in-package #:ethereum-lisp.evm.internal)

;;; CHAIN-RULES-FORK-LEVEL (src/protocol/chain-config/rules.lisp) orders the
;;; rules; the historical gas selection below reads it.

(defun context-at-least-fork-level-p (context level)
  ;; A missing rule set is the existing EVM API's "latest supported rules"
  ;; default.  An explicit rule set with no flags is Frontier.
  (let ((rules (and context (evm-context-chain-rules context))))
    (or (null rules)
        (>= (chain-rules-fork-level rules) level))))

(defun context-homestead-p (context)
  (context-at-least-fork-level-p context 3))

(defun context-eip150-p (context)
  (context-at-least-fork-level-p context 4))

(defun context-eip158-p (context)
  (context-at-least-fork-level-p context 6))

(defun context-constantinople-p (context)
  (context-at-least-fork-level-p context 8))

(defun context-petersburg-p (context)
  (context-at-least-fork-level-p context 9))

(defun context-istanbul-p (context)
  (context-at-least-fork-level-p context 10))

(defun context-berlin-p (context)
  (context-at-least-fork-level-p context 11))

(defun context-london-p (context)
  (context-at-least-fork-level-p context 12))

(defun make-child-evm-context (parent
                               &key state address caller call-value input
                                    read-only-p)
  (make-evm-context
   :state state
   :address address
   :caller caller
   :origin (evm-context-origin parent)
   :call-value call-value
   :gas-price (evm-context-gas-price parent)
   :input input
   :coinbase (evm-context-coinbase parent)
   :timestamp (evm-context-timestamp parent)
   :block-number (evm-context-block-number parent)
   :slot-number (evm-context-slot-number parent)
   :prev-randao (evm-context-prev-randao parent)
   :difficulty (evm-context-difficulty parent)
   :random-p (evm-context-random-p parent)
   :gas-limit (evm-context-gas-limit parent)
   :chain-id (evm-context-chain-id parent)
   :chain-rules (evm-context-chain-rules parent)
   :precompile-contracts (evm-context-precompile-contracts parent)
   :base-fee (evm-context-base-fee parent)
   :blob-hashes (evm-context-blob-hashes parent)
   :blob-base-fee (evm-context-blob-base-fee parent)
   :transient-storage (evm-context-transient-storage parent)
   :storage-originals (evm-context-storage-originals parent)
   :storage-clears (evm-context-storage-clears parent)
   :selfdestructed-addresses (evm-context-selfdestructed-addresses parent)
   :accessed-storage (evm-context-accessed-storage parent)
   :accessed-addresses (evm-context-accessed-addresses parent)
   :block-hashes (evm-context-block-hashes parent)
   :created-accounts (evm-context-created-accounts parent)
   :depth (1+ (evm-context-depth parent))
   :read-only-p read-only-p))
