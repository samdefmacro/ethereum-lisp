(in-package #:ethereum-lisp.test)

;;;; Serving eth requests: resolving header, body, and receipt queries against a
;;;; chain, and answering a real peer's requests over a loopback RLPx session.
;;;;
;;;; The query tests run against a synthetic backend rather than a chain store,
;;;; which is what lets them state awkward shapes directly — a side chain the
;;;; canonical index does not reach, a block held without its receipts.

(defun eth-serve-test-block (number parent-hash &key (marker 0)
                                                     transactions receipts)
  "A structurally valid block at NUMBER under PARENT-HASH. MARKER goes in the
extra data, so two blocks at one number hash differently."
  (ethereum-lisp.blocks:make-block-from-parts
   :header (make-block-header :number number
                              :parent-hash parent-hash
                              :difficulty 0
                              :gas-limit 30000000
                              :gas-used 0
                              :timestamp (+ 1600000000 number)
                              :extra-data (vector marker))
   :transactions transactions
   :receipts receipts))

(defun eth-serve-test-chain (length &key (marker 0))
  "A chain of LENGTH blocks numbered 0..LENGTH-1, each the parent of the next."
  (let ((blocks '())
        (parent (zero-hash32)))
    (dotimes (number length (nreverse blocks))
      (let ((block (eth-serve-test-block number parent :marker marker)))
        (push block blocks)
        (setf parent (block-hash block))))))

(defun eth-serve-test-backend (blocks &key (canonical blocks))
  "A serve backend holding every block in BLOCKS, of which CANONICAL are the
ones reachable by number."
  (let ((by-hash (make-hash-table :test #'equalp))
        (by-number (make-hash-table)))
    (dolist (block blocks)
      (setf (gethash (hash32-bytes (block-hash block)) by-hash) block))
    (dolist (block canonical)
      (setf (gethash (block-header-number (block-header block)) by-number) block))
    (make-eth-serve-backend
     :block-by-number (lambda (number) (gethash number by-number))
     :block-by-hash (lambda (hash) (gethash hash by-hash)))))

(defun eth-serve-test-headers (backend &rest request-arguments)
  "Resolve a GetBlockHeaders query and return the resulting block numbers."
  (mapcar #'block-header-number
          (eth-serve-headers
           backend
           (apply #'ethereum-lisp.eth-wire:make-eth-get-block-headers
                  :request-id 1 request-arguments))))

(deftest eth-serve-resolves-number-mode-header-queries
  (:layer :unit :module :p2p)
  (let ((backend (eth-serve-test-backend (eth-serve-test-chain 20))))
    ;; Forward from a number, the shape the download driver asks for.
    (is (equal '(1 2 3) (eth-serve-test-headers backend :origin-number 1 :amount 3)))
    ;; Backward, and with a skip in each direction.
    (is (equal '(5 4 3)
               (eth-serve-test-headers backend :origin-number 5 :amount 3
                                               :reverse t)))
    (is (equal '(0 3 6)
               (eth-serve-test-headers backend :origin-number 0 :amount 3 :skip 2)))
    (is (equal '(9 6 3)
               (eth-serve-test-headers backend :origin-number 9 :amount 3 :skip 2
                                               :reverse t)))
    ;; A walk that runs off either end stops rather than wrapping or erroring.
    (is (equal '(18 19)
               (eth-serve-test-headers backend :origin-number 18 :amount 5)))
    (is (equal '(1 0)
               (eth-serve-test-headers backend :origin-number 1 :amount 5
                                               :reverse t)))
    (is (equal '(2 0)
               (eth-serve-test-headers backend :origin-number 2 :amount 5 :skip 1
                                               :reverse t)))
    ;; An origin we do not have is answered with an empty list, not an error.
    (is (null (eth-serve-test-headers backend :origin-number 999 :amount 3)))))

(deftest eth-serve-resolves-hash-mode-header-queries
  (:layer :unit :module :p2p)
  (let* ((chain (eth-serve-test-chain 20))
         (backend (eth-serve-test-backend chain))
         (hash-at (lambda (number)
                    (hash32-bytes (block-hash (nth number chain))))))
    ;; A hash origin anchors the first header; the walk continues by number.
    (is (equal '(5 6 7)
               (eth-serve-test-headers backend :origin-hash (funcall hash-at 5)
                                               :amount 3)))
    ;; Backwards from a hash follows parent links.
    (is (equal '(5 4 3)
               (eth-serve-test-headers backend :origin-hash (funcall hash-at 5)
                                               :amount 3 :reverse t)))
    (is (equal '(9 6 3)
               (eth-serve-test-headers backend :origin-hash (funcall hash-at 9)
                                               :amount 3 :skip 2 :reverse t)))
    (is (equal '(5 8 11)
               (eth-serve-test-headers backend :origin-hash (funcall hash-at 5)
                                               :amount 3 :skip 2)))
    ;; The parent walk stops at genesis instead of running past it.
    (is (equal '(1 0)
               (eth-serve-test-headers backend :origin-hash (funcall hash-at 1)
                                               :amount 5 :reverse t)))
    ;; An unknown hash yields nothing.
    (is (null (eth-serve-test-headers
               backend
               :origin-hash (hex-to-bytes
                             "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
               :amount 3)))))

(deftest eth-serve-hash-mode-does-not-walk-onto-the-canonical-chain
  (:layer :unit :module :p2p)
  ;; A forward hash-mode query anchored to a side-chain block must stop rather
  ;; than continue with canonical blocks, which do not descend from it. Serving
  ;; those would answer a question about one branch with headers from another.
  (let* ((chain (eth-serve-test-chain 10))
         (side (eth-serve-test-block 5 (block-hash (nth 4 chain)) :marker 7))
         (backend (eth-serve-test-backend (cons side chain) :canonical chain))
         (side-hash (hash32-bytes (block-hash side))))
    (is (not (bytes= side-hash (hash32-bytes (block-hash (nth 5 chain))))))
    ;; Only the side block itself comes back.
    (is (equal '(5) (eth-serve-test-headers backend :origin-hash side-hash
                                                    :amount 3)))
    ;; Backwards it walks its own parents, which are shared with the canonical
    ;; chain below the fork, so that direction does return a run.
    (is (equal '(5 4 3) (eth-serve-test-headers backend :origin-hash side-hash
                                                        :amount 3 :reverse t)))))

(deftest eth-serve-caps-header-queries-at-the-serve-limit
  (:layer :unit :module :p2p)
  (let* ((chain (eth-serve-test-chain 30))
         (backend (eth-serve-test-backend chain)))
    ;; The amount is honored below the cap and clamped above it.
    (is (= 30 (length (eth-serve-test-headers backend :origin-number 0
                                                      :amount 100))))
    (is (> +eth-max-headers-serve+ 30))
    (let ((request (ethereum-lisp.eth-wire:make-eth-get-block-headers
                    :request-id 1 :origin-number 0
                    :amount (* 10 +eth-max-headers-serve+))))
      (is (= 30 (length (eth-serve-headers backend request)))))))

(deftest eth-serve-returns-bodies-for-the-blocks-it-holds
  (:layer :unit :module :p2p)
  (let* ((transaction (make-legacy-transaction :nonce 1 :gas-price 2
                                               :gas-limit 21000 :value 3
                                               :data #(1) :v 27 :r 4 :s 5))
         (with-transaction (eth-serve-test-block 1 (zero-hash32)
                                                 :transactions (list transaction)))
         (empty (eth-serve-test-block 2 (block-hash with-transaction)))
         (backend (eth-serve-test-backend (list with-transaction empty)))
         (unknown (hex-to-bytes
                   "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"))
         (bodies (eth-serve-bodies
                  backend
                  (list (hash32-bytes (block-hash with-transaction))
                        unknown
                        (hash32-bytes (block-hash empty))))))
    ;; The unknown hash is left out; the reply is what we found, in order.
    (is (= 2 (length bodies)))
    (is (= 1 (length (ethereum-lisp.eth-wire:eth-block-body-transactions
                      (first bodies)))))
    (is (null (ethereum-lisp.eth-wire:eth-block-body-transactions
               (second bodies))))
    (is (bytes= (transaction-encoding transaction)
                (transaction-encoding
                 (first (ethereum-lisp.eth-wire:eth-block-body-transactions
                         (first bodies))))))))

(deftest eth-serve-skips-blocks-whose-receipts-are-missing
  (:layer :unit :module :p2p)
  ;; A block held without its receipts — a header and body accepted but never
  ;; executed — is skipped. Answering with a short receipt list would read as a
  ;; block with fewer transactions.
  (let* ((transaction (make-legacy-transaction :nonce 1 :gas-price 2
                                               :gas-limit 21000 :value 3
                                               :data #(1) :v 27 :r 4 :s 5))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (executed (eth-serve-test-block 1 (zero-hash32)
                                         :transactions (list transaction)
                                         :receipts (list receipt)))
         (unexecuted (eth-serve-test-block 2 (block-hash executed)
                                           :transactions (list transaction)))
         (backend (eth-serve-test-backend (list executed unexecuted)))
         (blocks (eth-serve-receipt-blocks
                  backend
                  (list (hash32-bytes (block-hash executed))
                        (hash32-bytes (block-hash unexecuted)))
                  68)))
    (is (= 1 (length blocks)))
    (is (= 1 (block-header-number (block-header (first blocks)))))))

;;; Serving over a real connection.

(defun eth-serve-test-status (config head-number best-hash)
  (eth-build-status config *eth-sync-test-genesis* head-number 0 best-hash 0))

(deftest eth-serve-answers-a-peer-over-a-socket
  (:layer :integration :module :p2p :requires-local-sockets t)
  ;; The whole responder path end to end: a real RLPx session in which the
  ;; server installs a serve backend and never hand-writes a reply, and the
  ;; client's ordinary download helpers get correct answers back.
  (let* ((config (eth-sync-test-config))
         (server-static
          #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (client-static
          #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (server-static-pub (secp256k1-private-key-public-key server-static))
         (transaction (make-legacy-transaction :nonce 1 :gas-price 2
                                               :gas-limit 21000 :value 3
                                               :data #(1) :v 27 :r 4 :s 5))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (genesis (eth-serve-test-block 0 (zero-hash32)))
         (block-1 (eth-serve-test-block 1 (block-hash genesis)
                                        :transactions (list transaction)
                                        :receipts (list receipt)))
         (block-2 (eth-serve-test-block 2 (block-hash block-1)))
         (chain (list genesis block-1 block-2))
         (backend (eth-serve-test-backend chain))
         (listener (make-instance 'sb-bsd-sockets:inet-socket
                                  :type :stream :protocol :tcp)))
    (flet ((hello (client-id)
             (make-devp2p-hello
              :client-id client-id
              :capabilities (list (make-devp2p-capability "eth" 68))
              :node-id server-static-pub))
           (status ()
             (eth-serve-test-status config 2 (hash32-bytes (block-hash block-2)))))
      (setf (sb-bsd-sockets:sockopt-reuse-address listener) t)
      (unwind-protect
           (progn
             (sb-bsd-sockets:socket-bind
              listener (sb-bsd-sockets:make-inet-address "127.0.0.1") 0)
             (sb-bsd-sockets:socket-listen listener 1)
             (multiple-value-bind (address port)
                 (sb-bsd-sockets:socket-name listener)
               (declare (ignore address))
               (let ((server-error nil))
                 (let ((server-thread
                         (sb-thread:make-thread
                          (lambda ()
                            (handler-case
                                (let* ((client-socket
                                         (sb-bsd-sockets:socket-accept listener))
                                       (stream (p2p-binary-socket-stream client-socket))
                                       (connection (rlpx-accept-stream stream
                                                                       server-static))
                                       (peer (eth-peer-connect
                                              connection (hello "srv") (status)
                                              :serve-backend backend)))
                                  ;; Three requests, all answered by the serve
                                  ;; layer rather than by this thread.
                                  (eth-peer-serve-loop peer :max-messages 3))
                              (error (condition) (setf server-error condition))))
                          :name "eth-serve-test-server")))
                   (let ((client-socket (make-instance 'sb-bsd-sockets:inet-socket
                                                       :type :stream :protocol :tcp)))
                     (sb-bsd-sockets:socket-connect
                      client-socket (sb-bsd-sockets:make-inet-address "127.0.0.1")
                      port)
                     (let* ((stream (p2p-binary-socket-stream client-socket))
                            (connection (rlpx-connect-stream stream client-static
                                                             server-static-pub))
                            (peer (eth-peer-connect connection (hello "cli")
                                                    (status))))
                       (let ((headers (eth-peer-get-block-headers
                                       peer :origin-number 0 :amount 5)))
                         (is (equal '(0 1 2) (mapcar #'block-header-number headers)))
                         (is (bytes= (hash32-bytes (block-hash block-1))
                                     (hash32-bytes (block-header-hash
                                                    (second headers))))))
                       (let ((bodies (eth-peer-get-block-bodies
                                      peer (list (hash32-bytes (block-hash block-1))
                                                 (hash32-bytes (block-hash block-2))))))
                         (is (= 2 (length bodies)))
                         (is (bytes=
                              (transaction-encoding transaction)
                              (transaction-encoding
                               (first (ethereum-lisp.eth-wire:eth-block-body-transactions
                                       (first bodies)))))))
                       ;; Receipts have no download helper yet, so the request
                       ;; and the reply are read directly.
                       (let ((request-id (eth-peer-next-request-id peer)))
                         (eth-peer-send
                          peer ethereum-lisp.eth-wire:+eth-message-get-receipts+
                          (ethereum-lisp.eth-wire:encode-eth-get-receipts
                           request-id
                           (list (hash32-bytes (block-hash block-1)))))
                         (multiple-value-bind (eth-id payload) (eth-peer-read peer)
                           (is (= ethereum-lisp.eth-wire:+eth-message-receipts+
                                  eth-id))
                           (let ((items (rlp-list-items (rlp-decode payload))))
                             (is (= request-id
                                    (bytes-to-integer
                                     (ensure-byte-vector (first items)))))
                             (let* ((blocks (rlp-list-items (second items)))
                                    (receipts (rlp-list-items (first blocks))))
                               (is (= 1 (length blocks)))
                               (is (= 1 (length receipts)))
                               ;; eth/68 serves the consensus encoding.
                               (is (bytes=
                                    (transaction-receipt-encoding transaction receipt)
                                    (rlp-encode (first receipts))))))))))
                   (sb-thread:join-thread server-thread)
                   (when server-error
                     (error "eth serve server side failed: ~A" server-error))))))
        (ignore-errors (sb-bsd-sockets:socket-close listener))))))
