(in-package #:ethereum-lisp.test)

;;;; The bloom prefilter on log queries.
;;;;
;;;; A bloom answers one question definitively: a value it does NOT contain is
;;;; not in the block. The whole risk of using it is the reverse mistake --
;;;; ruling out a block that really does match -- so that is what these tests
;;;; are about.

(defun bloom-test-log (address-hex &rest topic-hexes)
  (make-log-entry :address (address-from-hex address-hex)
                  :topics (mapcar #'hash32-from-hex topic-hexes)
                  :data #(1 2 3)))

(defun bloom-test-block (logs)
  "A block whose header bloom really is the bloom of its receipts' logs."
  (let* ((receipt (make-receipt :status 1 :cumulative-gas-used 21000 :logs logs))
         (transaction (make-legacy-transaction :nonce 1 :gas-price 2
                                               :gas-limit 21000 :value 3
                                               :v 27 :r 4 :s 5)))
    (ethereum-lisp.blocks:make-block-from-parts
     :header (make-block-header :number 1 :difficulty 0 :gas-limit 30000000
                                :extra-data (make-byte-vector 0)
                                :logs-bloom (bloom-bytes
                                             (ethereum-lisp.blocks:receipts-logs-bloom (list receipt))))
     :transactions (list transaction)
     :receipts (list receipt))))

(defparameter *bloom-test-address* "0x00000000000000000000000000000000000000aa")
(defparameter *bloom-test-other-address* "0x00000000000000000000000000000000000000bb")
(defparameter *bloom-test-topic*
  "0x1111111111111111111111111111111111111111111111111111111111111111")
(defparameter *bloom-test-other-topic*
  "0x2222222222222222222222222222222222222222222222222222222222222222")

(deftest log-bloom-prefilter-never-excludes-a-matching-block
  (:layer :unit :module :rpc)
  ;; THE invariant. If any log in the block matches the filter, the bloom test
  ;; must say "maybe" -- a false negative here silently loses real results, and
  ;; would be invisible until somebody's event query came back empty.
  (let* ((block (bloom-test-block
                 (list (bloom-test-log *bloom-test-address* *bloom-test-topic*))))
         (address (address-from-hex *bloom-test-address*))
         (topic (hash32-from-hex *bloom-test-topic*)))
    ;; Every filter that genuinely matches must survive the prefilter.
    (dolist (filter (list (list nil nil)
                          (list (list address) nil)
                          (list nil (list (list topic)))
                          (list (list address) (list (list topic)))
                          ;; A wildcard first position with nothing after it.
                          (list (list address) (list nil))))
      (destructuring-bind (addresses topics) filter
        (is (ethereum-lisp.public-api::eth-rpc-block-bloom-may-match-p
             block addresses topics))
        ;; And the full path really does return the log.
        (is (= 1 (length (ethereum-lisp.public-api::eth-rpc-block-logs-object
                          block addresses topics))))))))

(deftest log-bloom-prefilter-rules-out-blocks-it-can
  (:layer :unit :module :rpc)
  ;; The point of the thing: a block that cannot match is skipped without
  ;; touching a receipt.
  (let* ((block (bloom-test-block
                 (list (bloom-test-log *bloom-test-address* *bloom-test-topic*))))
         (absent-address (address-from-hex *bloom-test-other-address*))
         (absent-topic (hash32-from-hex *bloom-test-other-topic*))
         (present-address (address-from-hex *bloom-test-address*)))
    ;; An address that is not in the block.
    (is (not (ethereum-lisp.public-api::eth-rpc-block-bloom-may-match-p
              block (list absent-address) nil)))
    ;; A topic that is not in the block.
    (is (not (ethereum-lisp.public-api::eth-rpc-block-bloom-may-match-p
              block nil (list (list absent-topic)))))
    ;; A present address AND an absent topic: every constrained position has to
    ;; be satisfiable, so this is still ruled out.
    (is (not (ethereum-lisp.public-api::eth-rpc-block-bloom-may-match-p
              block (list present-address) (list (list absent-topic)))))
    ;; An address alternative that IS present rescues the query, since the
    ;; address list is an OR.
    (is (ethereum-lisp.public-api::eth-rpc-block-bloom-may-match-p
         block (list absent-address present-address) nil))
    ;; And the full path agrees with the prefilter in every case.
    (is (null (ethereum-lisp.public-api::eth-rpc-block-logs-object
               block (list absent-address) nil)))
    (is (null (ethereum-lisp.public-api::eth-rpc-block-logs-object
               block nil (list (list absent-topic)))))))

(deftest log-bloom-prefilter-scans-when-it-has-nothing-to-go-on
  (:layer :unit :module :rpc)
  ;; Refusing to scan on missing information would drop real results, so a
  ;; block with no bloom on its header is always scanned.
  (let ((blind (ethereum-lisp.blocks:make-block-from-parts
                :header (make-block-header :number 1 :difficulty 0
                                           :gas-limit 30000000
                                           :extra-data (make-byte-vector 0))
                :transactions (list (make-legacy-transaction
                                     :nonce 1 :gas-price 2 :gas-limit 21000
                                     :value 3 :v 27 :r 4 :s 5))
                :receipts (list (make-receipt
                                 :status 1 :cumulative-gas-used 21000
                                 :logs (list (bloom-test-log
                                              *bloom-test-address*
                                              *bloom-test-topic*)))))))
    (is (ethereum-lisp.public-api::eth-rpc-block-bloom-may-match-p
         blind (list (address-from-hex *bloom-test-other-address*)) nil))
    ;; Scanned, and then correctly rejected by the real matcher.
    (is (null (ethereum-lisp.public-api::eth-rpc-block-logs-object
               blind (list (address-from-hex *bloom-test-other-address*)) nil)))
    (is (= 1 (length (ethereum-lisp.public-api::eth-rpc-block-logs-object
                      blind (list (address-from-hex *bloom-test-address*))
                      nil))))))
