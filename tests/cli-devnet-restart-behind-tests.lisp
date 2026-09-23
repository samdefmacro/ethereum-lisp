(in-package #:ethereum-lisp.test)

;;;; A restarted node a few hundred blocks behind its consensus client.
;;;;
;;;; Hoodi d203fee6, 2026-09-23: a node that had completed snap sync and
;;;; followed the head for hours was stopped cleanly for two hours and
;;;; restarted on its datadir, about 680 blocks behind.  Instead of executing
;;;; those blocks forward from its head it re-entered SNAP
;;;; (peer.snap.pivot_rebased fromPivot 3680535, the finished session's old
;;;; pivot, "retainedStateProgress T"), re-healed the state delta, and then
;;;; exited 1 with "Buffered candidate export refuses a known block".
;;;;
;;;; Two defects, one test each:
;;;;
;;;; 1. The scheduler judged the finished snap session by the state of its old
;;;;    target, and the 128-block state retention window had since deleted
;;;;    that state, so the session read as unfinished and pinned SNAP.  It also
;;;;    sent every target more than 64 blocks ahead to SNAP, even from a head
;;;;    with executable state.  geth (38271784, eth/downloader/syncmode.go)
;;;;    re-enters snap only when the head state is missing or the head is
;;;;    below the last pivot.
;;;;
;;;; 2. A peer block that the SNAP skeleton had already made known, arriving
;;;;    again while its parent was still missing, was buffered as an
;;;;    unexecuted remote candidate; the durable exporter refuses that
;;;;    known-and-buffered combination and the refusal killed the node.

(defparameter *restart-behind-retention-depth* 8
  "A short state retention window, so a fixture of a few dozen blocks shows
what the 128-block production window did to the snap target on Hoodi.")

(defun restart-behind-engine-call (node request)
  "Send REQUEST through NODE's shipped Engine RPC context; return its result."
  (let* ((response
           (ethereum-lisp.rpc:rpc-handle-request
            request
            (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
             (ethereum-lisp.cli::devnet-node-service node))))
         (failure (cdr (assoc "error" response :test #'string=))))
    (when failure
      (error "Engine ~A failed: ~S"
             (cdr (assoc "method" request :test #'string=)) failure))
    (cdr (assoc "result" response :test #'string=))))

(defun restart-behind-new-payload (node block)
  "engine_newPayload BLOCK as a consensus client would; return the status."
  (multiple-value-bind (version payload)
      (ethereum-lisp.cli::devnet-peer-block-executable-inputs
       block (ethereum-lisp.cli::devnet-node-config node))
    (unless (<= version 2)
      (error "Restart fixture expects a pre-Cancun payload, got V~D" version))
    (let ((result
            (restart-behind-engine-call
             node
             (list (cons "jsonrpc" "2.0")
                   (cons "id" 7)
                   (cons "method" (format nil "engine_newPayloadV~D" version))
                   (cons "params"
                         (list
                          (ethereum-lisp.engine-api:engine-rpc-executable-data-object
                           payload)))))))
      (cdr (assoc "status" result :test #'string=)))))

(defun restart-behind-forkchoice (node block)
  "engine_forkchoiceUpdated to BLOCK; return the payload status."
  (let ((result
          (restart-behind-engine-call
           node (devnet-engine-priority-fcu-request (block-hash block)))))
    (cdr (assoc "status"
                (cdr (assoc "payloadStatus" result :test #'string=))
                :test #'string=))))

(defun restart-behind-make-node (database-path)
  (let ((node
          (ethereum-lisp.cli:make-devnet-node
           :genesis-json *eth-sync-paris-genesis-json*
           :database-path database-path :db-engine :rocksdb
           :port 0 :public-port 0)))
    (setf (ethereum-lisp.chain-store.state:memory-chain-store-state-retention-depth
           (ethereum-lisp.chain-store.state::chain-store-require-memory-store
            (ethereum-lisp.cli::devnet-node-store node)))
          *restart-behind-retention-depth*)
    node))

(defun restart-behind-follow (node blocks)
  "Deliver BLOCKS one by one as a synced consensus client does."
  (dolist (block blocks)
    (is (string= +payload-status-valid+ (restart-behind-new-payload node block)))
    (is (string= +payload-status-valid+ (restart-behind-forkchoice node block)))))

(defun restart-behind-write-completed-snap-session
    (node pivot target &key (completed-p t))
  "Leave the durable records a snap sync to TARGET leaves behind.

COMPLETED-P false leaves an unfinished session instead."
  (let* ((store (ethereum-lisp.cli::devnet-node-store node))
         (database
           (ethereum-lisp.node-store.persistence:database-engine-payload-store-database
            store))
         (config (ethereum-lisp.cli::devnet-node-config node))
         (genesis-hash
           (block-hash (ethereum-lisp.cli::devnet-node-genesis-block node)))
         (authority-id
           (ethereum-lisp.cli::devnet-persistence-state-authority-id
            (ethereum-lisp.cli::devnet-node-persistence-state node)))
         (pivot-header (block-header pivot))
         (batch (make-kv-write-batch)))
    (ethereum-lisp.snap-sync::snap-sync-populate-progress-batch
     batch
     (ethereum-lisp.snap-sync::snap-sync-make-progress
      :pivot-hash (block-hash pivot)
      :pivot-number (block-header-number pivot-header)
      :state-root (block-header-state-root pivot-header)
      :partial-root (block-header-state-root pivot-header)
      :target-hash (block-hash target)
      :chain-id (chain-config-chain-id config)
      :genesis-hash genesis-hash
      :authority-id authority-id
      :completed-p completed-p))
    (ethereum-lisp.node-store.persistence::node-store-populate-snap-skeleton-progress-batch
     database batch
     (ethereum-lisp.node-store.persistence:make-node-store-snap-skeleton-progress
      :authority-id authority-id
      :chain-id (chain-config-chain-id config)
      :genesis-hash genesis-hash
      :target-number (block-header-number (block-header target))
      :target-hash (block-hash target)
      :anchor-number (1- (block-header-number pivot-header))
      :anchor-hash (block-header-parent-hash pivot-header)
      :pivot-number (block-header-number pivot-header)
      :pivot-hash (block-hash pivot)
      :last-number (block-header-number (block-header target))
      :last-hash (block-hash target)))
    (kv-apply-batch database batch)))

(defun restart-behind-serve-range (chain sources start-number target-number
                                   expected-parent-hash expected-target-hash
                                   import-batch)
  "A multi-peer download double serving CHAIN (a vector indexed by number)."
  (declare (ignore sources))
  (is (hash32= expected-parent-hash
               (block-hash (aref chain (1- start-number)))))
  (is (hash32= expected-target-hash (block-hash (aref chain target-number))))
  (loop for from from start-number to target-number by 64
        for to = (min target-number (+ from 63))
        do (funcall import-batch
                    (loop for number from from to to
                          collect (aref chain number))))
  (1+ (- target-number start-number)))

(deftest devnet-restart-behind-a-finished-snap-sync-forward-syncs-to-the-cl-target
  (:layer :integration :module :p2p)
  ;; RED control (pre-fix): the finished session reads as unfinished once
  ;; retention has deleted its target's state, and the 320-block target is
  ;; beyond the 64-block snap trigger, so the coordinator calls
  ;; DEVNET-NODE-SNAP-SYNC-TARGET instead of downloading forward (the test
  ;; records snapEntries 1 and the target never executes).
  (let* ((datadir (devnet-cli-temp-directory "ethereum-lisp-restart-behind"))
         (database-path
           (ethereum-lisp.cli::devnet-cli-datadir-database-path
            datadir :rocksdb))
         (head-number 24)
         (target-number (+ head-number 320))
         (snap-pivot-number 5)
         (snap-target-number 10)
         (chain nil))
    (unwind-protect
         (ethereum-lisp.cli::call-with-devnet-cli-kv-database-cache
          (lambda ()
            (unwind-protect
                 (let ((node (restart-behind-make-node database-path)))
                   (let ((genesis
                           (ethereum-lisp.cli::devnet-node-genesis-block node)))
                     (setf chain
                           (coerce
                            (cons genesis
                                  (eth-sync-produce-empty-blocks
                                   genesis
                                   (ethereum-lisp.cli::devnet-node-config node)
                                   (1+ target-number)))
                            'vector)))
                   ;; Snap sync finished at the target, which then executed...
                   (restart-behind-follow
                    node (loop for number from 1 to snap-target-number
                               collect (aref chain number)))
                   (restart-behind-write-completed-snap-session
                    node (aref chain snap-pivot-number)
                    (aref chain snap-target-number))
                   ;; ...and the node followed the head well past the window.
                   (restart-behind-follow
                    node (loop for number from (1+ snap-target-number)
                                 to head-number
                               collect (aref chain number)))
                   (let ((store (ethereum-lisp.cli::devnet-node-store node)))
                     (is (= head-number (chain-store-head-number store)))
                     ;; The premise: retention deleted the old target's state.
                     (is (not (chain-store-state-available-p
                               store
                               (block-hash
                                (aref chain snap-target-number)))))))
                 ;; A clean stop.
                 (devnet-peer-sync-test-drop-cached-rocksdb-handle
                  database-path))
            (unwind-protect
                 (let* ((node (restart-behind-make-node database-path))
                        (store (ethereum-lisp.cli::devnet-node-store node))
                        (target (aref chain target-number))
                        (syncing
                          (ethereum-lisp.public-api::admin-backend-syncing
                           (ethereum-lisp.cli::devnet-node-admin-backend
                            (list node))))
                        (snap-entries 0)
                        (gap-fills 0)
                        (downloads '())
                        (passes 0))
                   (is (= head-number (chain-store-head-number store)))
                   ;; The consensus client is synced: it hands over the newest
                   ;; blocks and the head, which the node cannot execute yet.
                   (loop for number from (- target-number 2) to target-number
                         do (is (string= +payload-status-syncing+
                                         (restart-behind-new-payload
                                          node (aref chain number)))))
                   (is (string= +payload-status-syncing+
                                (restart-behind-forkchoice node target)))
                   (is (listp (funcall syncing)))
                   (devnet-peer-sync-call-with-function-overrides
                    (list
                     (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
                           (lambda (seen-node &key snap-only-p)
                             (declare (ignore seen-node snap-only-p))
                             ;; Snap-capable peers are connected, as on Hoodi.
                             (list :snap-peer)))
                     (cons 'ethereum-lisp.cli::devnet-node-sync-peer-sources
                           (lambda (seen-node)
                             (declare (ignore seen-node))
                             (list :peer-source)))
                     (cons 'ethereum-lisp.cli::devnet-node-snap-sync-target
                           (lambda (seen-node seen-target)
                             (declare (ignore seen-node seen-target))
                             (incf snap-entries)
                             :snap))
                     (cons 'ethereum-lisp.cli::devnet-node-fill-sync-gaps-with-live-peer
                           (lambda (seen-node)
                             (declare (ignore seen-node))
                             (incf gap-fills)
                             0))
                     (cons 'ethereum-lisp.eth-sync:eth-sync-download-blocks-multi
                           (lambda (sources import-block
                                    &key start-number target-number
                                         expected-parent-hash
                                         expected-target-hash import-batch
                                    &allow-other-keys)
                             (declare (ignore import-block))
                             (push (list start-number target-number) downloads)
                             (restart-behind-serve-range
                              chain sources start-number target-number
                              expected-parent-hash expected-target-hash
                              import-batch)))
                     (cons 'ethereum-lisp.cli::devnet-peer-manager-log
                           (lambda (&rest arguments)
                             (declare (ignore arguments)))))
                    (lambda ()
                      (loop repeat 3
                            until (chain-store-state-available-p
                                   store (block-hash target))
                            do (incf passes)
                               (ethereum-lisp.cli::devnet-node-multi-sync-pass
                                node))))
                   (unless (zerop snap-entries)
                     (error "Coordinator re-entered SNAP ~D time~:P for a ~D-block ~
gap from a head with state (passes ~D, downloads ~S)"
                            snap-entries (- target-number head-number)
                            passes downloads))
                   (is (= 0 gap-fills))
                   ;; One forward download from the head to the target's parent.
                   (is (equal (list (list (1+ head-number) (1- target-number)))
                              downloads))
                   (is (chain-store-state-available-p store (block-hash target)))
                   ;; The consensus client's next forkchoice publishes it.
                   (is (string= +payload-status-valid+
                                (restart-behind-forkchoice node target)))
                   (is (= target-number (chain-store-head-number store)))
                   (is (eq :false (funcall syncing)))
                   ;; And the node now follows the head again.
                   (let ((next (aref chain (1+ target-number))))
                     (is (string= +payload-status-valid+
                                  (restart-behind-new-payload node next)))
                     (is (string= +payload-status-valid+
                                  (restart-behind-forkchoice node next)))
                     (is (= (1+ target-number)
                            (chain-store-head-number store)))))
              (devnet-peer-sync-test-drop-cached-rocksdb-handle
               database-path))))
      (uiop:delete-directory-tree datadir
                                  :validate t
                                  :if-does-not-exist :ignore))))

(deftest devnet-restart-behind-still-snaps-an-unfinished-session
  (:layer :integration :module :p2p)
  ;; Positive control for the test above: a durable session that has NOT
  ;; completed keeps its recovery path even when the target is near.
  (let* ((datadir (devnet-cli-temp-directory "ethereum-lisp-restart-unfinished"))
         (database-path
           (ethereum-lisp.cli::devnet-cli-datadir-database-path
            datadir :rocksdb)))
    (unwind-protect
         (ethereum-lisp.cli::call-with-devnet-cli-kv-database-cache
          (lambda ()
            (unwind-protect
                 (let* ((node (restart-behind-make-node database-path))
                        (genesis
                          (ethereum-lisp.cli::devnet-node-genesis-block node))
                        (chain
                          (coerce
                           (cons genesis
                                 (eth-sync-produce-empty-blocks
                                  genesis
                                  (ethereum-lisp.cli::devnet-node-config node)
                                  30))
                           'vector))
                        (store (ethereum-lisp.cli::devnet-node-store node))
                        (database
                          (ethereum-lisp.node-store.persistence:database-engine-payload-store-database
                           store)))
                   (restart-behind-follow
                    node (loop for number from 1 to 12
                               collect (aref chain number)))
                   (restart-behind-write-completed-snap-session
                    node (aref chain 20) (aref chain 30) :completed-p nil)
                   (is (= 20 (ethereum-lisp.cli::devnet-node-durable-snap-pivot-number
                              node)))
                   (restart-behind-new-payload node (aref chain 30))
                   (is (ethereum-lisp.cli::devnet-node-snap-target-required-p
                        node (block-hash (aref chain 30)))))
              (devnet-peer-sync-test-drop-cached-rocksdb-handle
               database-path))))
      (uiop:delete-directory-tree datadir
                                  :validate t
                                  :if-does-not-exist :ignore))))

(deftest devnet-forward-sync-bound-sends-a-far-or-fresh-target-to-snap
  (:layer :integration :module :p2p)
  ;; Positive controls for the forward-sync distance: a node at genesis (no
  ;; synced chain yet) and a target beyond the bound both still take SNAP.
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (store (ethereum-lisp.cli::devnet-node-store node))
         (genesis (ethereum-lisp.cli::devnet-node-genesis-block node))
         (blocks
           (eth-sync-produce-empty-blocks
            genesis (ethereum-lisp.cli::devnet-node-config node) 2))
         (bound ethereum-lisp.cli::+devnet-forward-sync-maximum-distance+))
    (flet ((remote-at (number)
             (let ((block
                     (make-block
                      :header
                      (make-block-header
                       :parent-hash
                       (make-hash32 (make-byte-vector 32 :initial-element 9))
                       :number number :gas-limit 30000000 :timestamp number))))
               (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
                store block)
               (block-hash block))))
      ;; Fresh node: 100 blocks ahead of genesis is a snap target.
      (is (ethereum-lisp.cli::devnet-node-snap-target-required-p
           node (remote-at 100)))
      (restart-behind-follow node blocks)
      (is (= 2 (chain-store-head-number store)))
      ;; A synced head: within the bound forward-syncs, beyond it snaps.
      (is (not (ethereum-lisp.cli::devnet-node-snap-target-required-p
                node (remote-at (+ 2 bound)))))
      (is (ethereum-lisp.cli::devnet-node-snap-target-required-p
           node (remote-at (+ 3 bound)))))))

(deftest devnet-peer-block-known-from-the-snap-skeleton-is-not-rebuffered
  (:layer :integration :module :p2p)
  ;; RED control (pre-fix): the second admission of BLOCK signals
  ;; BLOCK-VALIDATION-ERROR "Buffered candidate export refuses a known block"
  ;; out of the durable exporter, which on the coordinator thread is fatal.
  (let* ((datadir (devnet-cli-temp-directory "ethereum-lisp-known-rebuffer"))
         (database-path
           (ethereum-lisp.cli::devnet-cli-datadir-database-path
            datadir :rocksdb)))
    (unwind-protect
         (ethereum-lisp.cli::call-with-devnet-cli-kv-database-cache
          (lambda ()
            (unwind-protect
                 (let* ((node (restart-behind-make-node database-path))
                        (store (ethereum-lisp.cli::devnet-node-store node))
                        (database
                          (ethereum-lisp.node-store.persistence:database-engine-payload-store-database
                           store))
                        (config (ethereum-lisp.cli::devnet-node-config node))
                        (genesis
                          (ethereum-lisp.cli::devnet-node-genesis-block node))
                        (blocks (eth-sync-produce-empty-blocks genesis config 6))
                        (anchor (nth 2 blocks))
                        (pivot (nth 3 blocks))
                        (target (nth 4 blocks)))
                   ;; A peer block arrives before its parent: buffered.
                   (multiple-value-bind (status candidate)
                       (ethereum-lisp.cli::devnet-peer-sync-import-block
                        node pivot :require-valid-p t)
                     (is (string= +payload-status-syncing+
                                  (payload-status-status status)))
                     (is candidate))
                   ;; The snap skeleton then makes it a known block.
                   (ethereum-lisp.node-store.persistence:node-store-export-snap-skeleton-batch-to-kv
                    database (list pivot target)
                    (ethereum-lisp.node-store.persistence:make-node-store-snap-skeleton-progress
                     :authority-id
                     (ethereum-lisp.cli::devnet-persistence-state-authority-id
                      (ethereum-lisp.cli::devnet-node-persistence-state node))
                     :chain-id (chain-config-chain-id config)
                     :genesis-hash (block-hash genesis)
                     :target-number 5 :target-hash (block-hash target)
                     :anchor-number 3 :anchor-hash (block-hash anchor)
                     :pivot-number 4 :pivot-hash (block-hash pivot)
                     :last-number 5 :last-hash (block-hash target)))
                   (is (chain-store-known-block store (block-hash pivot)))
                   ;; The same block again, parent still missing.
                   (multiple-value-bind (status candidate)
                       (handler-case
                           (ethereum-lisp.cli::devnet-peer-sync-import-block
                            node pivot :require-valid-p t)
                         (block-validation-error (condition)
                           (error "Re-admitting a known skeleton block failed: ~A"
                                  condition)))
                     (is (string= +payload-status-syncing+
                                  (payload-status-status status)))
                     (is (null candidate)))
                   ;; Positive control: once the gap closes it executes.
                   (dolist (block (subseq blocks 0 3))
                     (is (string= +payload-status-valid+
                                  (payload-status-status
                                   (ethereum-lisp.cli::devnet-peer-sync-import-block
                                    node block :require-valid-p t)))))
                   (is (string= +payload-status-valid+
                                (payload-status-status
                                 (ethereum-lisp.cli::devnet-peer-sync-import-block
                                  node pivot :require-valid-p t))))
                   (is (chain-store-state-available-p store (block-hash pivot))))
              (devnet-peer-sync-test-drop-cached-rocksdb-handle
               database-path))))
      (uiop:delete-directory-tree datadir
                                  :validate t
                                  :if-does-not-exist :ignore))))
