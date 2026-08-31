(in-package #:ethereum-lisp.node-store.persistence)

;;;; Bounded, read-through chain provider.
;;;;
;;;; DATABASE-CHAIN-STORE deliberately includes MEMORY-CHAIN-STORE: the latter
;;;; remains the transaction-local overlay and bounded cache used by the
;;;; existing consensus services, while durable history stays in the key/value
;;;; database.  Reads below are point lookups.  No iterator or whole-database
;;;; import is part of construction or ordinary lookup.

(defconstant +node-store-direct-account-cache-generation-limit+ 4096
  "Maximum immutable account snapshots retained in one cache generation.")

(defstruct (database-chain-store
            (:include memory-chain-store))
  (database (error "Database chain store requires a database")
            :type key-value-database)
  (account-cache (make-hash-table :test 'equal) :type hash-table)
  (previous-account-cache (make-hash-table :test 'equal) :type hash-table)
  (account-cache-lock
    #+sbcl (sb-thread:make-mutex :name "ethereum-lisp-account-cache")
    #-sbcl nil))

(defun make-empty-database-chain-store (database)
  "Construct a direct provider with fresh memory-overlay slot defaults.

Common Lisp does not carry the included structure's constructor defaults into
the derived structure constructor on every implementation.  Move the freshly
allocated base overlay into the derived object explicitly so no inherited
hash-table slot can start as NIL."
  (let ((store (make-database-chain-store :database database))
        (defaults (make-memory-chain-store)))
    (setf
     (memory-chain-store-blocks store)
     (memory-chain-store-blocks defaults)
     (memory-chain-store-number-blocks store)
     (memory-chain-store-number-blocks defaults)
     (memory-chain-store-canonical-hashes store)
     (memory-chain-store-canonical-hashes defaults)
     (memory-chain-store-transaction-locations store)
     (memory-chain-store-transaction-locations defaults)
     (memory-chain-store-account-balances store)
     (memory-chain-store-account-balances defaults)
     (memory-chain-store-account-nonces store)
     (memory-chain-store-account-nonces defaults)
     (memory-chain-store-account-codes store)
     (memory-chain-store-account-codes defaults)
     (memory-chain-store-account-storage store)
     (memory-chain-store-account-storage defaults)
     (memory-chain-store-head-number store)
     (memory-chain-store-head-number defaults)
     (memory-chain-store-state-blocks store)
     (memory-chain-store-state-blocks defaults)
     (memory-chain-store-state-diffs store)
     (memory-chain-store-state-diffs defaults)
     (memory-chain-store-state-roots store)
     (memory-chain-store-state-roots defaults)
     (memory-chain-store-state-tries store)
     (memory-chain-store-state-tries defaults)
     (memory-chain-store-state-code-bodies store)
     (memory-chain-store-state-code-bodies defaults)
     (memory-chain-store-state-baseline-interval store)
     (memory-chain-store-state-baseline-interval defaults)
     (memory-chain-store-state-retention-depth store)
     (memory-chain-store-state-retention-depth defaults)
     (memory-chain-store-remote-blocks store)
     (memory-chain-store-remote-blocks defaults)
     (memory-chain-store-remote-block-metadata store)
     (memory-chain-store-remote-block-metadata defaults)
     (memory-chain-store-remote-block-durable-deletions store)
     (memory-chain-store-remote-block-durable-deletions defaults)
     (memory-chain-store-forkchoice-sync-targets store)
     (memory-chain-store-forkchoice-sync-targets defaults)
     (memory-chain-store-forkchoice-sync-target-metadata store)
     (memory-chain-store-forkchoice-sync-target-metadata defaults)
     (memory-chain-store-invalid-tipsets store)
     (memory-chain-store-invalid-tipsets defaults)
     (memory-chain-store-invalid-tipset-metadata store)
     (memory-chain-store-invalid-tipset-metadata defaults)
     (memory-chain-store-invalid-tipset-durable-deletions store)
     (memory-chain-store-invalid-tipset-durable-deletions defaults)
     (memory-chain-store-durable-cache-change-tracking-enabled-p store)
     (memory-chain-store-durable-cache-change-tracking-enabled-p defaults)
     (memory-chain-store-invalid-block-hits store)
     (memory-chain-store-invalid-block-hits defaults)
     (memory-chain-store-prepared-payloads store)
     (memory-chain-store-prepared-payloads defaults)
     (memory-chain-store-prepared-payload-metadata store)
     (memory-chain-store-prepared-payload-metadata defaults)
     (memory-chain-store-blob-sidecars store)
     (memory-chain-store-blob-sidecars defaults)
     (memory-chain-store-blob-sidecar-metadata store)
     (memory-chain-store-blob-sidecar-metadata defaults)
     (memory-chain-store-log-filters store)
     (memory-chain-store-log-filters defaults)
     (memory-chain-store-next-log-filter-id store)
     (memory-chain-store-next-log-filter-id defaults)
     (memory-chain-store-head-checkpoint store)
     (memory-chain-store-head-checkpoint defaults)
     (memory-chain-store-safe-checkpoint store)
     (memory-chain-store-safe-checkpoint defaults)
     (memory-chain-store-finalized-checkpoint store)
     (memory-chain-store-finalized-checkpoint defaults))
    store))

(defun database-engine-payload-store-p (store)
  "True when STORE's chain component reads through a durable KV database."
  (typep (chain-store-component store) 'database-chain-store))

(defun database-engine-payload-store-database (store)
  "Return STORE's backing database, refusing a non-database store."
  (let ((chain-store (chain-store-component store)))
    (unless (typep chain-store 'database-chain-store)
      (block-validation-fail
       "Node store does not have a direct database chain provider"))
    (database-chain-store-database chain-store)))

(defmethod chain-store-backing-block ((store database-chain-store) hash)
  (unless (hash32-p hash)
    (block-validation-fail "Durable block lookup requires a hash32"))
  (let ((identifier (hash32-bytes hash))
        (database (database-chain-store-database store)))
    (multiple-value-bind (record present-p)
        (kv-get-chain-record database :block identifier)
      (if present-p
          (handler-case
              (let ((block
                      (chain-store-block-from-persisted-record
                       database identifier record "Durable block")))
                (unless (hash32= hash (block-hash block))
                  (storage-fail
                   "Durable block key does not match its encoded block hash"))
                ;; Receipts live in their own record. Attach them on the same
                ;; point read so a restarted candidate is byte-for-byte suitable
                ;; for idempotent re-export and for execution of its child.
                (multiple-value-bind (receipt-record receipt-present-p)
                    (kv-get-chain-record database :receipt identifier)
                  (cond
                    (receipt-present-p
                     (setf (block-receipts block)
                           (block-receipts-from-record block receipt-record)))
                    ((block-transactions block)
                     (storage-fail
                      "Durable block with transactions is missing receipts"))))
                (values block t))
            (storage-error (condition) (error condition))
            (error (condition)
              (storage-fail "Durable block record is invalid: ~A" condition)))
          (values nil nil)))))

(defmethod chain-store-backing-canonical-hash
    ((store database-chain-store) number)
  (unless (and (integerp number) (not (minusp number)))
    (block-validation-fail
     "Durable canonical block number must be non-negative"))
  (multiple-value-bind (identifier present-p)
      (kv-get-chain-canonical-hash
       (database-chain-store-database store) number)
    (if present-p
        (progn
          (unless (and (byte-vector-p identifier)
                       (= 32 (length identifier)))
            (storage-fail
             "Durable canonical index must contain a 32-byte hash"))
          (values (make-hash32 identifier) t))
        (values nil nil))))

(defmethod chain-store-backing-transaction-location
    ((store database-chain-store) hash)
  (unless (hash32-p hash)
    (block-validation-fail
     "Durable transaction-location lookup requires a hash32"))
  (let ((identifier (hash32-bytes hash)))
    (multiple-value-bind (record present-p)
        (kv-get-chain-record
         (database-chain-store-database store)
         :transaction-location
         identifier)
      (if present-p
          (values
           ;; The shared validator checks the block, canonical index,
           ;; transaction hash, receipt, and log offset without retaining the
           ;; historical result in the production overlay.  Validate the
           ;; location against the same durable snapshot as RECORD.  The
           ;; public chain-store lookup applies the newer in-memory canonical
           ;; overlay afterwards and therefore hides a displaced location
           ;; while the forkchoice WAL batch is still pending.
           (chain-store-transaction-location-from-kv
            store identifier record
            :canonical-block-p-function
            (lambda (block)
              (multiple-value-bind (canonical-hash present-p)
                  (chain-store-backing-canonical-hash
                   store
                   (block-header-number (block-header block)))
                (and present-p
                     (hash32= canonical-hash (block-hash block))))))
           t)
          (values nil nil)))))

(defmethod chain-store-cache-backing-read-p ((store database-chain-store))
  (declare (ignore store))
  nil)

(defmethod chain-store-backing-state-root
    ((store database-chain-store) block-hash)
  (unless (hash32-p block-hash)
    (block-validation-fail "Durable state lookup requires a block hash32"))
  (multiple-value-bind (root present-p)
      (kv-get-chain-record
       (database-chain-store-database store)
       :state-history
       (hash32-bytes block-hash))
    (if present-p
        (progn
          (unless (= 32 (length root))
            (storage-fail
             "Durable state-history record must contain a 32-byte root"))
          (let* ((root (make-hash32 root))
                 (block (engine-payload-store-known-block store block-hash))
                 (header-root
                   (and block (block-header-state-root (block-header block)))))
            (unless block
              (storage-fail
               "Durable state-history record references an unknown block"))
            (unless (and header-root (hash32= root header-root))
              (storage-fail
               "Durable state-history root does not match the block header"))
            (values root t)))
        (values nil nil))))

(defun node-store-direct-trie-node-loader (store)
  (lambda (hash)
    (chain-store-backing-trie-node store hash)))

(defun node-store-direct-account-cache-key (block-hash address)
  (engine-payload-store-account-key block-hash address))

(defun node-store-direct-account-cache-lookup-unlocked (store key)
  (multiple-value-bind (account present-p)
      (gethash key (database-chain-store-account-cache store))
    (if present-p
        (values account t)
        (gethash key (database-chain-store-previous-account-cache store)))))

(defun node-store-direct-account-cache-lookup (store key)
  #+sbcl
  (sb-thread:with-mutex ((database-chain-store-account-cache-lock store))
    (node-store-direct-account-cache-lookup-unlocked store key))
  #-sbcl
  (node-store-direct-account-cache-lookup-unlocked store key))

(defun node-store-direct-account-cache-put-unlocked (store key account)
  (when (>= (hash-table-count (database-chain-store-account-cache store))
            +node-store-direct-account-cache-generation-limit+)
    (setf (database-chain-store-previous-account-cache store)
          (database-chain-store-account-cache store)
          (database-chain-store-account-cache store)
          (make-hash-table :test 'equal)))
  (setf (gethash key (database-chain-store-account-cache store)) account)
  account)

(defun node-store-direct-account-cache-put (store key account)
  #+sbcl
  (sb-thread:with-mutex ((database-chain-store-account-cache-lock store))
    (node-store-direct-account-cache-put-unlocked store key account))
  #-sbcl
  (node-store-direct-account-cache-put-unlocked store key account))

(defun node-store-direct-account-from-trie
    (account-trie pending-tries address)
  (multiple-value-bind (record account-present-p)
      (mpt-get account-trie (keccak-256 (address-bytes address)))
    (if account-present-p
        (values
         (handler-case
             (ethereum-lisp.state:decode-state-account-rlp record)
           (storage-error (condition) (error condition))
           (error (condition)
             (storage-fail
              "Durable account record is invalid: ~A" condition)))
         pending-tries
         t
         t)
        (values nil pending-tries nil t))))

(defun node-store-direct-account (store block-hash address)
  "Resolve one secure-trie account and preserve state/account absence separately."
  (unless (hash32-p block-hash)
    (block-validation-fail
     "Durable account lookup requires a block hash32"))
  (unless (address-p address)
    (block-validation-fail
     "Durable account lookup requires an address"))
  (let ((pending-tries
          (chain-store-state-persistence-tries store block-hash)))
    (if pending-tries
        ;; A dirty trie is transaction-local and mutable until its block batch
        ;; commits.  Never publish it into the immutable durable read cache.
        (node-store-direct-account-from-trie
         (first pending-tries) pending-tries address)
        (let ((key
                (node-store-direct-account-cache-key block-hash address)))
          (multiple-value-bind (cached-account cached-p)
              (node-store-direct-account-cache-lookup store key)
            (if cached-p
                (values cached-account nil (not (null cached-account)) t)
                (multiple-value-bind (root state-present-p)
                    (chain-store-backing-state-root store block-hash)
                  (if state-present-p
                      (multiple-value-bind
                          (account ignored-tries account-present-p
                                   ignored-state-present-p)
                          (node-store-direct-account-from-trie
                           (make-persisted-mpt
                            root (node-store-direct-trie-node-loader store))
                           nil
                           address)
                        (declare
                         (ignore ignored-tries ignored-state-present-p))
                        (node-store-direct-account-cache-put
                         store key account)
                        (values account nil account-present-p t))
                      (values nil nil nil nil)))))))))

(defmethod chain-store-backing-account-state
    ((store database-chain-store) block-hash address)
  (multiple-value-bind
      (account pending-tries account-present-p state-present-p)
      (node-store-direct-account store block-hash address)
    (declare (ignore pending-tries))
    (if account-present-p
        (values
         (state-account-balance account)
         (state-account-nonce account)
         (state-account-code-hash account)
         (state-account-storage-root account)
         t
         t)
        (values 0 0 nil nil nil state-present-p))))

(defun node-store-direct-storage-trie (store pending-tries root)
  (or
   (find-if
    (lambda (trie)
      (bytes= (mpt-root-hash trie) (hash32-bytes root)))
    ;; The first pending trie is the account trie.  Only the remaining tries
    ;; can be storage tries, and only touched storage tries are retained here.
    (rest pending-tries))
   (make-persisted-mpt root (node-store-direct-trie-node-loader store))))

(defmethod chain-store-backing-account-storage
    ((store database-chain-store) block-hash address slot)
  (unless (hash32-p slot)
    (block-validation-fail
     "Durable account storage lookup requires a hash32 slot"))
  (multiple-value-bind
      (account pending-tries account-present-p state-present-p)
      (node-store-direct-account store block-hash address)
    (cond
      ((not state-present-p)
       (values 0 nil nil))
      ((not account-present-p)
       (values 0 nil t))
      (t
       (let ((storage-trie
               (node-store-direct-storage-trie
                store pending-tries (state-account-storage-root account))))
         (multiple-value-bind (encoded present-p)
             (mpt-get storage-trie (keccak-256 (hash32-bytes slot)))
           (if present-p
               (let ((value
                       (handler-case
                           (rlp-uint-field
                            (rlp-decode-one encoded)
                            "Durable account storage value")
                         (storage-error (condition) (error condition))
                         (error (condition)
                           (storage-fail
                            "Durable account storage record is invalid: ~A"
                            condition)))))
                 (unless (uint256-p value)
                   (storage-fail
                    "Durable account storage value must be uint256"))
                 (values value t t))
               (values 0 nil t))))))))

(defmethod chain-store-backing-trie-node
    ((store database-chain-store) hash)
  (let ((identifier
          (if (hash32-p hash)
              (hash32-bytes hash)
              (ensure-byte-vector hash))))
    (unless (= 32 (length identifier))
      (block-validation-fail
       "Durable trie-node lookup requires a 32-byte hash"))
    (kv-get-chain-record
     (database-chain-store-database store) :trie-node identifier)))

(defun node-store-direct-pending-code (store identifier)
  (block found
    (maphash
     (lambda (block-key code-bodies)
       (declare (ignore block-key))
       (dolist (code code-bodies)
         (when (bytes=
                identifier
                (hash32-bytes (keccak-256-hash code)))
           (return-from found (values (copy-seq code) t)))))
     (memory-chain-store-state-code-bodies store))
    (values nil nil)))

(defmethod chain-store-backing-code ((store database-chain-store) hash)
  (let ((identifier
          (if (hash32-p hash)
              (hash32-bytes hash)
              (ensure-byte-vector hash))))
    (unless (= 32 (length identifier))
      (block-validation-fail
       "Durable code lookup requires a 32-byte hash"))
    (multiple-value-bind (pending pending-p)
        (node-store-direct-pending-code store identifier)
      (if pending-p
          (values pending t)
          (multiple-value-bind (code present-p)
              (kv-get-chain-record
               (database-chain-store-database store) :code identifier)
            (when present-p
              (unless (bytes=
                       identifier (hash32-bytes (keccak-256-hash code)))
                (storage-fail
                 "Durable code record does not hash to its content address")))
            (values code present-p))))))

(defmethod chain-store-backing-blob-sidecar
    ((store database-chain-store) hash)
  (let ((identifier
          (if (hash32-p hash)
              (hash32-bytes hash)
              (ensure-byte-vector hash))))
    (unless (= 32 (length identifier))
      (block-validation-fail
       "Durable blob-sidecar lookup requires a 32-byte versioned hash"))
    (multiple-value-bind (record present-p)
        (kv-get-chain-record
         (database-chain-store-database store) :blob-sidecar identifier)
      (if present-p
          (handler-case
              (let ((blob-and-proofs
                      (chain-store-blob-sidecar-record-from-rlp record)))
                (unless (bytes=
                         identifier
                         (hash32-bytes
                          (kzg-commitment-to-versioned-hash
                           (engine-blob-and-proofs-commitment
                            blob-and-proofs))))
                  (storage-fail
                   "Durable blob-sidecar key does not match its commitment"))
                ;; A content-addressed commitment does not authenticate the
                ;; blob or proof bytes. Revalidate durable point reads before
                ;; getBlobs/devp2p can observe them after restart.
                (chain-store-validate-blob-and-proofs blob-and-proofs)
                (values blob-and-proofs t))
            (storage-error (condition)
              (error condition))
            (ethereum-lisp.kzg:kzg-unavailable-error (condition)
              ;; A missing local verifier is a capability failure. It says
              ;; nothing about the durable bytes and must not be relabeled as
              ;; storage corruption by this adapter boundary.
              (error condition))
            (error (condition)
              (storage-fail
               "Durable blob-sidecar record is invalid: ~A" condition)))
          (values nil nil)))))

(defmethod chain-store-durable-state-provider-p
    ((store database-chain-store))
  (declare (ignore store))
  t)

(defun node-store-database-checkpoint-hash (database label)
  (multiple-value-bind (identifier present-p)
      (kv-get-chain-checkpoint database label)
    (if present-p
        (progn
          (unless (and (byte-vector-p identifier)
                       (= 32 (length identifier)))
            (storage-fail
             "Durable ~A checkpoint must contain a 32-byte hash" label))
          (values (make-hash32 identifier) t))
        (values nil nil))))

(defun node-store-install-direct-checkpoints (store)
  "Install only the three bounded checkpoint values and the head block.

History, canonical indexes, transaction locations, receipts, and state remain
in the database and are point-read through the provider."
  (let ((database (database-chain-store-database store)))
    (multiple-value-bind (head-hash head-p)
        (node-store-database-checkpoint-hash database :head)
      (multiple-value-bind (safe-hash safe-p)
          (node-store-database-checkpoint-hash database :safe)
        (multiple-value-bind (finalized-hash finalized-p)
            (node-store-database-checkpoint-hash database :finalized)
          (when (and (or safe-p finalized-p) (not head-p))
            (storage-fail
             "Durable safe/finalized checkpoint requires a head checkpoint"))
          (flet ((require-checkpoint-block (hash label)
                   (when hash
                     (or (engine-payload-store-known-block store hash)
                         (storage-fail
                          "Durable ~A checkpoint references an unknown block"
                          label)))))
            (let ((head-block (require-checkpoint-block head-hash "head"))
                  (safe-block (require-checkpoint-block safe-hash "safe"))
                  (finalized-block
                    (require-checkpoint-block finalized-hash "finalized")))
              (when head-block
                (let* ((head-number
                         (block-header-number (block-header head-block)))
                       (canonical
                         (engine-payload-store-canonical-hash
                          store head-number)))
                  (unless (and canonical (hash32= canonical head-hash))
                    (storage-fail
                     "Durable head checkpoint is not the canonical head"))
                  (setf (memory-chain-store-head-number store) head-number)))
              (dolist (entry
                       (list (cons "head" head-hash)
                             (cons "safe" safe-hash)
                             (cons "finalized" finalized-hash)))
                (when (cdr entry)
                  (unless (nth-value
                           1
                           (chain-store-backing-state-root store (cdr entry)))
                    (storage-fail
                     "Durable ~A checkpoint has no persisted state root"
                     (car entry)))))
              ;; Full ancestry verification is an offline VERIFY operation.
              ;; Startup checks the atomic control record and basic ordering
              ;; without walking retained history.
              (when (and head-block safe-block
                         (> (block-header-number (block-header safe-block))
                            (block-header-number (block-header head-block))))
                (storage-fail
                 "Durable safe checkpoint is newer than head"))
              (when (and head-block finalized-block
                         (> (block-header-number
                             (block-header finalized-block))
                            (block-header-number (block-header head-block))))
                (storage-fail
                 "Durable finalized checkpoint is newer than head"))
              (when (and safe-block finalized-block
                         (> (block-header-number (block-header finalized-block))
                            (block-header-number (block-header safe-block))))
                (storage-fail
                 "Durable finalized checkpoint is newer than safe"))
              (setf
               (memory-chain-store-head-checkpoint store)
               (make-chain-store-checkpoint
                :label :head :block-hash head-hash)
               (memory-chain-store-safe-checkpoint store)
               (make-chain-store-checkpoint
                :label :safe :block-hash safe-hash)
               (memory-chain-store-finalized-checkpoint store)
               (make-chain-store-checkpoint
                :label :finalized :block-hash finalized-hash))))))))
  store)

(defun make-database-engine-payload-store (database)
  "Construct a node store that reads chain history directly from DATABASE.

Construction performs a fixed number of point reads.  It refuses an unknown
schema or an interrupted migration/copy, but never hydrates the database."
  (unless (typep database 'key-value-database)
    (block-validation-fail
     "Direct database chain provider requires a key-value database"))
  (let ((version (node-store-chain-schema-version database)))
    (unless (= version +kv-chain-schema-version+)
      (block-validation-fail
       "Direct database provider requires migrated schema ~D, got ~D"
       +kv-chain-schema-version+ version)))
  (let ((chain-store (make-empty-database-chain-store database)))
    (node-store-install-direct-checkpoints chain-store)
    (make-engine-payload-memory-store :chain-store chain-store)))
