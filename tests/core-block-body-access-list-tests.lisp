(in-package #:ethereum-lisp.test)

(deftest block-body-collaborator-package-boundaries
  (let ((requests (find-package '#:ethereum-lisp.execution-requests))
        (access-lists (find-package '#:ethereum-lisp.block-access-lists))
        (core (find-package '#:ethereum-lisp.core)))
    (is (not (member core (package-use-list requests))))
    (is (not (member core (package-use-list access-lists))))
    (is (not (member requests (package-use-list access-lists))))
    (dolist (entry `((,requests "EXECUTION-REQUESTS-HASH")
                     (,access-lists "BLOCK-ACCESS-ACCOUNT")
                     (,access-lists "BLOCK-ACCESS-LIST-FROM-RLP")))
      (destructuring-bind (owner name) entry
        (multiple-value-bind (owned-symbol owned-status)
            (find-symbol name owner)
          (multiple-value-bind (core-symbol core-status)
              (find-symbol name core)
            (is (eq :external owned-status))
            (is (eq :external core-status))
            (is (eq owned-symbol core-symbol))))))
    (dolist (package (list requests access-lists))
      (multiple-value-bind (symbol status)
          (find-symbol "BLOCK-HEADER" package)
        (is (null symbol))
        (is (null status))))))

(deftest block-body-validates-execution-requests-hash
  (let* ((block (make-block :requests (list #(#x00 #xbb) #(#x01 #xaa))))
         (header (block-header block)))
    (is (validate-block-body-roots block))
    (is (string= (hash32-to-hex
                  (execution-requests-hash (block-requests block)))
                 (hash32-to-hex (block-header-requests-hash header))))
    (setf (block-header-requests-hash header) (zero-hash32))
    (signals block-validation-error
      (validate-block-body-roots block)))
  (let ((header-without-requests
          (make-block-header :requests-hash
                             (execution-requests-hash (list #(#x01 #xaa))))))
    (signals block-validation-error
      (validate-block-body-roots
       (make-block :header header-without-requests))))
  (let ((pre-prague-block (make-block :requests (list #(#x01 #xaa)))))
    (setf (block-header-requests-hash (block-header pre-prague-block)) nil)
    (signals block-validation-error
      (validate-block-body-roots pre-prague-block))))

(deftest block-body-validates-request-list-before-hash-derivation
  (let ((block (make-block)))
    (setf (block-requests block) "not a request list"
          (block-requests-present-p block) t)
    (signals block-validation-error
      (validate-block-body-roots block))))

(deftest block-body-validates-block-access-list-hash
  (let* ((block (make-block :block-access-list '()))
         (header (block-header block)))
    (is (validate-block-body-roots block))
    (is (string= (hash32-to-hex (block-access-list-hash '()))
                 (hash32-to-hex
                  (block-header-block-access-list-hash header))))
    (setf (block-header-block-access-list-hash header) (zero-hash32))
    (signals block-validation-error
      (validate-block-body-roots block)))
  (let* ((account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")))
         (block (make-block :block-access-list (list account))))
    (is (validate-block-body-roots block))
    (is (bytes= (block-access-list-rlp (list account))
                (block-encoded-block-access-list block)))
    (is (string= (hash32-to-hex (block-access-list-hash (list account)))
                 (hash32-to-hex
                  (block-header-block-access-list-hash
                   (block-header block))))))
  (let* ((account (make-block-access-account
                   :address (address-from-hex
                             "0x0000000000000000000000000000000000000001")))
         (encoded (block-access-list-rlp (list account)))
         (block (make-block :block-access-list-rlp encoded)))
    (is (block-block-access-list-present-p block))
    (is (bytes= encoded (block-encoded-block-access-list block)))
    (is (bytes= encoded
                (block-access-list-rlp (block-block-access-list block))))
    (is (string= (hash32-to-hex (block-access-list-rlp-hash encoded))
                 (hash32-to-hex
                  (block-header-block-access-list-hash
                   (block-header block)))))
    (is (validate-block-body-roots block))
    (setf (block-encoded-block-access-list block) (block-access-list-rlp '()))
    (signals block-validation-error
      (validate-block-body-roots block))
    (signals block-validation-error
      (make-block :block-access-list (list account)
                  :block-access-list-rlp encoded)))
  (let ((header-without-body
          (make-block-header :block-access-list-hash
                             (block-access-list-hash '()))))
    (signals block-validation-error
      (validate-block-body-roots
       (make-block :header header-without-body))))
  (let ((pre-amsterdam-block (make-block :block-access-list '())))
    (setf (block-header-block-access-list-hash
           (block-header pre-amsterdam-block)) nil)
    (signals block-validation-error
      (validate-block-body-roots pre-amsterdam-block))))

(deftest block-body-validates-block-access-list-code-change-size
  (let* ((address (address-from-hex
                   "0x0000000000000000000000000000000000000001"))
         (config (make-chain-config :london-block 0
                                    :amsterdam-time 0))
         (limit-code (make-byte-vector
                      +block-access-list-amsterdam-max-code-size+))
         (oversized-code (make-byte-vector
                          (1+ +block-access-list-amsterdam-max-code-size+)))
         (limit-account
           (make-block-access-account
            :address address
            :code-changes
            (list (make-block-access-code-change :tx-index 1
                                                 :code limit-code))))
         (oversized-account
           (make-block-access-account
            :address address
            :code-changes
            (list (make-block-access-code-change :tx-index 1
                                                 :code oversized-code))))
         (limit-block
           (make-block :header (make-block-header :timestamp 0)
                       :block-access-list (list limit-account)))
         (oversized-block
           (make-block :header (make-block-header :timestamp 0)
                       :block-access-list (list oversized-account))))
    (is (validate-block-body-against-config limit-block config))
    (signals block-validation-error
      (validate-block-body-against-config oversized-block config))
    (signals block-validation-error
      (validate-block-body-roots
       limit-block
       :block-access-list-max-code-size
       +block-access-list-max-code-size+))))

(deftest block-body-validates-block-access-list-item-gas-limit
  (let* ((address (address-from-hex
                   "0x0000000000000000000000000000000000000001"))
         (read-slot (hash32-from-hex
                     "0x0000000000000000000000000000000000000000000000000000000000000001"))
         (write-slot (hash32-from-hex
                      "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (slot-writes (make-block-access-slot-writes
                       :slot write-slot
                       :accesses
                       (list (make-block-access-storage-write
                              :tx-index 0
                              :value-after 7))))
         (account (make-block-access-account
                   :address address
                   :storage-writes (list slot-writes)
                   :storage-reads (list read-slot)))
         (access-list (list account))
         (config (make-chain-config :london-block 0
                                    :amsterdam-time 0))
         (limit-block
           (make-block :header (make-block-header
                                :timestamp 0
                                :gas-limit
                                (* 3 +block-access-list-item-gas-cost+))
                       :block-access-list access-list))
         (oversized-block
           (make-block :header (make-block-header
                                :timestamp 0
                                :gas-limit
                                (* 2 +block-access-list-item-gas-cost+))
                       :block-access-list access-list)))
    (is (= 3 (block-access-list-item-count access-list)))
    (is (validate-block-access-list-fields access-list
                                           :max-items 3))
    (signals block-validation-error
      (validate-block-access-list-fields access-list
                                         :max-items 2))
    (is (validate-block-body-against-config limit-block config))
    (signals block-validation-error
      (validate-block-body-against-config oversized-block config))))

(deftest block-body-validates-block-access-list-shape-before-hash
  (let ((block (make-block)))
    (setf (block-block-access-list block) "not a block access list"
          (block-block-access-list-present-p block) t)
    (signals block-validation-error
      (validate-block-body-roots block))))
