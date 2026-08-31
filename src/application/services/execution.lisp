(in-package #:ethereum-lisp.execution-service)

(defconstant +blockhash-history-limit+ 256)

(defun chain-store-block-hashes-for-header (store header)
  "Build HEADER's BLOCKHASH window by following its own parent branch.

Hashes derivable from child headers remain usable when an older ancestor record
is not retained. Entries beyond the first missing ancestor are marked unavailable
so execution only fails if EVM code actually queries unavailable history."
  (let* ((block-hashes (make-hash-table :test 'eql))
         (number (block-header-number header))
         (history-count (min +blockhash-history-limit+ number)))
    (when (plusp number)
      (labels ((mark-unavailable-from (offset)
                 (loop for missing-offset from offset below history-count
                       for missing-number = (- number 1 missing-offset)
                       do (setf (gethash missing-number block-hashes)
                                :unavailable))))
        (let ((expected-hash (block-header-parent-hash header)))
          (if (null expected-hash)
              (mark-unavailable-from 0)
              (dotimes (offset history-count)
                (unless expected-hash
                  (mark-unavailable-from offset)
                  (return))
                (let ((expected-number (- number 1 offset)))
                  (setf (gethash expected-number block-hashes) expected-hash)
                  (when (< (1+ offset) history-count)
                    (let ((ancestor
                            (chain-store-known-block store expected-hash)))
                      (unless ancestor
                        (mark-unavailable-from (1+ offset))
                        (return))
                      ;; KNOWN-BLOCK is hash-addressed: in-memory entries are
                      ;; inserted under the block's computed hash, while a
                      ;; durable read verifies the decoded block against its
                      ;; lookup key before returning it. Re-hashing every one
                      ;; of the 256 ancestors here repeated that already-proven
                      ;; invariant for every payload build.
                      (let ((ancestor-header (block-header ancestor)))
                        (unless (= expected-number
                                   (block-header-number ancestor-header))
                          (storage-fail
                           "BLOCKHASH ancestor number is inconsistent"))
                        (setf expected-hash
                              (block-header-parent-hash
                               ancestor-header)))))))))))
    block-hashes))

(defun commit-state-db-to-chain-store (store block-hash state)
  ;; A lazily-backed post-state carries a TOUCHED set that is a complete record
  ;; of what the block changed relative to its parent, so the diff path commits
  ;; only those accounts instead of materializing and iterating the whole world.
  ;; The full iterator remains for the baseline path (which needs every account)
  ;; and for non-lazy states, whose untouched remainder is not known to equal
  ;; the parent -- there the proven full-iteration diff is preserved exactly.
  (let* ((chain-store (chain-store-require-memory-store store))
         (direct-p (chain-store-durable-state-provider-p chain-store))
         (persist-p
           (or direct-p
               (not (state-db-lazy-p state))
               (state-db-persistence-ready-p state))))
    (unless direct-p
      (chain-store-commit-post-state
       store block-hash
       (lambda (visit)
         (state-db-for-each-account
          state
          (lambda (address account code storage-entries)
            (funcall visit
                     address
                     (state-account-balance account)
                     (state-account-nonce account)
                     code
                     storage-entries))))
       :iterate-touched
       (when (state-db-lazy-p state)
         (lambda (visit)
           (state-db-for-each-touched-account
            state
            (lambda (address present-p account code storage-entries)
              (if present-p
                  (funcall visit
                           address t
                           (state-account-balance account)
                           (state-account-nonce account)
                           code
                           storage-entries)
                  (funcall visit address nil nil nil nil nil))))))))
    (when persist-p
      (let ((root (state-db-root state))
            (code-bodies nil))
        (state-db-for-each-touched-account
         state
         (lambda (address present-p account code storage-entries)
           (declare (ignore address account storage-entries))
           (when (and present-p (plusp (length code)))
             (pushnew code code-bodies :test #'bytes=))))
        (chain-store-put-state-persistence
         store block-hash root
         (state-db-persistence-tries state) code-bodies)))
    ;; The root and exact dirty trie set are now owned by the chain-store
    ;; journal. Reusing STATE for another block must start a fresh touched set;
    ;; lazy account/trie caches remain available and bounded by actual access.
    (state-db-clear-touched-accounts state))
  store)

(defun chain-store-state-db (store block-hash)
  (when (chain-store-state-available-p store block-hash)
    (labels
        ((load-all (state)
           (chain-store-for-each-account
            store block-hash
            (lambda (address balance nonce code storage-entries)
              (unless (state-db-account-loaded-p state address)
                (state-db-set-account
                 state address
                 (make-state-account :nonce nonce :balance balance))
                (when (plusp (length code))
                  (state-db-set-code state address code))
                (dolist (entry storage-entries)
                  (state-db-set-storage
                   state address (car entry) (cdr entry)))))))
         (trie-node-loader (hash)
           (chain-store-backing-trie-node
            (chain-store-require-memory-store store) hash)))
      (let* ((root (chain-store-state-root store block-hash))
             (committed-tries
               (chain-store-state-persistence-tries store block-hash)))
        (if (and root
                 (chain-store-durable-state-provider-p
                  (chain-store-require-memory-store store)))
            (let ((account-trie
                    (if committed-tries
                        (copy-mpt (first committed-tries))
                        (make-persisted-mpt root #'trie-node-loader))))
              (make-lazy-state-db
               (lambda (address)
                 (multiple-value-bind (account-record present-p)
                     (mpt-get account-trie
                              (keccak-256 (address-bytes address)))
                   (if present-p
                       (let* ((account
                                (handler-case
                                    (decode-state-account-rlp account-record)
                                  (storage-error (condition)
                                    (error condition))
                                  (error (condition)
                                    (storage-fail
                                     "Persisted account record is invalid: ~A"
                                     condition))))
                              (code-hash (state-account-code-hash account))
                              (code
                                (if (hash32= code-hash +empty-code-hash+)
                                    (make-byte-vector 0)
                                    (multiple-value-bind
                                        (persisted-code code-present-p)
                                        (chain-store-backing-code
                                         (chain-store-require-memory-store store)
                                         code-hash)
                                      (cond
                                        (code-present-p persisted-code)
                                        (committed-tries
                                         (chain-store-account-code
                                          store block-hash address))
                                        (t
                                         (storage-fail
                                          "Persisted account code is missing"))))))
                              (storage-root
                                (state-account-storage-root account))
                              (storage-trie
                                (let ((committed-storage-trie
                                        (and committed-tries
                                             (find-if
                                              (lambda (trie)
                                                (hash32=
                                                 (make-hash32
                                                  (mpt-root-hash trie))
                                                 storage-root))
                                              (rest committed-tries)))))
                                  ;; Proposal/private execution must never
                                  ;; mutate the store-owned pending trie object.
                                  (if committed-storage-trie
                                      (copy-mpt committed-storage-trie)
                                      (make-persisted-mpt
                                       storage-root #'trie-node-loader)))))
                         (values account code t nil storage-trie))
                       (values nil nil nil))))
               nil
               ;; Hashed account keys have no reversible whole-world
               ;; materializer. Memory/file oracles take the flat branch below.
               nil
               :trie account-trie
               :cached-root root
               :direct-trie-p t))
            (make-lazy-state-db
             (lambda (address)
               (multiple-value-bind (balance balance-present-p)
                   (chain-store-account-balance store block-hash address)
                 (let ((storage-entries
                         (chain-store-account-storage-entries
                          store block-hash address))
                       (code
                         (chain-store-account-code
                          store block-hash address)))
                   (multiple-value-bind (nonce nonce-present-p)
                       (chain-store-account-nonce store block-hash address)
                     (if (or balance-present-p nonce-present-p storage-entries
                             (plusp (length code)))
                         (values
                          (make-state-account
                           :nonce nonce
                           :balance balance
                           :code-hash
                           (ethereum-lisp.crypto:keccak-256-hash code))
                          code
                          t
                          storage-entries)
                         (values nil nil nil))))))
             (lambda (address slot)
               (chain-store-account-storage store block-hash address slot))
             #'load-all))))))

(defun execute-atomic-block-commit (store state thunk)
  (let ((state-snapshot (state-db-transaction-snapshot state))
        (completed-p nil))
    ;; Keep the cleanup around the complete store transaction, not merely its
    ;; callback. A durable batch may fail after THUNK has staged state and
    ;; cleared TOUCHED; ERROR handlers alone would miss THROW/RETURN-FROM.
    (unwind-protect
         (multiple-value-prog1
             (chain-store-atomic-commit store thunk)
           (setf completed-p t))
      (unless completed-p
        (state-db-revert-transaction-snapshot state state-snapshot)))))

(defun execute-and-commit-block
    (store state executor
     &key (state-available-p t) (canonicalize-p t))
  (execute-atomic-block-commit
   store
   state
   (lambda ()
     (multiple-value-bind (block receipts)
         (funcall executor)
       (engine-payload-store-put-block
        store block
        :state-available-p state-available-p
        :canonicalize-p canonicalize-p)
       (when state-available-p
         (commit-state-db-to-chain-store store (block-hash block) state))
       (values block receipts)))))

(defun execute-and-commit-signed-block
    (store state transactions
     &key expected-chain-id
          (header (make-block-header))
          parent-header
          chain-rules
          chain-config
          block-hashes
          (apply-block-rewards-p nil)
          (ommers '())
          (withdrawals nil withdrawals-supplied-p)
          (requests nil requests-supplied-p)
          (block-access-list nil block-access-list-supplied-p)
          (block-access-list-rlp nil block-access-list-rlp-supplied-p)
          expected-block-hash
          (state-available-p t)
          (canonicalize-p t))
  (execute-and-commit-block
   store
   state
   (lambda ()
     (apply
      #'execute-signed-block
      state
      transactions
      (append
       (list :expected-chain-id expected-chain-id
             :expected-block-hash expected-block-hash
             :header header
             :parent-header
             (or parent-header
                 (let ((parent-hash (block-header-parent-hash header)))
                   (when parent-hash
                     (let ((parent-block
                             (chain-store-known-block store parent-hash)))
                       (and parent-block (block-header parent-block))))))
             :chain-rules chain-rules
             :chain-config chain-config
             :block-hashes
             (or block-hashes
                 (chain-store-block-hashes-for-header store header))
             :apply-block-rewards-p apply-block-rewards-p
             :ommers ommers)
       (when withdrawals-supplied-p
         (list :withdrawals withdrawals))
       (when requests-supplied-p
         (list :requests requests))
       (when block-access-list-supplied-p
         (list :block-access-list block-access-list))
       (when block-access-list-rlp-supplied-p
         (list :block-access-list-rlp block-access-list-rlp)))))
   :state-available-p state-available-p
   :canonicalize-p canonicalize-p))

(defun execute-and-commit-engine-payload
    (store block config &key (state-available-p t))
  (let* ((header (block-header block))
         (expected-block-hash (block-hash block))
         (number (block-header-number header))
         (parent-hash (block-header-parent-hash header))
         (state (if (plusp number)
                    (chain-store-state-db store parent-hash)
                    (make-state-db))))
    (unless state
      (if (and (plusp number)
               (chain-store-state-available-p store parent-hash))
          (storage-fail
           "Engine payload parent state marker has no readable state")
          (state-unavailable-fail
           "Engine payload parent state is unavailable")))
    (apply
     #'execute-and-commit-signed-block
     store
     state
     (block-transactions block)
     (append
      (list :expected-chain-id (chain-config-chain-id config)
            :expected-block-hash expected-block-hash
            :header header
            :chain-config config
            :ommers (block-ommers block)
            ;; Imported blocks always pass through consensus finalization.
            ;; Ethash finalization credits block and ommer rewards; the same
            ;; helper is a no-op for a post-Merge header.  This mirrors geth's
            ;; StateProcessor -> Engine.Finalize boundary and keeps historical
            ;; P2P/offline imports from silently omitting PoW rewards.
            :apply-block-rewards-p t
            :state-available-p state-available-p
            ;; Engine imports are hash-addressed candidates. Consensus selects
            ;; the canonical view later through forkchoiceUpdated.
            :canonicalize-p nil)
      (when (block-withdrawals-present-p block)
        (list :withdrawals (block-withdrawals block)))
      (when (block-requests-present-p block)
        (list :requests (block-requests block)))
      (when (block-block-access-list-present-p block)
        (list :block-access-list (block-block-access-list block)))))))
