(in-package #:ethereum-lisp.test)

;;;; Transaction gossip: the four message codecs, the rules about what we will
;;;; and will not pass on, and a full announce-fetch-accept exchange between two
;;;; peers over a real RLPx session.
;;;;
;;;; The pool here is a hash table behind the backend closures, so these tests
;;;; state gossip behavior directly — including a pool that rejects. That a
;;;; gossiped transaction reaches the node's real transaction pool is a separate
;;;; test, in cli-devnet-node-tests.lisp.

(defun eth-gossip-test-transaction (nonce &key (gas-price 2))
  (make-legacy-transaction :nonce nonce :gas-price gas-price :gas-limit 21000
                           :value 3 :data #(1) :v 27 :r 4 :s 5))

(defun eth-gossip-test-typed-transaction (nonce)
  (make-dynamic-fee-transaction :chain-id 1 :nonce nonce :max-fee-per-gas 10
                                :max-priority-fee-per-gas 1 :gas-limit 21000
                                :value 4 :y-parity 1 :r 6 :s 7))

(defun eth-gossip-test-blob-transaction (nonce)
  (make-blob-transaction
   :chain-id 1 :nonce nonce :max-fee-per-gas 10 :max-priority-fee-per-gas 1
   :gas-limit 21000 :max-fee-per-blob-gas 1
   ;; A blob transaction must have a recipient; it cannot create a contract.
   :to (address-from-hex "0x0000000000000000000000000000000000003001")
   :blob-versioned-hashes
   (list (hex-to-bytes
          "0x0100000000000000000000000000000000000000000000000000000000000001"))
   :y-parity 0 :r 8 :s 9))

(defun eth-gossip-transaction-hash-bytes (transaction)
  (hash32-bytes (transaction-hash transaction)))

(defun eth-gossip-test-backend (&key (transactions '()) reject-p)
  "A backend over a hash-table pool. Returns (VALUES BACKEND POOL); REJECT-P, if
given, is a predicate marking transactions the pool turns down."
  (let ((pool (make-hash-table :test #'equalp)))
    (dolist (transaction transactions)
      (setf (gethash (eth-gossip-transaction-hash-bytes transaction) pool)
            transaction))
    (values
     (make-eth-serve-backend
      :pooled-transaction (lambda (hash) (gethash hash pool))
      :known-transaction-p (lambda (hash) (nth-value 1 (gethash hash pool)))
      :accept-transaction
      (lambda (transaction)
        (when (and reject-p (funcall reject-p transaction))
          (error "test pool rejected the transaction"))
        (setf (gethash (eth-gossip-transaction-hash-bytes transaction) pool)
              transaction)))
     pool)))

(defun eth-gossip-test-peer (backend)
  "A peer with no connection, for exercising the parts that only touch state."
  (ethereum-lisp.eth-sync::%make-eth-peer :serve-backend backend))

;;; Codecs.

(deftest eth-transactions-message-round-trips
  (:layer :unit :module :p2p)
  (let* ((transactions (list (eth-gossip-test-transaction 1)
                             (eth-gossip-test-typed-transaction 2)))
         (decoded (ethereum-lisp.eth-wire:decode-eth-transactions
                   (ethereum-lisp.eth-wire:encode-eth-transactions transactions))))
    (is (= 2 (length decoded)))
    ;; Both encodings survive: the legacy one rides as a list, the typed one as
    ;; an opaque string, and each comes back byte-identical.
    (loop for sent in transactions
          for got in decoded
          do (is (bytes= (transaction-encoding sent)
                         (transaction-encoding got))))))

(deftest eth-new-pooled-transaction-hashes-round-trips
  (:layer :unit :module :p2p)
  (let ((transactions (list (eth-gossip-test-transaction 1)
                            (eth-gossip-test-typed-transaction 2))))
    (multiple-value-bind (types sizes hashes)
        (ethereum-lisp.eth-wire:decode-eth-new-pooled-transaction-hashes
         (ethereum-lisp.eth-wire:encode-eth-new-pooled-transaction-hashes
          transactions))
      ;; Three columns of equal length, aligned by position.
      (is (equal '(0 2) types))
      (is (equal (mapcar (lambda (transaction)
                           (length (transaction-encoding transaction)))
                         transactions)
                 sizes))
      (loop for transaction in transactions
            for hash in hashes
            do (is (bytes= (eth-gossip-transaction-hash-bytes transaction) hash))))
    ;; An announcement with no transactions still encodes and decodes.
    (multiple-value-bind (types sizes hashes)
        (ethereum-lisp.eth-wire:decode-eth-new-pooled-transaction-hashes
         (ethereum-lisp.eth-wire:encode-eth-new-pooled-transaction-hashes '()))
      (is (null types))
      (is (null sizes))
      (is (null hashes)))))

(deftest eth-new-pooled-transaction-hashes-rejects-ragged-columns
  (:layer :unit :module :p2p)
  ;; A peer whose columns disagree is malformed. Pairing them up anyway would
  ;; silently attach one transaction's size to another's hash.
  (signals error
    (ethereum-lisp.eth-wire:decode-eth-new-pooled-transaction-hashes
     (rlp-encode
      (make-rlp-list
       (ensure-byte-vector #(0 2))
       (make-rlp-list (integer-to-minimal-bytes 100))
       (make-rlp-list
        (hex-to-bytes
         "0x1111111111111111111111111111111111111111111111111111111111111111")
        (hex-to-bytes
         "0x2222222222222222222222222222222222222222222222222222222222222222")))))))

(deftest eth-pooled-transaction-messages-round-trip
  (:layer :unit :module :p2p)
  (let ((hashes (list (eth-gossip-transaction-hash-bytes
                       (eth-gossip-test-transaction 1))
                      (eth-gossip-transaction-hash-bytes
                       (eth-gossip-test-transaction 2)))))
    (multiple-value-bind (request-id decoded)
        (ethereum-lisp.eth-wire:decode-eth-get-pooled-transactions
         (ethereum-lisp.eth-wire:encode-eth-get-pooled-transactions 9 hashes))
      (is (= 9 request-id))
      (is (= 2 (length decoded)))
      (is (bytes= (first hashes) (first decoded)))))
  (let ((transactions (list (eth-gossip-test-transaction 1)
                            (eth-gossip-test-typed-transaction 2))))
    (multiple-value-bind (request-id decoded)
        (ethereum-lisp.eth-wire:decode-eth-pooled-transactions
         (ethereum-lisp.eth-wire:encode-eth-pooled-transactions 11 transactions))
      (is (= 11 request-id))
      (is (= 2 (length decoded)))
      (is (bytes= (transaction-encoding (second transactions))
                  (transaction-encoding (second decoded)))))))

;;; What we will and will not pass on.

(deftest eth-gossip-excludes-blob-transactions
  (:layer :unit :module :p2p)
  ;; We neither announce nor serve blob transactions, because their pooled form
  ;; carries a sidecar we do not produce. Promising one we cannot deliver is
  ;; worse than staying quiet about it.
  (let ((plain (eth-gossip-test-transaction 1))
        (blob (eth-gossip-test-blob-transaction 2)))
    (is (eth-gossipable-transaction-p plain))
    (is (not (eth-gossipable-transaction-p blob)))
    (multiple-value-bind (backend pool)
        (eth-gossip-test-backend :transactions (list plain blob))
      (declare (ignore pool))
      ;; Asked for both by hash, only the plain one is served.
      (let ((served (eth-serve-pooled-transactions
                     backend
                     (list (eth-gossip-transaction-hash-bytes blob)
                           (eth-gossip-transaction-hash-bytes plain)))))
        (is (= 1 (length served)))
        (is (bytes= (transaction-encoding plain)
                    (transaction-encoding (first served))))))))

(deftest eth-gossip-serves-and-verifies-versioned-blob-wrapper
  (:layer :unit :module :p2p)
  (let* ((blob (make-byte-vector +blob-byte-size+))
         (commitment (make-byte-vector +kzg-commitment-size+))
         (proofs
           (loop repeat +cell-proofs-per-blob+
                 collect (make-byte-vector +kzg-proof-size+)))
         (transaction
           (make-blob-transaction
            :chain-id 1
            :to (address-from-hex
                 "0x0000000000000000000000000000000000003001")
            :blob-versioned-hashes
            (list (kzg-commitment-to-versioned-hash commitment))))
         (sidecar
           (make-blob-sidecar :blobs (list blob)
                              :commitments (list commitment)
                              :proofs proofs))
         (stored-sidecar nil)
         (accepted nil)
         (server
           (make-eth-serve-backend
            :pooled-transaction (lambda (hash)
                                  (declare (ignore hash))
                                  transaction)
            :pooled-blob-sidecar (lambda (value)
                                   (declare (ignore value))
                                   sidecar)))
         (client
           (make-eth-serve-backend
            :accept-blob-sidecar
            (lambda (value) (setf stored-sidecar value))
            :accept-transaction
            (lambda (value) (setf accepted value)))))
    (let ((served
            (eth-serve-pooled-transactions
             server (list (eth-gossip-transaction-hash-bytes transaction)))))
      (is (= 1 (length served)))
      (is (typep (first served) 'blob-network-transaction))
      (let ((*kzg-cell-proof-verifier*
              (lambda (verified-blob verified-commitment verified-proofs)
                (and (bytes= blob verified-blob)
                     (bytes= commitment verified-commitment)
                     (= +cell-proofs-per-blob+
                        (length verified-proofs))))))
        (is (= 1 (eth-accept-transactions client served)))))
    (is stored-sidecar)
    (is (eq transaction accepted))))

(deftest eth-gossip-serves-only-the-pooled-transactions-it-has
  (:layer :unit :module :p2p)
  (let* ((held (eth-gossip-test-transaction 1))
         (missing (eth-gossip-test-transaction 2)))
    (multiple-value-bind (backend pool) (eth-gossip-test-backend
                                         :transactions (list held))
      (declare (ignore pool))
      (let ((served (eth-serve-pooled-transactions
                     backend
                     (list (eth-gossip-transaction-hash-bytes missing)
                           (eth-gossip-transaction-hash-bytes held)
                           ;; A malformed hash is skipped, not an error.
                           (ensure-byte-vector #(1 2 3))))))
        (is (= 1 (length served)))
        (is (bytes= (transaction-encoding held)
                    (transaction-encoding (first served))))))))

(deftest eth-gossip-accepts-what-the-pool-takes-and-skips-what-it-rejects
  (:layer :unit :module :p2p)
  ;; Peers relay without pre-filtering for us, so one transaction the pool turns
  ;; down must not cost us the connection or the rest of the batch.
  (let ((good (eth-gossip-test-transaction 1))
        (bad (eth-gossip-test-transaction 2))
        (also-good (eth-gossip-test-transaction 3)))
    (multiple-value-bind (backend pool)
        (eth-gossip-test-backend
         :reject-p (lambda (transaction) (= (transaction-nonce transaction) 2)))
      (is (= 2 (eth-accept-transactions backend (list good bad also-good))))
      (is (= 2 (hash-table-count pool)))
      (is (null (gethash (eth-gossip-transaction-hash-bytes bad) pool))))))

(deftest eth-gossip-queues-only-announced-hashes-worth-fetching
  (:layer :unit :module :p2p)
  (let* ((held (eth-gossip-test-transaction 1))
         (wanted (eth-gossip-test-transaction 2)))
    (multiple-value-bind (backend pool) (eth-gossip-test-backend
                                         :transactions (list held))
      (declare (ignore pool))
      (let ((peer (eth-gossip-test-peer backend))
            (held-hash (eth-gossip-transaction-hash-bytes held))
            (wanted-hash (eth-gossip-transaction-hash-bytes wanted)))
        ;; One already in the pool, one new, one announced twice, one malformed.
        (is (= 1 (eth-peer-queue-announced-hashes
                  peer backend
                  (list held-hash wanted-hash wanted-hash
                        (ensure-byte-vector #(1 2 3))))))
        (is (= 1 (eth-peer-announced-hash-count peer)))
        ;; Re-announcing what is already queued adds nothing.
        (is (= 0 (eth-peer-queue-announced-hashes peer backend
                                                  (list wanted-hash))))
        ;; Taking them empties the queue, so a peer that never answers does not
        ;; leave us asking for the same hashes forever.
        (let ((taken (eth-peer-take-announced-hashes peer 10)))
          (is (= 1 (length taken)))
          (is (bytes= wanted-hash (first taken))))
        (is (= 0 (eth-peer-announced-hash-count peer)))))))

(deftest eth-gossip-bounds-the-announced-hash-queue
  (:layer :unit :module :p2p)
  ;; A peer announcing faster than we fetch must not grow our memory without
  ;; bound; past the limit the excess is dropped.
  (multiple-value-bind (backend pool) (eth-gossip-test-backend)
    (declare (ignore pool))
    (let* ((peer (eth-gossip-test-peer backend))
           (over (+ +eth-max-announced-transaction-hashes+ 50))
           (hashes (loop for n from 1 to over
                         collect (eth-gossip-transaction-hash-bytes
                                  (eth-gossip-test-transaction n)))))
      (is (= +eth-max-announced-transaction-hashes+
             (eth-peer-queue-announced-hashes peer backend hashes)))
      (is (= +eth-max-announced-transaction-hashes+
             (eth-peer-announced-hash-count peer)))
      (is (= 25 (length (eth-peer-take-announced-hashes peer 25)))))))

;;; A full exchange over a real session.

(deftest eth-gossip-announce-fetch-and-accept-over-a-socket
  (:layer :integration :module :p2p :requires-local-sockets t)
  ;; The whole path: the server announces a transaction by hash, the client
  ;; queues it, asks for it, and puts it in its pool — every message handled by
  ;; the gossip layer on both sides.
  (let* ((config (eth-sync-test-config))
         (server-static
          #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (client-static
          #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (server-static-pub (secp256k1-private-key-public-key server-static))
         (offered (eth-gossip-test-transaction 7))
         (blob (eth-gossip-test-blob-transaction 8))
         (listener (make-instance 'sb-bsd-sockets:inet-socket
                                  :type :stream :protocol :tcp)))
    (multiple-value-bind (server-backend server-pool)
        (eth-gossip-test-backend :transactions (list offered blob))
      (declare (ignore server-pool))
      (multiple-value-bind (client-backend client-pool) (eth-gossip-test-backend)
        (flet ((hello (client-id)
                 (make-devp2p-hello
                  :client-id client-id
                  :capabilities (list (make-devp2p-capability "eth" 68))
                  :node-id server-static-pub))
               (status ()
                 (eth-build-status config *eth-sync-test-genesis* 0 0
                                   *eth-sync-test-genesis* 0)))
          (setf (sb-bsd-sockets:sockopt-reuse-address listener) t)
          (unwind-protect
               (progn
                 (sb-bsd-sockets:socket-bind
                  listener (sb-bsd-sockets:make-inet-address "127.0.0.1") 0)
                 (sb-bsd-sockets:socket-listen listener 1)
                 (multiple-value-bind (address port)
                     (sb-bsd-sockets:socket-name listener)
                   (declare (ignore address))
                   (let ((server-error nil)
                         (announced nil))
                     (let ((server-thread
                             (sb-thread:make-thread
                              (lambda ()
                                (handler-case
                                    (let* ((cs (sb-bsd-sockets:socket-accept
                                                listener))
                                           (stream (p2p-binary-socket-stream cs))
                                           (connection (rlpx-accept-stream
                                                        stream server-static))
                                           (peer (eth-peer-connect
                                                  connection (hello "srv")
                                                  (status)
                                                  :serve-backend server-backend)))
                                      ;; Announce both; only the plain one is
                                      ;; advertised, so only it can be asked for.
                                      (setf announced
                                            (eth-peer-announce-transactions
                                             peer (list offered blob)))
                                      ;; Answer the client's request for it.
                                      (eth-peer-serve-loop peer :max-messages 1))
                                  (error (condition)
                                    (setf server-error condition))))
                              :name "eth-gossip-test-server")))
                       (let ((client-socket
                               (make-instance 'sb-bsd-sockets:inet-socket
                                              :type :stream :protocol :tcp)))
                         (sb-bsd-sockets:socket-connect
                          client-socket
                          (sb-bsd-sockets:make-inet-address "127.0.0.1") port)
                         (let* ((stream (p2p-binary-socket-stream client-socket))
                                (connection (rlpx-connect-stream
                                             stream client-static
                                             server-static-pub))
                                (peer (eth-peer-connect
                                       connection (hello "cli") (status)
                                       :serve-backend client-backend)))
                           ;; Read the announcement, which only queues hashes.
                           (eth-peer-serve-loop peer :max-messages 1)
                           (is (= 1 (eth-peer-announced-hash-count peer)))
                           (is (zerop (hash-table-count client-pool)))
                           ;; Then ask for what was announced and pool it.
                           (is (= 1 (eth-peer-fetch-announced-transactions peer)))
                           (is (= 0 (eth-peer-announced-hash-count peer)))
                           (is (= 1 (hash-table-count client-pool)))
                           (let ((received (gethash
                                            (eth-gossip-transaction-hash-bytes
                                             offered)
                                            client-pool)))
                             (is (not (null received)))
                             (is (bytes= (transaction-encoding offered)
                                         (transaction-encoding received))))))
                       (sb-thread:join-thread server-thread)
                       (when server-error
                         (error "eth gossip server side failed: ~A" server-error))
                       ;; The blob transaction was never advertised.
                       (is (= 1 announced))))))
            (ignore-errors (sb-bsd-sockets:socket-close listener))))))))
