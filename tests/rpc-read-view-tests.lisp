(in-package #:ethereum-lisp.test)

;;;; Public reads answered from the published read view, without the store guard.
;;;;
;;;; On the 8e95b990 Hoodi run a public eth_blockNumber waited 10-30 s behind the
;;;; node's store guard, which block execution, batch import and Engine requests
;;;; hold back to back. These tests hold the guard on another thread, the way a
;;;; long import does, and ask the node's own public RPC context -- the one its
;;;; HTTP and WebSocket listeners serve -- for the reads the view covers.

(defparameter *read-view-test-chain-id* 1337
  "The chain id of *ETH-SYNC-PARIS-GENESIS-JSON*, so fixture senders recover.")

(defun read-view-test-transactions ()
  (loop for nonce from 0 below 2
        collect (fixture-sign-legacy-transaction
                 (make-legacy-transaction
                  :nonce nonce :gas-price 8 :gas-limit 21000
                  :to (make-address (make-byte-vector 20 :initial-element #x55))
                  :value (1+ nonce))
                 1 *read-view-test-chain-id*)))

(defun read-view-test-receipts (transactions)
  (loop for transaction in transactions
        for index from 1
        collect (make-receipt
                 :status 1
                 :cumulative-gas-used (* index 21000)
                 :logs (list (make-log-entry
                              :address (make-address
                                        (make-byte-vector 20 :initial-element #x66))
                              :topics (list (make-hash32
                                             (make-byte-vector
                                              32 :initial-element index)))
                              :data (make-byte-vector 1 :initial-element index))))))

(defun read-view-test-extend (store parent count &key transactions-at)
  "Canonically append COUNT blocks after PARENT; return the new tip.
The block numbered TRANSACTIONS-AT carries two signed transactions and their
receipts, each with one log."
  (loop repeat count
        do (let* ((number (1+ (block-header-number (block-header parent))))
                  (transactions (and (eql number transactions-at)
                                     (read-view-test-transactions)))
                  (block
                    (make-block
                     :header (make-block-header
                              :parent-hash (block-hash parent)
                              :number number
                              :timestamp (1+ (block-header-timestamp
                                              (block-header parent)))
                              :gas-limit 30000000
                              :base-fee-per-gas 7)
                     :transactions transactions
                     :receipts (read-view-test-receipts transactions))))
             (engine-payload-store-put-block
              store block :state-available-p t :canonicalize-p t)
             (setf parent block)))
  parent)

(defun read-view-test-node (&key (blocks 6) (transactions-at 3))
  "A node whose canonical chain is genesis plus BLOCKS blocks, extended under
its own store guard so the release hook publishes the view as it does live."
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0))
         (store (ethereum-lisp.cli:devnet-node-store node)))
    (ethereum-lisp.cli::call-with-devnet-node-store-guard
     node
     (lambda ()
       (read-view-test-extend store (ethereum-lisp.cli:devnet-node-genesis-block node)
                              blocks :transactions-at transactions-at)))
    node))

(defun read-view-test-request (method params)
  (format nil "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"~A\",\"params\":~A}"
          method params))

(defun read-view-test-call (node request &key guarded-p)
  "REQUEST through the node's public RPC context, exactly as its listeners do.
GUARDED-P answers it the pre-view way instead: under the guard, from the live
store, which is the reference every view answer must equal."
  (let ((context (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
                  (ethereum-lisp.cli:devnet-node-public-service node))))
    (when guarded-p
      (setf context (copy-structure context)
            (ethereum-lisp.rpc::rpc-context-read-view-function context) nil))
    (ethereum-lisp.rpc:rpc-handle-request-json request context)))

(defun read-view-test-block-3-requests (node)
  "(REQUEST ...) for reads the view must answer: head, block, header,
receipts, transactions and logs, by number, by hash and by tag."
  (let* ((store (ethereum-lisp.cli:devnet-node-store node))
         (block-3 (chain-store-block-by-number store 3))
         (hash-3 (hash32-to-hex (block-hash block-3)))
         (tx-hashes (mapcar (lambda (transaction)
                              (hash32-to-hex (transaction-hash transaction)))
                            (block-transactions block-3))))
    (list
     (read-view-test-request "eth_blockNumber" "[]")
     (read-view-test-request "eth_chainId" "[]")
     (read-view-test-request "net_version" "[]")
     (read-view-test-request "web3_clientVersion" "[]")
     (read-view-test-request "eth_getBlockByNumber" "[\"latest\",false]")
     (read-view-test-request "eth_getBlockByNumber" "[\"0x3\",true]")
     (read-view-test-request "eth_getBlockByHash"
                             (format nil "[\"~A\",true]" hash-3))
     (read-view-test-request "eth_getHeaderByNumber" "[\"0x2\"]")
     (read-view-test-request "eth_getBlockTransactionCountByHash"
                             (format nil "[\"~A\"]" hash-3))
     (read-view-test-request "eth_getBlockReceipts" "[\"0x3\"]")
     (read-view-test-request "eth_getTransactionReceipt"
                             (format nil "[\"~A\"]" (second tx-hashes)))
     (read-view-test-request "eth_getTransactionByHash"
                             (format nil "[\"~A\"]" (first tx-hashes)))
     (read-view-test-request "eth_getTransactionByBlockNumberAndIndex"
                             "[\"0x3\",\"0x1\"]")
     (read-view-test-request "eth_getLogs"
                             "[{\"fromBlock\":\"0x1\",\"toBlock\":\"latest\"}]"))))

(defun read-view-test-under-held-guard (node requests &key (patience 2)
                                                           after-release)
  "Answer each of REQUESTS on its own thread while another thread holds NODE's
store guard. Returns a list of (REQUEST ANSWER-DURING-HOLD MILLISECONDS), where
ANSWER-DURING-HOLD is :TIMEOUT when the request was still waiting after
PATIENCE seconds. AFTER-RELEASE, when given, is called with the list of the
answers each request finally produced once the guard was released."
  #-sbcl
  (progn node requests patience after-release
         (skip-test "Store-guard contention probe requires SBCL threads"))
  #+sbcl
  (let* ((entered (sb-thread:make-semaphore :count 0))
         (release (sb-thread:make-semaphore :count 0))
         (holder
           (sb-thread:make-thread
            (lambda ()
              (handler-case
                  (ethereum-lisp.cli::call-with-devnet-node-store-guard
                   node
                   (lambda ()
                     (sb-thread:signal-semaphore entered)
                     (sb-thread:wait-on-semaphore release)))
                (serious-condition (condition)
                  (sb-thread:signal-semaphore entered)
                  condition)))
            :name "read-view-test-guard-holder"))
         (workers '())
         (results '()))
    (unwind-protect
         (progn
           (sb-thread:wait-on-semaphore entered)
           (dolist (request requests)
             (let* ((start (get-internal-real-time))
                    (worker
                      (sb-thread:make-thread
                       (lambda ()
                         (handler-case
                             (list :answer (read-view-test-call node request)
                                   (- (get-internal-real-time) start))
                           (serious-condition (condition)
                             (list :error (princ-to-string condition) 0))))
                       :name "read-view-test-request"))
                    (outcome (sb-thread:join-thread
                              worker :timeout patience :default :timeout)))
               (push worker workers)
               (push (if (eq outcome :timeout)
                         (list request :timeout nil)
                         (list request (second outcome)
                               (round (* 1000 (third outcome))
                                      internal-time-units-per-second)))
                     results))))
      (sb-thread:signal-semaphore release)
      (sb-thread:join-thread holder :default nil))
    (let ((final (mapcar (lambda (worker)
                           (second (sb-thread:join-thread
                                    worker :default nil :timeout 30)))
                         (reverse workers))))
      (when after-release
        (funcall after-release final)))
    (nreverse results)))

(deftest public-reads-are-answered-while-the-store-guard-is-held
  ;; RED on f1f079f6: every request below waited for the guard, so each one
  ;; timed out here. The answers must also be the ones the guarded live store
  ;; gives with the guard free: the view is a copy, not a second opinion.
  (let* ((node (read-view-test-node))
         (requests (read-view-test-block-3-requests node))
         (guarded (mapcar (lambda (request)
                            (read-view-test-call node request :guarded-p t))
                          requests))
         (during (read-view-test-under-held-guard node requests)))
    (is (= (length requests) (length during)))
    (loop for (request answer milliseconds) in during
          for expected in guarded
          do (unless (stringp answer)
               (error "~A waited for the guard" request))
             (unless (equal expected answer)
               (error "~A answered ~A from the view, ~A guarded"
                      request answer expected))
             (unless (< milliseconds 1000)
               (error "~A took ~D ms" request milliseconds)))
    ;; The fixture really has content to disagree about.
    (is (search "\"logs\":[{" (nth 10 guarded)))
    (is (search "\"transactions\":[{" (nth 5 guarded)))))

(deftest reads-outside-the-view-still-wait-for-the-guard-and-then-answer
  ;; The control for the test above: the holder really does hold the guard
  ;; (a state read, which the view never serves, times out), and a read the
  ;; view cannot answer completely -- a block above the head, an unknown
  ;; transaction -- is not answered from a
  ;; guess but falls back to the live store once the guard is free.
  (let* ((node (read-view-test-node))
         (requests
           (list (read-view-test-request
                  "eth_getBalance"
                  "[\"0x0000000000000000000000000000000000001001\",\"latest\"]")
                 (read-view-test-request "eth_getBlockByNumber" "[\"0x7\",false]")
                 (read-view-test-request
                  "eth_getTransactionReceipt"
                  (format nil "[\"0x~A\"]" (make-string 64 :initial-element #\a)))))
         (final nil)
         (during (read-view-test-under-held-guard
                  node requests
                  :patience 0.3
                  :after-release (lambda (answers) (setf final answers)))))
    (loop for (request answer) in during
          do (unless (eq :timeout answer)
               (error "~A did not wait for the guard: ~A" request answer)))
    (is (search "\"result\":\"0x" (first final)))
    (is (search "\"result\":null" (second final)))
    (is (search "\"result\":null" (third final)))))

(deftest the-read-view-shows-committed-holds-only
  ;; A hold that has extended the chain but not yet released must stay
  ;; invisible (it may still roll back), and the next release must publish it.
  #-sbcl (skip-test "Store-guard contention probe requires SBCL threads")
  #+sbcl
  (let* ((node (read-view-test-node))
         (store (ethereum-lisp.cli:devnet-node-store node))
         (request (read-view-test-request "eth_blockNumber" "[]"))
         (entered (sb-thread:make-semaphore :count 0))
         (release (sb-thread:make-semaphore :count 0))
         (holder
           (sb-thread:make-thread
            (lambda ()
              (handler-case
                  (ethereum-lisp.cli::call-with-devnet-node-store-guard
                   node
                   (lambda ()
                     (read-view-test-extend
                      store (chain-store-latest-block store) 1)
                     (sb-thread:signal-semaphore entered)
                     (sb-thread:wait-on-semaphore release)))
                (serious-condition (condition)
                  (sb-thread:signal-semaphore entered)
                  condition)))))
         (during nil))
    (unwind-protect
         (progn
           (sb-thread:wait-on-semaphore entered)
           (setf during (read-view-test-call node request)))
      (sb-thread:signal-semaphore release)
      (sb-thread:join-thread holder :default nil))
    (is (search "\"result\":\"0x6\"" during))
    (is (search "\"result\":\"0x7\"" (read-view-test-call node request)))))

(deftest read-view-publication-reuses-the-window-and-matches-the-live-index
  ;; Every published entry must be the live canonical block at its number,
  ;; whether the head moved by one block, by several in one hold, or not at
  ;; all (then the previous view itself is returned), and the window is capped.
  (let* ((node (read-view-test-node :blocks 2 :transactions-at nil))
         (store (ethereum-lisp.cli:devnet-node-store node))
         (views '()))
    (flet ((publish ()
             (let ((view (ethereum-lisp.node-store:node-store-publish-read-view
                          store (first views) :window 4)))
               (push view views)
               view))
           (entries-match-live-p (view)
             (let ((entries (ethereum-lisp.node-store::node-store-read-view-entries
                             view)))
               (and (plusp (length entries))
                    (loop for entry across entries
                          for number downfrom (ethereum-lisp.node-store:node-store-read-view-head-number view)
                          always (and (= number
                                         (ethereum-lisp.node-store::node-store-read-view-entry-number
                                          entry))
                                      (hash32= (chain-store-canonical-hash store number)
                                               (ethereum-lisp.node-store::node-store-read-view-entry-hash
                                                entry))))))))
      (let ((first-view (publish)))
        (is (= 2 (ethereum-lisp.node-store:node-store-read-view-head-number first-view)))
        (is (= 3 (length (ethereum-lisp.node-store::node-store-read-view-entries
                          first-view))))
        (is (entries-match-live-p first-view))
        (is (eq first-view (publish)))
        (read-view-test-extend store (chain-store-latest-block store) 1)
        (let ((second-view (publish)))
          (is (= 3 (ethereum-lisp.node-store:node-store-read-view-head-number second-view)))
          (is (= 4 (length (ethereum-lisp.node-store::node-store-read-view-entries
                            second-view))))
          (is (entries-match-live-p second-view))
          ;; The shared ancestry is the old entries themselves, not copies.
          (is (eq (svref (ethereum-lisp.node-store::node-store-read-view-entries
                          first-view) 0)
                  (svref (ethereum-lisp.node-store::node-store-read-view-entries
                          second-view) 1))))
        (read-view-test-extend store (chain-store-latest-block store) 5)
        (let ((third-view (publish)))
          (is (= 8 (ethereum-lisp.node-store:node-store-read-view-head-number third-view)))
          (is (= 4 (length (ethereum-lisp.node-store::node-store-read-view-entries
                            third-view))))
          (is (entries-match-live-p third-view)))))))
