(in-package #:ethereum-lisp.node-store.persistence)

;;; Durable, non-canonical import staging.  Staged records are deliberately
;;; isolated from the public chain tables: only forkchoice may publish
;;; canonical hashes, checkpoints, transaction locations, or txpool changes.

(defconstant +node-store-staged-import-version+ 1)
(defconstant +node-store-staged-transaction-index-version+ 1)
(defconstant +node-store-chain-config-fingerprint-version+ 1)

(defparameter +node-store-staged-import-identifier+ "local")

(defparameter +node-store-staged-import-stage-names+
  '((:headers . "headers")
    (:bodies . "bodies")
    (:execution . "execution")
    (:receipts . "receipts")
    (:transaction-index . "transaction-index")))

(defparameter +node-store-staged-import-mode-names+
  '((:ready . "ready")
    (:forward . "forward")
    (:unwind . "unwind")))

(defstruct (node-store-stage-progress
            (:constructor %make-node-store-stage-progress
                (number block-hash)))
  number
  block-hash)

(defstruct (node-store-staged-import-state
            (:constructor %make-node-store-staged-import-state
                (&key revision mode anchor target unwind-target progresses
                      authority-id chain-id genesis-hash
                      chain-config-fingerprint)))
  revision
  mode
  anchor
  target
  unwind-target
  progresses
  authority-id
  chain-id
  genesis-hash
  chain-config-fingerprint)

(defun node-store-chain-config-optional-uint-rlp-object (value label)
  (cond
    ((null value) (make-rlp-list))
    ((and (integerp value) (not (minusp value)))
     (make-rlp-list value))
    (t
     (block-validation-fail
      "Staged import chain config ~A must be a non-negative integer or NIL"
      label))))

(defun node-store-chain-config-boolean-rlp-object (value)
  (cond
    ((null value) 0)
    ((eq value t) 1)
    (t
     (block-validation-fail
      "Staged import chain config boolean must be T or NIL"))))

(defun node-store-chain-config-optional-hash32-rlp-object (value label)
  (cond
    ((null value) (make-rlp-list))
    ((hash32-p value) (make-rlp-list (hash32-bytes value)))
    (t
     (block-validation-fail
      "Staged import chain config ~A must be a hash32 or NIL" label))))

(defun node-store-chain-config-optional-address-rlp-object (value label)
  (cond
    ((null value) (make-rlp-list))
    ((address-p value) (make-rlp-list (address-bytes value)))
    (t
     (block-validation-fail
      "Staged import chain config ~A must be an address or NIL" label))))

(defun node-store-chain-config-blob-schedule-rlp-object (schedule)
  (unless (listp schedule)
    (block-validation-fail
     "Staged import custom blob schedule must be a list"))
  (apply
   #'make-rlp-list
   (mapcar
    (lambda (entry)
      (unless (typep entry 'blob-schedule-entry)
        (block-validation-fail
         "Staged import custom blob schedule entry is malformed"))
      (let ((timestamp (blob-schedule-entry-timestamp entry))
            (target (blob-schedule-entry-target-blobs entry))
            (maximum (blob-schedule-entry-max-blobs entry))
            (fraction (blob-schedule-entry-update-fraction entry)))
        (unless (and (integerp timestamp) (not (minusp timestamp))
                     (integerp target) (not (minusp target))
                     (integerp maximum) (not (minusp maximum))
                     (integerp fraction) (plusp fraction))
          (block-validation-fail
           "Staged import custom blob schedule values are invalid"))
        (make-rlp-list timestamp target maximum fraction)))
    schedule)))

(defun node-store-chain-config-fingerprint (chain-config)
  "Return a versioned, deterministic commitment to every CHAIN-CONFIG field."
  (unless (typep chain-config 'chain-config)
    (block-validation-fail
     "Staged import requires a chain config"))
  (unless (uint256-p (chain-config-chain-id chain-config))
    (block-validation-fail
     "Staged import chain id must be a uint256"))
  (keccak-256-hash
   (rlp-encode
    (make-rlp-list
     "ethereum-lisp/staged-import/chain-config"
     +node-store-chain-config-fingerprint-version+
     (chain-config-chain-id chain-config)
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-homestead-block chain-config) "homestead block")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-dao-fork-block chain-config) "DAO fork block")
     (node-store-chain-config-boolean-rlp-object
      (chain-config-dao-fork-support chain-config))
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-eip150-block chain-config) "EIP-150 block")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-eip155-block chain-config) "EIP-155 block")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-eip158-block chain-config) "EIP-158 block")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-byzantium-block chain-config) "Byzantium block")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-constantinople-block chain-config)
      "Constantinople block")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-petersburg-block chain-config) "Petersburg block")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-istanbul-block chain-config) "Istanbul block")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-muir-glacier-block chain-config) "Muir Glacier block")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-berlin-block chain-config) "Berlin block")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-london-block chain-config) "London block")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-arrow-glacier-block chain-config) "Arrow Glacier block")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-gray-glacier-block chain-config) "Gray Glacier block")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-shanghai-time chain-config) "Shanghai time")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-cancun-time chain-config) "Cancun time")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-prague-time chain-config) "Prague time")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-osaka-time chain-config) "Osaka time")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-bpo1-time chain-config) "BPO1 time")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-bpo2-time chain-config) "BPO2 time")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-bpo3-time chain-config) "BPO3 time")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-bpo4-time chain-config) "BPO4 time")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-bpo5-time chain-config) "BPO5 time")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-amsterdam-time chain-config) "Amsterdam time")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-ubt-time chain-config) "UBT time")
     (node-store-chain-config-boolean-rlp-object
      (chain-config-enable-ubt-at-genesis-p chain-config))
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-terminal-total-difficulty chain-config)
      "terminal total difficulty")
     (node-store-chain-config-boolean-rlp-object
      (chain-config-terminal-total-difficulty-passed chain-config))
     (node-store-chain-config-optional-hash32-rlp-object
      (chain-config-terminal-block-hash chain-config) "terminal block hash")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-terminal-block-number chain-config)
      "terminal block number")
     (node-store-chain-config-optional-uint-rlp-object
      (chain-config-merge-netsplit-block chain-config)
      "merge netsplit block")
     (node-store-chain-config-optional-address-rlp-object
      (chain-config-deposit-contract-address chain-config)
      "deposit contract address")
     (node-store-chain-config-blob-schedule-rlp-object
      (chain-config-custom-blob-schedule chain-config))))))

(defun node-store-validate-staged-import-chain-config (state chain-config)
  (unless (hash32=
           (node-store-staged-import-state-chain-config-fingerprint state)
           (node-store-chain-config-fingerprint chain-config))
    (block-validation-fail
     "Staged import chain config does not match its persisted fingerprint"))
  chain-config)

(defun node-store-staged-import-stages ()
  (mapcar #'car +node-store-staged-import-stage-names+))

(defun node-store-staged-import-stage-name (stage)
  (or (cdr (assoc stage +node-store-staged-import-stage-names+))
      (block-validation-fail
       "Unknown staged import stage: ~S" stage)))

(defun node-store-staged-import-stage-from-name (name)
  (or (car (rassoc name +node-store-staged-import-stage-names+
                    :test #'string=))
      (block-validation-fail
       "Unknown staged import stage name: ~S" name)))

(defun node-store-staged-import-mode-name (mode)
  (or (cdr (assoc mode +node-store-staged-import-mode-names+))
      (block-validation-fail
       "Unknown staged import mode: ~S" mode)))

(defun node-store-staged-import-mode-from-name (name)
  (or (car (rassoc name +node-store-staged-import-mode-names+
                    :test #'string=))
      (block-validation-fail
       "Unknown staged import mode name: ~S" name)))

(defun node-store-make-stage-progress (number block-hash)
  (unless (uint64-value-p number)
    (block-validation-fail
     "Staged import progress number must be a uint64"))
  (unless (hash32-p block-hash)
    (block-validation-fail
     "Staged import progress block hash must be a hash32"))
  (%make-node-store-stage-progress number block-hash))

(defun node-store-stage-progress= (left right)
  (and (= (node-store-stage-progress-number left)
          (node-store-stage-progress-number right))
       (hash32= (node-store-stage-progress-block-hash left)
                (node-store-stage-progress-block-hash right))))

(defun node-store-stage-progress-for-block (block)
  (unless (typep block 'ethereum-block)
    (block-validation-fail
     "Staged import input must be an Ethereum block"))
  (node-store-make-stage-progress
   (block-header-number (block-header block))
   (block-hash block)))

(defun node-store-staged-import-stage-progress (state stage)
  (unless (node-store-staged-import-state-p state)
    (block-validation-fail
     "Staged import stage lookup requires a staged import state"))
  (node-store-staged-import-stage-name stage)
  (or (cdr (assoc stage
                  (node-store-staged-import-state-progresses state)))
      (block-validation-fail
       "Staged import state is missing stage ~S" stage)))

(defun node-store-stage-progress-rlp-object (progress)
  (make-rlp-list
   (node-store-stage-progress-number progress)
   (hash32-bytes (node-store-stage-progress-block-hash progress))))

(defun node-store-stage-progress-from-rlp-object (value label)
  (let ((fields (rlp-list-field value label)))
    (unless (= (length fields) 2)
      (block-validation-fail "~A must contain 2 fields" label))
    (node-store-make-stage-progress
     (rlp-uint-field (first fields) (format nil "~A number" label))
     (make-hash32
      (rlp-sized-bytes-field
       (second fields) 32 (format nil "~A block hash" label))))))

(defun node-store-staged-import-authority (database)
  (multiple-value-bind (metadata present-p)
      (node-store-read-persistence-metadata database)
    (unless present-p
      (block-validation-fail
       "Staged import requires versioned database persistence metadata"))
    (unless (eq (node-store-persistence-metadata-role metadata)
                :database)
      (block-validation-fail
       "Staged import requires database persistence authority"))
    (values
     (node-store-persistence-metadata-authority-id metadata)
     (node-store-persistence-metadata-chain-id metadata)
     (node-store-persistence-metadata-genesis-hash metadata))))

(defun node-store-validate-staged-import-authority (database state)
  (multiple-value-bind (authority-id chain-id genesis-hash)
      (node-store-staged-import-authority database)
    (unless (and (hash32= authority-id
                          (node-store-staged-import-state-authority-id
                           state))
                 (= chain-id
                    (node-store-staged-import-state-chain-id state))
                 (hash32= genesis-hash
                          (node-store-staged-import-state-genesis-hash
                           state)))
      (block-validation-fail
       "Staged import persistence identity changed")))
  state)

(defun node-store-staged-import-state-record-rlp (state)
  (rlp-encode
   (make-rlp-list
    +node-store-staged-import-version+
    (hash32-bytes
     (node-store-staged-import-state-authority-id state))
    (node-store-staged-import-state-chain-id state)
    (hash32-bytes
     (node-store-staged-import-state-genesis-hash state))
    (hash32-bytes
     (node-store-staged-import-state-chain-config-fingerprint state))
    (node-store-staged-import-state-revision state)
    (node-store-staged-import-mode-name
     (node-store-staged-import-state-mode state))
    (node-store-stage-progress-rlp-object
     (node-store-staged-import-state-anchor state))
    (node-store-stage-progress-rlp-object
     (node-store-staged-import-state-target state))
    (if (node-store-staged-import-state-unwind-target state)
        (node-store-stage-progress-rlp-object
         (node-store-staged-import-state-unwind-target state))
        (make-rlp-list))
    (apply
     #'make-rlp-list
     (mapcar
      (lambda (stage)
        (let ((progress
                (node-store-staged-import-stage-progress state stage)))
          (make-rlp-list
           (node-store-staged-import-stage-name stage)
           (node-store-stage-progress-number progress)
           (hash32-bytes
            (node-store-stage-progress-block-hash progress)))))
      (node-store-staged-import-stages))))))

(defun node-store-staged-import-stage-record-from-rlp-object
    (value expected-stage)
  (let ((fields (rlp-list-field value "Staged import stage progress")))
    (unless (= (length fields) 3)
      (block-validation-fail
       "Staged import stage progress must contain 3 fields"))
    (let ((stage
            (node-store-staged-import-stage-from-name
             (bytes-to-ascii
              (rlp-bytes-field
               (first fields) "Staged import stage name")))))
      (unless (eq stage expected-stage)
        (block-validation-fail
         "Staged import stage progress order is invalid"))
      (cons
       stage
       (node-store-make-stage-progress
        (rlp-uint-field
         (second fields) "Staged import stage number")
        (make-hash32
         (rlp-sized-bytes-field
          (third fields) 32 "Staged import stage block hash")))))))

(defun node-store-staged-import-state-from-record (record)
  (handler-case
      (let ((fields
              (rlp-list-field
               (rlp-decode-one record)
               "Staged import control record")))
        (unless (= (length fields) 11)
          (block-validation-fail
           "Staged import control record must contain 11 fields"))
        (let* ((version
                 (rlp-uint-field
                  (first fields) "Staged import control version"))
               (authority-id
                 (make-hash32
                  (rlp-sized-bytes-field
                   (second fields) 32 "Staged import authority id")))
               (chain-id
                 (rlp-uint-field
                  (third fields) "Staged import chain id"))
               (genesis-hash
                 (make-hash32
                  (rlp-sized-bytes-field
                   (fourth fields) 32 "Staged import genesis hash")))
               (chain-config-fingerprint
                 (make-hash32
                  (rlp-sized-bytes-field
                   (fifth fields) 32
                   "Staged import chain config fingerprint")))
               (revision
                 (rlp-uint-field
                  (sixth fields) "Staged import revision"))
               (mode
                 (node-store-staged-import-mode-from-name
                  (bytes-to-ascii
                   (rlp-bytes-field
                    (seventh fields) "Staged import mode"))))
               (anchor
                 (node-store-stage-progress-from-rlp-object
                  (eighth fields) "Staged import anchor"))
               (target
                 (node-store-stage-progress-from-rlp-object
                  (ninth fields) "Staged import target"))
               (unwind-fields
                 (rlp-list-field
                  (tenth fields) "Staged import unwind target"))
               (unwind-target
                 (cond
                   ((null unwind-fields) nil)
                   ((= (length unwind-fields) 2)
                    (node-store-stage-progress-from-rlp-object
                     (tenth fields) "Staged import unwind target"))
                   (t
                    (block-validation-fail
                     "Staged import unwind target must be empty or contain 2 fields"))))
               (stage-values
                 (rlp-list-field
                  (nth 10 fields) "Staged import stage progresses"))
               (stages (node-store-staged-import-stages)))
          (unless (= version +node-store-staged-import-version+)
            (block-validation-fail
             "Unsupported staged import control version: ~D" version))
          (unless (uint256-p chain-id)
            (block-validation-fail
             "Staged import chain id must be a uint256"))
          (unless (uint64-value-p revision)
            (block-validation-fail
             "Staged import revision must be a uint64"))
          (unless (= (length stage-values) (length stages))
            (block-validation-fail
             "Staged import control record must contain all stage progresses"))
          (%make-node-store-staged-import-state
           :revision revision
           :mode mode
           :anchor anchor
           :target target
           :unwind-target unwind-target
           :progresses
           (loop for value in stage-values
                 for stage in stages
                 collect
                 (node-store-staged-import-stage-record-from-rlp-object
                  value stage))
           :authority-id authority-id
           :chain-id chain-id
           :genesis-hash genesis-hash
           :chain-config-fingerprint chain-config-fingerprint)))
    (block-validation-error (condition)
      (error condition))
    (error (condition)
      (block-validation-fail
       "Invalid staged import control record: ~A" condition))))

(defun node-store-read-staged-import-state (database)
  (unless (typep database 'key-value-database)
    (block-validation-fail
     "Staged import source must be a key-value database"))
  (multiple-value-bind (record present-p)
      (kv-get-chain-record
       database :stage-progress +node-store-staged-import-identifier+)
    (if present-p
        (values
         (node-store-validate-staged-import-authority
          database
          (node-store-staged-import-state-from-record record))
         t)
        (values nil nil))))

(defun node-store-require-staged-record
    (database kind identifier label)
  (multiple-value-bind (record present-p)
      (kv-get-chain-record database kind identifier)
    (unless present-p
      (block-validation-fail
       "~A record is missing" label))
    record))

(defun node-store-validate-staged-block-body (block)
  (let ((header (block-header block)))
    (unless (hash32= (transaction-list-root (block-transactions block))
                     (block-header-transactions-root header))
      (block-validation-fail
       "Staged block transaction root does not match its header"))
    (unless (hash32= (ommers-hash (block-ommers block))
                     (block-header-ommers-hash header))
      (block-validation-fail
       "Staged block ommers root does not match its header"))
    (cond
      ((block-header-withdrawals-root header)
       (unless (and (block-withdrawals-present-p block)
                    (hash32=
                     (withdrawal-list-root (block-withdrawals block))
                     (block-header-withdrawals-root header)))
         (block-validation-fail
          "Staged block withdrawals do not match its header")))
      ((block-withdrawals-present-p block)
       (block-validation-fail
        "Staged block has withdrawals without a header commitment")))
    (when (block-requests-present-p block)
      (unless (and
               (block-header-requests-hash header)
               (hash32=
                (ethereum-lisp.execution-requests:execution-requests-hash
                 (block-requests block))
                (block-header-requests-hash header)))
        (block-validation-fail
         "Staged block requests do not match its header")))
    (cond
      ((block-header-block-access-list-hash header)
       (unless (and (block-block-access-list-present-p block)
                    (hash32=
                     (validated-block-access-list-commitment block)
                     (block-header-block-access-list-hash header)))
         (block-validation-fail
          "Staged block access list does not match its header")))
      ((block-block-access-list-present-p block)
       (block-validation-fail
        "Staged block has an access list without a header commitment"))))
  block)

(defun node-store-staged-import-header
    (database state progress)
  (let* ((anchor-p
           (node-store-stage-progress=
            progress (node-store-staged-import-state-anchor state)))
         (identifier
           (hash32-bytes
            (node-store-stage-progress-block-hash progress)))
         (record
           (node-store-require-staged-record
            database :staged-header identifier
            (if anchor-p "Staged import pinned anchor header"
                "Staged header")))
         (header (block-header-from-rlp record)))
    (unless (and (= (block-header-number header)
                    (node-store-stage-progress-number progress))
                 (hash32= (block-header-hash header)
                          (node-store-stage-progress-block-hash progress)))
      (block-validation-fail
       "Staged import header does not match its progress"))
    header))

(defun node-store-staged-import-block
    (database state progress)
  (let* ((anchor-p
           (node-store-stage-progress=
            progress (node-store-staged-import-state-anchor state)))
         (identifier
           (hash32-bytes
            (node-store-stage-progress-block-hash progress)))
         (record
           (node-store-require-staged-record
            database :staged-block identifier
            (if anchor-p "Staged import pinned anchor block"
                "Staged block")))
         (block
           (chain-store-block-from-persisted-record
            database identifier record
            (if anchor-p "Staged import pinned anchor block"
                "Staged block"))))
    (unless (and (= (block-header-number (block-header block))
                    (node-store-stage-progress-number progress))
                 (hash32= (block-hash block)
                          (node-store-stage-progress-block-hash progress))
                 (bytes= (block-header-rlp (block-header block))
                          (block-header-rlp
                           (node-store-staged-import-header
                            database state progress))))
      (block-validation-fail
       "Staged import block does not match its progress or header"))
    (node-store-validate-staged-block-body block)))

(defun node-store-staged-import-parent-progress
    (database state progress)
  (let ((anchor (node-store-staged-import-state-anchor state)))
    (when (node-store-stage-progress= progress anchor)
      (block-validation-fail
       "Staged import cannot walk below its anchor"))
    (let ((header
            (node-store-staged-import-header database state progress)))
      (unless (plusp (node-store-stage-progress-number progress))
        (block-validation-fail
         "Staged import non-anchor progress cannot be block zero"))
      (node-store-make-stage-progress
       (1- (node-store-stage-progress-number progress))
       (block-header-parent-hash header)))))

(defun node-store-staged-import-ancestor-p
    (database state ancestor descendant)
  (let ((ancestor-number (node-store-stage-progress-number ancestor))
        (descendant-number (node-store-stage-progress-number descendant)))
    (when (<= ancestor-number descendant-number)
      (loop with current = descendant
            while (> (node-store-stage-progress-number current)
                     ancestor-number)
            do (setf current
                     (node-store-staged-import-parent-progress
                      database state current))
            finally
               (return (node-store-stage-progress= ancestor current))))))

(defun node-store-staged-import-path
    (database state progress)
  (let ((anchor (node-store-staged-import-state-anchor state))
        (path '())
        (current progress))
    (loop until (node-store-stage-progress= current anchor)
          do (push current path)
             (setf current
                   (node-store-staged-import-parent-progress
                    database state current)))
    path))

(defun node-store-validate-staged-receipt-record
    (block record)
  (let ((receipts (block-receipts-from-record block record)))
    (validate-block-execution-roots
     block receipts
     (block-header-state-root (block-header block))
     :transactions (block-transactions block))
    receipts))

(defun node-store-validate-staged-state-record
    (block record)
  (let ((store (make-engine-payload-memory-store))
        (identifier (hash32-bytes (block-hash block))))
    (chain-store-put-block store block)
    (chain-store-import-state-record-from-kv store identifier record)
    t))

(defun node-store-staged-transaction-index-identifier
    (block-hash index)
  (unless (uint64-value-p index)
    (block-validation-fail
     "Staged transaction index must be a uint64"))
  (concat-bytes
   (hash32-bytes block-hash)
   (let ((bytes (make-byte-vector 8)))
     (dotimes (offset 8 bytes)
       (setf (aref bytes (- 7 offset))
             (ldb (byte 8 (* offset 8)) index))))))

(defun node-store-staged-transaction-index-record
    (transaction log-index-start)
  (unless (uint64-value-p log-index-start)
    (block-validation-fail
     "Staged transaction log index must be a uint64"))
  (rlp-encode
   (make-rlp-list
    +node-store-staged-transaction-index-version+
    (hash32-bytes (transaction-hash transaction))
    log-index-start)))

(defun node-store-validate-staged-transaction-index-record
    (record transaction log-index-start)
  (handler-case
      (let ((fields
              (rlp-list-field
               (rlp-decode-one record)
               "Staged transaction index record")))
        (unless (= (length fields) 3)
          (block-validation-fail
           "Staged transaction index record must contain 3 fields"))
        (unless (= (rlp-uint-field
                    (first fields) "Staged transaction index version")
                   +node-store-staged-transaction-index-version+)
          (block-validation-fail
           "Unsupported staged transaction index version"))
        (unless (hash32=
                 (rlp-hash32-field
                  (second fields) "Staged transaction hash")
                 (transaction-hash transaction))
          (block-validation-fail
           "Staged transaction index hash does not match its block"))
        (unless (= (rlp-uint-field
                    (third fields) "Staged transaction log index")
                   log-index-start)
          (block-validation-fail
           "Staged transaction log index is inconsistent"))
        t)
    (block-validation-error (condition)
      (error condition))
    (error (condition)
      (block-validation-fail
       "Invalid staged transaction index record: ~A" condition))))

(defun node-store-validate-staged-transaction-index-for-block
    (database block receipts)
  (loop with log-index-start = 0
        for transaction in (block-transactions block)
        for receipt in receipts
        for index from 0
        for identifier =
          (node-store-staged-transaction-index-identifier
           (block-hash block) index)
        for record =
          (node-store-require-staged-record
           database :staged-transaction-index identifier
           "Staged transaction index")
        do (node-store-validate-staged-transaction-index-record
            record transaction log-index-start)
           (incf log-index-start (length (receipt-logs receipt)))
           (unless (uint64-value-p log-index-start)
             (block-validation-fail
              "Staged transaction log index exceeds uint64")))
  t)

(defun node-store-validate-staged-import-anchor-index
    (database anchor &key require-finalized-p)
  (let ((identifier
          (hash32-bytes
           (node-store-stage-progress-block-hash anchor))))
    (multiple-value-bind (canonical-hash present-p)
        (kv-get-chain-canonical-hash
         database (node-store-stage-progress-number anchor))
      (unless (and present-p
                   (= (length canonical-hash) 32)
                   (bytes= canonical-hash identifier))
        (block-validation-fail
         "Staged import anchor is not public canonical state")))
    (when require-finalized-p
      (multiple-value-bind (finalized-hash present-p)
          (kv-get-chain-checkpoint database :finalized)
        (unless (and present-p
                     (= (length finalized-hash) 32)
                     (bytes= finalized-hash identifier))
          (block-validation-fail
           "Staged import anchor must be the finalized checkpoint")))))
  anchor)

(defun node-store-public-staged-import-anchor-records
    (database anchor supplied-block)
  (let* ((identifier
           (hash32-bytes
            (node-store-stage-progress-block-hash anchor)))
         (block-record
           (node-store-require-staged-record
            database :block identifier "Public staged import anchor block"))
         (header-record
           (node-store-require-staged-record
            database :header identifier "Public staged import anchor header"))
         (receipt-record
           (node-store-require-staged-record
            database :receipt identifier "Public staged import anchor receipt"))
         (state-record
           (node-store-require-staged-record
            database :state identifier "Public staged import anchor state"))
         (block
           (chain-store-block-from-persisted-record
            database identifier block-record
            "Public staged import anchor block")))
    (node-store-validate-staged-import-anchor-index
     database anchor :require-finalized-p t)
    (unless (and (= (block-header-number (block-header block))
                    (node-store-stage-progress-number anchor))
                 (hash32= (block-hash block)
                          (node-store-stage-progress-block-hash anchor))
                 (bytes= header-record
                          (block-header-rlp (block-header block))))
      (block-validation-fail
       "Public staged import anchor records are inconsistent"))
    (node-store-validate-staged-block-body block)
    (node-store-validate-staged-receipt-record block receipt-record)
    (node-store-validate-staged-state-record block state-record)
    (unless (and (hash32= (block-hash supplied-block)
                          (block-hash block))
                 (chain-store-persisted-block= supplied-block block)
                 (bytes= (block-receipts-record-rlp supplied-block)
                         receipt-record))
      (block-validation-fail
       "Supplied staged import anchor does not match persisted finalized state"))
    (values (chain-store-block-record-rlp block)
            header-record receipt-record state-record)))

(defun node-store-validate-staged-import-anchor (database state)
  (let* ((anchor (node-store-staged-import-state-anchor state))
         (identifier
           (hash32-bytes
            (node-store-stage-progress-block-hash anchor)))
         (block (node-store-staged-import-block database state anchor))
         (receipt-record
           (node-store-require-staged-record
            database :staged-receipt identifier
            "Pinned staged import anchor receipt"))
         (state-record
           (node-store-require-staged-record
            database :staged-state identifier
            "Pinned staged import anchor state")))
    (node-store-validate-staged-import-anchor-index database anchor)
    (node-store-validate-staged-receipt-record block receipt-record)
    (node-store-validate-staged-state-record block state-record)
    block))

(defun node-store-validate-staged-import-chain-identity
    (database state)
  (multiple-value-bind (genesis-hash present-p)
      (kv-get-chain-canonical-hash database 0)
    (unless (and present-p
                 (= (length genesis-hash) 32)
                 (bytes=
                  genesis-hash
                  (hash32-bytes
                   (node-store-staged-import-state-genesis-hash state))))
      (block-validation-fail
       "Staged import metadata genesis does not match the canonical database")))
  state)

(defun node-store-staged-import-all-progress-at-p (state target)
  (every
   (lambda (stage)
     (node-store-stage-progress=
      (node-store-staged-import-stage-progress state stage)
      target))
   (node-store-staged-import-stages)))

(defun node-store-validate-staged-import-relations
    (database state)
  (let* ((anchor (node-store-staged-import-state-anchor state))
         (target (node-store-staged-import-state-target state))
         (stages (node-store-staged-import-stages))
         (progresses
           (mapcar
            (lambda (stage)
              (node-store-staged-import-stage-progress state stage))
            stages)))
    (unless (node-store-staged-import-ancestor-p
             database state anchor target)
      (block-validation-fail
       "Staged import target is not descended from its anchor"))
    (dolist (progress progresses)
      (unless (and
               (node-store-staged-import-ancestor-p
                database state anchor progress)
               (node-store-staged-import-ancestor-p
                database state progress target))
        (block-validation-fail
         "Staged import progress is outside the active target path")))
    (loop for earlier in progresses
          for later in (rest progresses)
          do (unless (node-store-staged-import-ancestor-p
                      database state later earlier)
               (block-validation-fail
                "Staged import dependency progress is inverted")))
    (ecase (node-store-staged-import-state-mode state)
      (:ready
       (when (node-store-staged-import-state-unwind-target state)
         (block-validation-fail
          "Ready staged import state cannot retain an unwind target"))
       (unless (node-store-staged-import-all-progress-at-p state target)
         (block-validation-fail
          "Ready staged import state must have every stage at target")))
      (:forward
       (when (node-store-staged-import-state-unwind-target state)
         (block-validation-fail
          "Forward staged import state cannot retain an unwind target"))
       (when (node-store-stage-progress= anchor target)
         (block-validation-fail
          "Forward staged import target must be above its anchor"))
       (let ((parent
               (node-store-staged-import-parent-progress
                database state target))
             (incomplete-p nil))
         (dolist (progress progresses)
           (cond
             ((node-store-stage-progress= progress target)
              (when incomplete-p
                (block-validation-fail
                 "Staged import completed stages must form a prefix")))
             ((node-store-stage-progress= progress parent)
              (setf incomplete-p t))
             (t
              (block-validation-fail
               "Forward staged import progress must be at target or its parent"))))
         (unless incomplete-p
           (block-validation-fail
            "Complete staged import target must be in ready mode"))))
      (:unwind
       (let ((unwind-target
               (node-store-staged-import-state-unwind-target state)))
         (unless unwind-target
           (block-validation-fail
            "Unwind staged import state requires an unwind target"))
         (unless (node-store-staged-import-ancestor-p
                  database state anchor unwind-target)
           (block-validation-fail
            "Staged import unwind target is below its anchor"))
         (unless (node-store-staged-import-ancestor-p
                  database state unwind-target target)
           (block-validation-fail
            "Staged import unwind target is not on the active path"))
         (when (node-store-stage-progress= unwind-target target)
           (block-validation-fail
            "Staged import unwind target must be below the active target"))
         (dolist (progress progresses)
           (unless (node-store-staged-import-ancestor-p
                    database state unwind-target progress)
             (block-validation-fail
              "Staged import progress is below its unwind target")))
         (when (node-store-staged-import-all-progress-at-p
                state unwind-target)
           (block-validation-fail
            "Completed staged unwind must be in ready mode"))))))
  state)

(defun node-store-validate-staged-import-outputs
    (database state)
  (dolist (progress
           (node-store-staged-import-path
            database state
            (node-store-staged-import-stage-progress state :headers)))
    (node-store-staged-import-header database state progress))
  (dolist (progress
           (node-store-staged-import-path
            database state
            (node-store-staged-import-stage-progress state :bodies)))
    (node-store-staged-import-block database state progress))
  (dolist (progress
           (node-store-staged-import-path
            database state
            (node-store-staged-import-stage-progress state :execution)))
    (let* ((block
             (node-store-staged-import-block database state progress))
           (identifier (hash32-bytes (block-hash block)))
           (receipt-record
             (node-store-require-staged-record
              database :staged-receipt identifier
              "Staged execution receipt"))
           (state-record
             (node-store-require-staged-record
              database :staged-state identifier
              "Staged execution state")))
      (node-store-validate-staged-receipt-record block receipt-record)
      (node-store-validate-staged-state-record block state-record)))
  (dolist (progress
           (node-store-staged-import-path
            database state
            (node-store-staged-import-stage-progress state :receipts)))
    (let* ((block
             (node-store-staged-import-block database state progress))
           (record
             (node-store-require-staged-record
              database :staged-receipt
              (hash32-bytes (block-hash block))
              "Staged receipt")))
      (node-store-validate-staged-receipt-record block record)))
  (dolist (progress
           (node-store-staged-import-path
            database state
            (node-store-staged-import-stage-progress
             state :transaction-index)))
    (let* ((block
             (node-store-staged-import-block database state progress))
           (record
             (node-store-require-staged-record
              database :staged-receipt
              (hash32-bytes (block-hash block))
              "Staged transaction-index receipt"))
           (receipts
             (node-store-validate-staged-receipt-record block record)))
      (node-store-validate-staged-transaction-index-for-block
       database block receipts)))
  state)

(defun node-store-validate-staged-import (database)
  (multiple-value-bind (state present-p)
      (node-store-read-staged-import-state database)
    (unless present-p
      (block-validation-fail
       "Staged import control state is not initialized"))
    (node-store-validate-staged-import-chain-identity database state)
    (node-store-validate-staged-import-anchor database state)
    (node-store-validate-staged-import-relations database state)
    (node-store-validate-staged-import-outputs database state)
    state))

(defun node-store-staged-import-next-action (database)
  (let ((state (node-store-validate-staged-import database)))
    (ecase (node-store-staged-import-state-mode state)
      (:ready
       (values :forward :headers nil))
      (:forward
       (let ((target (node-store-staged-import-state-target state)))
         (dolist (stage (node-store-staged-import-stages))
           (unless (node-store-stage-progress=
                    (node-store-staged-import-stage-progress state stage)
                    target)
             (return-from node-store-staged-import-next-action
               (values :forward stage target))))
         (block-validation-fail
          "Forward staged import state has no pending stage")))
      (:unwind
       (let ((target
               (node-store-staged-import-state-unwind-target state)))
         (dolist (stage
                  (reverse (node-store-staged-import-stages)))
           (unless (node-store-stage-progress=
                    (node-store-staged-import-stage-progress state stage)
                    target)
             (return-from node-store-staged-import-next-action
               (values :unwind stage target))))
         (values :finish-unwind nil target))))))

(defun node-store-staged-import-next-revision (state)
  (let ((revision (node-store-staged-import-state-revision state)))
    (unless (< revision (1- (ash 1 64)))
      (block-validation-fail
       "Staged import revision is exhausted"))
    (1+ revision)))

(defun node-store-staged-import-progresses-with
    (state stage progress)
  (mapcar
   (lambda (entry)
     (if (eq (car entry) stage)
         (cons stage progress)
         (cons (car entry) (cdr entry))))
   (node-store-staged-import-state-progresses state)))

(defun node-store-write-staged-import-state (database state batch)
  (kv-batch-put-chain-record
   batch
   :stage-progress
   +node-store-staged-import-identifier+
   (node-store-staged-import-state-record-rlp state))
  (kv-apply-batch database batch)
  state)

(defun node-store-begin-staged-import
    (database anchor-block &key chain-config)
  "Initialize DATABASE staging at public canonical ANCHOR-BLOCK.

The first implementation is an offline, deterministic single-writer
boundary.  CHAIN-CONFIG is committed into the control record so a restart
cannot silently change fork rules.  This boundary does not provide
cross-handle file-database serialization."
  (unless (typep database 'key-value-database)
    (block-validation-fail
     "Staged import target must be a key-value database"))
  (let ((anchor (node-store-stage-progress-for-block anchor-block))
        (chain-config-fingerprint
          (node-store-chain-config-fingerprint chain-config)))
    (multiple-value-bind (existing-state present-p)
        (node-store-read-staged-import-state database)
      (when present-p
        (node-store-validate-staged-import database)
        (node-store-validate-staged-import-chain-config
         existing-state chain-config)
        (if (and (eq (node-store-staged-import-state-mode existing-state)
                     :ready)
                 (node-store-stage-progress=
                  (node-store-staged-import-state-anchor existing-state)
                  anchor)
                 (node-store-stage-progress=
                  (node-store-staged-import-state-target existing-state)
                  anchor))
            (return-from node-store-begin-staged-import
              (values existing-state :already-initialized))
            (block-validation-fail
             "Staged import control state is already initialized"))))
    (multiple-value-bind (authority-id chain-id genesis-hash)
        (node-store-staged-import-authority database)
      (let ((state
              (%make-node-store-staged-import-state
               :revision 0
               :mode :ready
               :anchor anchor
               :target anchor
               :unwind-target nil
               :progresses
               (mapcar
                (lambda (stage) (cons stage anchor))
                (node-store-staged-import-stages))
               :authority-id authority-id
               :chain-id chain-id
               :genesis-hash genesis-hash
               :chain-config-fingerprint chain-config-fingerprint)))
        (unless (= chain-id (chain-config-chain-id chain-config))
          (block-validation-fail
           "Staged import chain config does not match persistence metadata"))
        (node-store-validate-staged-import-chain-identity database state)
        (multiple-value-bind
              (block-record header-record receipt-record state-record)
            (node-store-public-staged-import-anchor-records
             database anchor anchor-block)
          (let ((batch (make-kv-write-batch))
                (identifier (hash32-bytes (block-hash anchor-block))))
            (declare (ignore block-record))
            (node-store-put-immutable-block-body-record
             database batch :staged-block anchor-block
             "Pinned staged import anchor block")
            (node-store-put-immutable-record
             database batch :staged-header identifier header-record
             "Pinned staged import anchor header")
            (node-store-put-immutable-record
             database batch :staged-receipt identifier receipt-record
             "Pinned staged import anchor receipt")
            (node-store-put-immutable-record
             database batch :staged-state identifier state-record
             "Pinned staged import anchor state")
            (node-store-write-staged-import-state database state batch)))
        (values state :initialized)))))

(defun node-store-staged-import-forward-stage (state)
  (ecase (node-store-staged-import-state-mode state)
    (:ready :headers)
    (:forward
     (let ((target (node-store-staged-import-state-target state)))
       (or
        (find-if
         (lambda (stage)
           (not
            (node-store-stage-progress=
             (node-store-staged-import-stage-progress state stage)
             target)))
         (node-store-staged-import-stages))
        (block-validation-fail
         "Forward staged import state has no pending stage"))))
    (:unwind
     (block-validation-fail
      "Staged import cannot move forward while unwind is active"))))

(defun node-store-staged-import-source-block (source block)
  (chain-store-require-memory-store source)
  (let ((source-block (chain-store-known-block source (block-hash block))))
    (unless (and source-block
                 (chain-store-persisted-block= source-block block))
      (block-validation-fail
       "Staged import source does not contain the supplied block"))
    source-block))

(defun node-store-staged-import-put-header
    (database batch block)
  (let ((identifier (hash32-bytes (block-hash block))))
    (node-store-put-immutable-record
     database batch :staged-header identifier
     (block-header-rlp (block-header block))
     "Staged header")))

(defun node-store-staged-import-put-body
    (database batch block)
  (node-store-validate-staged-block-body block)
  (node-store-put-immutable-block-body-record
   database batch :staged-block block "Staged block"))

(defun node-store-staged-import-put-execution
    (database batch state block chain-config)
  ;; A resumed pre-migration staged record may still carry the BAL inline.
  ;; Canonicalize it into the staged body plus hash-addressed side data in the
  ;; same batch that publishes the execution result.
  (node-store-put-immutable-block-body-record
   database batch :staged-block block "Staged execution block")
  (let ((execution-store (make-engine-payload-memory-store)))
    (node-store-hydrate-staged-import
     execution-store database
     :stage :execution
     :chain-config chain-config
     :import-txpool-p nil)
    (multiple-value-bind (executed-block receipts)
        (ethereum-lisp.execution-service:execute-and-commit-engine-payload
         execution-store
         (chain-store-block-with-access-list-side-data
          database
          (hash32-bytes (block-hash block))
          (block-from-rlp (block-rlp block))
          "Staged execution block"
          :legacy-encoded-block-access-list
          (block-encoded-block-access-list block)
          :legacy-block-access-list-present-p
          (block-block-access-list-present-p block))
         chain-config)
      (declare (ignore receipts))
      (unless (and (hash32= (block-hash executed-block)
                            (block-hash block))
                   (chain-store-persisted-block= executed-block block))
        (block-validation-fail
         "Staged execution result does not match the supplied block"))
      (unless (node-store-stage-progress=
               (node-store-staged-import-stage-progress state :execution)
               (node-store-staged-import-parent-progress
                database state
                (node-store-stage-progress-for-block executed-block)))
        (block-validation-fail
         "Staged execution parent progress is inconsistent"))
      (let* ((identifier (hash32-bytes (block-hash executed-block)))
             (state-record
               (chain-store-state-record-rlp
                execution-store (block-hash executed-block)))
             (receipt-record
               (block-receipts-record-rlp executed-block)))
        (node-store-validate-staged-state-record
         executed-block state-record)
        (node-store-validate-staged-receipt-record
         executed-block receipt-record)
        (node-store-put-immutable-record
         database batch :staged-state identifier state-record
         "Staged execution state")
        (node-store-put-immutable-record
         database batch :staged-receipt identifier receipt-record
         "Staged execution receipt")))))

(defun node-store-staged-import-validate-receipts-stage
    (database state block)
  (let* ((progress (node-store-stage-progress-for-block block))
         (persisted-block
           (node-store-staged-import-block database state progress))
         (record
           (node-store-require-staged-record
            database :staged-receipt
            (hash32-bytes (block-hash block))
            "Staged receipt")))
    (unless (chain-store-persisted-block= persisted-block block)
      (block-validation-fail
       "Staged receipt block differs from the staged body"))
    (node-store-validate-staged-receipt-record persisted-block record)))

(defun node-store-staged-import-put-transaction-index
    (database batch block receipts)
  (loop with log-index-start = 0
        for transaction in (block-transactions block)
        for receipt in receipts
        for index from 0
        do (node-store-put-immutable-record
            database batch :staged-transaction-index
            (node-store-staged-transaction-index-identifier
             (block-hash block) index)
            (node-store-staged-transaction-index-record
             transaction log-index-start)
            "Staged transaction index")
           (incf log-index-start (length (receipt-logs receipt)))
           (unless (uint64-value-p log-index-start)
             (block-validation-fail
              "Staged transaction log index exceeds uint64"))))

(defun node-store-staged-import-forward-input-block
    (source database block state stage)
  (if (member stage '(:execution :receipts :transaction-index))
      (let* ((target (node-store-staged-import-state-target state))
             (persisted-block
               (node-store-staged-import-block database state target)))
        (when block
          (unless (and (typep block 'ethereum-block)
                       (chain-store-persisted-block=
                        block persisted-block))
            (block-validation-fail
             "Staged import input differs from the durable block")))
        (when source
          (node-store-staged-import-source-block
           source (or block persisted-block)))
        persisted-block)
      (progn
        (unless (and source block)
          (block-validation-fail
           "Header and body stages require an external block source"))
        (node-store-staged-import-source-block source block))))

(defun node-store-forward-staged-import-block
    (source database block &key stage chain-config)
  "Advance one BLOCK through one atomic staged-import STAGE.

SOURCE is a memory node store containing the deterministic header/body input.
Execution reconstructs the persisted parent state, executes the block under
CHAIN-CONFIG, and persists only the derived state and receipts after their
header commitments match.  Execution, receipt verification, and transaction
indexing can resume with SOURCE and BLOCK both NIL once the body is durable.
When STAGE is NIL, the persisted control state selects the next legal stage."
  (let* ((state (node-store-validate-staged-import database))
         (target (node-store-staged-import-state-target state))
         (selected-stage
           (or stage (node-store-staged-import-forward-stage state)))
         (source-block
           (progn
             (node-store-staged-import-stage-name selected-stage)
             (node-store-staged-import-forward-input-block
              source database block state selected-stage)))
         (block-progress
           (node-store-stage-progress-for-block source-block)))
    (node-store-validate-staged-import-chain-config state chain-config)
    (when (eq (node-store-staged-import-state-mode state) :unwind)
      (block-validation-fail
       "Staged import cannot move forward while unwind is active"))
    (if (eq selected-stage :headers)
        (cond
          ((node-store-stage-progress= block-progress target)
           (unless (node-store-stage-progress=
                    (node-store-staged-import-stage-progress state :headers)
                    target)
             (block-validation-fail
              "Staged import header progress is inconsistent"))
           (return-from node-store-forward-staged-import-block
             (values state :already-complete)))
          ((not (eq (node-store-staged-import-state-mode state) :ready))
           (block-validation-fail
            "Staged import must finish its target before adding a header"))
          ((or (/= (node-store-stage-progress-number block-progress)
                   (1+ (node-store-stage-progress-number target)))
               (not
                (hash32=
                 (block-header-parent-hash (block-header source-block))
                 (node-store-stage-progress-block-hash target))))
           (block-validation-fail
            "Staged import header must directly extend its completed target")))
        (progn
          (unless (node-store-stage-progress= block-progress target)
            (block-validation-fail
             "Staged import stage block does not match the active target"))
          (when (node-store-stage-progress=
                 (node-store-staged-import-stage-progress
                  state selected-stage)
                 target)
            (return-from node-store-forward-staged-import-block
              (values state :already-complete)))
          (unless (eq selected-stage
                      (node-store-staged-import-forward-stage state))
            (block-validation-fail
             "Staged import stage dependency is not complete"))
          (unless (node-store-stage-progress=
                   (node-store-staged-import-stage-progress
                    state selected-stage)
                   (node-store-staged-import-parent-progress
                    database state target))
            (block-validation-fail
             "Staged import stage cannot skip an intermediate block"))))
    (let* ((batch (make-kv-write-batch))
           (new-target
             (if (eq selected-stage :headers) block-progress target)))
      (ecase selected-stage
        (:headers
         (validate-block-header-against-config
          (node-store-staged-import-header database state target)
          (block-header source-block)
          chain-config)
         (node-store-staged-import-put-header
          database batch source-block))
        (:bodies
         (let ((persisted-header
                 (node-store-staged-import-header
                  database state block-progress)))
           (unless (bytes= (block-header-rlp persisted-header)
                           (block-header-rlp
                            (block-header source-block)))
             (block-validation-fail
              "Staged block does not match the staged header")))
         (validate-block-body-against-config source-block chain-config)
         (node-store-staged-import-put-body
          database batch source-block))
        (:execution
         (node-store-staged-import-put-execution
          database batch state source-block chain-config))
        (:receipts
         (node-store-staged-import-validate-receipts-stage
          database state source-block))
        (:transaction-index
         (node-store-staged-import-put-transaction-index
          database batch source-block
          (node-store-staged-import-validate-receipts-stage
           database state source-block))))
      (let* ((new-progresses
               (node-store-staged-import-progresses-with
                state selected-stage block-progress))
             (complete-p
               (every
                (lambda (entry)
                  (node-store-stage-progress= (cdr entry) new-target))
                new-progresses))
             (new-state
               (%make-node-store-staged-import-state
                :revision (node-store-staged-import-next-revision state)
                :mode (if complete-p :ready :forward)
                :anchor (node-store-staged-import-state-anchor state)
                :target new-target
                :unwind-target nil
                :progresses new-progresses
                :authority-id
                (node-store-staged-import-state-authority-id state)
                :chain-id
                (node-store-staged-import-state-chain-id state)
                :genesis-hash
                (node-store-staged-import-state-genesis-hash state)
                :chain-config-fingerprint
                (node-store-staged-import-state-chain-config-fingerprint
                 state))))
        (node-store-write-staged-import-state database new-state batch)
        (values new-state :advanced)))))

(defun node-store-begin-staged-unwind (database ancestor-block)
  "Persist reverse-order unwind intent toward ANCESTOR-BLOCK."
  (let* ((state (node-store-validate-staged-import database))
         (ancestor (node-store-stage-progress-for-block ancestor-block))
         (target (node-store-staged-import-state-target state)))
    (when (eq (node-store-staged-import-state-mode state) :unwind)
      (if (node-store-stage-progress=
           ancestor
           (node-store-staged-import-state-unwind-target state))
          (return-from node-store-begin-staged-unwind
            (values state :already-unwinding))
          (block-validation-fail
           "Staged import already has a different unwind target")))
    (unless (node-store-staged-import-ancestor-p
             database state
             (node-store-staged-import-state-anchor state)
             ancestor)
      (block-validation-fail
       "Staged import unwind target is below its anchor"))
    (unless (node-store-staged-import-ancestor-p
             database state ancestor target)
      (block-validation-fail
       "Staged import unwind target is not on the active path"))
    (dolist (stage (node-store-staged-import-stages))
      (unless (node-store-staged-import-ancestor-p
               database state ancestor
               (node-store-staged-import-stage-progress state stage))
        (block-validation-fail
         "Staged import cannot unwind above incomplete stage progress")))
    (let ((persisted-block
            (node-store-staged-import-block database state ancestor)))
      (unless (chain-store-persisted-block=
               persisted-block ancestor-block)
        (block-validation-fail
         "Staged import unwind block does not match persisted data")))
    (when (node-store-stage-progress= ancestor target)
      (return-from node-store-begin-staged-unwind
        (values state :already-at-target)))
    (let ((new-state
            (%make-node-store-staged-import-state
             :revision (node-store-staged-import-next-revision state)
             :mode :unwind
             :anchor (node-store-staged-import-state-anchor state)
             :target target
             :unwind-target ancestor
             :progresses
             (node-store-staged-import-state-progresses state)
             :authority-id
             (node-store-staged-import-state-authority-id state)
             :chain-id
             (node-store-staged-import-state-chain-id state)
             :genesis-hash
             (node-store-staged-import-state-genesis-hash state)
             :chain-config-fingerprint
             (node-store-staged-import-state-chain-config-fingerprint
              state))))
      (node-store-write-staged-import-state
       database new-state (make-kv-write-batch))
      (values new-state :unwind-started))))

(defun node-store-staged-import-unwind-stage (state)
  (let ((target (node-store-staged-import-state-unwind-target state)))
    (find-if
     (lambda (stage)
       (not
        (node-store-stage-progress=
         (node-store-staged-import-stage-progress state stage)
         target)))
     (reverse (node-store-staged-import-stages)))))

(defun node-store-unwind-staged-import-step (database)
  "Rewind one stage marker by one block, retaining hash-addressed side data."
  (let ((state (node-store-validate-staged-import database)))
    (unless (eq (node-store-staged-import-state-mode state) :unwind)
      (block-validation-fail
       "Staged import unwind is not active"))
    (let* ((unwind-target
             (node-store-staged-import-state-unwind-target state))
           (stage (node-store-staged-import-unwind-stage state))
           (new-progresses
             (if stage
                 (let* ((progress
                          (node-store-staged-import-stage-progress
                           state stage))
                        (parent
                          (node-store-staged-import-parent-progress
                           database state progress)))
                   (unless (node-store-staged-import-ancestor-p
                            database state unwind-target parent)
                     (block-validation-fail
                      "Staged import unwind step crossed its target"))
                   (node-store-staged-import-progresses-with
                    state stage parent))
                 (node-store-staged-import-state-progresses state)))
           (complete-p
             (every
              (lambda (entry)
                (node-store-stage-progress=
                 (cdr entry) unwind-target))
              new-progresses))
           (new-state
             (%make-node-store-staged-import-state
              :revision (node-store-staged-import-next-revision state)
              :mode (if complete-p :ready :unwind)
              :anchor (node-store-staged-import-state-anchor state)
              :target
              (if complete-p
                  unwind-target
                  (node-store-staged-import-state-target state))
              :unwind-target (unless complete-p unwind-target)
              :progresses new-progresses
              :authority-id
              (node-store-staged-import-state-authority-id state)
              :chain-id
              (node-store-staged-import-state-chain-id state)
              :genesis-hash
              (node-store-staged-import-state-genesis-hash state)
              :chain-config-fingerprint
              (node-store-staged-import-state-chain-config-fingerprint
               state))))
      (node-store-write-staged-import-state
       database new-state (make-kv-write-batch))
      (values new-state (or stage :finished)))))

(defun node-store-copy-key-value-database (source target)
  (let ((iterator (kv-iterator source)))
    (loop
      (multiple-value-bind (key value present-p)
          (funcall iterator)
        (unless present-p
          (return target))
        (kv-put target key value)))))

(defun node-store-populate-staged-hydration-batch
    (database staging-database state horizon batch)
  (dolist (progress
           (cons
            (node-store-staged-import-state-anchor state)
            (node-store-staged-import-path
             database state horizon)))
    (let* ((identifier
             (hash32-bytes
              (node-store-stage-progress-block-hash progress)))
           (header-record
             (node-store-require-staged-record
              database :staged-header identifier
              "Staged hydration header"))
           (block-record
             (node-store-require-staged-record
              database :staged-block identifier
              "Staged hydration block"))
           (state-record
             (node-store-require-staged-record
              database :staged-state identifier
              "Staged hydration state"))
           (receipt-record
             (node-store-require-staged-record
              database :staged-receipt identifier
              "Staged hydration receipt")))
      (node-store-put-immutable-record
       staging-database batch :header identifier header-record
       "Staged hydration header")
      (node-store-put-immutable-record
       staging-database batch :block identifier block-record
       "Staged hydration block")
      (node-store-put-immutable-record
       staging-database batch :state identifier state-record
       "Staged hydration state")
      (node-store-put-immutable-record
       staging-database batch :receipt identifier receipt-record
       "Staged hydration receipt")))
  batch)

(defun node-store-require-fresh-staged-hydration-target (store)
  (let ((chain-store (chain-store-require-memory-store store)))
    (unless
        (and
         (every
          #'zerop
          (mapcar
           #'hash-table-count
           (list
            (memory-chain-store-blocks chain-store)
            (memory-chain-store-number-blocks chain-store)
            (memory-chain-store-canonical-hashes chain-store)
            (memory-chain-store-transaction-locations chain-store)
            (memory-chain-store-account-balances chain-store)
            (memory-chain-store-account-nonces chain-store)
            (memory-chain-store-account-codes chain-store)
            (memory-chain-store-account-storage chain-store)
            (memory-chain-store-state-blocks chain-store)
            (memory-chain-store-remote-blocks chain-store)
            (memory-chain-store-invalid-tipsets chain-store)
            (memory-chain-store-prepared-payloads chain-store)
            (memory-chain-store-blob-sidecars chain-store)
            (memory-chain-store-log-filters chain-store))))
         (zerop (memory-chain-store-head-number chain-store))
         (= 1 (memory-chain-store-next-log-filter-id chain-store))
         (null
          (chain-store-checkpoint-block-hash
           (memory-chain-store-head-checkpoint chain-store)))
         (null
          (chain-store-checkpoint-block-hash
           (memory-chain-store-safe-checkpoint chain-store)))
         (null
          (chain-store-checkpoint-block-hash
           (memory-chain-store-finalized-checkpoint chain-store)))
         (null (engine-payload-store-pooled-transactions store))
         (not
          (engine-payload-store-txpool-database-change-tracking-enabled-p
           store))
         (null
          (engine-payload-store-txpool-database-dirty-transaction-hashes
           store)))
      (block-validation-fail
       "Staged hydration target must be a fresh startup store")))
  store)

(defun node-store-hydrate-staged-import
    (store database &key (stage :transaction-index)
                         expected-chain-id chain-config
                         track-txpool-database-changes-p
                         (import-txpool-p t))
  "Hydrate validated staged data into a fresh STORE without changing DATABASE.

The staged path is overlaid as noncanonical public records in a temporary
memory database, then passed through the normal atomic node importer.
Canonical publication remains the responsibility of forkchoice."
  (node-store-require-fresh-staged-hydration-target store)
  (unless (member stage '(:execution :receipts :transaction-index))
    (block-validation-fail
     "Staged hydration requires execution-complete data"))
  (let ((state (node-store-validate-staged-import database)))
    (node-store-validate-staged-import-chain-config state chain-config)
    (when (and expected-chain-id
               (/= expected-chain-id
                   (node-store-staged-import-state-chain-id state)))
      (block-validation-fail
       "Staged hydration expected chain id does not match persistence metadata"))
    (when (eq (node-store-staged-import-state-mode state) :unwind)
      (block-validation-fail
       "Staged import cannot hydrate while unwind is active"))
    (let* ((horizon
             (node-store-staged-import-stage-progress state stage))
           (staging-database (make-memory-key-value-database))
           (batch (make-kv-write-batch)))
      (node-store-copy-key-value-database database staging-database)
      (node-store-populate-staged-hydration-batch
       database staging-database state horizon batch)
      (kv-apply-batch staging-database batch)
      (node-store-import-from-kv
       store staging-database
       :expected-chain-id
       (node-store-staged-import-state-chain-id state)
       :chain-config chain-config
       :track-txpool-database-changes-p
       track-txpool-database-changes-p
       :import-txpool-p import-txpool-p))))
