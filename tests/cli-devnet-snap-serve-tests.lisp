(in-package #:ethereum-lisp.test)

;;;; Peer-session store-guard holds step aside for a waiting Engine request.
;;;;
;;;; Hoodi (b5161312, 2026-09-24): from 00:26Z, once the node had head state
;;;; and advertised snap/1, peer-session holds of 20-134 s kept Engine requests
;;;; waiting (node.store_guard.long_hold, engineWaiting=true). A served snap/1
;;;; request is one guard hold; the forward batch importer already ends its
;;;; hold when an Engine request waits, and a server now does the same between
;;;; items and answers the proved prefix it has.

(defun devnet-snap-serve-ms-since (started-at)
  (round (* 1000 (- (get-internal-real-time) started-at))
         internal-time-units-per-second))

#+sbcl
(defun devnet-snap-serve-yield-run (node root)
  "Serve a full-range GetAccountRange from NODE's snap backend on a thread,
each account slowed by 50 ms and with no time budget, and 0.3 s into it take
NODE's store guard as an Engine request. Returns (VALUES RESPONSE SERVE-MS
ENGINE-MS)."
  (let* ((backend (ethereum-lisp.cli::devnet-peer-snap-backend node))
         (priority
           (ethereum-lisp.rpc::rpc-context-request-guard-function
            (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
             (ethereum-lisp.cli:devnet-node-service node))))
         (request
           (ethereum-lisp.snap:make-snap-get-account-range
            7 root (make-byte-vector 32)
            (make-byte-vector 32 :initial-element #xff) (* 2 1024 1024)))
         (response nil)
         (serve-ms nil)
         (server
           (sb-thread:make-thread
            (lambda ()
              ;; A condition here must not kill the suite process.
              (handler-case
                  (let ((started-at (get-internal-real-time))
                        (ethereum-lisp.snap-sync::*snap-sync-serve-seconds*
                          nil))
                    (setf response
                          (funcall (ethereum-lisp.snap:snap-state-backend-account-range
                                    backend)
                                   request)
                          serve-ms (devnet-snap-serve-ms-since started-at)))
                (serious-condition (condition) (setf response condition))))
            :name "snap-serve-yield-server")))
    (sleep 0.3)
    (let ((started-at (get-internal-real-time)))
      (funcall priority (lambda () :ran))
      (let ((engine-ms (devnet-snap-serve-ms-since started-at)))
        (sb-thread:join-thread server :timeout 60 :default nil)
        (values response serve-ms engine-ms)))))

(deftest devnet-peer-snap-serve-steps-aside-for-a-waiting-engine-request
  (:layer :integration :module :p2p)
  ;; A RocksDB devnet node's real snap backend (the one DEVNET-PEER-SNAP-
  ;; BACKEND gives every peer session) serves a whole-state account range
  ;; with every account slowed by 50 ms; an Engine request arrives 0.3 s in.
  ;; Fixed: the server answers the accounts it has, proved, and the Engine
  ;; request waits for about one account. Control (the priority signal
  ;; ignored, as at 886afd05): the Engine request waits out the whole range.
  #-sbcl (skip-test "store guard waits require SBCL threads")
  #+sbcl
  (let ((dir (namestring
              (devnet-cli-temp-directory "ethereum-lisp-devnet-snap-serve")))
        (slow 'ethereum-lisp.snap-sync::snap-sync-slim-account-body)
        (pending 'ethereum-lisp.cli::devnet-node-store-guard-priority-pending-p))
    (unwind-protect
         (ethereum-lisp.cli::call-with-devnet-cli-kv-database-cache
          (lambda ()
            (let* ((node (ethereum-lisp.cli:make-devnet-node
                          :genesis-json (devnet-np-latency-genesis-json
                                         '(1 2) 40)
                          :database-path dir :db-engine :rocksdb))
                   (root (hash32-bytes
                          (block-header-state-root
                           (block-header
                            (ethereum-lisp.cli:devnet-node-genesis-block
                             node))))))
              (is (ethereum-lisp.cli::devnet-peer-snap-backend node))
              (sb-int:encapsulate slow 'snap-serve-yield
                                  (lambda (function &rest arguments)
                                    (sleep 0.05)
                                    (apply function arguments)))
              (unwind-protect
                   (multiple-value-bind (fixed fixed-serve-ms fixed-engine-ms)
                       (devnet-snap-serve-yield-run node root)
                     (multiple-value-bind (old old-serve-ms old-engine-ms)
                         (progn
                           (sb-int:encapsulate pending 'snap-serve-yield
                                               (lambda (function &rest arguments)
                                                 (declare (ignore function
                                                                  arguments))
                                                 nil))
                           (unwind-protect (devnet-snap-serve-yield-run node root)
                             (sb-int:unencapsulate pending 'snap-serve-yield)))
                       (let ((fixed-accounts
                               (and (typep fixed 'ethereum-lisp.snap:snap-account-range)
                                    (length (ethereum-lisp.snap:snap-account-range-accounts
                                             fixed))))
                             (old-accounts
                               (and (typep old 'ethereum-lisp.snap:snap-account-range)
                                    (length (ethereum-lisp.snap:snap-account-range-accounts
                                             old)))))
                         (format t "~&# snap serve behind an Engine request: fixed ~D accounts, served ~D ms, Engine waited ~D ms; ignoring the signal ~D accounts, served ~D ms, Engine waited ~D ms~%"
                                 fixed-accounts fixed-serve-ms fixed-engine-ms
                                 old-accounts old-serve-ms old-engine-ms)
                         (is (integerp fixed-accounts))
                         (is (integerp old-accounts))
                         (when (and fixed-accounts old-accounts)
                           ;; Fixed: a proved prefix, and the guard at once.
                           (is (<= 1 fixed-accounts))
                           (is (< fixed-accounts old-accounts))
                           (is (< fixed-engine-ms 800))
                           (is (snap-serve-bounds-verifies-p root fixed))
                           ;; Control: every account, and the Engine request
                           ;; waited for them.
                           (is (>= old-accounts 40))
                           (is (>= old-engine-ms 1200))
                           (is (snap-serve-bounds-verifies-p root old))))))
                (sb-int:unencapsulate slow 'snap-serve-yield))
              (let ((database
                      (ethereum-lisp.cli::devnet-cli-cached-kv-database dir)))
                (when database
                  (ethereum-lisp.database:close-rocksdb-key-value-database
                   database))))))
      (uiop:delete-directory-tree
       (uiop:ensure-directory-pathname dir)
       :validate t :if-does-not-exist :ignore))))

(deftest devnet-peer-tx-admission-holds-the-guard-per-chunk
  (:layer :integration :module :p2p)
  ;; Admission recovers every sender under the store guard. A wire batch is
  ;; admitted in chunks, one hold each, so the guard's Engine deferral runs
  ;; between chunks. 150 transactions are three holds; at 886afd05 one.
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0 :public-port 0))
         (backend (ethereum-lisp.cli::devnet-peer-serve-backend node))
         (guard 'ethereum-lisp.cli::call-with-devnet-node-store-guard-as)
         (holds '())
         (transactions
           (loop for nonce below 150
                 collect (make-legacy-transaction
                          :nonce nonce :gas-price 1 :gas-limit 21000
                          :to (address-from-hex
                               "0x0000000000000000000000000000000000000042")
                          :value 0))))
    (sb-int:encapsulate guard 'tx-admission-chunks
                        (lambda (function node label thunk)
                          (push label holds)
                          (funcall function node label thunk)))
    (unwind-protect
         ;; Unsigned transactions: every one is refused, and still admitted
         ;; (and refused) under a hold.
         (is (eql 0 (funcall (ethereum-lisp.eth-sync::eth-serve-backend-accept-transactions
                              backend)
                             transactions)))
      (sb-int:unencapsulate guard 'tx-admission-chunks))
    (is (= 3 (count "tx-admission" holds :test #'equal)))))
