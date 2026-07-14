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
         (node-store-export-txpool-records-to-kv
          (devnet-node-store node)
          (devnet-cli-make-output-kv-database journal-path))
         t)))))

(defun make-devnet-rejournal-state
    (node interval-seconds &key (now-function #'get-universal-time))
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

(defun devnet-node-pending-mining-transactions (node)
  (let* ((store (devnet-node-store node))
         (expected-chain-id
           (chain-config-chain-id (devnet-node-config node))))
    (engine-payload-store-pending-mining-transactions
     store expected-chain-id)))

(defun devnet-node-seal-pending-block-without-guard (node &key timestamp)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (let* ((store (devnet-node-store node))
         (config (devnet-node-config node))
         (parent (chain-store-latest-block store))
         (pending-transactions
           (devnet-node-pending-mining-transactions node)))
    (when (and parent pending-transactions)
      (let* ((parent-header (block-header parent))
             (parent-hash (block-hash parent))
             (parent-timestamp (block-header-timestamp parent-header))
             (timestamp (max (or timestamp 0) (1+ parent-timestamp)))
             (block-number (1+ (block-header-number parent-header)))
             (gas-limit (block-header-gas-limit parent-header))
             (expected-chain-id (chain-config-chain-id config))
             (transactions
               (engine-select-mining-transactions
                pending-transactions gas-limit expected-chain-id))
             (state (chain-store-state-db store parent-hash))
             (cancun-p (chain-config-cancun-p config block-number timestamp))
             (shanghai-p (chain-config-shanghai-p config block-number
                                                   timestamp))
             (prague-p (chain-config-prague-p config block-number timestamp))
             (amsterdam-p
               (chain-config-amsterdam-p config block-number timestamp))
             (base-fee-per-gas
               (if (block-header-base-fee-per-gas parent-header)
                   (expected-base-fee-per-gas parent-header)
                   0))
             (cancun-header-arguments nil)
             (fork-body-arguments nil))
        (when transactions
          (unless state
            (error "Devnet dev-period parent state is unavailable"))
          (when cancun-p
            (multiple-value-bind (target-blob-gas max-blob-gas
                                  update-fraction)
                (chain-config-blob-schedule config block-number timestamp)
              (setf cancun-header-arguments
                    (list
                     :blob-gas-used 0
                     :excess-blob-gas
                     (expected-excess-blob-gas
                      parent-header
                      :target-blob-gas target-blob-gas
                      :max-blob-gas max-blob-gas
                      :eip7918-p (chain-config-osaka-p config block-number
                                                        timestamp)
                      :update-fraction update-fraction)
                     :parent-beacon-root (zero-hash32)))))
          (when shanghai-p
            (setf fork-body-arguments
                  (append fork-body-arguments (list :withdrawals '()))))
          (when prague-p
            (setf fork-body-arguments
                  (append fork-body-arguments (list :requests '()))))
          (when amsterdam-p
            (setf fork-body-arguments
                  (append fork-body-arguments (list :block-access-list '()))))
          (multiple-value-bind (block receipts)
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
                 :state-available-p t)
                fork-body-arguments))
            (declare (ignore receipts))
            block))))))

(defun devnet-node-seal-pending-block (node &key timestamp)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (call-with-devnet-node-store-guard
   node
   (lambda ()
     (devnet-node-seal-pending-block-without-guard
      node :timestamp timestamp))))

(defun make-devnet-dev-period-state
    (node interval-seconds &key (now-function #'get-universal-time))
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
        (setf (devnet-dev-period-state-last-run-time state) now)
        (devnet-node-seal-pending-block
         (devnet-dev-period-state-node state)
         :timestamp now)))))

(defun devnet-node-export-database (node &key state-prune-before)
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (call-with-devnet-node-store-guard
   node
   (lambda ()
     (when state-prune-before
       (chain-store-prune-state-before
        (devnet-node-store node) state-prune-before))
     (let ((database-path (devnet-node-database-path node)))
       (when database-path
         (node-store-export-to-kv
          (devnet-node-store node)
          (devnet-cli-make-output-kv-database database-path))))
     (let ((journal-path (devnet-node-txpool-journal-path node)))
       (when journal-path
         (node-store-export-txpool-records-to-kv
          (devnet-node-store node)
          (devnet-cli-make-output-kv-database journal-path))
         t)))))
