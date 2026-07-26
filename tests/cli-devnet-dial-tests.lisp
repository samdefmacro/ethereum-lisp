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
