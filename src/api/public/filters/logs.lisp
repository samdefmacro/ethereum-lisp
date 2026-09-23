(in-package #:ethereum-lisp.public-api)

(defconstant +eth-rpc-max-log-topic-slots+ 4)
(defconstant +eth-rpc-max-log-subtopics+ 1000)
(defconstant +eth-rpc-max-log-block-range+ 5000)

(defconstant +eth-rpc-max-log-addresses+ 1000
  "geth's LogQueryLimit default (eth/ethconfig/config.go:70 at 38271784): more
addresses than this in one filter is refused with -32000 \"exceed max addresses
or topics per search position\" (eth/filters/api.go:46, :451-454).")

(defparameter *eth-rpc-max-log-results* 10000
  "The most logs one eth_getLogs or eth_getFilterLogs answer may carry. Our
policy, not geth's (geth has no result bound): a query over it is refused with
EIP-1474's -32005 \"limit exceeded\" code as soon as the scan crosses the bound,
before the rest of the range is read or any response is encoded. NIL disables
the bound.")

(defun eth-rpc-log-topic-limit-fail ()
  (engine-rpc-fail -32000 "exceed max topics"))

(defun eth-rpc-address= (left right)
  (and left
       right
       (bytes= (address-bytes left) (address-bytes right))))

(defun eth-rpc-log-address-match-p (log addresses)
  (and (not (eq addresses :empty-address-set))
       (or (null addresses)
           (some (lambda (address)
                   (eth-rpc-address= (log-entry-address log) address))
                 addresses))))

(defun eth-rpc-log-topics-match-p (log topic-filters)
  (let ((topics (log-entry-topics log)))
    (or (null topic-filters)
        (loop for slot in topic-filters
              for index from 0
              always (and (not (eq slot :empty-topic-set))
                          (< index (length topics))
                          (or (null slot)
                              (some (lambda (topic)
                                      (hash32= (nth index topics) topic))
                                    slot)))))))

(defun eth-rpc-bloom-has-any-p (bloom values)
  "Whether BLOOM might contain any of VALUES, as raw bytes."
  (some (lambda (value) (bloom-contains-p bloom value)) values))

(defun eth-rpc-block-bloom-may-match-p (block addresses topic-filters)
  "Whether BLOCK could possibly contain a log matching the filter.

A bloom filter answers one question definitively: a value it does NOT contain is
definitely not in the block. So this is a cheap NEGATIVE test that lets a whole
block's receipts be skipped without decoding them -- which is the difference
between reading one 256-byte header field and walking every receipt of every
block in the range. A positive answer means only 'maybe', and the caller still
matches each log properly; false positives cost nothing but the scan we would
have done anyway.

Returns T when there is nothing to go on -- no bloom on the header, or a filter
with no constraints -- because refusing to scan on missing information would
drop real results."
  (let ((bloom-bytes (block-header-logs-bloom (block-header block))))
    (if (null bloom-bytes)
        t
        (let ((bloom (make-bloom bloom-bytes)))
          (and
           ;; Any ONE of the requested addresses may match, so the block is
           ;; only ruled out when none of them is present.
           (or (null addresses)
               (eq addresses :empty-address-set)
               (eth-rpc-bloom-has-any-p
                bloom (mapcar #'address-bytes addresses)))
           ;; Every constrained position must be satisfiable, since a log has to
           ;; match all of them; a NIL slot is a wildcard and constrains nothing.
           (loop for slot in topic-filters
                 always (or (null slot)
                            (eq slot :empty-topic-set)
                            (eth-rpc-bloom-has-any-p
                             bloom (mapcar #'topic-bytes slot)))))))))

(defun eth-rpc-log-filter-object (params method)
  (unless (= 1 (length params))
    (block-validation-fail "~A params must contain exactly one filter"
                           method))
  (let ((filter (first params)))
    (unless (or (null filter) (json-null-p filter) (json-object-p filter))
      (block-validation-fail "~A filter must be an object" method))
    (unless (json-null-p filter) filter)))

(defun eth-rpc-log-filter-addresses (filter method)
  (let ((value (json-object-field filter "address")))
    (cond
      ((or (null value) (json-null-p value)) nil)
      ((stringp value)
       (list (eth-rpc-address-param value method "address")))
      ((json-empty-array-p value)
       :empty-address-set)
      ((json-array-p value)
       (mapcar (lambda (address)
                 (unless (stringp address)
                   (block-validation-fail
                    "~A address filter entries must be addresses" method))
                 (eth-rpc-address-param address method "address"))
               (json-array-values value)))
      (t
       (block-validation-fail
        "~A address filter must be an address or address array" method)))))

(defun eth-rpc-log-filter-topic (value method)
  (cond
      ((or (null value) (json-null-p value)) nil)
      ((stringp value)
       (list (eth-rpc-hash-param (list value) method "topic")))
      ((json-empty-array-p value)
       nil)
      ((json-array-p value)
       (let ((values (json-array-values value)))
         (when (> (length values) +eth-rpc-max-log-subtopics+)
           (eth-rpc-log-topic-limit-fail))
         (mapcar (lambda (topic)
                   (unless (stringp topic)
                     (block-validation-fail
                      "~A topic filter entries must be topics" method))
                   (eth-rpc-hash-param (list topic) method "topic"))
                 values)))
    (t
     (block-validation-fail
      "~A topic filter slots must be null, a topic, or topic array" method))))

(defun eth-rpc-log-filter-check-query-limit (addresses)
  "Refuse more than +ETH-RPC-MAX-LOG-ADDRESSES+ ADDRESSES, as geth does once the
whole filter has parsed (eth/filters/api.go:451-454 for eth_getLogs,
filter_system.go:301-304 for filters and subscriptions). Per-position topic
counts never reach this bound: more than +ETH-RPC-MAX-LOG-SUBTOPICS+ is already
refused while parsing, as geth's UnmarshalJSON refuses it."
  (when (and (listp addresses)
             (> (length addresses) +eth-rpc-max-log-addresses+))
    (engine-rpc-fail -32000
                     "exceed max addresses or topics per search position")))

(defun eth-rpc-log-filter-topics (filter method)
  (let ((topics (json-object-field filter "topics")))
    (cond
      ((or (null topics) (json-null-p topics)) nil)
      ((json-array-p topics)
       (let ((values (json-array-values topics)))
         (when (> (length values) +eth-rpc-max-log-topic-slots+)
           (eth-rpc-log-topic-limit-fail))
         (mapcar (lambda (topic)
                   (eth-rpc-log-filter-topic topic method))
                 values)))
      (t
       (block-validation-fail
        "~A topics filter must be an array" method)))))

(defun eth-rpc-log-filter-from-pending-p (filter)
  (and (not (json-object-field-present-p filter "blockHash"))
       (eth-rpc-pending-block-tag-p
        (json-object-field filter "fromBlock"))))

(defun eth-rpc-log-filter-block-source (filter store method)
  "Validate FILTER's block selection and say which blocks it covers, without
loading any of them. Returns (VALUES :BLOCK BLOCK), (VALUES :NONE) for a
pending-only filter, or (VALUES :RANGE FROM TO). Every range check happens here,
so an out-of-bounds request is refused before any block is read."
  (cond
    ((json-object-field-present-p filter "blockHash")
     (when (or (json-object-field-present-p filter "fromBlock")
               (json-object-field-present-p filter "toBlock"))
       (block-validation-fail
        "~A blockHash cannot be combined with fromBlock or toBlock"
        method))
     (let ((block-hash (eth-rpc-hash-param
                        (list (json-object-field filter "blockHash"))
                        method
                        "block hash")))
       (let ((block (chain-store-known-block store block-hash)))
         (if block
             (values :block block)
             (engine-rpc-fail -32000 "unknown block")))))
    ((eth-rpc-log-filter-from-pending-p filter)
     (when (json-object-field-present-p filter "toBlock")
       (eth-rpc-block-number-param
        (list (json-object-field filter "toBlock"))
        store
        method))
     (values :none))
    (t
     (let* ((from-number (eth-rpc-block-number-param
                          (list (or (json-object-field filter "fromBlock")
                                    "latest"))
                          store
                          method))
            (to-number (eth-rpc-block-number-param
                        (list (or (json-object-field filter "toBlock")
                                  "latest"))
                        store
                        method))
            (head-number (chain-store-head-number store)))
       (when (> from-number to-number)
         (block-validation-fail
          "~A fromBlock must be less than or equal to toBlock" method))
       (when (and head-number (> to-number head-number))
         (block-validation-fail
          "~A block range extends beyond current head block" method))
       (when (> (- to-number from-number) +eth-rpc-max-log-block-range+)
         (block-validation-fail
          "~A block range exceeds the ~D-block limit"
          method +eth-rpc-max-log-block-range+))
       (values :range from-number to-number)))))

(defun eth-rpc-map-log-filter-blocks (function filter store method)
  "Call FUNCTION on each block FILTER covers, in order, one block at a time.

The range is streamed rather than collected first: a 5,000-block query used to
hold every block of the range in a list before the first bloom was looked at."
  (multiple-value-bind (kind first last)
      (eth-rpc-log-filter-block-source filter store method)
    (ecase kind
      (:block (funcall function first))
      (:none nil)
      (:range
       (loop for number from first to last
             for block = (chain-store-block-by-number store number)
             when block
               do (funcall function block))))))

(defun eth-rpc-log-filter-blocks (filter store method)
  (let ((blocks '()))
    (eth-rpc-map-log-filter-blocks
     (lambda (block) (push block blocks)) filter store method)
    (nreverse blocks)))


(defun eth-rpc-block-logs-object
    (block addresses topic-filters &key removed-p)
  (when (and block
             (= (length (block-transactions block))
                (length (block-receipts block)))
             ;; Cheap negative first: the header's bloom rules most blocks out
             ;; without touching a single receipt.
             (eth-rpc-block-bloom-may-match-p block addresses topic-filters))
    (loop with log-index-start = 0
          for transaction in (block-transactions block)
          for receipt in (block-receipts block)
          for transaction-index from 0
          append (loop for log in (receipt-logs receipt)
                       for log-index from log-index-start
                       when (and (eth-rpc-log-address-match-p log addresses)
                                 (eth-rpc-log-topics-match-p
                                  log topic-filters))
                         collect (eth-rpc-log-object
                                  log
                                  block
                                  transaction
                                  transaction-index
                                  log-index
                                  :removed-p removed-p))
          do (incf log-index-start (length (receipt-logs receipt))))))

(defun eth-rpc-filter-logs (filter store method)
  "The logs FILTER selects, refused as soon as they number more than
*ETH-RPC-MAX-LOG-RESULTS*: the scan stops at the block that crosses the limit
instead of building the whole answer first."
  (let* ((addresses (eth-rpc-log-filter-addresses filter method))
         (topic-filters (eth-rpc-log-filter-topics filter method))
         (limit *eth-rpc-max-log-results*)
         (count 0)
         (chunks '()))
    (eth-rpc-log-filter-check-query-limit addresses)
    (eth-rpc-map-log-filter-blocks
     (lambda (block)
       (let ((logs (eth-rpc-block-logs-object block addresses topic-filters)))
         (when logs
           (incf count (length logs))
           (when (and limit (> count limit))
             (engine-rpc-fail -32005
                              (format nil "query returned more than ~D results"
                                      limit)))
           (push logs chunks))))
     filter store method)
    (eth-rpc-json-array (loop for logs in (nreverse chunks) append logs))))
