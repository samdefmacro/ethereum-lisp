(in-package #:ethereum-lisp.test)

;;;; The dial scheduler, as truth tables.
;;;;
;;;; Every test here is pure: no socket, no thread, no sleep, and `now` is an
;;;; integer the test chooses. That is the point of the design — a redial after
;;;; a cooldown is checked by passing a larger number, not by waiting.

(defun dial-test-registry (&key (max-peers 9) (self "ff") (base 10) (ceiling 100)
                                (max-doublings 3) (max-active 8))
  "Returns (VALUES REGISTRY TABLE) with small tuning numbers."
  (values (ethereum-lisp.cli:make-devnet-dial-registry :base-cooldown base :ceiling ceiling
                                     :max-doublings max-doublings
                                     :max-active-dials max-active)
          (ethereum-lisp.cli:make-devnet-peer-table :self-id-hex self :max-peers max-peers)))

(defun dial-test-connect (table id-hex direction now)
  (ethereum-lisp.cli:devnet-peer-table-admit
   table
   (ethereum-lisp.cli:make-devnet-peer-entry :id-hex id-hex :direction direction
                           :remote-host "127.0.0.1" :remote-port 30303)
   now))

(deftest devnet-dial-verdict-truth-table
  (:layer :unit :module :devnet)
  (multiple-value-bind (registry table) (dial-test-registry)
    ;; A peer we have never heard of is not dialed.
    (is (eq :unknown (ethereum-lisp.cli:devnet-dial-verdict registry table "aa" 0)))
    (ethereum-lisp.cli:devnet-dial-registry-put-static registry "aa" "enode://aa@127.0.0.1:30303")
    (is (eq :dial (ethereum-lisp.cli:devnet-dial-verdict registry table "aa" 0)))
    ;; Ourselves, which nothing in the tree checked before: --peer pointing at
    ;; our own enode used to dial us in a loop.
    (ethereum-lisp.cli:devnet-dial-registry-put-static registry "ff" "enode://ff@127.0.0.1:30303")
    (is (eq :self (ethereum-lisp.cli:devnet-dial-verdict registry table "ff" 0)))
    ;; A dial already in flight.
    (ethereum-lisp.cli:devnet-dial-registry-mark-dialing registry "aa" 0)
    (is (eq :already-dialing (ethereum-lisp.cli:devnet-dial-verdict registry table "aa" 0)))
    ;; Connected wins over cooling down, and is direction-blind: this clause is
    ;; what recognises a peer that dialed US while we were dialing IT.
    (ethereum-lisp.cli:devnet-dial-registry-mark-done registry "aa" 1 :outcome :failed)
    (dial-test-connect table "aa" :inbound 1)
    (is (eq :already-connected (ethereum-lisp.cli:devnet-dial-verdict registry table "aa" 1)))
    (ethereum-lisp.cli:devnet-peer-table-remove table "aa")
    ;; Now only the cooldown stands in the way, and it lifts on its own.
    (is (eq :cooling-down (ethereum-lisp.cli:devnet-dial-verdict registry table "aa" 1)))
    (is (eq :dial (ethereum-lisp.cli:devnet-dial-verdict registry table "aa" 1000)))))

(deftest devnet-dial-backoff-escalates-to-a-ceiling
  (:layer :unit :module :devnet)
  (multiple-value-bind (registry table) (dial-test-registry :base 10 :ceiling 100
                                                            :max-doublings 3)
    (declare (ignore table))
    (is (= 10 (ethereum-lisp.cli:devnet-dial-backoff-seconds registry 0)))
    (is (= 20 (ethereum-lisp.cli:devnet-dial-backoff-seconds registry 1)))
    (is (= 40 (ethereum-lisp.cli:devnet-dial-backoff-seconds registry 2)))
    (is (= 80 (ethereum-lisp.cli:devnet-dial-backoff-seconds registry 3)))
    ;; Past the doubling limit it stops growing rather than escalating forever...
    (is (= 80 (ethereum-lisp.cli:devnet-dial-backoff-seconds registry 4)))
    (is (= 80 (ethereum-lisp.cli:devnet-dial-backoff-seconds registry 50))))
  ;; ...and the ceiling clamps it even when the doublings would exceed it.
  (multiple-value-bind (registry table) (dial-test-registry :base 10 :ceiling 25
                                                            :max-doublings 5)
    (declare (ignore table))
    (is (= 25 (ethereum-lisp.cli:devnet-dial-backoff-seconds registry 3)))))

(deftest devnet-dial-cooldown-is-stamped-when-the-dial-starts
  (:layer :unit :module :devnet)
  ;; The rule the whole design turns on. A peer held for a long session is
  ;; instantly redialable; a peer that flaps is throttled -- both from the same
  ;; arithmetic, with no per-outcome special case.
  (multiple-value-bind (registry table) (dial-test-registry :base 10)
    (ethereum-lisp.cli:devnet-dial-registry-put-static registry "aa" "enode://aa@127.0.0.1:30303")
    ;; A long session: dialed at 100, disconnected at 1000.
    (ethereum-lisp.cli:devnet-dial-registry-mark-dialing registry "aa" 100)
    (ethereum-lisp.cli:devnet-dial-registry-mark-connected registry "aa" 101)
    (ethereum-lisp.cli:devnet-dial-registry-mark-done registry "aa" 1000 :outcome :disconnected)
    (let ((candidate (ethereum-lisp.cli:devnet-dial-registry-candidate registry "aa")))
      (is (eq :idle (ethereum-lisp.cli:devnet-dial-candidate-state candidate)))
      (is (= 0 (ethereum-lisp.cli:devnet-dial-candidate-failures candidate)))
      ;; Eligible again from 110, which is long past: redial is immediate.
      (is (= 110 (ethereum-lisp.cli:devnet-dial-candidate-next-eligible-at candidate))))
    (is (eq :dial (ethereum-lisp.cli:devnet-dial-verdict registry table "aa" 1000)))
    ;; A flapping peer: dialed at 1000, gone at 1001.
    (ethereum-lisp.cli:devnet-dial-registry-mark-dialing registry "aa" 1000)
    (ethereum-lisp.cli:devnet-dial-registry-mark-done registry "aa" 1001 :outcome :failed)
    (is (eq :cooling-down (ethereum-lisp.cli:devnet-dial-verdict registry table "aa" 1001)))
    ;; One failure: 10 * 2^1 = 20 seconds from the dial START.
    (is (= 1020 (ethereum-lisp.cli:devnet-dial-candidate-next-eligible-at
                 (ethereum-lisp.cli:devnet-dial-registry-candidate registry "aa"))))
    (is (eq :dial (ethereum-lisp.cli:devnet-dial-verdict registry table "aa" 1020)))
    ;; A refusal counts exactly as a failure does.
    (ethereum-lisp.cli:devnet-dial-registry-mark-dialing registry "aa" 2000)
    (ethereum-lisp.cli:devnet-dial-registry-mark-done registry "aa" 2001 :outcome :refused)
    (is (= 2 (ethereum-lisp.cli:devnet-dial-candidate-failures
              (ethereum-lisp.cli:devnet-dial-registry-candidate registry "aa"))))
    ;; And marking an idle candidate done again does not corrupt it.
    (ethereum-lisp.cli:devnet-dial-registry-mark-done registry "aa" 2002 :outcome :failed)
    (is (eq :idle (ethereum-lisp.cli:devnet-dial-candidate-state
                   (ethereum-lisp.cli:devnet-dial-registry-candidate registry "aa"))))))

(deftest devnet-dial-slots-leave-room-to-be-reached
  (:layer :unit :module :devnet)
  ;; Dialing may not fill every slot: a node that dials itself full cannot be
  ;; reached from outside, which is what the inbound wave exists to allow.
  (multiple-value-bind (registry table) (dial-test-registry :max-peers 9)
    ;; 9 peers, ratio 3 => at most 3 held by dialing.
    (is (= 3 (ethereum-lisp.cli:devnet-dial-free-slots registry table)))
    (dial-test-connect table "01" :outbound 0)
    (is (= 2 (ethereum-lisp.cli:devnet-dial-free-slots registry table)))
    ;; Inbound peers do not consume dial slots.
    (dial-test-connect table "02" :inbound 0)
    (is (= 2 (ethereum-lisp.cli:devnet-dial-free-slots registry table)))
    (dial-test-connect table "03" :outbound 0)
    (dial-test-connect table "04" :outbound 0)
    (is (= 0 (ethereum-lisp.cli:devnet-dial-free-slots registry table)))
    (is (= 3 (ethereum-lisp.cli:devnet-peer-table-count-by-direction table :outbound)))
    (is (= 1 (ethereum-lisp.cli:devnet-peer-table-count-by-direction table :inbound))))
  ;; Dials in flight count against the budget too.
  (multiple-value-bind (registry table) (dial-test-registry :max-peers 9)
    (dolist (id '("a1" "a2" "a3" "a4"))
      (ethereum-lisp.cli:devnet-dial-registry-put-static registry id "enode://x@127.0.0.1:1"))
    (ethereum-lisp.cli:devnet-dial-registry-mark-dialing registry "a1" 0)
    (is (= 2 (ethereum-lisp.cli:devnet-dial-free-slots registry table)))
    (is (= 1 (ethereum-lisp.cli:devnet-dial-registry-dialing-count registry)))
    (is (eq :no-slot
            (progn (ethereum-lisp.cli:devnet-dial-registry-mark-dialing registry "a2" 0)
                   (ethereum-lisp.cli:devnet-dial-registry-mark-dialing registry "a3" 0)
                   (ethereum-lisp.cli:devnet-dial-verdict registry table "a4" 0)))))
  ;; A peer limit of zero means no dialing at all, not unlimited.
  (multiple-value-bind (registry table) (dial-test-registry :max-peers 0)
    (ethereum-lisp.cli:devnet-dial-registry-put-static registry "aa" "enode://aa@127.0.0.1:1")
    (is (= 0 (ethereum-lisp.cli:devnet-dial-free-slots registry table)))
    (is (eq :no-slot (ethereum-lisp.cli:devnet-dial-verdict registry table "aa" 0))))
  ;; The hard cap wins over a generous ratio.
  (multiple-value-bind (registry table) (dial-test-registry :max-peers 600
                                                            :max-active 8)
    (is (= 8 (ethereum-lisp.cli:devnet-dial-free-slots registry table)))))

(deftest devnet-dial-plan-is-deterministic-and-bounded
  (:layer :unit :module :devnet)
  (multiple-value-bind (registry table) (dial-test-registry :max-peers 9)
    ;; Configured peers come before discovered ones whatever the insert order.
    (ethereum-lisp.cli:devnet-dial-registry-offer-dynamic registry "d1" "enode://d1@127.0.0.1:1")
    (ethereum-lisp.cli:devnet-dial-registry-put-static registry "s2" "enode://s2@127.0.0.1:1")
    (ethereum-lisp.cli:devnet-dial-registry-offer-dynamic registry "d0" "enode://d0@127.0.0.1:1")
    (ethereum-lisp.cli:devnet-dial-registry-put-static registry "s1" "enode://s1@127.0.0.1:1")
    (let ((plan (mapcar #'ethereum-lisp.cli:devnet-dial-candidate-id-hex
                        (ethereum-lisp.cli:devnet-dial-registry-plan registry table 0))))
      ;; Three slots, statics first, ties broken by identity so the order never
      ;; depends on hash iteration.
      (is (equal '("s1" "s2" "d0") plan)))
    ;; Claiming the plan marks every candidate, so a second call plans nothing.
    (let ((claimed (ethereum-lisp.cli:devnet-dial-registry-claim-plan registry table 0)))
      (is (= 3 (length claimed)))
      (is (= 3 (ethereum-lisp.cli:devnet-dial-registry-dialing-count registry)))
      (is (null (ethereum-lisp.cli:devnet-dial-registry-plan registry table 0))))))

(deftest devnet-dial-registry-forgets-dead-discovered-peers-only
  (:layer :unit :module :devnet)
  ;; Discovery returns every node it has SEEN, not only the ones that answered,
  ;; so the candidate set has to be bounded or it grows forever.
  (multiple-value-bind (registry table) (dial-test-registry :base 10)
    (declare (ignore table))
    (ethereum-lisp.cli:devnet-dial-registry-offer-dynamic registry "d1" "enode://d1@127.0.0.1:1")
    (ethereum-lisp.cli:devnet-dial-registry-put-static registry "s1" "enode://s1@127.0.0.1:1")
    ;; Fail both past the forget threshold.
    (dotimes (i (1+ ethereum-lisp.cli:+devnet-dial-dynamic-forget-failures+))
      (dolist (id '("d1" "s1"))
        (ethereum-lisp.cli:devnet-dial-registry-mark-dialing registry id (* i 1000))
        (ethereum-lisp.cli:devnet-dial-registry-mark-done registry id (* i 1000) :outcome :failed)))
    (is (= 1 (ethereum-lisp.cli:devnet-dial-registry-expire registry 100000)))
    ;; The discovered one is gone; the operator's stays, however often it fails.
    (is (null (ethereum-lisp.cli:devnet-dial-registry-candidate registry "d1")))
    (is (ethereum-lisp.cli:devnet-dial-registry-candidate registry "s1"))
    ;; A candidate still cooling down is not expired even if it has failed a lot.
    (ethereum-lisp.cli:devnet-dial-registry-offer-dynamic registry "d2" "enode://d2@127.0.0.1:1")
    (dotimes (i (1+ ethereum-lisp.cli:+devnet-dial-dynamic-forget-failures+))
      (ethereum-lisp.cli:devnet-dial-registry-mark-dialing registry "d2" 200000)
      (ethereum-lisp.cli:devnet-dial-registry-mark-done registry "d2" 200000 :outcome :failed))
    (is (= 0 (ethereum-lisp.cli:devnet-dial-registry-expire registry 200000)))
    (is (ethereum-lisp.cli:devnet-dial-registry-candidate registry "d2")))
  ;; Re-offering never disturbs an existing candidate's cooldown, and promoting
  ;; a discovered peer to configured keeps its history.
  (multiple-value-bind (registry table) (dial-test-registry)
    (declare (ignore table))
    (ethereum-lisp.cli:devnet-dial-registry-offer-dynamic registry "d1" "enode://d1@127.0.0.1:1")
    (ethereum-lisp.cli:devnet-dial-registry-mark-dialing registry "d1" 500)
    (ethereum-lisp.cli:devnet-dial-registry-mark-done registry "d1" 501 :outcome :failed)
    (let ((before (ethereum-lisp.cli:devnet-dial-candidate-next-eligible-at
                   (ethereum-lisp.cli:devnet-dial-registry-candidate registry "d1"))))
      (is (null (ethereum-lisp.cli:devnet-dial-registry-offer-dynamic registry "d1" "enode://x@1:1")))
      (ethereum-lisp.cli:devnet-dial-registry-put-static registry "d1" "enode://d1@127.0.0.1:1")
      (let ((candidate (ethereum-lisp.cli:devnet-dial-registry-candidate registry "d1")))
        (is (eq :static (ethereum-lisp.cli:devnet-dial-candidate-kind candidate)))
        (is (= 1 (ethereum-lisp.cli:devnet-dial-candidate-failures candidate)))
        (is (= before (ethereum-lisp.cli:devnet-dial-candidate-next-eligible-at candidate)))))))

;;;; The dialer end to end. Every join below is bounded and asserted on: the
;;;; unit and integration layers have no per-test timeout, so a test that can
;;;; block does not fail, it stops the run.

(deftest devnet-dialer-holds-an-outbound-session-and-shuts-down
  (:layer :integration :module :devnet :requires-local-sockets t)
  ;; The deliverable of the wave: a dialed peer becomes a LONG-LIVED session on
  ;; the same pump an accepted one gets, instead of the old dial-download-hangup.
  ;; Two real nodes, one listening and one dialing, then both told to stop.
  (let* ((listener-key #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (server (ethereum-lisp.cli:make-devnet-node
                  :genesis-json *eth-sync-paris-genesis-json*
                  :port 0 :public-port 0
                  :p2p-host "127.0.0.1" :p2p-port 0
                  :max-peers 4 :node-key listener-key))
         (listener (make-eth-sync-socket-listener :host "127.0.0.1" :port 0))
         (server-controller (ethereum-lisp.cli::make-devnet-shutdown-controller))
         (client-controller (ethereum-lisp.cli::make-devnet-shutdown-controller))
         (server-error nil)
         (client-error nil)
         (client nil))
    (setf (ethereum-lisp.cli::devnet-node-p2p-port server)
          (eth-sync-listener-port listener))
    (unwind-protect
         (multiple-value-bind (accept-thread server-sessions)
             (ethereum-lisp.cli:devnet-start-p2p-listener-thread
              server listener server-controller
              (lambda (condition) (setf server-error condition)))
           ;; The dialer is pointed at the listener's real enode.
           (setf client
                 (ethereum-lisp.cli:make-devnet-node
                  :genesis-json *eth-sync-paris-genesis-json*
                  :port 0 :public-port 0 :max-peers 4
                  :peers (list (ethereum-lisp.cli::devnet-node-enode server))))
           (multiple-value-bind (dial-thread client-sessions)
               (ethereum-lisp.cli:devnet-start-dial-scheduler-thread
                client client-controller
                (lambda (condition) (setf client-error condition)))
             (is (not (null dial-thread)))
             (let ((server-table (ethereum-lisp.cli:devnet-node-peer-table server))
                   (client-table (ethereum-lisp.cli:devnet-node-peer-table client)))
               ;; Both sides record the peer, in opposite directions.
               (loop repeat 150
                     until (and (plusp (ethereum-lisp.cli:devnet-peer-table-count
                                        server-table))
                                (plusp (ethereum-lisp.cli:devnet-peer-table-count
                                        client-table)))
                     do (sleep 0.1))
               (is (= 1 (ethereum-lisp.cli:devnet-peer-table-count server-table)))
               (is (= 1 (ethereum-lisp.cli:devnet-peer-table-count client-table)))
               (is (= 1 (ethereum-lisp.cli:devnet-peer-table-count-by-direction
                         client-table :outbound)))
               (is (= 1 (ethereum-lisp.cli:devnet-peer-table-count-by-direction
                         server-table :inbound)))
               ;; THE point: it is still held a moment later. The old one-shot
               ;; dialer had disconnected by now.
               (sleep 1.5)
               (is (= 1 (ethereum-lisp.cli:devnet-peer-table-count client-table)))
               (is (= 1 (ethereum-lisp.cli:devnet-peer-table-count server-table)))
               ;; The peer is reported outbound, with a negotiated eth version.
               (let ((entry (first (ethereum-lisp.cli:devnet-peer-table-snapshot
                                    client-table))))
                 (is (eq :outbound (getf entry :direction)))
                 (is (member (getf entry :eth-version) '(68 69))))
               ;; And the dial registry knows it owns that connection.
               (is (eq :connected
                       (ethereum-lisp.cli:devnet-dial-candidate-state
                        (first (loop for id being the hash-keys
                                       of (ethereum-lisp.cli::devnet-dial-registry-candidates
                                           (ethereum-lisp.cli:devnet-node-dial-registry client))
                                     using (hash-value candidate)
                                     collect candidate))))))
             ;; Now stop both, and assert every thread comes back.
             (ethereum-lisp.cli:devnet-shutdown-request client-controller)
             (ethereum-lisp.cli:devnet-shutdown-request server-controller)
             (is (not (eq :timeout (sb-thread:join-thread dial-thread :timeout 15
                                                                      :default :timeout))))
             (ethereum-lisp.cli:devnet-join-peer-sessions client-sessions :timeout 10)
             (dolist (thread (funcall client-sessions))
               (is (not (sb-thread:thread-alive-p thread))))
             (is (not (eq :timeout (sb-thread:join-thread accept-thread :timeout 15
                                                                       :default :timeout))))
             (ethereum-lisp.cli:devnet-join-peer-sessions server-sessions :timeout 10)
             (dolist (thread (funcall server-sessions))
               (is (not (sb-thread:thread-alive-p thread))))
             (is (null client-error))
             (is (null server-error))))
      (eth-sync-listener-close listener))))

(deftest devnet-dial-scheduler-does-not-start-without-anything-to-dial
  (:layer :unit :module :devnet)
  ;; A node with no configured peers, no bootnodes and no listener has nothing
  ;; to dial and no way to be told about one, so it pays for no thread at all.
  (let ((node (ethereum-lisp.cli:make-devnet-node
               :genesis-json *eth-sync-paris-genesis-json*
               :port 0 :public-port 0)))
    (is (null (ethereum-lisp.cli:devnet-start-dial-scheduler-thread
               node (ethereum-lisp.cli::make-devnet-shutdown-controller)
               (lambda (condition) (declare (ignore condition)))))))
  ;; A listener alone is reason enough: admin_addPeer can add one at runtime.
  (let ((node (ethereum-lisp.cli:make-devnet-node
               :genesis-json *eth-sync-paris-genesis-json*
               :port 0 :public-port 0 :p2p-host "127.0.0.1" :p2p-port 30399))
        (controller (ethereum-lisp.cli::make-devnet-shutdown-controller)))
    (multiple-value-bind (thread sessions)
        (ethereum-lisp.cli:devnet-start-dial-scheduler-thread
         node controller (lambda (condition) (declare (ignore condition))))
      (declare (ignore sessions))
      (is (not (null thread)))
      (ethereum-lisp.cli:devnet-shutdown-request controller)
      (is (not (eq :timeout (sb-thread:join-thread thread :timeout 15
                                                          :default :timeout)))))))

(deftest eth-sync-backfill-walks-back-to-common-ground
  (:layer :integration :module :p2p :requires-local-sockets t)
  ;; Consensus-driven sync. The client hands us a block whose parent we do not
  ;; have, so it is buffered and nothing can execute it. The gap-fill walks
  ;; BACKWARDS from that parent by hash -- the only direction that works when
  ;; all we know is a hash somewhere ahead -- until it reaches a block we hold,
  ;; then executes forward.
  (multiple-value-bind (store config genesis-block)
      (eth-sync-make-seeded-store *eth-sync-paris-genesis-json*)
    (let* ((produced (coerce (eth-sync-produce-empty-blocks genesis-block config 5)
                             'vector))
           (genesis-hash (hash32-bytes (block-hash genesis-block)))
           (target (aref produced 4))
           (server-static
            #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
           (client-static
            #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
           (server-static-pub (secp256k1-private-key-public-key server-static))
           (listener (make-eth-sync-socket-listener :host "127.0.0.1" :port 0))
           (server-error nil)
           (imported '()))
      (flet ((status ()
               (eth-build-status config genesis-hash 5 0
                                 (hash32-bytes (block-hash target)) 0)))
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
                                                  socket server-static (status)
                                                  :serve-backend
                                                  (eth-serve-test-backend
                                                   (cons genesis-block
                                                         (coerce produced 'list))))))
                                       ;; Answer whatever the backfill asks
                                       ;; for. The client hangs up when it is
                                       ;; done, which reaches us as an EOF on
                                       ;; the next read -- expected, not a
                                       ;; failure, and the assertions that
                                       ;; matter are all on the client side.
                                       (ignore-errors
                                        (eth-peer-serve-loop peer
                                                             :max-messages 8)))
                                  (ignore-errors
                                   (sb-bsd-sockets:socket-close socket)))))
                          (error (condition) (setf server-error condition))))
                      :name "eth-backfill-test-server")))
               (multiple-value-bind (peer socket)
                   (eth-sync-connect-peer "127.0.0.1"
                                          (eth-sync-listener-port listener)
                                          server-static-pub client-static
                                          (eth-build-status config genesis-hash 0 0
                                                            genesis-hash 0))
                 (unwind-protect
                      ;; We hold only genesis; the target's PARENT is block 4.
                      (let ((filled (eth-sync-fill-gap
                                     peer
                                     (hash32-bytes
                                      (block-header-parent-hash
                                       (block-header target)))
                                     (lambda (hash)
                                       (and (chain-store-known-block
                                             store (make-hash32 hash))
                                            t))
                                     (lambda (block) (push block imported)))))
                        ;; Blocks 1..4: everything between genesis and the
                        ;; buffered block's parent.
                        (is (= 4 filled))
                        (setf imported (nreverse imported))
                        (is (equal '(1 2 3 4)
                                   (mapcar (lambda (block)
                                             (block-header-number
                                              (block-header block)))
                                           imported)))
                        ;; In execution order, each on the last -- which is the
                        ;; only order that can work.
                        (is (bytes= genesis-hash
                                    (hash32-bytes
                                     (block-header-parent-hash
                                      (block-header (first imported))))))
                        ;; And a gap-fill toward something we already hold is a
                        ;; no-op rather than a re-download.
                        (is (= 0 (eth-sync-fill-gap
                                  peer genesis-hash
                                  (lambda (hash)
                                    (bytes= hash genesis-hash))
                                  (lambda (block) (declare (ignore block))
                                    (error "must not import"))))))
                   (ignore-errors (sb-bsd-sockets:socket-close socket))))
               (is (not (eq :timeout (sb-thread:join-thread server-thread
                                                            :timeout 15
                                                            :default :timeout))))
               (when server-error
                 (error "backfill server side failed: ~A" server-error)))
          (eth-sync-listener-close listener))))))

(deftest devnet-chain-context-never-waits-for-the-store-guard
  (:layer :unit :module :devnet)
  ;; Discovery reads our fork id -- for the candidate filter, and for the record
  ;; we serve -- and it must never BLOCK to do it. The store guard is held for
  ;; the whole of a block import, so a background thread that waits on it does
  ;; not run slowly, it stops for as long as the node is busy, which is exactly
  ;; when peers matter.
  ;;
  ;; A regression test in the literal sense. The first version of the fork-id
  ;; filter took the guard here, and a live node under load then logged not one
  ;; crawl in half an hour: no error, no telemetry, just a parked thread. The
  ;; whole suite stayed green, because a test node's guard is never held long
  ;; enough for anyone to notice -- so the holder below is the test.
  (let ((node (ethereum-lisp.cli:make-devnet-node
               :genesis-json *eth-sync-paris-genesis-json*
               :port 0 :public-port 0)))
    ;; Warm the cache while the guard is free.
    (is (ethereum-lisp.cli::devnet-node-chain-context node))
    (let ((entered nil) (release nil) (elapsed nil))
      (let ((holder (sb-thread:make-thread
                     (lambda ()
                       ;; An unhandled condition in ANY thread takes the whole
                       ;; run down under `sbcl --script'.
                       (handler-case
                           (ethereum-lisp.cli::call-with-devnet-node-store-guard
                            node
                            (lambda ()
                              (setf entered t)
                              (loop until release do (sleep 0.01))))
                         (error () nil)))
                     :name "devnet-store-guard-holder")))
        (loop until entered do (sleep 0.01))
        (let ((start (get-internal-real-time)))
          ;; Still answers, from the cache, with the guard held against it.
          (is (ethereum-lisp.cli::devnet-node-chain-context node))
          (setf elapsed (/ (float (- (get-internal-real-time) start))
                           internal-time-units-per-second)))
        (setf release t)
        (sb-thread:join-thread holder))
      ;; Three orders of magnitude of slack: the claim is "did not wait for the
      ;; holder", not any particular speed.
      (is (< elapsed 1)))))
