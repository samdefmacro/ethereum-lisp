(in-package #:ethereum-lisp.test)

;;;; The session pump.
;;;;
;;;; Almost all of this is a truth table over a pure function: no clock, no
;;;; socket, no thread, `now` passed in as an integer. That is deliberate. The
;;;; one property that cannot be tested that way — that a connection carrying
;;;; only keepalives still comes back to the loop — needs a real socket, and it
;;;; is the single most important test in the file.

(defun eth-pump-test-action (&key (policy (make-eth-pump-policy))
                                  (last-read 0) (last-ping 0) (last-drain 0)
                                  (now 0) readable-p stop-p drainable-p
                                  urgent-drainable-p
                                  request-p chain-update-p broadcast-p)
  (let ((state (make-eth-pump-state)))
    (setf (eth-pump-state-last-read-at state) last-read
          (eth-pump-state-last-ping-at state) last-ping
          (eth-pump-state-last-drain-at state) last-drain)
    (eth-pump-next-action policy state now
                          :readable-p readable-p :stop-p stop-p
                          :request-p request-p :drainable-p drainable-p
                          :urgent-drainable-p urgent-drainable-p
                          :chain-update-p chain-update-p
                          :broadcast-p broadcast-p)))

(deftest eth-pump-next-action-truth-table
  (:layer :unit :module :p2p)
  ;; Queued snap healing requests are dependent and therefore cannot overlap.
  ;; Keep the default writer wake bounded tightly enough that the readiness
  ;; poll itself cannot reduce a healthy peer to about one request per second.
  (is (plusp +eth-pump-read-tick-seconds+))
  (is (<= +eth-pump-read-tick-seconds+ 0.05d0))
  ;; Stopping beats everything: a shutdown must never wait on a peer.
  (is (eq :stop (eth-pump-test-action :stop-p t)))
  (is (eq :stop (eth-pump-test-action :stop-p t :readable-p t)))
  (is (eq :stop (eth-pump-test-action :stop-p t :now 10000)))
  (is (eq :stop (eth-pump-test-action :stop-p t :readable-p t :drainable-p t
                                      :broadcast-p t :now 10000)))
  ;; A queued coordinator request outranks readability.  Its response loop
  ;; handles interleaved peer traffic, and allowing reads to win here would
  ;; starve snap healing on a continuously talkative public peer.
  (is (eq :request
          (eth-pump-test-action :readable-p t :request-p t :now 20)))
  ;; Without a request, reading beats every periodic job so a talkative peer is
  ;; drained before we add periodic traffic of our own...
  (is (eq :read (eth-pump-test-action :readable-p t)))
  (is (eq :read (eth-pump-test-action :readable-p t :now 20)))
  (is (eq :read (eth-pump-test-action :readable-p t :drainable-p t :now 20)))
  ;; An omitted eth/72 blob is not merely periodic gossip: it cannot be
  ;; admitted until GetCells completes and must not starve behind a peer that
  ;; keeps the descriptor readable.
  (is (eq :drain
          (eth-pump-test-action :readable-p t :drainable-p t
                                :urgent-drainable-p t :now 3)))
  ;; Transaction hashes are a block-building dependency, not a two-second
  ;; maintenance job. Fetch them on the first loop turn after announcement.
  (is (eq :drain
          (eth-pump-test-action :readable-p t :drainable-p t
                                :urgent-drainable-p t :now 0)))
  ;; ...and in particular, a peer whose data is already waiting can never be
  ;; timed out as idle.
  (is (eq :read (eth-pump-test-action :readable-p t :now 100000)))
  ;; Nothing readable: the periodic jobs, in order.
  (is (eq :idle-timeout (eth-pump-test-action :now 61)))
  ;; Coordinator requests run on the sole socket writer and outrank periodic
  ;; traffic, including an otherwise-due idle timeout.
  (is (eq :request (eth-pump-test-action :now 61 :request-p t)))
  (is (eq :ping (eth-pump-test-action :now 20)))
  (is (eq :drain (eth-pump-test-action :now 3 :drainable-p t)))
  (is (eq :chain-update
          (eth-pump-test-action :now 1 :chain-update-p t)))
  (is (eq :chain-update
          (eth-pump-test-action :now 1 :chain-update-p t :broadcast-p t)))
  (is (eq :broadcast (eth-pump-test-action :now 1 :broadcast-p t)))
  (is (eq :wait (eth-pump-test-action :now 1)))
  ;; A drain is only due when there is something to ask for.
  (is (eq :wait (eth-pump-test-action :now 3)))
  ;; Boundaries are inclusive: due AT the interval, not one tick after.
  (is (eq :ping (eth-pump-test-action :now +eth-pump-ping-interval-seconds+)))
  (is (eq :wait (eth-pump-test-action
                 :now (1- +eth-pump-ping-interval-seconds+))))
  (is (eq :idle-timeout
          (eth-pump-test-action :now +eth-pump-idle-timeout-seconds+)))
  ;; A NIL interval turns that behavior off rather than firing constantly.
  (let ((policy (make-eth-pump-policy :ping-interval-seconds nil
                                      :idle-timeout-seconds nil
                                      :drain-interval-seconds nil)))
    (is (eq :wait (eth-pump-test-action :policy policy :now 100000)))
    (is (eq :wait (eth-pump-test-action :policy policy :now 100000
                                        :drainable-p t)))
    (is (eq :read (eth-pump-test-action :policy policy :now 100000
                                        :readable-p t)))))

(deftest eth-peer-run-session-does-not-starve-a-queued-request
  (:layer :unit :module :p2p)
  ;; Exercise the shipped loop, not only its pure policy.  READABLE-FUNCTION is
  ;; deliberately always true, matching an active Hoodi peer.  The request must
  ;; run without touching the connection; the pre-fix loop instead tries to
  ;; read and signals because this test peer intentionally has no connection.
  (let ((peer (ethereum-lisp.eth-sync::%make-eth-peer))
        (request-calls 0)
        (readiness-calls 0))
    (multiple-value-bind (actions reason)
        (eth-peer-run-session
         peer
         :readable-function
         (lambda (timeout)
           (declare (ignore timeout))
           (incf readiness-calls)
           t)
         :pending-request
         (lambda ()
           (lambda () (incf request-calls)))
         :max-actions 1)
      (is (= 1 actions))
      (is (eq :max-actions reason))
      (is (= 1 request-calls))
      (is (zerop readiness-calls)))))

(deftest eth-peer-run-session-reads-while-transaction-fetches-are-capped
  (:layer :unit :module :p2p)
  ;; Unanswered async fetches must not leave hash gossip permanently urgent.
  ;; At capacity the pump reads replies; once the five-second geth timeout has
  ;; elapsed, the stale metadata is pruned and the queued hash becomes fetchable.
  (let* ((backend
           (make-eth-serve-backend
            :known-transaction-p
            (lambda (hash) (declare (ignore hash)) nil)))
         (peer
           (ethereum-lisp.eth-sync::%make-eth-peer
            :serve-backend backend))
         (pending
           (ethereum-lisp.eth-sync::eth-peer-pending-pooled-transaction-request-table
            peer))
         (queued-hash (make-byte-vector 32 :initial-element #xaa))
         (read-symbol 'ethereum-lisp.eth-sync:eth-peer-read-once)
         (send-symbol 'ethereum-lisp.eth-sync:eth-peer-send)
         (real-read (fdefinition read-symbol))
         (real-send (fdefinition send-symbol))
         (events '())
         (sends 0))
    (dotimes (request-id 64)
      (setf
       (gethash request-id pending)
       (ethereum-lisp.eth-sync::make-eth-pooled-transaction-request
        (list
         (ethereum-lisp.eth-sync::make-eth-transaction-announcement
          (make-byte-vector 32 :initial-element request-id) 3 100))
        100)))
    (is (= 1 (eth-peer-queue-announced-hashes
              peer backend (list queued-hash)
              :types '(3) :sizes '(100))))
    (unwind-protect
         (progn
           (setf (fdefinition read-symbol)
                 (lambda (candidate)
                   (is (eq peer candidate))
                   (values :base +devp2p-message-pong+ nil))
                 (fdefinition send-symbol)
                 (lambda (candidate message-id payload)
                   (declare (ignore payload))
                   (is (eq peer candidate))
                   (is (= ethereum-lisp.eth-wire:+eth-message-get-pooled-transactions+
                          message-id))
                   (incf sends)))
           (multiple-value-bind (actions reason)
               (eth-peer-run-session
                peer
                :now-function (lambda () 104)
                :readable-function
                (lambda (timeout) (declare (ignore timeout)) t)
                :on-event (lambda (event) (push event events))
                :max-actions 1)
             (is (= 1 actions))
             (is (eq :max-actions reason)))
           (is (equal '(:read) events))
           (is (zerop sends))
           (is (= 1 (eth-peer-announced-hash-count peer)))
           (is (= 1
                  (ethereum-lisp.eth-sync::eth-peer-request-announced-transactions
                   peer :now 105)))
           (is (= 1 sends))
           (is (zerop (eth-peer-announced-hash-count peer)))
           (is (= 1 (hash-table-count pending))))
      (setf (fdefinition read-symbol) real-read
            (fdefinition send-symbol) real-send))))

(deftest eth-peer-run-session-retains-broadcast-behind-request
  (:layer :unit :module :p2p)
  (let* ((peer (ethereum-lisp.eth-sync::%make-eth-peer))
         (broadcast-symbol
           'ethereum-lisp.eth-sync:eth-peer-broadcast-transactions)
         (announce-symbol
           'ethereum-lisp.eth-sync:eth-peer-announce-transactions)
         (real-broadcast (fdefinition broadcast-symbol))
         (real-announce (fdefinition announce-symbol))
         (request-pending-p t)
         (broadcast-pending-p t)
         (pending-calls 0)
         (sent '()))
    (unwind-protect
         (progn
           (setf
            (fdefinition broadcast-symbol)
            (lambda (candidate transactions)
              (is (eq peer candidate))
              (push (list :full transactions) sent)
              0)
            (fdefinition announce-symbol)
            (lambda (candidate transactions)
              (is (eq peer candidate))
              (push (list :announce transactions) sent)
              1))
           (multiple-value-bind (actions reason)
               (eth-peer-run-session
                peer
                :policy
                (make-eth-pump-policy
                 :ping-interval-seconds nil
                 :idle-timeout-seconds nil
                 :drain-interval-seconds nil)
                :pending-request
                (lambda ()
                  (when request-pending-p
                    (setf request-pending-p nil)
                    (lambda () nil)))
                :pending-broadcast
                (lambda ()
                  (incf pending-calls)
                  (when broadcast-pending-p
                    (setf broadcast-pending-p nil)
                    (list :blob-transaction)))
                :max-actions 2)
             (is (= 2 actions))
             (is (eq :max-actions reason)))
           (is (= 1 pending-calls))
           (is
            (equal
             '((:full (:blob-transaction)) (:announce (:blob-transaction)))
             (nreverse sent))))
      (setf (fdefinition broadcast-symbol) real-broadcast
            (fdefinition announce-symbol) real-announce))))

(deftest eth-peer-run-session-routes-a-pipelined-snap-response
  (:layer :unit :module :p2p)
  (let* ((peer (ethereum-lisp.eth-sync::%make-eth-peer))
         (read-symbol 'ethereum-lisp.eth-sync:eth-peer-read-once)
         (real-read (fdefinition read-symbol))
         (payload
           (ethereum-lisp.snap:encode-snap-message
            ethereum-lisp.snap:+snap-message-account-range+
            (ethereum-lisp.snap:make-snap-account-range 77 nil nil)))
         (routed nil))
    (unwind-protect
         (progn
           (setf (fdefinition read-symbol)
                 (lambda (candidate)
                   (is (eq peer candidate))
                   (values :snap
                           ethereum-lisp.snap:+snap-message-account-range+
                           payload)))
           (multiple-value-bind (actions reason)
               (eth-peer-run-session
                peer
                :readable-function (lambda (timeout)
                                     (declare (ignore timeout))
                                     t)
                :snap-response-handler
                (lambda (message-id encoded)
                  (setf routed
                        (list message-id
                              (ethereum-lisp.snap:snap-account-range-id
                               (ethereum-lisp.snap:decode-snap-message
                                message-id encoded))))
                  t)
                :max-actions 1)
             (is (= 1 actions))
             (is (eq :max-actions reason)))
           (is (equal
                (list ethereum-lisp.snap:+snap-message-account-range+ 77)
                routed)))
      (setf (fdefinition read-symbol) real-read))))

(deftest eth-peer-run-session-answers-an-empty-snap-trie-request
  (:layer :unit :module :p2p)
  ;; Pinned geth 101035a1 TestSnapTrieNodes distinguishes an empty Paths list
  ;; from a list containing an empty path set: the former receives an empty
  ;; TrieNodes response and keeps the shared eth+snap session usable.
  (let* ((state (make-state-db))
         (database (make-memory-key-value-database))
         (peer (ethereum-lisp.eth-sync::%make-eth-peer))
         (backend
           (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
            database state))
         (read-symbol 'ethereum-lisp.eth-sync:eth-peer-read-once)
         (send-symbol 'ethereum-lisp.eth-sync:eth-peer-send-snap)
         (real-read (fdefinition read-symbol))
         (real-send (fdefinition send-symbol))
         (sent nil)
         (request
           (ethereum-lisp.snap:make-snap-get-trie-nodes
            76 (hash32-bytes (state-db-root state)) '() 500))
         (payload
           (ethereum-lisp.snap:encode-snap-message
            ethereum-lisp.snap:+snap-message-get-trie-nodes+ request)))
    (setf (ethereum-lisp.eth-sync::eth-peer-snap-offset peer) 100
          (ethereum-lisp.eth-sync::eth-peer-snap-backend peer) backend)
    (unwind-protect
         (progn
           (setf (fdefinition read-symbol)
                 (lambda (candidate)
                   (is (eq peer candidate))
                   (values :snap
                           ethereum-lisp.snap:+snap-message-get-trie-nodes+
                           payload)))
           (setf (fdefinition send-symbol)
                 (lambda (candidate message-id encoded)
                   (is (eq peer candidate))
                   (setf sent
                         (list
                          message-id
                          (ethereum-lisp.snap:decode-snap-message
                           message-id encoded)))))
           (multiple-value-bind (actions reason)
               (eth-peer-run-session
                peer :readable-function (lambda (timeout)
                                          (declare (ignore timeout)) t)
                :max-actions 1)
             (is (= 1 actions))
             (is (eq :max-actions reason))))
      (setf (fdefinition read-symbol) real-read
            (fdefinition send-symbol) real-send))
    (is sent)
    (is (= ethereum-lisp.snap:+snap-message-trie-nodes+ (first sent)))
    (let ((response (second sent)))
      (is (= 76 (ethereum-lisp.snap:snap-trie-nodes-id response)))
      (is (null (ethereum-lisp.snap:snap-trie-nodes-nodes response))))))

(deftest eth-peer-run-session-rejects-an-empty-snap-trie-path-set
  (:layer :unit :module :p2p)
  ;; Pinned geth 101035a1 TestSnapTrieNodes disconnects on this request.
  (let* ((state (make-state-db))
         (database (make-memory-key-value-database))
         (peer (ethereum-lisp.eth-sync::%make-eth-peer))
         (backend
           (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
            database state))
         (read-symbol 'ethereum-lisp.eth-sync:eth-peer-read-once)
         (send-symbol 'ethereum-lisp.eth-sync:eth-peer-send-snap)
         (real-read (fdefinition read-symbol))
         (real-send (fdefinition send-symbol))
         (sent nil)
         (caught nil)
         (request
           (ethereum-lisp.snap:make-snap-get-trie-nodes
            77 (hash32-bytes (state-db-root state))
            (list nil (list #(0))) 5000))
         (payload
           (ethereum-lisp.snap:encode-snap-message
            ethereum-lisp.snap:+snap-message-get-trie-nodes+ request)))
    (setf (ethereum-lisp.eth-sync::eth-peer-snap-offset peer) 100
          (ethereum-lisp.eth-sync::eth-peer-snap-backend peer) backend)
    (unwind-protect
         (progn
           (setf (fdefinition read-symbol)
                 (lambda (candidate)
                   (is (eq peer candidate))
                   (values :snap
                           ethereum-lisp.snap:+snap-message-get-trie-nodes+
                           payload)))
           (setf (fdefinition send-symbol)
                 (lambda (&rest arguments)
                   (declare (ignore arguments))
                   (setf sent t)))
           (handler-case
               (eth-peer-run-session
                peer :readable-function (lambda (timeout)
                                          (declare (ignore timeout)) t)
                :max-actions 1)
             (error (condition) (setf caught condition))))
      (setf (fdefinition read-symbol) real-read
            (fdefinition send-symbol) real-send))
    (is caught)
    (is (search "empty path set" (princ-to-string caught)
                :test #'char-equal))
    (is (not sent))))

(deftest eth-peer-run-session-answers-a-nonsensically-long-snap-trie-path
  (:layer :unit :module :p2p)
  ;; Pinned geth 101035a1 TestSnapTrieNodes lines 640-649 requires one
  ;; empty-node placeholder for a nonsensically long account-trie path.
  (let* ((state (make-state-db))
         (database (make-memory-key-value-database))
         (peer (ethereum-lisp.eth-sync::%make-eth-peer))
         (backend
           (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
            database state))
         (read-symbol 'ethereum-lisp.eth-sync:eth-peer-read-once)
         (send-symbol 'ethereum-lisp.eth-sync:eth-peer-send-snap)
         (real-read (fdefinition read-symbol))
         (real-send (fdefinition send-symbol))
         (sent nil)
         (path
           #(0 1 2 3 4 5 6 7 8 0 1 2 3 4 5 6 7 8
             0 1 2 3 4 5 6 7 8 0 1 2 3 4 5 6 7 8
             0 1 2 3 4 5 6 7 8 0 1 2 3 4 5 6 7 8))
         (request
           (ethereum-lisp.snap:make-snap-get-trie-nodes
            78 (hash32-bytes (state-db-root state)) (list (list path)) 5000))
         (payload
           (ethereum-lisp.snap:encode-snap-message
            ethereum-lisp.snap:+snap-message-get-trie-nodes+ request)))
    (setf (ethereum-lisp.eth-sync::eth-peer-snap-offset peer) 100
          (ethereum-lisp.eth-sync::eth-peer-snap-backend peer) backend)
    (unwind-protect
         (progn
           (setf (fdefinition read-symbol)
                 (lambda (candidate)
                   (is (eq peer candidate))
                   (values :snap
                           ethereum-lisp.snap:+snap-message-get-trie-nodes+
                           payload)))
           (setf (fdefinition send-symbol)
                 (lambda (candidate message-id encoded)
                   (is (eq peer candidate))
                   (setf sent
                         (list
                          message-id
                          (ethereum-lisp.snap:decode-snap-message
                           message-id encoded)))))
           (multiple-value-bind (actions reason)
               (eth-peer-run-session
                peer :readable-function (lambda (timeout)
                                          (declare (ignore timeout)) t)
                :max-actions 1)
             (is (= 1 actions))
             (is (eq :max-actions reason))))
      (setf (fdefinition read-symbol) real-read
            (fdefinition send-symbol) real-send))
    (is sent)
    (is (= ethereum-lisp.snap:+snap-message-trie-nodes+ (first sent)))
    (let* ((response (second sent))
           (nodes (ethereum-lisp.snap:snap-trie-nodes-nodes response)))
      (is (= 78 (ethereum-lisp.snap:snap-trie-nodes-id response)))
      (is (= 1 (length nodes)))
      (is (zerop (length (first nodes)))))))

(deftest eth-peer-run-session-answers-a-snap-trie-root-before-a-storage-miss
  (:layer :unit :module :p2p)
  ;; Pinned geth 101035a1 TestSnapTrieNodes lines 629-638 requests the account
  ;; root before an unavailable short storage-account path. Only the root node
  ;; appears in the response, and the shared eth+snap session remains usable.
  (let* ((state (make-state-db))
         (database (make-memory-key-value-database))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000042"))
         (root
           (progn
             (state-db-set-account state address (make-state-account :balance 1))
             (hash32-bytes (state-db-root state))))
         (peer (ethereum-lisp.eth-sync::%make-eth-peer))
         (backend
           (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
            database state))
         (read-symbol 'ethereum-lisp.eth-sync:eth-peer-read-once)
         (send-symbol 'ethereum-lisp.eth-sync:eth-peer-send-snap)
         (real-read (fdefinition read-symbol))
         (real-send (fdefinition send-symbol))
         (sent nil)
         (request
           (ethereum-lisp.snap:make-snap-get-trie-nodes
            79 root (list (list #(0)) (list #(1) #(0))) 5000))
         (payload
           (ethereum-lisp.snap:encode-snap-message
            ethereum-lisp.snap:+snap-message-get-trie-nodes+ request)))
    (setf (ethereum-lisp.eth-sync::eth-peer-snap-offset peer) 100
          (ethereum-lisp.eth-sync::eth-peer-snap-backend peer) backend)
    (unwind-protect
         (progn
           (setf (fdefinition read-symbol)
                 (lambda (candidate)
                   (is (eq peer candidate))
                   (values :snap
                           ethereum-lisp.snap:+snap-message-get-trie-nodes+
                           payload)))
           (setf (fdefinition send-symbol)
                 (lambda (candidate message-id encoded)
                   (is (eq peer candidate))
                   (setf sent
                         (list
                          message-id
                          (ethereum-lisp.snap:decode-snap-message
                           message-id encoded)))))
           (multiple-value-bind (actions reason)
               (eth-peer-run-session
                peer :readable-function (lambda (timeout)
                                          (declare (ignore timeout)) t)
                :max-actions 1)
             (is (= 1 actions))
             (is (eq :max-actions reason))))
      (setf (fdefinition read-symbol) real-read
            (fdefinition send-symbol) real-send))
    (is sent)
    (is (= ethereum-lisp.snap:+snap-message-trie-nodes+ (first sent)))
    (let* ((response (second sent))
           (nodes (ethereum-lisp.snap:snap-trie-nodes-nodes response)))
      (is (= 79 (ethereum-lisp.snap:snap-trie-nodes-id response)))
      (is (= 1 (length nodes)))
      (is (plusp (length (first nodes))))
      (is (bytes= root (keccak-256 (first nodes)))))))

(deftest eth-peer-run-session-answers-a-known-snap-storage-root
  (:layer :unit :module :p2p)
  ;; Pinned geth 101035a1 TestSnapTrieNodes lines 690-703 requests compact
  ;; path zero beneath a known account hash and expects that storage trie root.
  (let* ((state (make-state-db))
         (database (make-memory-key-value-database))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000042"))
         (slot
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (root
           (progn
             (state-db-set-storage state address slot 256)
             (hash32-bytes (state-db-root state))))
         (storage-root (hash32-bytes (state-db-get-storage-root state address)))
         (account-hash (keccak-256 (address-bytes address)))
         (peer (ethereum-lisp.eth-sync::%make-eth-peer))
         (backend
           (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
            database state))
         (read-symbol 'ethereum-lisp.eth-sync:eth-peer-read-once)
         (send-symbol 'ethereum-lisp.eth-sync:eth-peer-send-snap)
         (real-read (fdefinition read-symbol))
         (real-send (fdefinition send-symbol))
         (sent nil)
         (request
           (ethereum-lisp.snap:make-snap-get-trie-nodes
            80 root (list (list account-hash #(0))) 5000))
         (payload
           (ethereum-lisp.snap:encode-snap-message
            ethereum-lisp.snap:+snap-message-get-trie-nodes+ request)))
    (setf (ethereum-lisp.eth-sync::eth-peer-snap-offset peer) 100
          (ethereum-lisp.eth-sync::eth-peer-snap-backend peer) backend)
    (unwind-protect
         (progn
           (setf (fdefinition read-symbol)
                 (lambda (candidate)
                   (is (eq peer candidate))
                   (values :snap
                           ethereum-lisp.snap:+snap-message-get-trie-nodes+
                           payload)))
           (setf (fdefinition send-symbol)
                 (lambda (candidate message-id encoded)
                   (is (eq peer candidate))
                   (setf sent
                         (list
                          message-id
                          (ethereum-lisp.snap:decode-snap-message
                           message-id encoded)))))
           (multiple-value-bind (actions reason)
               (eth-peer-run-session
                peer :readable-function (lambda (timeout)
                                          (declare (ignore timeout)) t)
                :max-actions 1)
             (is (= 1 actions))
             (is (eq :max-actions reason))))
      (setf (fdefinition read-symbol) real-read
            (fdefinition send-symbol) real-send))
    (is sent)
    (is (= ethereum-lisp.snap:+snap-message-trie-nodes+ (first sent)))
    (let* ((response (second sent))
           (nodes (ethereum-lisp.snap:snap-trie-nodes-nodes response)))
      (is (= 80 (ethereum-lisp.snap:snap-trie-nodes-id response)))
      (is (= 1 (length nodes)))
      (is (plusp (length (first nodes))))
      (is (bytes= storage-root (keccak-256 (first nodes)))))))

(deftest eth-peer-run-session-answers-multiple-known-snap-storage-nodes
  (:layer :unit :module :p2p)
  ;; Pinned geth 101035a1 TestSnapTrieNodes lines 705-719 requests the
  ;; storage root and compact child path 0x1b in the same account path set.
  (let* ((state (make-state-db))
         (database (make-memory-key-value-database))
         (address
           (address-from-hex "0x0000000000000000000000000000000000000042"))
         (slot-one
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (slot-two
           (hash32-from-hex
            "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (expected-storage-trie (make-mpt))
         (root
           (progn
             (state-db-set-storage state address slot-one 256)
             (state-db-set-storage state address slot-two 512)
             (hash32-bytes (state-db-root state))))
         (storage-root (hash32-bytes (state-db-get-storage-root state address)))
         (account-hash (keccak-256 (address-bytes address)))
         (peer (ethereum-lisp.eth-sync::%make-eth-peer))
         (backend
           (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
            database state))
         (read-symbol 'ethereum-lisp.eth-sync:eth-peer-read-once)
         (send-symbol 'ethereum-lisp.eth-sync:eth-peer-send-snap)
         (real-read (fdefinition read-symbol))
         (real-send (fdefinition send-symbol))
         (sent nil)
         (request
           (ethereum-lisp.snap:make-snap-get-trie-nodes
            81 root (list (list account-hash #(0) #(#x1b))) 5000))
         (payload
           (ethereum-lisp.snap:encode-snap-message
            ethereum-lisp.snap:+snap-message-get-trie-nodes+ request)))
    (mpt-put expected-storage-trie
             (keccak-256 (hash32-bytes slot-one)) (rlp-encode 256))
    (mpt-put expected-storage-trie
             (keccak-256 (hash32-bytes slot-two)) (rlp-encode 512))
    (is (bytes= storage-root (mpt-root-hash expected-storage-trie)))
    (multiple-value-bind (expected-child present-p)
        (mpt-get-node-by-compact-path expected-storage-trie #(#x1b))
      (is present-p)
      (setf (ethereum-lisp.eth-sync::eth-peer-snap-offset peer) 100
            (ethereum-lisp.eth-sync::eth-peer-snap-backend peer) backend)
      (unwind-protect
           (progn
             (setf (fdefinition read-symbol)
                   (lambda (candidate)
                     (is (eq peer candidate))
                     (values :snap
                             ethereum-lisp.snap:+snap-message-get-trie-nodes+
                             payload)))
             (setf (fdefinition send-symbol)
                   (lambda (candidate message-id encoded)
                     (is (eq peer candidate))
                     (setf sent
                           (list
                            message-id
                            (ethereum-lisp.snap:decode-snap-message
                             message-id encoded)))))
             (multiple-value-bind (actions reason)
                 (eth-peer-run-session
                  peer :readable-function (lambda (timeout)
                                            (declare (ignore timeout)) t)
                  :max-actions 1)
               (is (= 1 actions))
               (is (eq :max-actions reason))))
        (setf (fdefinition read-symbol) real-read
              (fdefinition send-symbol) real-send))
      (is sent)
      (is (= ethereum-lisp.snap:+snap-message-trie-nodes+ (first sent)))
      (let* ((response (second sent))
             (nodes (ethereum-lisp.snap:snap-trie-nodes-nodes response)))
        (is (= 81 (ethereum-lisp.snap:snap-trie-nodes-id response)))
        (is (= 2 (length nodes)))
        (is (bytes= storage-root (keccak-256 (first nodes))))
        (is (bytes= expected-child (second nodes)))))))

(deftest eth-peer-run-session-preserves-unsorted-snap-account-path-order
  (:layer :unit :module :p2p)
  ;; Pinned geth 101035a1 TestSnapTrieNodes lines 671-685 sends account
  ;; paths at prefix lengths 11, 2, and 1 and requires positional responses.
  (let* ((state (make-state-db))
         (database (make-memory-key-value-database))
         (address
           (address-from-hex "0x00000000000000000000000000000000000000df"))
         (other-address
           (address-from-hex "0x00000000000000000000000000000000000003e8"))
         (outside-prefix-address
           (address-from-hex "0x0000000000000000000000000000000000000042"))
         (account-hash (keccak-256 (address-bytes address)))
         (peer (ethereum-lisp.eth-sync::%make-eth-peer))
         (read-symbol 'ethereum-lisp.eth-sync:eth-peer-read-once)
         (send-symbol 'ethereum-lisp.eth-sync:eth-peer-send-snap)
         (real-read (fdefinition read-symbol))
         (real-send (fdefinition send-symbol))
         (sent nil))
    (state-db-set-account state address (make-state-account :balance 1))
    (state-db-set-account state other-address (make-state-account :balance 2))
    (state-db-set-account
     state outside-prefix-address (make-state-account :balance 3))
    (labels ((account-path (length)
               (let ((nibbles
                       (subseq (keybytes-to-nibbles account-hash) 0 length)))
                 (setf (aref nibbles (1- length)) 0)
                 (hex-prefix-encode nibbles))))
      (let* ((account-trie (ethereum-lisp.state::state-db-state-trie state))
             (paths (list (account-path 11)
                          (account-path 2)
                          (account-path 1)))
             (expected
               (mapcar
                (lambda (path)
                  (multiple-value-bind (node present-p)
                      (mpt-get-node-by-compact-path account-trie path)
                    (if present-p node (make-byte-vector 0))))
                paths))
             (root (hash32-bytes (state-db-root state)))
             (backend
               (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
                database state))
             (request
               (ethereum-lisp.snap:make-snap-get-trie-nodes
                82 root (mapcar #'list paths) 5000))
             (payload
               (ethereum-lisp.snap:encode-snap-message
                ethereum-lisp.snap:+snap-message-get-trie-nodes+ request)))
        (is (= 3 (length expected)))
        (is (zerop (length (first expected))))
        (is (plusp (length (second expected))))
        (is (plusp (length (third expected))))
        (setf (ethereum-lisp.eth-sync::eth-peer-snap-offset peer) 100
              (ethereum-lisp.eth-sync::eth-peer-snap-backend peer) backend)
        (unwind-protect
             (progn
               (setf (fdefinition read-symbol)
                     (lambda (candidate)
                       (is (eq peer candidate))
                       (values :snap
                               ethereum-lisp.snap:+snap-message-get-trie-nodes+
                               payload)))
               (setf (fdefinition send-symbol)
                     (lambda (candidate message-id encoded)
                       (is (eq peer candidate))
                       (setf sent
                             (list
                              message-id
                              (ethereum-lisp.snap:decode-snap-message
                               message-id encoded)))))
               (multiple-value-bind (actions reason)
                   (eth-peer-run-session
                    peer :readable-function (lambda (timeout)
                                              (declare (ignore timeout)) t)
                    :max-actions 1)
                 (is (= 1 actions))
                 (is (eq :max-actions reason))))
          (setf (fdefinition read-symbol) real-read
                (fdefinition send-symbol) real-send))
        (is sent)
        (is (= ethereum-lisp.snap:+snap-message-trie-nodes+ (first sent)))
        (let* ((response (second sent))
               (nodes (ethereum-lisp.snap:snap-trie-nodes-nodes response)))
          (is (= 82 (ethereum-lisp.snap:snap-trie-nodes-id response)))
          (is (= 3 (length nodes)))
          (loop for actual in nodes
                for wanted in expected
                do (is (bytes= wanted actual))))))))

(deftest eth-peer-run-session-preserves-known-snap-account-path-cardinality
  (:layer :unit :module :p2p)
  ;; Pinned geth 101035a1 TestSnapTrieNodes lines 651-669 requests all
  ;; account-path prefix lengths 1 through 65 and retains every miss in place.
  (let* ((state (make-state-db))
         (database (make-memory-key-value-database))
         (address
           (address-from-hex "0x00000000000000000000000000000000000000df"))
         (other-address
           (address-from-hex "0x00000000000000000000000000000000000003e8"))
         (outside-prefix-address
           (address-from-hex "0x0000000000000000000000000000000000000042"))
         (account-hash (keccak-256 (address-bytes address)))
         (peer (ethereum-lisp.eth-sync::%make-eth-peer))
         (read-symbol 'ethereum-lisp.eth-sync:eth-peer-read-once)
         (send-symbol 'ethereum-lisp.eth-sync:eth-peer-send-snap)
         (real-read (fdefinition read-symbol))
         (real-send (fdefinition send-symbol))
         (sent nil))
    (state-db-set-account state address (make-state-account :balance 1))
    (state-db-set-account state other-address (make-state-account :balance 2))
    (state-db-set-account
     state outside-prefix-address (make-state-account :balance 3))
    (let* ((account-nibbles (keybytes-to-nibbles account-hash))
           (account-trie (ethereum-lisp.state::state-db-state-trie state))
           (paths
             (loop for length from 1 to 65
                   collect
                   (let ((nibbles (subseq account-nibbles 0 length)))
                     (setf (aref nibbles (1- length)) 0)
                     (hex-prefix-encode nibbles))))
           (expected
             (mapcar
              (lambda (path)
                (multiple-value-bind (node present-p)
                    (mpt-get-node-by-compact-path account-trie path)
                  (if present-p node (make-byte-vector 0))))
              paths))
           (root (hash32-bytes (state-db-root state)))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              database state))
           (request
             (ethereum-lisp.snap:make-snap-get-trie-nodes
              83 root (mapcar #'list paths) 5000))
           (payload
             (ethereum-lisp.snap:encode-snap-message
              ethereum-lisp.snap:+snap-message-get-trie-nodes+ request)))
      (is (= 65 (length expected)))
      (is (plusp (length (first expected))))
      (is (plusp (length (second expected))))
      (is (every (lambda (node) (zerop (length node))) (cddr expected)))
      (setf (ethereum-lisp.eth-sync::eth-peer-snap-offset peer) 100
            (ethereum-lisp.eth-sync::eth-peer-snap-backend peer) backend)
      (unwind-protect
           (progn
             (setf (fdefinition read-symbol)
                   (lambda (candidate)
                     (is (eq peer candidate))
                     (values :snap
                             ethereum-lisp.snap:+snap-message-get-trie-nodes+
                             payload)))
             (setf (fdefinition send-symbol)
                   (lambda (candidate message-id encoded)
                     (is (eq peer candidate))
                     (setf sent
                           (list
                            message-id
                            (ethereum-lisp.snap:decode-snap-message
                             message-id encoded)))))
             (multiple-value-bind (actions reason)
                 (eth-peer-run-session
                  peer :readable-function (lambda (timeout)
                                            (declare (ignore timeout)) t)
                  :max-actions 1)
               (is (= 1 actions))
               (is (eq :max-actions reason))))
        (setf (fdefinition read-symbol) real-read
              (fdefinition send-symbol) real-send))
      (is sent)
      (is (= ethereum-lisp.snap:+snap-message-trie-nodes+ (first sent)))
      (let* ((response (second sent))
             (nodes (ethereum-lisp.snap:snap-trie-nodes-nodes response)))
        (is (= 83 (ethereum-lisp.snap:snap-trie-nodes-id response)))
        (is (= 65 (length nodes)))
        (loop for actual in nodes
              for wanted in expected
              do (is (bytes= wanted actual)))))))

(deftest eth-peer-run-session-preserves-snap-storage-range-boundaries
  (:layer :unit :module :p2p)
  ;; Pinned geth 101035a1 TestSnapGetStorageRanges lines 376-427 requires
  ;; inclusive exact-key limits and one next-available slot past an inexact
  ;; limit. Exercise those boundaries through the shared eth+snap session.
  (let* ((state (make-state-db))
         (database (make-memory-key-value-database))
         (peer (ethereum-lisp.eth-sync::%make-eth-peer))
         (address (address-from-hex
                   "0x0000000000000000000000000000000000005678"))
         (slot-preimages
           (mapcar
            (lambda (value)
              (make-hash32
               (ethereum-lisp.crypto::integer-to-fixed-bytes value 32)))
            '(1 2 3)))
         (account-hash (keccak-256 (address-bytes address)))
         (read-symbol 'ethereum-lisp.eth-sync:eth-peer-read-once)
         (send-symbol 'ethereum-lisp.eth-sync:eth-peer-send-snap)
         (real-read (fdefinition read-symbol))
         (real-send (fdefinition send-symbol))
         (zero (make-byte-vector 32))
         (maximum (make-byte-vector 32 :initial-element #xff))
         (payloads nil)
         (sent '()))
    (loop for slot in slot-preimages
          for value in '(2 1 3)
          do (state-db-set-storage state address slot value))
    (let* ((root (hash32-bytes (state-db-root state)))
           (entries (state-db-storage-range state address))
           (keys (mapcar #'state-storage-range-entry-proof-key entries))
           (first-key (first keys))
           (second-key (second keys))
           (first-plus-one
             (ethereum-lisp.crypto::integer-to-fixed-bytes
              (1+ (bytes-to-integer first-key)) 32))
           (second-plus-one
             (ethereum-lisp.crypto::integer-to-fixed-bytes
              (1+ (bytes-to-integer second-key)) 32))
           (bounds
             (list (list zero maximum)
                   (list first-key maximum)
                   (list first-plus-one maximum)
                   (list first-key second-key)
                   (list first-plus-one second-plus-one)))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              database state)))
      (is (= 3 (length keys)))
      (is (< (bytes-to-integer first-plus-one)
             (bytes-to-integer second-key)))
      (setf payloads
            (loop for (origin limit) in bounds
                  for request-id from 100
                  collect
                  (ethereum-lisp.snap:encode-snap-message
                   ethereum-lisp.snap:+snap-message-get-storage-ranges+
                   (ethereum-lisp.snap:make-snap-get-storage-ranges
                    request-id root (list account-hash) origin limit 1000))))
      (setf (ethereum-lisp.eth-sync::eth-peer-snap-offset peer) 100
            (ethereum-lisp.eth-sync::eth-peer-snap-backend peer) backend)
      (unwind-protect
           (progn
             (setf (fdefinition read-symbol)
                   (lambda (candidate)
                     (is (eq peer candidate))
                     (values :snap
                             ethereum-lisp.snap:+snap-message-get-storage-ranges+
                             (pop payloads))))
             (setf (fdefinition send-symbol)
                   (lambda (candidate message-id encoded)
                     (is (eq peer candidate))
                     (push
                      (list
                       message-id
                       (ethereum-lisp.snap:decode-snap-message
                        message-id encoded))
                      sent)))
             (multiple-value-bind (actions reason)
                 (eth-peer-run-session
                  peer :readable-function (lambda (timeout)
                                            (declare (ignore timeout))
                                            (not (null payloads)))
                  :max-actions 5)
               (is (= 5 actions))
               (is (eq :max-actions reason))))
        (setf (fdefinition read-symbol) real-read
              (fdefinition send-symbol) real-send))
      (setf sent (nreverse sent))
      (is (= 5 (length sent)))
      (loop for response-entry in sent
            for request-id from 100
            for expected in (list keys keys (rest keys)
                                  (subseq keys 0 2) (rest keys))
            do (is (= ethereum-lisp.snap:+snap-message-storage-ranges+
                      (first response-entry)))
               (let* ((response (second response-entry))
                      (groups
                        (ethereum-lisp.snap:snap-storage-ranges-slots response))
                      (actual
                        (mapcar #'ethereum-lisp.snap:snap-storage-data-hash
                                (first groups))))
                 (is (= request-id
                        (ethereum-lisp.snap:snap-storage-ranges-id response)))
                 (is (= 1 (length groups)))
                 (is (= (length expected) (length actual)))
                 (loop for wanted in expected
                       for received in actual
                       do (is (bytes= wanted received))))))))

(deftest eth-peer-run-session-omits-unavailable-snap-account-roots
  (:layer :unit :module :p2p)
  ;; Pinned geth 101035a1 TestSnapGetAccountRange lines 199-223 requires both
  ;; an unknown root and an unavailable historical genesis root to return no
  ;; accounts or proof nodes.  The retained current root is the positive control.
  (let* ((state (make-state-db))
         (database (make-memory-key-value-database))
         (peer (ethereum-lisp.eth-sync::%make-eth-peer))
         (address (address-from-hex
                   "0x0000000000000000000000000000000000001234"))
         (unknown-root (make-byte-vector 32))
         (historical-root nil)
         (current-root nil)
         (backend nil)
         (read-symbol 'ethereum-lisp.eth-sync:eth-peer-read-once)
         (send-symbol 'ethereum-lisp.eth-sync:eth-peer-send-snap)
         (real-read (fdefinition read-symbol))
         (real-send (fdefinition send-symbol))
         (origin (make-byte-vector 32))
         (limit (make-byte-vector 32 :initial-element #xff))
         (payloads nil)
         (sent '())
         (provider-roots '()))
    (setf (aref unknown-root 0) #x13
          (aref unknown-root 1) #x37
          historical-root (hash32-bytes (state-db-root state)))
    (state-db-set-account state address (make-state-account :balance 1))
    (setf current-root (hash32-bytes (state-db-root state))
          backend
          (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
           database state
           :state-provider
           (lambda (root)
             (push (copy-seq root) provider-roots)
             nil))
          payloads
          (mapcar
           (lambda (request)
             (ethereum-lisp.snap:encode-snap-message
              ethereum-lisp.snap:+snap-message-get-account-range+ request))
           (list
            (ethereum-lisp.snap:make-snap-get-account-range
             90 unknown-root origin limit 4000)
            (ethereum-lisp.snap:make-snap-get-account-range
             91 historical-root origin limit 4000)
            (ethereum-lisp.snap:make-snap-get-account-range
             92 current-root origin limit 4000))))
    (is (not (bytes= unknown-root historical-root)))
    (is (not (bytes= historical-root current-root)))
    (setf (ethereum-lisp.eth-sync::eth-peer-snap-offset peer) 100
          (ethereum-lisp.eth-sync::eth-peer-snap-backend peer) backend)
    (unwind-protect
         (progn
           (setf (fdefinition read-symbol)
                 (lambda (candidate)
                   (is (eq peer candidate))
                   (values :snap
                           ethereum-lisp.snap:+snap-message-get-account-range+
                           (pop payloads))))
           (setf (fdefinition send-symbol)
                 (lambda (candidate message-id encoded)
                   (is (eq peer candidate))
                   (push
                    (list
                     message-id
                     (ethereum-lisp.snap:decode-snap-message
                      message-id encoded))
                    sent)))
           (multiple-value-bind (actions reason)
               (eth-peer-run-session
                peer :readable-function (lambda (timeout)
                                          (declare (ignore timeout))
                                          (not (null payloads)))
                :max-actions 3)
             (is (= 3 actions))
             (is (eq :max-actions reason))))
      (setf (fdefinition read-symbol) real-read
            (fdefinition send-symbol) real-send))
    (setf sent (nreverse sent)
          provider-roots (nreverse provider-roots))
    (is (= 3 (length sent)))
    (is (= 2 (length provider-roots)))
    (is (bytes= unknown-root (first provider-roots)))
    (is (bytes= historical-root (second provider-roots)))
    (loop for response-entry in sent
          for request-id in '(90 91 92)
          for available-p in '(nil nil t)
          do (is (= ethereum-lisp.snap:+snap-message-account-range+
                    (first response-entry)))
             (let ((response (second response-entry)))
               (is (= request-id
                      (ethereum-lisp.snap:snap-account-range-id response)))
               (if available-p
                   (progn
                     (is (= 1 (length
                               (ethereum-lisp.snap:snap-account-range-accounts
                                response))))
                     (is (plusp
                          (length
                           (ethereum-lisp.snap:snap-account-range-proof
                            response)))))
                   (progn
                     (is (null
                          (ethereum-lisp.snap:snap-account-range-accounts
                           response)))
                     (is (null
                          (ethereum-lisp.snap:snap-account-range-proof
                           response)))))))))

(deftest eth-peer-run-session-omits-unknown-snap-code-hashes
  (:layer :unit :module :p2p)
  ;; Pinned geth 101035a1 TestSnapGetByteCodes lines 466-484 requires state
  ;; roots, repeated unknown hashes, and the empty trie root to produce no items.
  (let* ((state (make-state-db))
         (database (make-memory-key-value-database))
         (peer (ethereum-lisp.eth-sync::%make-eth-peer))
         (address (address-from-hex
                   "0x0000000000000000000000000000000000001234"))
         (backend nil)
         (read-symbol 'ethereum-lisp.eth-sync:eth-peer-read-once)
         (send-symbol 'ethereum-lisp.eth-sync:eth-peer-send-snap)
         (real-read (fdefinition read-symbol))
         (real-send (fdefinition send-symbol))
         (empty-root (hash32-bytes +empty-trie-hash+))
         (state-root nil)
         (payloads nil)
         (sent '()))
    (state-db-set-account state address (make-state-account :balance 1))
    (setf state-root (hash32-bytes (state-db-root state))
          backend
          (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
           database state)
          payloads
          (mapcar
           (lambda (request)
             (ethereum-lisp.snap:encode-snap-message
              ethereum-lisp.snap:+snap-message-get-bytecodes+ request))
           (list
            (ethereum-lisp.snap:make-snap-get-bytecodes
             84 (list empty-root state-root) 10000)
            (ethereum-lisp.snap:make-snap-get-bytecodes
             85 (list state-root state-root) 10000)
            (ethereum-lisp.snap:make-snap-get-bytecodes
             86 (list empty-root) 10000))))
    (is (not (bytes= empty-root state-root)))
    (setf (ethereum-lisp.eth-sync::eth-peer-snap-offset peer) 100
          (ethereum-lisp.eth-sync::eth-peer-snap-backend peer) backend)
    (unwind-protect
         (progn
           (setf (fdefinition read-symbol)
                 (lambda (candidate)
                   (is (eq peer candidate))
                   (values :snap
                           ethereum-lisp.snap:+snap-message-get-bytecodes+
                           (pop payloads))))
           (setf (fdefinition send-symbol)
                 (lambda (candidate message-id encoded)
                   (is (eq peer candidate))
                   (push
                    (list
                     message-id
                     (ethereum-lisp.snap:decode-snap-message
                      message-id encoded))
                    sent)))
           (multiple-value-bind (actions reason)
               (eth-peer-run-session
                peer :readable-function (lambda (timeout)
                                          (declare (ignore timeout))
                                          (not (null payloads)))
                :max-actions 3)
             (is (= 3 actions))
             (is (eq :max-actions reason))))
      (setf (fdefinition read-symbol) real-read
            (fdefinition send-symbol) real-send))
    (setf sent (nreverse sent))
    (is (= 3 (length sent)))
    (loop for response-entry in sent
          for request-id in '(84 85 86)
          do (is (= ethereum-lisp.snap:+snap-message-bytecodes+
                    (first response-entry)))
             (let ((response (second response-entry)))
               (is (= request-id
                      (ethereum-lisp.snap:snap-bytecodes-id response)))
               (is (null
                    (ethereum-lisp.snap:snap-bytecodes-codes response)))))))

(deftest eth-peer-run-session-serves-the-empty-snap-code-hash
  (:layer :unit :module :p2p)
  ;; Pinned geth 101035a1 TestSnapGetByteCodes lines 486-490 requires one
  ;; zero-length response item, rather than omitting the empty code hash.
  (let* ((state (make-state-db))
         (database (make-memory-key-value-database))
         (peer (ethereum-lisp.eth-sync::%make-eth-peer))
         (backend
           (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
            database state))
         (read-symbol 'ethereum-lisp.eth-sync:eth-peer-read-once)
         (send-symbol 'ethereum-lisp.eth-sync:eth-peer-send-snap)
         (real-read (fdefinition read-symbol))
         (real-send (fdefinition send-symbol))
         (sent nil)
         (request
           (ethereum-lisp.snap:make-snap-get-bytecodes
            84 (list (hash32-bytes +empty-code-hash+)) 10000))
         (payload
           (ethereum-lisp.snap:encode-snap-message
            ethereum-lisp.snap:+snap-message-get-bytecodes+ request)))
    (setf (ethereum-lisp.eth-sync::eth-peer-snap-offset peer) 100
          (ethereum-lisp.eth-sync::eth-peer-snap-backend peer) backend)
    (unwind-protect
         (progn
           (setf (fdefinition read-symbol)
                 (lambda (candidate)
                   (is (eq peer candidate))
                   (values :snap
                           ethereum-lisp.snap:+snap-message-get-bytecodes+
                           payload)))
           (setf (fdefinition send-symbol)
                 (lambda (candidate message-id encoded)
                   (is (eq peer candidate))
                   (setf sent
                         (list
                          message-id
                          (ethereum-lisp.snap:decode-snap-message
                           message-id encoded)))))
           (multiple-value-bind (actions reason)
               (eth-peer-run-session
                peer :readable-function (lambda (timeout)
                                          (declare (ignore timeout)) t)
                :max-actions 1)
             (is (= 1 actions))
             (is (eq :max-actions reason))))
      (setf (fdefinition read-symbol) real-read
            (fdefinition send-symbol) real-send))
    (is sent)
    (is (= ethereum-lisp.snap:+snap-message-bytecodes+ (first sent)))
    (let* ((response (second sent))
           (codes (ethereum-lisp.snap:snap-bytecodes-codes response)))
      (is (= 84 (ethereum-lisp.snap:snap-bytecodes-id response)))
      (is (= 1 (length codes)))
      (is (zerop (length (first codes)))))))

(deftest eth-peer-run-session-preserves-duplicate-empty-snap-code-hashes
  (:layer :unit :module :p2p)
  ;; Pinned geth 101035a1 TestSnapGetByteCodes lines 492-496 requires one
  ;; zero-length response item for every duplicate empty code hash requested.
  (let* ((state (make-state-db))
         (database (make-memory-key-value-database))
         (peer (ethereum-lisp.eth-sync::%make-eth-peer))
         (backend
           (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
            database state))
         (read-symbol 'ethereum-lisp.eth-sync:eth-peer-read-once)
         (send-symbol 'ethereum-lisp.eth-sync:eth-peer-send-snap)
         (real-read (fdefinition read-symbol))
         (real-send (fdefinition send-symbol))
         (sent nil)
         (empty-hash (hash32-bytes +empty-code-hash+))
         (request
           (ethereum-lisp.snap:make-snap-get-bytecodes
            85 (list empty-hash empty-hash empty-hash) 10000))
         (payload
           (ethereum-lisp.snap:encode-snap-message
            ethereum-lisp.snap:+snap-message-get-bytecodes+ request)))
    (setf (ethereum-lisp.eth-sync::eth-peer-snap-offset peer) 100
          (ethereum-lisp.eth-sync::eth-peer-snap-backend peer) backend)
    (unwind-protect
         (progn
           (setf (fdefinition read-symbol)
                 (lambda (candidate)
                   (is (eq peer candidate))
                   (values :snap
                           ethereum-lisp.snap:+snap-message-get-bytecodes+
                           payload)))
           (setf (fdefinition send-symbol)
                 (lambda (candidate message-id encoded)
                   (is (eq peer candidate))
                   (setf sent
                         (list
                          message-id
                          (ethereum-lisp.snap:decode-snap-message
                           message-id encoded)))))
           (multiple-value-bind (actions reason)
               (eth-peer-run-session
                peer :readable-function (lambda (timeout)
                                          (declare (ignore timeout)) t)
                :max-actions 1)
             (is (= 1 actions))
             (is (eq :max-actions reason))))
      (setf (fdefinition read-symbol) real-read
            (fdefinition send-symbol) real-send))
    (is sent)
    (is (= ethereum-lisp.snap:+snap-message-bytecodes+ (first sent)))
    (let* ((response (second sent))
           (codes (ethereum-lisp.snap:snap-bytecodes-codes response)))
      (is (= 85 (ethereum-lisp.snap:snap-bytecodes-id response)))
      (is (= 3 (length codes)))
      (is (every (lambda (code) (zerop (length code))) codes)))))

(deftest eth-peer-run-session-serves-all-requested-snap-bytecodes
  (:layer :unit :module :p2p)
  ;; Pinned geth 101035a1 TestSnapGetByteCodes lines 498-503 requires all
  ;; available contract code bodies when the byte budget contains them.
  (let* ((state (make-state-db))
         (database (make-memory-key-value-database))
         (peer (ethereum-lisp.eth-sync::%make-eth-peer))
         (backend
           (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
            database state))
         (read-symbol 'ethereum-lisp.eth-sync:eth-peer-read-once)
         (send-symbol 'ethereum-lisp.eth-sync:eth-peer-send-snap)
         (real-read (fdefinition read-symbol))
         (real-send (fdefinition send-symbol))
         (sent nil)
         (codes (list #(1 2 3) #(4 5 6 7) #(8 9 10 11 12)))
         (hashes (mapcar #'keccak-256 codes))
         (request
           (ethereum-lisp.snap:make-snap-get-bytecodes 86 hashes 100000))
         (payload
           (ethereum-lisp.snap:encode-snap-message
            ethereum-lisp.snap:+snap-message-get-bytecodes+ request)))
    (loop for hash in hashes
          for code in codes
          do (kv-put-chain-record database :code hash code))
    (setf (ethereum-lisp.eth-sync::eth-peer-snap-offset peer) 100
          (ethereum-lisp.eth-sync::eth-peer-snap-backend peer) backend)
    (unwind-protect
         (progn
           (setf (fdefinition read-symbol)
                 (lambda (candidate)
                   (is (eq peer candidate))
                   (values :snap
                           ethereum-lisp.snap:+snap-message-get-bytecodes+
                           payload)))
           (setf (fdefinition send-symbol)
                 (lambda (candidate message-id encoded)
                   (is (eq peer candidate))
                   (setf sent
                         (list
                          message-id
                          (ethereum-lisp.snap:decode-snap-message
                           message-id encoded)))))
           (multiple-value-bind (actions reason)
               (eth-peer-run-session
                peer :readable-function (lambda (timeout)
                                          (declare (ignore timeout)) t)
                :max-actions 1)
             (is (= 1 actions))
             (is (eq :max-actions reason))))
      (setf (fdefinition read-symbol) real-read
            (fdefinition send-symbol) real-send))
    (is sent)
    (is (= ethereum-lisp.snap:+snap-message-bytecodes+ (first sent)))
    (let* ((response (second sent))
           (actual (ethereum-lisp.snap:snap-bytecodes-codes response)))
      (is (= 86 (ethereum-lisp.snap:snap-bytecodes-id response)))
      (is (= 3 (length actual)))
      (loop for wanted in codes
            for body in actual
            do (is (bytes= wanted body))))))

(deftest eth-peer-run-session-serves-first-snap-bytecode-over-soft-limit
  (:layer :unit :module :p2p)
  ;; Pinned geth 101035a1 TestSnapGetByteCodes lines 505-516 requires one
  ;; available code even when its body exceeds a one-byte or zero-byte budget.
  (let* ((state (make-state-db))
         (database (make-memory-key-value-database))
         (peer (ethereum-lisp.eth-sync::%make-eth-peer))
         (backend
           (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
            database state))
         (read-symbol 'ethereum-lisp.eth-sync:eth-peer-read-once)
         (send-symbol 'ethereum-lisp.eth-sync:eth-peer-send-snap)
         (real-read (fdefinition read-symbol))
         (real-send (fdefinition send-symbol))
         (codes (list #(1 2 3) #(4 5 6 7) #(8 9 10 11 12)))
         (hashes (mapcar #'keccak-256 codes))
         (requests
           (list
            (ethereum-lisp.snap:make-snap-get-bytecodes 87 hashes 1)
            (ethereum-lisp.snap:make-snap-get-bytecodes 88 hashes 0)))
         (payloads
           (mapcar
            (lambda (request)
              (ethereum-lisp.snap:encode-snap-message
               ethereum-lisp.snap:+snap-message-get-bytecodes+ request))
            requests))
         (sent '()))
    (loop for hash in hashes
          for code in codes
          do (kv-put-chain-record database :code hash code))
    (setf (ethereum-lisp.eth-sync::eth-peer-snap-offset peer) 100
          (ethereum-lisp.eth-sync::eth-peer-snap-backend peer) backend)
    (unwind-protect
         (progn
           (setf (fdefinition read-symbol)
                 (lambda (candidate)
                   (is (eq peer candidate))
                   (values :snap
                           ethereum-lisp.snap:+snap-message-get-bytecodes+
                           (pop payloads))))
           (setf (fdefinition send-symbol)
                 (lambda (candidate message-id encoded)
                   (is (eq peer candidate))
                   (push
                    (list
                     message-id
                     (ethereum-lisp.snap:decode-snap-message
                      message-id encoded))
                    sent)))
           (multiple-value-bind (actions reason)
               (eth-peer-run-session
                peer :readable-function (lambda (timeout)
                                          (declare (ignore timeout))
                                          (not (null payloads)))
                :max-actions 2)
             (is (= 2 actions))
             (is (eq :max-actions reason))))
      (setf (fdefinition read-symbol) real-read
            (fdefinition send-symbol) real-send))
    (setf sent (nreverse sent))
    (is (= 2 (length sent)))
    (loop for response-entry in sent
          for request-id in '(87 88)
          do (is (= ethereum-lisp.snap:+snap-message-bytecodes+
                    (first response-entry)))
             (let* ((response (second response-entry))
                    (actual
                      (ethereum-lisp.snap:snap-bytecodes-codes response)))
               (is (= request-id
                      (ethereum-lisp.snap:snap-bytecodes-id response)))
               (is (= 1 (length actual)))
               (is (bytes= (first codes) (first actual)))))))

(deftest eth-peer-run-session-preserves-duplicate-snap-code-hashes
  (:layer :unit :module :p2p)
  ;; Pinned geth 101035a1 TestSnapGetByteCodes lines 518-523 requires one
  ;; response body for every repeated request of an available non-empty code.
  (let* ((state (make-state-db))
         (database (make-memory-key-value-database))
         (peer (ethereum-lisp.eth-sync::%make-eth-peer))
         (backend
           (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
            database state))
         (read-symbol 'ethereum-lisp.eth-sync:eth-peer-read-once)
         (send-symbol 'ethereum-lisp.eth-sync:eth-peer-send-snap)
         (real-read (fdefinition read-symbol))
         (real-send (fdefinition send-symbol))
         (sent nil)
         (code #(1 2 3 4))
         (code-hash (keccak-256 code))
         (request
           (ethereum-lisp.snap:make-snap-get-bytecodes
            89 (loop repeat 4 collect code-hash) 1000))
         (payload
           (ethereum-lisp.snap:encode-snap-message
            ethereum-lisp.snap:+snap-message-get-bytecodes+ request)))
    (kv-put-chain-record database :code code-hash code)
    (setf (ethereum-lisp.eth-sync::eth-peer-snap-offset peer) 100
          (ethereum-lisp.eth-sync::eth-peer-snap-backend peer) backend)
    (unwind-protect
         (progn
           (setf (fdefinition read-symbol)
                 (lambda (candidate)
                   (is (eq peer candidate))
                   (values :snap
                           ethereum-lisp.snap:+snap-message-get-bytecodes+
                           payload)))
           (setf (fdefinition send-symbol)
                 (lambda (candidate message-id encoded)
                   (is (eq peer candidate))
                   (setf sent
                         (list
                          message-id
                          (ethereum-lisp.snap:decode-snap-message
                           message-id encoded)))))
           (multiple-value-bind (actions reason)
               (eth-peer-run-session
                peer :readable-function (lambda (timeout)
                                          (declare (ignore timeout)) t)
                :max-actions 1)
             (is (= 1 actions))
             (is (eq :max-actions reason))))
      (setf (fdefinition read-symbol) real-read
            (fdefinition send-symbol) real-send))
    (is sent)
    (is (= ethereum-lisp.snap:+snap-message-bytecodes+ (first sent)))
    (let* ((response (second sent))
           (actual (ethereum-lisp.snap:snap-bytecodes-codes response)))
      (is (= 89 (ethereum-lisp.snap:snap-bytecodes-id response)))
      (is (= 4 (length actual)))
      (is (every (lambda (body) (bytes= code body)) actual)))))

(deftest eth-peer-run-session-answers-a-keepalive-and-still-returns
  (:layer :integration :module :p2p :requires-local-sockets t)
  ;; THE regression for the reader split. A peer that sends only a devp2p Ping
  ;; produces no subprotocol message ever, so a session built on the looping
  ;; ETH-WIRE-READ blocks inside it forever: the Pong goes out, but the loop
  ;; never returns, STOP-P is never consulted again and no periodic work runs.
  ;; The pump therefore runs on a thread here and the join is bounded, so a
  ;; regression fails red instead of stopping the whole suite.
  (let* ((config (eth-sync-test-config))
         (server-static
          #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (client-static
          #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (server-static-pub (secp256k1-private-key-public-key server-static))
         (listener (make-eth-sync-socket-listener :host "127.0.0.1" :port 0))
         (server-saw nil)
         (server-error nil))
    (flet ((status ()
             (eth-build-status config *eth-sync-test-genesis* 0 0
                               *eth-sync-test-best* 0)))
      (unwind-protect
           (let ((server-thread
                   (sb-thread:make-thread
                    (lambda ()
                      (handler-case
                          (multiple-value-bind (socket host port)
                              (eth-sync-listener-accept listener
                                                        :timeout-seconds 10)
                            (declare (ignore host port))
                            (when socket
                              (unwind-protect
                                   (let ((peer (eth-sync-accept-peer
                                                socket server-static (status))))
                                     ;; Only a keepalive. Never any eth message.
                                     (rlpx-send-ping (eth-peer-connection peer))
                                     (multiple-value-bind (kind id payload)
                                         (eth-peer-read-once peer)
                                       (declare (ignore payload))
                                       (setf server-saw (list kind id))))
                                (ignore-errors
                                 (sb-bsd-sockets:socket-close socket)))))
                        (error (condition) (setf server-error condition))))
                    :name "eth-pump-test-server")))
             (multiple-value-bind (peer socket)
                 (eth-sync-connect-peer "127.0.0.1"
                                        (eth-sync-listener-port listener)
                                        server-static-pub client-static (status))
               (unwind-protect
                    ;; The connection's own stream, never a second one over the
                    ;; same descriptor: two buffered streams on one socket would
                    ;; each hold half a frame.
                    (let* ((stream (rlpx-connection-stream
                                    (eth-peer-connection peer)))
                           (reads 0)
                           (result nil)
                           (pump-thread
                             (sb-thread:make-thread
                              (lambda ()
                                (handler-case
                                    (setf result
                                          (multiple-value-list
                                           (eth-peer-run-session
                                            peer
                                            :readable-function
                                            (lambda (timeout)
                                              ;; Buffered bytes are invisible to
                                              ;; a bare descriptor poll, so the
                                              ;; gate asks the stream first.
                                              (or (listen stream)
                                                  (sb-sys:wait-until-fd-usable
                                                   (sb-sys:fd-stream-fd stream)
                                                   :input timeout nil)))
                                            :on-event
                                            (lambda (action)
                                              (when (eq action :read)
                                                (incf reads)))
                                            ;; Stop once the keepalive has been
                                            ;; handled: reaching this at all is
                                            ;; the property under test.
                                            :stop-p (lambda () (plusp reads))
                                            :max-actions 50)))
                                  (error (condition) (setf result condition))))
                              :name "eth-pump-test-pump")))
                      ;; The session must come back. Against the looping reader
                      ;; this join times out and the assertion fails red.
                      (is (not (eq :timeout
                                   (sb-thread:join-thread pump-thread
                                                          :timeout 15
                                                          :default :timeout))))
                      (when (typep result 'condition)
                        (error "pump session failed: ~A" result))
                      (is (listp result))
                      (is (eq :stop (second result)))
                      (is (= 1 reads)))
                 (ignore-errors (sb-bsd-sockets:socket-close socket))))
             (is (not (eq :timeout (sb-thread:join-thread server-thread
                                                          :timeout 15
                                                          :default :timeout))))
             (when server-error
               (error "pump test server side failed: ~A" server-error))
             ;; The pump answered the keepalive rather than ignoring it.
             (is (equal (list :base +devp2p-message-pong+) server-saw)))
        (eth-sync-listener-close listener)))))
