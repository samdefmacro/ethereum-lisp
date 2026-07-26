(in-package #:ethereum-lisp.test)

;;;; Blocks the node must REFUSE.
;;;;
;;;; Every conformance path in this tree drives blocks the node should accept.
;;;; The negative half was structurally absent: the blockchain materializer
;;;; rejects any fixture carrying expectException, and both replay runners build
;;;; their block from transactions rather than decoding one, so a deliberately
;;;; invalid block could not be delivered to them at all.
;;;;
;;;; That absence matters more than the usual coverage gap. A client that
;;;; wrongly ACCEPTS a block follows a chain nobody else is on -- and nothing in
;;;; a valid-only corpus can catch it, because every case it runs is one the
;;;; node is supposed to say yes to.
;;;;
;;;; These drive the Engine API directly with corrupted payloads and assert
;;;; three things each time: the status is INVALID, the block is not retained as
;;;; known, and its state is not available. The last two matter because a node
;;;; that reports INVALID while still canonicalizing the block has diverged just
;;;; as badly, and the status alone would not show it.

(defun invalid-payload-test-response (store config block)
  (let ((payload (execution-payload-envelope-execution-payload
                  (block-to-executable-data block))))
    (cdr (assoc "result"
                (engine-rpc-handle-request
                 (engine-fixture-payload-request 401 payload)
                 store config
                 :import-function #'execute-and-commit-engine-payload)
                :test #'string=))))

(defun invalid-payload-test-status (result)
  (cdr (assoc "status" result :test #'string=)))

(defun assert-payload-refused (store config block label)
  "Submit BLOCK and assert the node refuses it without adopting it."
  (let* ((result (invalid-payload-test-response store config block))
         (status (invalid-payload-test-status result)))
    (is (string= "INVALID" status))
    ;; Refusing in the status while keeping the block would be the same
    ;; divergence wearing a different hat.
    (is (not (chain-store-state-available-p store (block-hash block))))
    (unless (string= "INVALID" status)
      (error "~A was not refused: status ~A" label status))))

(deftest engine-refuses-a-block-whose-state-root-is-wrong
  (:layer :integration :module :engine)
  ;; The single most important thing a client must refuse. A wrong state root
  ;; means the block claims a world state that its own transactions do not
  ;; produce; accepting it is how a client silently forks off the network.
  (multiple-value-bind (store config genesis-block)
      (eth-sync-make-seeded-store *eth-sync-paris-genesis-json*)
    (let* ((valid (first (eth-sync-produce-empty-blocks genesis-block config 1)))
           (header (block-header valid))
           (corrupt (ethereum-lisp.blocks:make-block-from-parts
                     :header (make-block-header
                              :parent-hash (block-header-parent-hash header)
                              :ommers-hash (block-header-ommers-hash header)
                              :beneficiary (block-header-beneficiary header)
                              :state-root (hash32-from-hex
                                           "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
                              :transactions-root (block-header-transactions-root header)
                              :receipts-root (block-header-receipts-root header)
                              :logs-bloom (block-header-logs-bloom header)
                              :difficulty (block-header-difficulty header)
                              :number (block-header-number header)
                              :gas-limit (block-header-gas-limit header)
                              :gas-used (block-header-gas-used header)
                              :timestamp (block-header-timestamp header)
                              :extra-data (block-header-extra-data header)
                              :mix-hash (block-header-mix-hash header)
                              :nonce (block-header-nonce header)
                              :base-fee-per-gas (block-header-base-fee-per-gas header))
                     :transactions (block-transactions valid)
                     :receipts '())))
      ;; The genuine block is accepted, so the refusal below is about the
      ;; corruption and not about the fixture being unusable.
      (is (string= "VALID"
                   (invalid-payload-test-status
                    (invalid-payload-test-response store config valid))))
      (assert-payload-refused store config corrupt "wrong state root"))))

(deftest engine-refuses-a-block-whose-parent-it-does-not-have
  (:layer :integration :module :engine)
  ;; A block whose parent is unknown cannot be executed -- there is no state to
  ;; execute it against. The node must NOT claim it validated one.
  (multiple-value-bind (store config genesis-block)
      (eth-sync-make-seeded-store *eth-sync-paris-genesis-json*)
    (let* ((chain (eth-sync-produce-empty-blocks genesis-block config 3))
           (orphan (third chain))
           (result (invalid-payload-test-response store config orphan))
           (status (invalid-payload-test-status result)))
      ;; SYNCING is the correct answer here, not VALID and not INVALID: the
      ;; block may be perfectly good, we simply cannot tell yet. Claiming
      ;; either verdict without the parent state would be a lie.
      (is (string= "SYNCING" status))
      (is (not (chain-store-state-available-p store (block-hash orphan)))))))

(deftest engine-refuses-a-block-with-a-mismatched-gas-used
  (:layer :integration :module :engine)
  ;; Gas used is a commitment to what execution consumed. A header claiming a
  ;; figure its transactions do not produce is invalid, and the check must not
  ;; be skipped just because the block is otherwise well-formed.
  (multiple-value-bind (store config genesis-block)
      (eth-sync-make-seeded-store *eth-sync-paris-genesis-json*)
    (let* ((valid (first (eth-sync-produce-empty-blocks genesis-block config 1)))
           (header (block-header valid))
           (corrupt (ethereum-lisp.blocks:make-block-from-parts
                     :header (make-block-header
                              :parent-hash (block-header-parent-hash header)
                              :ommers-hash (block-header-ommers-hash header)
                              :beneficiary (block-header-beneficiary header)
                              :state-root (block-header-state-root header)
                              :transactions-root (block-header-transactions-root header)
                              :receipts-root (block-header-receipts-root header)
                              :logs-bloom (block-header-logs-bloom header)
                              :difficulty (block-header-difficulty header)
                              :number (block-header-number header)
                              :gas-limit (block-header-gas-limit header)
                              ;; An empty block consumed nothing; claim otherwise.
                              :gas-used 21000
                              :timestamp (block-header-timestamp header)
                              :extra-data (block-header-extra-data header)
                              :mix-hash (block-header-mix-hash header)
                              :nonce (block-header-nonce header)
                              :base-fee-per-gas (block-header-base-fee-per-gas header))
                     :transactions (block-transactions valid)
                     :receipts '())))
      (assert-payload-refused store config corrupt "mismatched gas used"))))
