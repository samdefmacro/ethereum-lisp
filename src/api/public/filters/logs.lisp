(in-package #:ethereum-lisp.public-api)

(defconstant +eth-rpc-max-log-topic-slots+ 4)
(defconstant +eth-rpc-max-log-subtopics+ 1000)
(defconstant +eth-rpc-max-log-block-range+ 5000)

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
       :empty-topic-set)
      ((json-array-p value)
       (let ((values (json-array-values value)))
         (when (> (length values) +eth-rpc-max-log-subtopics+)
           (block-validation-fail
            "~A topic filter slot exceeds the ~D-topic limit"
            method +eth-rpc-max-log-subtopics+))
         (mapcar (lambda (topic)
                   (unless (stringp topic)
                     (block-validation-fail
                      "~A topic filter entries must be topics" method))
                   (eth-rpc-hash-param (list topic) method "topic"))
                 values)))
    (t
     (block-validation-fail
      "~A topic filter slots must be null, a topic, or topic array" method))))

(defun eth-rpc-log-filter-topics (filter method)
  (let ((topics (json-object-field filter "topics")))
    (cond
      ((or (null topics) (json-null-p topics)) nil)
      ((json-array-p topics)
       (let ((values (json-array-values topics)))
         (when (> (length values) +eth-rpc-max-log-topic-slots+)
           (block-validation-fail
            "~A topics filter exceeds the ~D-slot limit"
            method +eth-rpc-max-log-topic-slots+))
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

(defun eth-rpc-log-filter-blocks (filter store method)
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
             (list block)
             (block-validation-fail "~A blockHash is unknown" method)))))
    ((eth-rpc-log-filter-from-pending-p filter)
     (when (json-object-field-present-p filter "toBlock")
       (eth-rpc-block-number-param
        (list (json-object-field filter "toBlock"))
        store
        method))
     '())
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
       (loop for number from from-number to to-number
             for block = (chain-store-block-by-number store number)
             when block
               collect block)))))

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
  (let* ((addresses (eth-rpc-log-filter-addresses filter method))
         (topic-filters (eth-rpc-log-filter-topics filter method))
         (blocks (eth-rpc-log-filter-blocks filter store method))
         (logs (loop for block in blocks
                     append (eth-rpc-block-logs-object
                             block addresses topic-filters))))
    (eth-rpc-json-array logs)))
