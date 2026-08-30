(in-package #:ethereum-lisp.cli)

(defun devnet-node-prune-state-before (node block-number)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (call-with-devnet-node-store-guard
   node
   (lambda ()
     (when block-number
       (chain-store-prune-state-before
        (devnet-node-store node) block-number)))))

(defun devnet-node-rejournal (node)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (call-with-devnet-node-store-guard
   node
   (lambda ()
     (let ((journal-path (devnet-node-txpool-journal-path node)))
       (when journal-path
         (devnet-cli-call-with-next-persistence-generation
          (devnet-node-persistence-state node)
          :journal
          (lambda (metadata)
            (node-store-export-txpool-records-to-kv
             (devnet-node-store node)
             (devnet-cli-make-output-kv-database journal-path)
             :persistence-metadata metadata)))
         t)))))

(defun make-devnet-rejournal-state
    (node interval-seconds &key (now-function #'unix-time))
  (unless (typep node 'devnet-node)
    (error "Devnet rejournal state requires a devnet node"))
  (unless (or (null interval-seconds)
              (and (integerp interval-seconds) (<= 0 interval-seconds)))
    (error "Devnet rejournal interval must be a non-negative integer"))
  (unless (functionp now-function)
    (error "Devnet rejournal clock must be a function"))
  (%make-devnet-rejournal-state
   :node node
   :interval-seconds interval-seconds
   :now-function now-function
   :last-run-time (funcall now-function)))

(defun devnet-rejournal-state-enabled-p (state)
  (let ((node (devnet-rejournal-state-node state))
        (interval-seconds (devnet-rejournal-state-interval-seconds state)))
    (and node
         (devnet-node-txpool-journal-path node)
         interval-seconds
         (plusp interval-seconds))))

(defun devnet-rejournal-state-tick (state)
  (unless (typep state 'devnet-rejournal-state)
    (error "Devnet rejournal tick requires a devnet rejournal state"))
  (when (devnet-rejournal-state-enabled-p state)
    (let* ((now (funcall (devnet-rejournal-state-now-function state)))
           (last-run-time (devnet-rejournal-state-last-run-time state))
           (interval-seconds
             (devnet-rejournal-state-interval-seconds state)))
      (when (>= (- now last-run-time) interval-seconds)
        (setf (devnet-rejournal-state-last-run-time state) now)
        (devnet-node-rejournal (devnet-rejournal-state-node state))))))

(defun devnet-node-pending-mining-transactions (node &key base-fee)
  "The pending transactions in the order a block should try to include them.

BASE-FEE orders senders by what they actually pay at that base fee; without it
the deterministic address order is kept."
  (let* ((store (devnet-node-store node))
         (expected-chain-id
           (chain-config-chain-id (devnet-node-config node))))
    (engine-payload-store-pending-mining-transactions
     store expected-chain-id :base-fee base-fee)))

(defun devnet-node-persist-canonical-transition (node transition)
  (let ((persistence-function
          (devnet-node-canonical-transition-persistence-function node)))
    (when persistence-function
      ;; The adapter owns error classification: only an explicit STORAGE-ERROR
      ;; is retryable by the background worker.  Validation, corruption, and
      ;; callback invariant failures must escape unchanged and trigger the
      ;; worker's outer fail-stop path.
      (funcall persistence-function
               (devnet-node-store node)
               transition))))

(defun devnet-node-import-local-canonical-block (node block)
  "Execute and publish one explicitly supplied offline block.

This is deliberately narrower than peer/Engine admission.  The caller must
provide the next direct child of the current canonical head; imports never
silently create a reorg.  Execution, canonical publication, and the durable
forkchoice export all remain inside the existing unified import boundary.  The
explicit local-import authority is confined to this non-exported CLI helper;
it is how Hive's preloaded test chain can be reconstructed before the node
serves RPC, including post-Merge fixtures, without granting a network ingress
local canonical authority."
  (unless (typep node 'devnet-node)
    (error "Offline block import requires a devnet-node"))
  (unless (typep block 'ethereum-block)
    (block-validation-fail "Offline block import requires an Ethereum block"))
  (call-with-devnet-node-store-guard
   node
   (lambda ()
     (let* ((store (devnet-node-store node))
            (parent (chain-store-latest-block store))
            (header (block-header block)))
       (unless parent
         (storage-fail "Offline block import has no canonical parent"))
       (unless (and (= (block-header-number header)
                       (1+ (block-header-number (block-header parent))))
                    (hash32= (block-header-parent-hash header)
                             (block-hash parent)))
         (block-validation-fail
          "Offline block import must extend the current canonical head"))
       (build-import-and-publish-block
        store block (devnet-node-config node)
        :source :local
        :authority :local-dev
        :local-dev-authorized-p t
        :durability-function
        (lambda (callback-store transition)
          (declare (ignore callback-store))
          (devnet-node-persist-canonical-transition node transition)))))))

(defun devnet-node-import-local-canonical-blocks
    (node blocks &key (verify-pow-seals-p t))
  "Import BLOCKS in order, stopping at the first deterministic invalid block.

Returns the number of committed blocks, the validation condition (or NIL), and
the first invalid block (or NIL).
Each successful block is independently atomic and durably exported, matching
Hive's required last-valid-block behavior for a supplied chain.  Storage and
other local failures deliberately escape rather than being converted into a
valid-looking partial import."
  (unless (listp blocks)
    (block-validation-fail "Offline block import requires a proper block list"))
  (let ((imported 0)
        ;; Hive's pinned RPC fixtures deliberately carry fake historical PoW
        ;; seals, matching geth's NewFaker and Erigon's --fakepow adapters.
        ;; Rebinding the verifier here confines that compatibility behavior to
        ;; an explicit offline import call.  The default, P2P, Engine, and all
        ;; other admission paths retain the real configured Ethash verifier.
        (ethereum-lisp.consensus:*ethash-seal-verifier*
          (if verify-pow-seals-p
              ethereum-lisp.consensus:*ethash-seal-verifier*
              (lambda (header)
                (declare (ignore header))
                t))))
    (dolist (block blocks (values imported nil nil))
      ;; Hive's concatenated stream may begin with the genesis block that was
      ;; separately supplied to the client.  Geth's import path treats that
      ;; exact known block as a no-op.  Do the same only for an exact match of
      ;; the *current* canonical head: a same-height alternate hash still goes
      ;; through the direct-successor validation below and cannot create a
      ;; silent reorg.
      ;; A freshly seeded genesis has a canonical index and head number before
      ;; forkchoice has installed an explicit head checkpoint.  Use the same
      ;; canonical anchor as the import path below so an exact genesis replay
      ;; remains a no-op during that interval.
      (let ((head (chain-store-latest-block (devnet-node-store node))))
        (unless (and head (hash32= (block-hash block) (block-hash head)))
          (handler-case
              (progn
                (devnet-node-import-local-canonical-block node block)
                (incf imported))
            (block-validation-error (condition)
              (return (values imported condition block)))
            (ethereum-lisp.execution:transaction-validation-error (condition)
              (return (values imported condition block)))))))))

(defun devnet-cli-decode-import-chain (path)
  "Decode Hive's concatenated RLP block stream from PATH.

Hive's CHAIN.RLP is a sequence of complete RLP block items, not one RLP list.
Use the bounded generic decoder only to find each item's exact boundary, then
give the original bytes to the canonical block decoder."
  (let ((octets (devnet-cli-read-file-octets path))
        (start 0)
        (blocks '()))
    (loop while (< start (length octets))
          do (multiple-value-bind (ignored next)
                 (rlp-decode octets :start start :allow-trailing t
                                     ;; This only discovers an item's boundary,
                                     ;; but it still descends into the block's
                                     ;; transactions list.  Keep exactly the
                                     ;; canonical block decoder's admissible
                                     ;; per-list bound; Hive's genesis fixtures
                                     ;; may legitimately pre-fund far more than
                                     ;; a small hand-written test vector.
                                     :max-list-items
                                     ethereum-lisp.blocks:+block-max-rlp-list-items+)
               (declare (ignore ignored))
               (unless (> next start)
                 (error "Offline import decoder made no progress at byte ~D"
                        start))
               (push (block-from-rlp (subseq octets start next)) blocks)
               (setf start next)))
    (nreverse blocks)))

(defun devnet-cli-import-block-files (directory)
  "Decode the direct .rlp files in DIRECTORY in Hive's numeric filename order."
  (unless (uiop:directory-exists-p directory)
    (error "Offline block import directory does not exist: ~A" directory))
  (labels ((numeric-name (path)
             (parse-integer (or (pathname-name path) "") :junk-allowed t))
           (lessp (left right)
             (let ((left-number (numeric-name left))
                   (right-number (numeric-name right)))
               (if (and left-number right-number
                        (/= left-number right-number))
                   (< left-number right-number)
                   (string< (namestring left) (namestring right))))))
    (let ((files
            (sort
             (remove-if-not
              (lambda (path)
                (string-equal (or (pathname-type path) "") "rlp"))
              (uiop:directory-files directory))
             #'lessp)))
    (mapcar (lambda (path)
              (block-from-rlp
               (devnet-cli-read-file-octets path)))
            files))))

(defun devnet-cli-report-offline-import-failed-block (stream block)
  "Write a bounded summary of an invalid explicit offline-import block."
  (when block
    (let ((header (block-header block)))
      (format stream
              "offline.import.failure block=~D hash=~A stateRoot=~A gasUsed=~D beneficiary=~A difficulty=~D transactions=~D~%"
              (block-header-number header)
              (hash32-to-hex (block-hash block))
              (hash32-to-hex (block-header-state-root header))
              (block-header-gas-used header)
              (address-to-hex
               (or (block-header-beneficiary header) (zero-address)))
              (block-header-difficulty header)
              (length (block-transactions block)))
      (loop for transaction in (block-transactions block)
            for index from 0
            for data = (transaction-data transaction)
            for sender = (ignore-errors (transaction-sender transaction))
            do (format stream
                       "offline.import.failure.tx index=~D hash=~A sender=~A to=~A nonce=~D gas=~D value=~D dataBytes=~D dataPrefix=~A~%"
                       index
                       (hash32-to-hex (transaction-hash transaction))
                       (if sender (address-to-hex sender) "unavailable")
                       (if (transaction-to transaction)
                           (address-to-hex (transaction-to transaction))
                           "create")
                       (transaction-nonce transaction)
                       (transaction-gas-limit transaction)
                       (transaction-value transaction)
                       (length data)
                       (bytes-to-hex
                        (subseq data 0 (min (length data) 128))))))))

(defun devnet-cli-report-offline-import-result
    (output-stream source imported condition verify-pow-seals-p
     &optional failed-block)
  (flet ((report (stream)
           (format stream
                   "offline.import source=~A pow-seals=~A imported=~D~@[ stopped=~A~]~%"
                   source (if verify-pow-seals-p "verified" "skipped")
                   imported condition)
           (devnet-cli-report-offline-import-failed-block
            stream failed-block)))
    (report output-stream)
  ;; Hive retains the adapter and process diagnostic stream in its result
  ;; artifact.  Mirror this concise, non-sensitive startup outcome there: a
  ;; fixture's last-valid-prefix condition must be observable when a later RPC
  ;; query cannot see the expected preloaded block.
    (report *error-output*))
  ;; Hive captures the client's stdout through a pipe.  This is a startup
  ;; diagnostic needed to distinguish a fixture-validation prefix stop from an
  ;; RPC regression, so do not leave it buffered until the long-running server
  ;; happens to exit.
  (finish-output output-stream)
  (finish-output *error-output*))

(defun devnet-cli-import-preloaded-blocks (node options output-stream)
  "Import explicitly selected offline fixture blocks before the node is served.

An invalid block is ordinary fixture input: retain the independently durable
prefix and continue startup, as Hive's last-valid-block contract requires.
Unreadable paths, malformed containers, and storage failures are operator or
runtime errors and deliberately prevent startup."
  (let ((verify-pow-seals-p
          (not (getf options :import-chain-skip-pow-p))))
    (flet ((import-block-sequence (source blocks)
             (multiple-value-bind (imported condition failed-block)
                 (devnet-node-import-local-canonical-blocks
                  node blocks :verify-pow-seals-p verify-pow-seals-p)
               (devnet-cli-report-offline-import-result
                output-stream source imported condition
                verify-pow-seals-p failed-block))))
      (let ((chain-path (getf options :import-chain-path))
            (blocks-path (getf options :import-blocks-path)))
        (when chain-path
          (unless (probe-file chain-path)
            (error "Offline import chain does not exist: ~A" chain-path))
          (import-block-sequence "chain"
                                 (devnet-cli-decode-import-chain chain-path)))
        (when blocks-path
          (import-block-sequence "blocks"
                                 (devnet-cli-import-block-files blocks-path)))))))

(defun devnet-local-fork-body-arguments (config block-number timestamp)
  "Return supplied local-builder body data for the active fork.

Requests retain their pre-execution placeholder contract.  Amsterdam block
access lists do not: they are execution output and must be omitted so the
kernel derives and commits the actual list."
  (append
   (when (chain-config-shanghai-p config block-number timestamp)
     (list :withdrawals '()))
   (when (chain-config-prague-p config block-number timestamp)
     (list :requests '()))))

(defun devnet-node-seal-pending-block-without-guard (node &key timestamp)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (let* ((store (devnet-node-store node))
         (config (devnet-node-config node))
         ;; CHAIN-STORE-LATEST-BLOCK resolves the effective head number through
         ;; the canonical-hash index.  Unlike the optional forkchoice head
         ;; checkpoint, it is also available on a fresh genesis-only node, and
         ;; it never reads the same-height side-candidate cache.
         (parent (chain-store-latest-block store))
         (pending-transactions
           (devnet-node-pending-mining-transactions
            node
            ;; NIL when there is no base fee to compute a tip against, which
            ;; keeps the deterministic address order rather than failing.
            :base-fee (let ((parent (chain-store-latest-block store)))
                        (and parent
                             (ignore-errors
                              (expected-base-fee-per-gas
                               (block-header parent))))))))
    (when (and parent pending-transactions)
      (let* ((parent-header (block-header parent))
             (parent-hash (block-hash parent))
             (parent-timestamp (block-header-timestamp parent-header))
             (timestamp (max (or timestamp 0) (1+ parent-timestamp)))
             (block-number (1+ (block-header-number parent-header)))
             (gas-limit
               (engine-target-gas-limit
                (block-header-gas-limit parent-header)
                (devnet-node-miner-gas-limit node)))
             (expected-chain-id (chain-config-chain-id config))
             (transactions
               (engine-select-mining-transactions
                pending-transactions gas-limit expected-chain-id))
             (state (chain-store-state-db store parent-hash))
             (cancun-p (chain-config-cancun-p config block-number timestamp))
             (base-fee-per-gas
               (if (block-header-base-fee-per-gas parent-header)
                   (expected-base-fee-per-gas parent-header)
                   0))
             (cancun-header-arguments nil)
             (fork-body-arguments
               (devnet-local-fork-body-arguments
                config block-number timestamp)))
        (when transactions
          (unless state
            (error "Devnet dev-period parent state is unavailable"))
          (when cancun-p
            (multiple-value-bind (target-blob-gas max-blob-gas
                                  update-fraction)
                (chain-config-blob-schedule config block-number timestamp)
              (setf cancun-header-arguments
                    (list
                     :blob-gas-used (blob-gas-used transactions)
                     :excess-blob-gas
                     (expected-excess-blob-gas
                      parent-header
                      :target-blob-gas target-blob-gas
                      :max-blob-gas max-blob-gas
                      :eip7918-p (chain-config-osaka-p config block-number
                                                        timestamp)
                      :update-fraction update-fraction)
                     :parent-beacon-root (zero-hash32)))))
          ;; Amsterdam BAL side data is derived by execution.  Do not pass an
          ;; empty supplied value, which would reject every non-empty result.
          ;; --dev is an explicit embedded block-authority mode.  The unified
          ;; service owns both admission and the sole local publication token;
          ;; a public/non-dev post-Merge node cannot reach this path.
          (build-import-and-publish-block
           store
           (lambda ()
             (apply
              #'execute-and-commit-signed-block
              store
              state
              transactions
              (append
               (list
                :expected-chain-id expected-chain-id
                :header (apply
                         #'make-block-header
                         (append
                          (list
                           :parent-hash parent-hash
                           :beneficiary (devnet-node-coinbase node)
                           :number block-number
                           :gas-limit gas-limit
                           :timestamp timestamp
                           :base-fee-per-gas base-fee-per-gas
                           :mix-hash (zero-hash32))
                          cancun-header-arguments))
                :chain-config config
                :state-available-p t
                :canonicalize-p nil)
               fork-body-arguments)))
           config
           :source :dev-period
           :authority :local-dev
           :local-dev-authorized-p (devnet-node-dev-mode-p node)
           :durability-function
           (lambda (callback-store transition)
             (declare (ignore callback-store))
             (devnet-node-persist-canonical-transition node transition))))))))

(defun devnet-node-seal-pending-block (node &key timestamp)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (call-with-devnet-node-store-guard
   node
   (lambda ()
     (devnet-node-seal-pending-block-without-guard
      node :timestamp timestamp))))

(defun make-devnet-dev-period-state
    (node interval-seconds &key (now-function #'unix-time))
  (unless (typep node 'devnet-node)
    (error "Devnet dev-period state requires a devnet node"))
  (unless (or (null interval-seconds)
              (and (integerp interval-seconds) (<= 0 interval-seconds)))
    (error "Devnet dev-period interval must be a non-negative integer"))
  (unless (functionp now-function)
    (error "Devnet dev-period clock must be a function"))
  (%make-devnet-dev-period-state
   :node node
   :interval-seconds interval-seconds
   :now-function now-function
   :last-run-time (funcall now-function)))

(defun devnet-dev-period-state-enabled-p (state)
  (let ((node (devnet-dev-period-state-node state))
        (interval-seconds (devnet-dev-period-state-interval-seconds state)))
    (and node
         (devnet-node-dev-mode-p node)
         interval-seconds
         (plusp interval-seconds))))

(defun devnet-dev-period-state-tick (state)
  (unless (typep state 'devnet-dev-period-state)
    (error "Devnet dev-period tick requires a devnet dev-period state"))
  (when (devnet-dev-period-state-enabled-p state)
    (let* ((now (funcall (devnet-dev-period-state-now-function state)))
           (last-run-time (devnet-dev-period-state-last-run-time state))
           (interval-seconds
             (devnet-dev-period-state-interval-seconds state)))
      (when (>= (- now last-run-time) interval-seconds)
        (let ((sealed-block
                (devnet-node-seal-pending-block
                 (devnet-dev-period-state-node state)
                 :timestamp now)))
          ;; A failed durable commit must remain immediately retryable.  Empty
          ;; successful ticks still advance the interval as before.
          (setf (devnet-dev-period-state-last-run-time state) now)
          sealed-block)))))

(defun devnet-node-export-database (node &key state-prune-before)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (call-with-devnet-node-store-guard
   node
   (lambda ()
     (when state-prune-before
       (chain-store-prune-state-before
        (devnet-node-store node) state-prune-before))
     (let ((database-generation nil)
           (persistence-state (devnet-node-persistence-state node)))
       (let ((database-path (devnet-node-database-path node)))
         (when database-path
           (multiple-value-bind (result generation)
               (devnet-cli-call-with-next-persistence-generation
                persistence-state
                :database
                (lambda (metadata)
                  (let ((store (devnet-node-store node))
                        (database
                          (devnet-cli-make-output-kv-database
                           database-path (devnet-node-db-engine node))))
                    (if (database-engine-payload-store-p store)
                        ;; Chain/state/block deltas were already published in
                        ;; their request batches. Shutdown only needs the
                        ;; bounded txpool snapshot plus its authority record;
                        ;; treating the point-read overlay as a full database
                        ;; would delete history it never hydrated.
                        (node-store-export-txpool-records-to-kv
                         store database :persistence-metadata metadata)
                        (node-store-export-to-kv
                         store database :persistence-metadata metadata)))))
             (declare (ignore result))
             (setf database-generation generation))
           (engine-payload-store-clear-txpool-database-dirty-transaction-hashes
            (devnet-node-store node))))
       (let ((journal-path (devnet-node-txpool-journal-path node)))
         (when journal-path
           (if database-generation
               ;; The lifecycle snapshot is identical to the just-committed
               ;; database view, so both files publish one generation.  If the
               ;; journal write fails, the database already wins recovery.
               (node-store-export-txpool-records-to-kv
                (devnet-node-store node)
                (devnet-cli-make-output-kv-database journal-path)
                :persistence-metadata
                (devnet-cli-persistence-metadata-for-generation
                 persistence-state
                 :journal
                 database-generation
                 :base-chain-generation database-generation))
               (devnet-cli-call-with-next-persistence-generation
                persistence-state
                :journal
                (lambda (metadata)
                  (node-store-export-txpool-records-to-kv
                   (devnet-node-store node)
                   (devnet-cli-make-output-kv-database journal-path)
                   :persistence-metadata metadata))))
           t))))))
