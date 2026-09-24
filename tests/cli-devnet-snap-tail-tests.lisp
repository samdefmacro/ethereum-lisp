(in-package #:ethereum-lisp.test)

;;;; The bounded snap tail: executing the blocks between the pivot and the
;;;; consensus target once the pivot state exists.
;;;;
;;;; Hoodi, 2026-09-24 (container hoodi-el-sec5-04a3aff4): after a pivot
;;;; rebase to 3684866 and a 90-second heal, the tail executed 3684867 ..
;;;; 3684908 and then exited the node with "Snap target tail block 0x5b84...
;;;; returned SYNCING instead of VALID".  Block 3684909 carries a transaction
;;;; whose calldata names block 3684839 by number and hash, 70 blocks deep.
;;;; The skeleton starts at the pivot, so no block below it was known; the
;;;; BLOCKHASH window built for 3684909 ended at the pivot's parent, execution
;;;; signalled "BLOCK hash history is unavailable" (a STATE-UNAVAILABLE-ERROR),
;;;; and IMPORT-P2P-BLOCK-CANDIDATE answers that for a known block with
;;;; SYNCING.  The tail then treated SYNCING as a storage failure, which the
;;;; coordinator's outer boundary turns into a node shutdown with exit 1.

(defparameter +snap-tail-blockhash-depth+ 10
  "How far back the fixture contract reads BLOCKHASH.")

(defparameter +snap-tail-blockhash-contract+
  "0x0000000000000000000000000000000000002003")

(defun snap-tail-genesis-json ()
  "Paris genesis with a funded sender and a contract that stores a block hash.

The contract is PUSH1 10 NUMBER SUB BLOCKHASH PUSH1 0 SSTORE STOP: it writes
the hash of the block ten below the one executing it to slot zero, so the
post-state root (and therefore the VALID verdict) depends on that hash."
  (format nil "{\"config\":{\"chainId\":1337,\"terminalTotalDifficulty\":0,\"londonBlock\":0},\"nonce\":\"0x0\",\"timestamp\":\"0x0\",\"extraData\":\"0x\",\"gasLimit\":\"0x1c9c380\",\"difficulty\":\"0x0\",\"mixHash\":\"0x0000000000000000000000000000000000000000000000000000000000000000\",\"coinbase\":\"0x0000000000000000000000000000000000000000\",\"alloc\":{\"~A\":{\"balance\":\"0xde0b6b3a7640000\"},\"~A\":{\"balance\":\"0x0\",\"nonce\":\"0x1\",\"code\":\"0x60~2,'0X43034060005500\",\"storage\":{\"0x0000000000000000000000000000000000000000000000000000000000000000\":\"0x01\"}}}}"
          (address-to-hex
           (fixture-private-key-address
            +devnet-peer-sync-storage-writer-key+))
          +snap-tail-blockhash-contract+
          +snap-tail-blockhash-depth+))

(defun snap-tail-produce-chain (genesis-json count calls)
  "Return a vector of GENESIS and COUNT produced blocks, receipts attached.

A block whose number is in CALLS carries one call to the BLOCKHASH contract;
every other block is empty, so the state root below the first call is the
genesis root."
  (multiple-value-bind (producer config parent)
      (eth-sync-make-seeded-store genesis-json)
    (let ((chain (make-array (1+ count)))
          (contract (address-from-hex +snap-tail-blockhash-contract+))
          (nonce 0))
      (setf (aref chain 0) parent)
      (loop for number from 1 to count
            do (let* ((transactions
                        (when (member number calls)
                          (prog1
                              (list
                               (fixture-sign-legacy-transaction
                                (make-legacy-transaction
                                 :nonce nonce
                                 :gas-price 10000000000
                                 :gas-limit 100000
                                 :to contract
                                 :value 0
                                 :data (make-byte-vector 0))
                                +devnet-peer-sync-storage-writer-key+
                                (chain-config-chain-id config)))
                            (incf nonce))))
                      (attributes
                        (make-payload-attributes-v1
                         :timestamp
                         (+ (block-header-timestamp (block-header parent)) 12)
                         :prev-randao (zero-hash32)
                         :suggested-fee-recipient (zero-address)))
                      (block
                        (ethereum-lisp.engine-api::engine-rpc-build-prepared-payload-detached
                         producer parent attributes config transactions)))
                 (execute-and-commit-engine-payload producer block config)
                 ;; What a peer serves: the body plus its receipt group.
                 (setf (aref chain number)
                       (ethereum-lisp.blocks:make-block-from-parts
                        :header (block-header block)
                        :transactions (block-transactions block)
                        :receipts
                        (chain-store-block-receipts producer (block-hash block))
                        :ommers (block-ommers block)))
                 (setf parent block)))
      chain)))

(defun snap-tail-serve-range (chain start-number target-number
                              expected-parent-hash expected-target-hash
                              import-batch)
  "A multi-peer download double serving CHAIN in eight-block batches."
  (is (hash32= expected-target-hash (block-hash (aref chain target-number))))
  (when expected-parent-hash
    (is (hash32= expected-parent-hash
                 (block-hash (aref chain (1- start-number))))))
  (loop for from from start-number to target-number by 8
        for to = (min target-number (+ from 7))
        do (funcall import-batch
                    (loop for number from from to to
                          collect (aref chain number))))
  (1+ (- target-number start-number)))

(defun snap-tail-write-state-import (node database pivot target)
  "Leave what a completed snap state import of PIVOT leaves behind.

Every block up to the pivot is empty, so its state is the genesis state the
node already holds; the durable state-history record and the completed state
progress are what the real importer writes in its last batch."
  (let* ((config (ethereum-lisp.cli::devnet-node-config node))
         (pivot-header (block-header pivot))
         (progress
           (ethereum-lisp.snap-sync::snap-sync-make-progress
            :pivot-hash (block-hash pivot)
            :pivot-number (block-header-number pivot-header)
            :state-root (block-header-state-root pivot-header)
            :partial-root (block-header-state-root pivot-header)
            :target-hash (block-hash target)
            :chain-id (chain-config-chain-id config)
            :genesis-hash
            (block-hash (ethereum-lisp.cli::devnet-node-genesis-block node))
            :authority-id
            (ethereum-lisp.cli::devnet-persistence-state-authority-id
             (ethereum-lisp.cli::devnet-node-persistence-state node))
            :completed-p t)))
    (kv-put-chain-record
     database :state-history
     (hash32-bytes (block-hash pivot))
     (hash32-bytes (block-header-state-root pivot-header)))
    (let ((batch (make-kv-write-batch)))
      (ethereum-lisp.snap-sync::snap-sync-populate-progress-batch
       batch progress)
      (kv-apply-batch database batch))
    progress))

(defun call-with-snap-tail-fixture (name function)
  "Call FUNCTION with a RocksDB node and a 24-block chain whose block 22 reads
BLOCKHASH(12).  The snap pivot is block 20, the consensus target block 23."
  (let* ((genesis-json (snap-tail-genesis-json))
         (chain (snap-tail-produce-chain genesis-json 24 '(22)))
         (datadir (devnet-cli-temp-directory name))
         (database-path
           (ethereum-lisp.cli::devnet-cli-datadir-database-path
            datadir :rocksdb)))
    (unwind-protect
         (ethereum-lisp.cli::call-with-devnet-cli-kv-database-cache
          (lambda ()
            (unwind-protect
                 (let ((node
                         (ethereum-lisp.cli:make-devnet-node
                          :genesis-json genesis-json
                          :database-path database-path :db-engine :rocksdb
                          :port 0 :public-port 0)))
                   (funcall function node chain))
              (devnet-peer-sync-test-drop-cached-rocksdb-handle
               database-path))))
      (uiop:delete-directory-tree datadir
                                  :validate t
                                  :if-does-not-exist :ignore))))

(defun snap-tail-overrides (node chain pivot-number target-number
                            &key downloads logs state-imports)
  "Function overrides that stand in for the network around the real tail.

Target resolution, pivot selection, block download and the state import are
doubles; the skeleton export, the pivot installation and every tail block's
import are the shipped code.  DOWNLOADS, LOGS and STATE-IMPORTS are conses
whose CAR collects the observations."
  (let* ((store (ethereum-lisp.cli::devnet-node-store node))
         (database
           (ethereum-lisp.node-store.persistence:database-engine-payload-store-database
            store))
         (pivot (aref chain pivot-number))
         (target (aref chain target-number))
         (headers (loop for number from pivot-number to target-number
                        collect (block-header (aref chain number)))))
    (list
     (cons 'ethereum-lisp.cli::devnet-node-resolve-snap-target
           (lambda (seen-node target-hash)
             (declare (ignore seen-node))
             (is (hash32= (block-hash target) target-hash))
             (values :target-source (block-header target)
                     (block-header pivot) headers)))
     (cons 'ethereum-lisp.cli::devnet-node-select-snap-pivot
           (lambda (seen-node entry tail-headers)
             (declare (ignore seen-node))
             (values entry (block-header pivot) tail-headers)))
     (cons 'ethereum-lisp.cli::devnet-node-sync-peer-sources
           (lambda (seen-node)
             (declare (ignore seen-node))
             (list :peer-source)))
     (cons 'ethereum-lisp.eth-sync:eth-sync-download-blocks-multi
           (lambda (sources import-block
                    &key start-number target-number expected-parent-hash
                         expected-target-hash import-batch
                    &allow-other-keys)
             (declare (ignore sources import-block))
             (when downloads
               (push (list start-number target-number) (car downloads)))
             (snap-tail-serve-range
              chain start-number target-number
              expected-parent-hash expected-target-hash import-batch)))
     (cons 'ethereum-lisp.cli::devnet-node-snap-import-with-failover
           (lambda (seen-node seen-database pivot-header target-hash
                    &key preferred-entry target-number)
             (declare (ignore seen-node preferred-entry target-number
                              target-hash))
             (is (eq database seen-database))
             (is (hash32= (block-hash pivot) (block-header-hash pivot-header)))
             (when state-imports
               (incf (car state-imports)))
             (snap-tail-write-state-import node database pivot target)))
     (cons 'ethereum-lisp.cli::devnet-peer-manager-log
           (lambda (seen-node name &rest fields)
             (declare (ignore seen-node))
             (when logs
               (push (cons name fields) (car logs))))))))

(defun snap-tail-log-count (logs name)
  (count name (car logs) :key #'car :test #'string=))

(deftest devnet-snap-tail-executes-a-block-that-reads-hashes-below-the-pivot
  (:layer :integration :module :p2p)
  ;; RED control (5fee5219): DEVNET-NODE-SNAP-SYNC-TARGET signals
  ;; STORAGE-ERROR "Snap target tail block <block 22> returned SYNCING
  ;; instead of VALID", the Hoodi exit.  Blocks 20..23 are the skeleton and
  ;; nothing below 20 is known, so BLOCKHASH(12) in block 22 is unavailable.
  (call-with-snap-tail-fixture
   "ethereum-lisp-snap-tail-blockhash"
   (lambda (node chain)
     (let* ((store (ethereum-lisp.cli::devnet-node-store node))
            (target (aref chain 23))
            (downloads (list '()))
            (logs (list '()))
            (result nil))
       ;; The consensus client is ahead of the target, as on Hoodi, and its
       ;; newest block is buffered while the tail runs.
       (is (string= +payload-status-syncing+
                    (restart-behind-new-payload node (aref chain 24))))
       (devnet-peer-sync-call-with-function-overrides
        (snap-tail-overrides node chain 20 23 :downloads downloads :logs logs)
        (lambda ()
          (setf result
                (handler-case
                    (ethereum-lisp.cli::devnet-node-snap-sync-target
                     node (block-hash target))
                  (serious-condition (condition)
                    (error "The snap tail failed: ~A" condition))))))
       (is (eql 3 result))
       ;; Every tail block executed, the BLOCKHASH reader included: its VALID
       ;; verdict matched a post-state root that commits to the hash of 12.
       (dolist (number '(21 22 23))
         (is (chain-store-state-available-p
              store (block-hash (aref chain number)))))
       ;; The skeleton from the pivot, then the ancestors inside the first
       ;; tail block's BLOCKHASH window, linked to the pivot's parent.
       (is (equal '((20 23) (1 19)) (reverse (car downloads))))
       (dolist (number '(1 12 19))
         (is (chain-store-known-block store (block-hash (aref chain number)))))
       (is (= 1 (snap-tail-log-count logs "peer.snap.history_backfilled")))
       (is (= 0 (snap-tail-log-count logs "peer.snap.tail_retry")))
       (is (= 1 (snap-tail-log-count logs "peer.snap.target_completed")))
       ;; A second pass finds the window complete and downloads nothing more.
       (setf (car downloads) '())
       (devnet-peer-sync-call-with-function-overrides
        (snap-tail-overrides node chain 20 23 :downloads downloads :logs logs)
        (lambda ()
          (ethereum-lisp.cli::devnet-node-snap-backfill-blockhash-window
           node (block-header (aref chain 20)))))
       (is (null (car downloads)))))))

(deftest devnet-snap-tail-syncing-block-is-a-phase-outcome-not-a-node-failure
  (:layer :integration :module :p2p)
  ;; The policy half, with the cause left in place: the BLOCKHASH ancestry is
  ;; withheld, so block 22 answers SYNCING on every attempt.  RED control
  ;; (5fee5219): the coordinator pass lets STORAGE-ERROR "Snap target tail
  ;; block ... returned SYNCING instead of VALID" escape to the supervisor,
  ;; which stops the node.  Now the tail retries the block a bounded number
  ;; of times, the pass ends with peer.snap.tail_failed, and the next pass,
  ;; with the ancestry served, resumes at block 22.
  (call-with-snap-tail-fixture
   "ethereum-lisp-snap-tail-policy"
   (lambda (node chain)
     (let* ((store (ethereum-lisp.cli::devnet-node-store node))
            (target-hash (block-hash (aref chain 23)))
            (backfill
              (fdefinition
               'ethereum-lisp.cli::devnet-node-snap-backfill-blockhash-window))
            (withhold-p t)
            (backfills 0)
            (logs (list '()))
            (state-imports (list 0))
            (attempts ethereum-lisp.cli::*devnet-snap-tail-attempts*))
       (devnet-peer-sync-call-with-function-overrides
        (append
         (list
          (cons 'ethereum-lisp.cli::devnet-node-multi-sync-pass
                (lambda (seen-node)
                  (ethereum-lisp.cli::devnet-node-snap-sync-target
                   seen-node target-hash)))
          (cons 'ethereum-lisp.cli::devnet-node-snap-backfill-blockhash-window
                (lambda (seen-node pivot-header)
                  (incf backfills)
                  (if withhold-p
                      0
                      (funcall backfill seen-node pivot-header)))))
         (snap-tail-overrides node chain 20 23
                              :logs logs :state-imports state-imports))
        (lambda ()
          (is (null
               (handler-case
                   (ethereum-lisp.cli::devnet-node-sync-coordinator-pass node)
                 (serious-condition (condition)
                   (error "The coordinator pass let a tail outcome escape: ~A"
                          condition)))))
          (is (= 3 attempts))
          (is (= attempts backfills))
          (is (= (1- attempts)
                 (snap-tail-log-count logs "peer.snap.tail_retry")))
          (is (= 1 (snap-tail-log-count logs "peer.snap.tail_failed")))
          (let ((failed (find "peer.snap.tail_failed" (car logs)
                              :key #'car :test #'string=)))
            (is (equal (list "block" 22) (subseq (cdr failed) 0 2))))
          (is (= 0 (snap-tail-log-count logs "peer.snap.target_completed")))
          ;; Block 21 executed and stays executed; 22 is where the tail waits.
          (is (chain-store-state-available-p
               store (block-hash (aref chain 21))))
          (is (not (chain-store-state-available-p
                    store (block-hash (aref chain 22)))))
          ;; The next pass, with the ancestry served, finishes the tail.
          (setf withhold-p nil)
          (is (eql 3 (ethereum-lisp.cli::devnet-node-sync-coordinator-pass
                      node)))
          (is (= 1 (snap-tail-log-count logs "peer.snap.target_completed")))
          (is (= 1 (snap-tail-log-count logs "peer.snap.tail_failed")))
          (is (chain-store-state-available-p store target-hash))))))))
