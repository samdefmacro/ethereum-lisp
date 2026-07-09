(in-package #:ethereum-lisp.test)

(deftest block-execution-root-validation
  (let* ((address (address-from-hex "0x0000000000000000000000000000000000000001"))
         (topic (hash32-from-hex
                 "0x0000000000000000000000000000000000000000000000000000000000000002"))
         (log (make-log-entry :address address :topics (list topic) :data #(7)))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000
                                :logs (list log)))
         (state-root (hash32-from-hex
                      "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (block (make-block :receipts (list receipt)))
         (header (block-header block)))
    (setf (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (is (= 21000 (receipts-gas-used (list receipt))))
    (is (validate-block-execution-roots block (list receipt) state-root))
    (setf (block-header-gas-used header) 21001)
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root))
    (setf (block-header-gas-used header) 21000
          (block-header-receipts-root header) (zero-hash32))
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root))))

(deftest block-execution-validates-commitment-fields-before-comparison
  (let* ((receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (state-root (hash32-from-hex
                      "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (block (make-block :receipts (list receipt)))
         (header (block-header block)))
    (setf (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (setf (block-header-logs-bloom header) "not a bloom")
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root))
    (setf (block-header-logs-bloom header) (make-byte-vector 256)
          (block-header-receipts-root header) nil)
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root))
    (setf (block-header-receipts-root header) (receipt-list-root (list receipt))
          (block-header-state-root header) nil)
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root))
    (setf (block-header-state-root header) state-root)
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) nil))))

(deftest block-execution-validates-receipts-before-derived-fields
  (let* ((state-root (hash32-from-hex
                      "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (good-receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (block (make-block :receipts (list good-receipt)))
         (header (block-header block)))
    (setf (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (signals block-validation-error
      (validate-block-execution-roots block "not a receipt list" state-root))
    (signals block-validation-error
      (validate-block-execution-roots block (list "not a receipt") state-root))
    (signals block-validation-error
      (validate-block-execution-roots
       block
       (list (make-receipt :status 1
                           :cumulative-gas-used (ash 1 64)))
       state-root))
    (signals block-validation-error
      (validate-block-execution-roots
       block
       (list (make-receipt :post-state "not bytes"
                           :cumulative-gas-used 21000))
       state-root))
    (signals block-validation-error
      (validate-block-execution-roots
       block
       (list (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry :address nil))))
       state-root))
    (signals block-validation-error
      (validate-block-execution-roots
       block
       (list (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry
                           :topics (list nil)))))
       state-root))
    (signals block-validation-error
      (validate-block-execution-roots
       block
       (list (make-receipt
              :status 1
              :cumulative-gas-used 21000
              :logs (list (make-log-entry :data "not bytes"))))
       state-root))))

(deftest block-execution-rejects-pre-byzantium-receipts-by-config
  (let* ((post-state (make-byte-vector 32 :initial-element #x11))
         (receipt (make-receipt :post-state post-state
                                :cumulative-gas-used 21000))
         (state-root (hash32-from-hex
                      "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (block (make-block :receipts (list receipt)))
         (header (block-header block))
         (pre-byzantium-config (make-chain-config :byzantium-block 100))
         (byzantium-config (make-chain-config :byzantium-block 0)))
    (setf (block-header-number header) 42
          (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (signals block-validation-error
      (validate-block-execution-roots block (list receipt) state-root
                                      :chain-config pre-byzantium-config))
    (is (validate-block-execution-roots block (list receipt) state-root
                                        :chain-config byzantium-config))))

(deftest block-execution-validates-receipt-cumulative-gas-order
  (let* ((first-receipt (make-receipt :status 1
                                      :cumulative-gas-used 30000))
         (second-receipt (make-receipt :status 1
                                       :cumulative-gas-used 21000))
         (receipts (list first-receipt second-receipt))
         (state-root (hash32-from-hex
                      "0x1111111111111111111111111111111111111111111111111111111111111111"))
         (block (make-block :receipts receipts))
         (header (block-header block)))
    (setf (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (signals block-validation-error
      (validate-block-execution-roots block receipts state-root)))
  (let* ((first-receipt (make-receipt :status 1
                                      :cumulative-gas-used 21000))
         (second-receipt (make-receipt :status 1
                                       :cumulative-gas-used 21000))
         (receipts (list first-receipt second-receipt))
         (state-root (hash32-from-hex
                      "0x2222222222222222222222222222222222222222222222222222222222222222"))
         (block (make-block :receipts receipts))
         (header (block-header block)))
    (setf (block-header-gas-used header) 21000
          (block-header-state-root header) state-root)
    (signals block-validation-error
      (validate-block-execution-roots block receipts state-root))))

