(in-package #:ethereum-lisp.test)

;;;; Account existence before EIP-158 (Spurious Dragon), and the Frontier
;;;; creation rules, each against go-ethereum v1.17.6: gasCallIntrinsic,
;;;; gasSelfdestruct, EVM.Call, EVM.create, IntrinsicGas. The legacy EEST
;;;; v5.4.0 directories frontier/precompiles, frontier/create,
;;;; frontier/opcodes, frontier/touch and frontier/examples exercise the same
;;;; rules end to end (OPTIONAL-LEGACY-EEST-PRE-MERGE-BLOCKCHAIN-BURN-DOWN).

(defun pre-spurious-dragon-test-rules (level)
  (ecase level
    (:frontier (make-chain-rules :chain-id 1))
    (:homestead (make-chain-rules :chain-id 1 :homestead-p t))
    (:tangerine (make-chain-rules :chain-id 1 :homestead-p t :eip150-p t))
    (:spurious (make-chain-rules :chain-id 1 :homestead-p t :eip150-p t
                                 :eip155-p t :eip158-p t))))

(defun pre-spurious-dragon-test-address (byte)
  (let ((bytes (make-byte-vector 20)))
    (setf (aref bytes 19) byte)
    (address-from-hex (bytes-to-hex bytes))))

(defun pre-spurious-dragon-test-run (level code &key (target nil target-p)
                                                     (caller-balance 0)
                                                     gas-limit)
  "Run CODE from 0xaa under LEVEL's rules; TARGET, when given, is created
first as an empty account. Returns the result and the state."
  (let* ((state (make-state-db))
         (caller (pre-spurious-dragon-test-address #xaa)))
    (state-db-set-account state caller
                          (make-state-account :balance caller-balance))
    (when (and target-p target)
      (state-db-set-account state target (make-state-account)))
    (values
     (apply #'execute-bytecode code
            :context (make-evm-context
                      :state state :address caller
                      :chain-rules (pre-spurious-dragon-test-rules level))
            (when gas-limit (list :gas-limit gas-limit)))
     state)))

(defun pre-spurious-dragon-test-zero-value-call (target)
  "CALL TARGET with value 0 and 100 gas, then STOP; PUSH1 0, not PUSH0."
  (concat-bytes #(#x60 0 #x60 0 #x60 0 #x60 0 #x60 0 #x73)
                (address-bytes target)
                #(#x60 100 #xf1 0)))

(deftest pre-spurious-dragon-call-charges-and-creates-an-absent-callee
  ;; Before EIP-158 a CALL to an account that does not exist costs the
  ;; new-account 25000 whatever the value, and makes the account; from
  ;; EIP-158 a zero-value CALL does neither.
  (let* ((target (pre-spurious-dragon-test-address #xcc))
         (code (pre-spurious-dragon-test-zero-value-call target)))
    (dolist (level '(:homestead :tangerine))
      (multiple-value-bind (absent state)
          (pre-spurious-dragon-test-run level code)
        (let ((present (pre-spurious-dragon-test-run level code
                                                     :target target)))
          (is (= 1 (first (evm-result-stack absent))))
          (is (= 25000 (- (evm-result-gas-used absent)
                          (evm-result-gas-used present))))
          (is (state-db-get-account state target)))))
    (multiple-value-bind (absent state)
        (pre-spurious-dragon-test-run :spurious code)
      (let ((present (pre-spurious-dragon-test-run :spurious code
                                                   :target target)))
        (is (= (evm-result-gas-used present) (evm-result-gas-used absent)))
        (is (null (state-db-get-account state target)))))))

(deftest pre-spurious-dragon-selfdestruct-charges-and-creates-an-absent-beneficiary
  ;; From EIP-150 and before EIP-158, SELFDESTRUCT to a beneficiary that
  ;; does not exist costs 25000 even with nothing to send, and the credit
  ;; makes the account; from EIP-158 neither happens for a zero balance.
  (let* ((beneficiary (pre-spurious-dragon-test-address #xbb))
         (code (concat-bytes #(#x73) (address-bytes beneficiary) #(#xff))))
    (multiple-value-bind (absent state)
        (pre-spurious-dragon-test-run :tangerine code)
      (let ((present (pre-spurious-dragon-test-run :tangerine code
                                                   :target beneficiary)))
        (is (= 25000 (- (evm-result-gas-used absent)
                        (evm-result-gas-used present))))
        (is (state-db-get-account state beneficiary))))
    (multiple-value-bind (absent state)
        (pre-spurious-dragon-test-run :spurious code)
      (let ((present (pre-spurious-dragon-test-run :spurious code
                                                   :target beneficiary)))
        (is (= (evm-result-gas-used present) (evm-result-gas-used absent)))
        (is (null (state-db-get-account state beneficiary)))))))

(defun pre-spurious-dragon-test-create-code (initcode)
  "Store INITCODE (at most 32 bytes) in memory and CREATE it with value 0."
  (let ((size (length initcode)))
    (concat-bytes (vector (+ #x5f size)) initcode
                  #(#x60 0 #x52)
                  (vector #x60 size #x60 (- 32 size) #x60 0 #xf0 0))))

(deftest pre-spurious-dragon-create-starts-a-contract-at-nonce-zero
  ;; EIP-161 (EIP-158 in go-ethereum's rules) starts a new contract at
  ;; nonce 1; before it, at 0.
  (let ((code (pre-spurious-dragon-test-create-code #(0))))
    (dolist (entry '((:homestead . 0) (:spurious . 1)))
      (multiple-value-bind (result state)
          (pre-spurious-dragon-test-run (car entry) code)
        (let ((created (ethereum-lisp.evm.internal::word-to-address
                        (first (evm-result-stack result)))))
          (is (= (cdr entry)
                 (state-account-nonce (state-db-get-account state created)))))))))

(deftest frontier-create-keeps-a-contract-whose-deposit-is-out-of-gas
  ;; Initcode returning 100 bytes owes a 20000 deposit it cannot pay. In
  ;; Frontier the contract stays, without code, its address is pushed and the
  ;; creation's unspent gas comes back; from Homestead the creation fails and
  ;; its gas is gone.
  (let* ((initcode #(#x60 100 #x60 0 #xf3))
         (code (pre-spurious-dragon-test-create-code initcode))
         (gas-limit 32200))
    (multiple-value-bind (frontier state)
        (pre-spurious-dragon-test-run :frontier code :gas-limit gas-limit)
      (let ((homestead (pre-spurious-dragon-test-run :homestead code
                                                     :gas-limit gas-limit))
            (created (ethereum-lisp.evm.internal::word-to-address
                      (first (evm-result-stack frontier)))))
        (is (plusp (first (evm-result-stack frontier))))
        (is (state-db-get-account state created))
        (is (zerop (length (state-db-get-code state created))))
        (is (zerop (first (evm-result-stack homestead))))
        (is (= gas-limit (evm-result-gas-used homestead)))
        (is (< (evm-result-gas-used frontier) gas-limit))))))

(deftest frontier-creation-transaction-pays-no-creation-surcharge
  ;; TxGasContractCreation (53000) applies from Homestead; a Frontier
  ;; creation pays TxGas (21000).
  (let ((create (make-legacy-transaction :to nil
                                         :data (make-byte-vector 0))))
    (is (= 21000 (transaction-intrinsic-gas
                  create :chain-rules
                  (pre-spurious-dragon-test-rules :frontier))))
    (is (= 53000 (transaction-intrinsic-gas
                  create :chain-rules
                  (pre-spurious-dragon-test-rules :homestead))))))
