(in-package #:ethereum-lisp.test)

;;;; The Merge transition by terminal total difficulty (EIP-3675), and the
;;;; per-block total difficulty the chain store keeps for it.
;;;;
;;;; A configuration with a positive TTD and no netsplit block at or below the
;;;; height (mainnet, and Sepolia below 1735371) leaves the transition to the
;;;; chain's total difficulty. The tests build a proof-of-work chain whose
;;;; first child reaches a small TTD, so that child is the terminal block.

(defun merge-transition-test-config (terminal-total-difficulty)
  (make-chain-config :chain-id 1
                     :homestead-block 0 :eip150-block 0 :eip155-block 0
                     :eip158-block 0 :byzantium-block 0
                     :constantinople-block 0 :petersburg-block 0
                     :istanbul-block 0 :berlin-block 0
                     :terminal-total-difficulty terminal-total-difficulty))

(defconstant +merge-transition-test-genesis-difficulty+ #x20000)

(defun merge-transition-test-genesis-store ()
  "A store holding a proof-of-work genesis; returns it and the genesis."
  (let* ((store (make-engine-payload-memory-store))
         (state (make-state-db))
         (genesis
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :ommers-hash +empty-ommers-hash+
             :beneficiary (zero-address)
             :state-root (state-db-root state)
             :difficulty +merge-transition-test-genesis-difficulty+
             :number 0
             :gas-limit 30000000
             :timestamp 0
             :extra-data (make-byte-vector 0)
             :mix-hash (zero-hash32)
             :nonce (make-byte-vector 8)))))
    (engine-payload-store-put-block store genesis :state-available-p t)
    (commit-state-db-to-chain-store store (block-hash genesis) state)
    (values store genesis)))

(defun merge-transition-test-child (store config parent &key difficulty)
  "Execute an empty child of PARENT; return it and its post-state.
DIFFICULTY defaults to the Ethash difficulty the configuration expects; 0
makes a proof-of-stake header."
  (let* ((parent-header (block-header parent))
         (timestamp (+ 13 (block-header-timestamp parent-header)))
         (difficulty (or difficulty
                         (expected-ethash-difficulty
                          config timestamp parent-header)))
         (state (state-db-copy
                 (chain-store-state-db store (block-hash parent)))))
    (values
     (execute-signed-block
      state '()
      :expected-chain-id 1
      :header (make-block-header
               :parent-hash (block-hash parent)
               :ommers-hash +empty-ommers-hash+
               :beneficiary (zero-address)
               :difficulty difficulty
               :number (1+ (block-header-number parent-header))
               :gas-limit (block-header-gas-limit parent-header)
               :timestamp timestamp
               :extra-data (make-byte-vector 0)
               :mix-hash (zero-hash32)
               :nonce (make-byte-vector 8))
      :chain-config config
      :apply-block-rewards-p t)
     state)))

(defun merge-transition-test-refusal (thunk)
  "The message of the block validation error THUNK signals, or NIL."
  (handler-case (progn (funcall thunk) nil)
    (block-validation-error (condition)
      (princ-to-string condition))))

(deftest merge-transition-follows-the-terminal-total-difficulty
  ;; Genesis is below the TTD and its first child reaches it, so that child is
  ;; the terminal proof-of-work block: its child must be proof-of-stake, and
  ;; genesis's child cannot be.
  (let ((*ethash-seal-verifier* (constantly t)))
    (multiple-value-bind (store genesis) (merge-transition-test-genesis-store)
      (let* ((config (merge-transition-test-config
                      (1+ +merge-transition-test-genesis-difficulty+)))
             (terminal (merge-transition-test-child store config genesis)))
        (import-block-candidate store terminal config)
        (let ((first-stake
                (merge-transition-test-child store config terminal
                                             :difficulty 0))
              (late-work (merge-transition-test-child store config terminal))
              (early-stake
                (merge-transition-test-child store config genesis
                                             :difficulty 0)))
          ;; The first proof-of-stake block imports on the terminal block.
          (is (import-block-candidate store first-stake config))
          ;; A proof-of-work block cannot follow the terminal block.
          (let ((refusal (merge-transition-test-refusal
                          (lambda ()
                            (import-block-candidate store late-work config)))))
            (is refusal)
            (is (search "difficulty must be zero" refusal)))
          ;; A proof-of-stake block cannot come before the TTD is reached.
          (let ((refusal (merge-transition-test-refusal
                          (lambda ()
                            (import-block-candidate store early-stake
                                                    config)))))
            (is refusal)
            (is (search "before the terminal total difficulty" refusal)))
          ;; Proof of stake continues on proof of stake.
          (is (import-block-candidate
               store
               (merge-transition-test-child store config first-stake
                                            :difficulty 0)
               config))
          ;; Totals: genesis carries its own difficulty, and a
          ;; proof-of-stake block adds nothing.
          (let ((terminal-total
                  (+ +merge-transition-test-genesis-difficulty+
                     (block-header-difficulty (block-header terminal)))))
            (is (= +merge-transition-test-genesis-difficulty+
                   (chain-store-block-total-difficulty
                    store (block-hash genesis))))
            (is (= terminal-total
                   (chain-store-block-total-difficulty
                    store (block-hash terminal))))
            (is (= terminal-total
                   (chain-store-block-total-difficulty
                    store (block-hash first-stake))))))))))

(deftest merge-transition-refuses-a-terminal-block-past-the-ttd
  ;; With a TTD genesis already reaches, genesis is the terminal block: its
  ;; proof-of-work child is refused (a positive difficulty after the TTD), and
  ;; so is a proof-of-stake grandchild through a proof-of-work block that was
  ;; only reachable by skipping validation.
  (let ((*ethash-seal-verifier* (constantly t)))
    (multiple-value-bind (store genesis) (merge-transition-test-genesis-store)
      (let ((config (merge-transition-test-config
                     +merge-transition-test-genesis-difficulty+)))
        (multiple-value-bind (work work-state)
            (merge-transition-test-child store config genesis)
          (let ((refusal (merge-transition-test-refusal
                          (lambda ()
                            (import-block-candidate store work config)))))
            (is refusal)
            (is (search "difficulty must be zero" refusal)))
          (is (import-block-candidate
               store
               (merge-transition-test-child store config genesis
                                            :difficulty 0)
               config))
          ;; Plant the refused proof-of-work block with its total, as a store
          ;; would hold it had an earlier rule admitted it, and ask for a
          ;; proof-of-stake child: its parent is not the terminal block.
          (engine-payload-store-put-block store work :state-available-p t)
          (commit-state-db-to-chain-store store (block-hash work) work-state)
          (let ((refusal
                (merge-transition-test-refusal
                 (lambda ()
                   (validate-block-header-against-config
                    (block-header work)
                    (block-header
                     (merge-transition-test-child store config work
                                                  :difficulty 0))
                    config
                    :parent-total-difficulty
                    (chain-store-block-total-difficulty
                     store (block-hash work)))))))
            (is refusal)
            (is (search "past the terminal block" refusal))))))))

(deftest merge-transition-without-total-difficulty-follows-the-parent
  ;; A chain entered at a proof-of-stake pivot has no total difficulty. A
  ;; proof-of-stake parent then makes its child proof-of-stake (go-ethereum
  ;; v1.17.6 beacon VerifyHeader); a proof-of-work parent cannot be shown
  ;; terminal, so a proof-of-stake child of one is refused.
  (let ((*ethash-seal-verifier* (constantly t))
        (config (merge-transition-test-config (ash 1 70)))
        (store (make-engine-payload-memory-store))
        (state (make-state-db)))
    (flet ((pivot (difficulty)
             (let ((block
                     (make-block
                      :header
                      (make-block-header
                       ;; An ancestor this store never saw.
                       :parent-hash (make-hash32
                                     (keccak-256
                                      (integer-to-minimal-bytes
                                       (1+ difficulty))))
                       :ommers-hash +empty-ommers-hash+
                       :beneficiary (zero-address)
                       :state-root (state-db-root state)
                       :difficulty difficulty
                       :number 1000
                       :gas-limit 30000000
                       :timestamp 100000
                       :extra-data (make-byte-vector 0)
                       :mix-hash (zero-hash32)
                       :nonce (make-byte-vector 8)))))
               (engine-payload-store-put-block store block
                                               :state-available-p t)
               (commit-state-db-to-chain-store store (block-hash block) state)
               block)))
      (let ((stake-pivot (pivot 0))
            (work-pivot (pivot #x20000)))
        (is (import-block-candidate
             store
             (merge-transition-test-child store config stake-pivot
                                          :difficulty 0)
             config))
        (let ((refusal
                (merge-transition-test-refusal
                 (lambda ()
                   (import-block-candidate
                    store
                    (merge-transition-test-child store config work-pivot
                                                 :difficulty 0)
                    config)))))
          (is refusal)
          (is (search "total difficulty is unknown" refusal)))
        (is (null (chain-store-block-total-difficulty
                   store (block-hash stake-pivot))))))))

(defun merge-transition-test-post-merge-pair (number timestamp)
  "A proof-of-stake London parent at NUMBER and its empty child."
  (let* ((parent (make-block-header
                  :parent-hash (make-hash32 (keccak-256 (make-byte-vector 1)))
                  :ommers-hash +empty-ommers-hash+
                  :difficulty 0
                  :number number
                  :gas-limit 30000000
                  :gas-used 15000000
                  :timestamp timestamp
                  :extra-data (make-byte-vector 0)
                  :mix-hash (zero-hash32)
                  :nonce (make-byte-vector 8)
                  :base-fee-per-gas 10000000000))
         (child (make-block-header
                 :parent-hash (block-header-hash parent)
                 :ommers-hash +empty-ommers-hash+
                 :difficulty 0
                 :number (1+ number)
                 :gas-limit 30000000
                 :gas-used 0
                 :timestamp (+ 12 timestamp)
                 :extra-data (make-byte-vector 0)
                 :mix-hash (zero-hash32)
                 :nonce (make-byte-vector 8)
                 :base-fee-per-gas 10000000000)))
    (values parent child)))

(deftest public-preset-post-merge-headers-validate-as-proof-of-stake
  ;; Mainnet names no netsplit block and Sepolia's (1735371) follows its
  ;; merge, so neither configuration alone says a block below it is
  ;; proof-of-stake. A proof-of-stake parent does, with no total difficulty.
  (dolist (entry (list (list :mainnet 17000000 1681000000)
                       (list :sepolia 1600000 1670000000)))
    (destructuring-bind (name number timestamp) entry
      (let ((config (built-in-genesis-preset-config
                     (find-built-in-genesis-preset name))))
        (multiple-value-bind (parent child)
            (merge-transition-test-post-merge-pair number timestamp)
          (is (validate-block-header-against-config parent child config))
          ;; The same child with a proof-of-work difficulty is refused.
          (setf (block-header-difficulty child) #x20000)
          (is (merge-transition-test-refusal
               (lambda ()
                 (validate-block-header-against-config
                  parent child config)))))))))

(deftest post-merge-authority-reads-the-block-under-a-ttd-configuration
  ;; Local publication and debug_setHead are refused for a proof-of-stake
  ;; view. Under a TTD configuration the height alone cannot say which blocks
  ;; those are; the admitted block's own difficulty does. The blocks are put
  ;; as a store holds admitted ones, so only the authority rule is measured.
  (let ((*ethash-seal-verifier* (constantly t)))
    (multiple-value-bind (store genesis) (merge-transition-test-genesis-store)
      (let ((config (merge-transition-test-config
                     (1+ +merge-transition-test-genesis-difficulty+))))
        (flet ((admit (parent &rest arguments)
                 (multiple-value-bind (block state)
                     (apply #'merge-transition-test-child
                            store config parent arguments)
                   (engine-payload-store-put-block
                    store block :state-available-p t :canonicalize-p nil)
                   (commit-state-db-to-chain-store
                    store (block-hash block) state)
                   block)))
        (let* ((terminal (admit genesis))
               (stake (admit terminal :difficulty 0)))
          (is (publish-canonical-block store terminal config
                                       :authority :local-dev))
          (is (merge-transition-test-refusal
               (lambda ()
                 (publish-canonical-block store stake config
                                          :authority :local-dev))))
          (is (= 1 (chain-store-head-number store)))
          (is (publish-canonical-block store stake config
                                       :authority :local-dev
                                       :local-dev-authorized-p t))
          (is (= 2 (chain-store-head-number store)))
          (let ((response
                  (engine-rpc-handle-request
                   (list (cons "jsonrpc" "2.0")
                         (cons "id" 12)
                         (cons "method" "debug_setHead")
                         (cons "params" (list "0x1")))
                   store config
                   :allowed-method-p #'engine-rpc-public-method-p)))
            (is (= -32602
                   (cdr (assoc "code"
                               (cdr (assoc "error" response
                                           :test #'string=))
                               :test #'string=))))
            (is (= 2 (chain-store-head-number store))))))))))

(defun merge-transition-test-work-chain (count difficulty)
  "A store with a proof-of-work chain of COUNT blocks of DIFFICULTY each,
every one with (empty) state; returns the store and the blocks, oldest first."
  (let ((store (make-engine-payload-memory-store))
        (state (make-state-db))
        (blocks '())
        (parent-hash (zero-hash32)))
    (dotimes (number count)
      (let ((block (make-block
                    :header (make-block-header
                             :number number
                             :parent-hash parent-hash
                             :state-root (state-db-root state)
                             :difficulty difficulty
                             :timestamp number
                             :gas-limit 30000000))))
        (chain-store-put-block store block :state-available-p t)
        (commit-state-db-to-chain-store store (block-hash block) state)
        (push block blocks)
        (setf parent-hash (block-hash block))))
    (let ((ordered (nreverse blocks)))
      (chain-store-set-canonical-head store (block-hash (car (last ordered))))
      (values store ordered))))

(deftest total-difficulty-survives-export-reopen-and-direct-reads
  ;; Every block's total is written with its records, read back by the direct
  ;; provider one point read at a time, derived for a block the direct
  ;; provider admits, and restored by a full import.
  (multiple-value-bind (source blocks)
      (merge-transition-test-work-chain 8 #x20000)
    (let ((database (make-memory-key-value-database)))
      (node-store-export-to-kv source database)
      (loop for block in blocks
            for index from 1
            do (is (nth-value
                    1 (kv-get-chain-record database :total-difficulty
                                           (hash32-bytes (block-hash block)))))
               (is (= (* index #x20000)
                      (chain-store-block-total-difficulty
                       source (block-hash block)))))
      ;; A full import restores every total, and derives them in height order
      ;; from a database written before the records existed.
      (let ((legacy (make-memory-key-value-database)))
        (node-store-export-to-kv source legacy)
        (dolist (block blocks)
          (kv-delete-chain-record legacy :total-difficulty
                                  (hash32-bytes (block-hash block))))
        (dolist (from (list database legacy))
          (let ((restored (make-engine-payload-memory-store)))
            (node-store-import-from-kv restored from)
            (loop for block in blocks
                  for index from 1
                  do (is (= (* index #x20000)
                            (chain-store-block-total-difficulty
                             restored (block-hash block))))))))
      (let* ((direct (make-database-engine-payload-store database))
             (middle (nth 4 blocks))
             (tip (car (last blocks))))
        (is (= (* 5 #x20000)
               (chain-store-block-total-difficulty direct (block-hash middle))))
        (ethereum-lisp.txpool:engine-payload-store-enable-txpool-database-change-tracking
         direct)
        ;; A child the direct provider admits derives its total from the
        ;; durable parent's, and the forkchoice batch writes it.
        (let* ((state (chain-store-state-db direct (block-hash tip)))
               (child (make-block
                       :header (make-block-header
                                :number 8
                                :parent-hash (block-hash tip)
                                :state-root (state-db-root state)
                                :difficulty #x30000
                                :timestamp 8
                                :gas-limit 30000000))))
          (engine-payload-store-put-block
           direct child :state-available-p t :canonicalize-p nil)
          (commit-state-db-to-chain-store direct (block-hash child) state)
          (is (= (+ (* 8 #x20000) #x30000)
                 (chain-store-block-total-difficulty
                  direct (block-hash child))))
          (chain-store-update-forkchoice-checkpoints
           direct
           (make-forkchoice-state
            :head-block-hash (block-hash child)
            :safe-block-hash (block-hash (first blocks))
            :finalized-block-hash (block-hash (first blocks))))
          (multiple-value-bind (head transition)
              (chain-store-set-canonical-head direct (block-hash child))
            (declare (ignore head))
            (node-store-export-forkchoice-to-kv direct transition database))
          (is (= (+ (* 8 #x20000) #x30000)
                 (chain-store-block-total-difficulty
                  (make-database-engine-payload-store database)
                  (block-hash child)))))))))
