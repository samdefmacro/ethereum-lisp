(in-package #:ethereum-lisp.test)

;;;; Pre-Merge parity with go-ethereum v1.17.6 for the rules the mainnet
;;;; inventory (docs/gap-analysis/mainnet-inventory.md) listed as gaps or as
;;;; unit-only: the Frontier and Homestead signers, EIP-170 before Spurious
;;;; Dragon, single-flag rule sets, the eth/68 Status total difficulty, and the
;;;; DAO drain and ommer rewards on a synthetic proof-of-work chain imported
;;;; through IMPORT-BLOCK-CANDIDATE, the signer the public RPC recovers a
;;;; stored or pooled sender with, and every fork predicate read over a
;;;; single-flag rule set. Expected values are computed from geth's
;;;; formulas in each test, never read back from our own execution.

(defparameter *premerge-test-private-key*
  #x4646464646464646464646464646464646464646464646464646464646464646
  "The EIP-155 example key; any valid scalar would do.")

(defparameter *premerge-test-recipient*
  (address-from-hex "0x3535353535353535353535353535353535353535"))

(defparameter *premerge-test-miner*
  (address-from-hex "0x00000000000000000000000000000000000000c1"))

(defconstant +premerge-test-ttd+ (1- (ash 1 63))
  "go-ethereum's math.MaxInt64, the TTD BlockTest.Run gives a network without
one, so every block below is proof-of-work.")

(defun premerge-test-config (&rest forks)
  "A chain-id-1 configuration with FORKS (MAKE-CHAIN-CONFIG block arguments)
and a TTD no test chain reaches."
  (apply #'make-chain-config :chain-id 1
         :terminal-total-difficulty +premerge-test-ttd+
         forks))

(defun premerge-test-sign (transaction &key chain-id high-s-p)
  "TRANSACTION signed with *PREMERGE-TEST-PRIVATE-KEY*: unprotected (V 27/28)
without CHAIN-ID, EIP-155 protected with it. HIGH-S-P replaces s by n - s and
flips the recovery id, the other valid signature over the same hash."
  (let* ((hash (if chain-id
                   (legacy-transaction-signing-hash transaction
                                                    :chain-id chain-id)
                   (legacy-transaction-signing-hash transaction)))
         (signature (secp256k1-sign (hash32-bytes hash)
                                    *premerge-test-private-key*))
         (r (bytes-to-integer (subseq signature 0 32)))
         (s (bytes-to-integer (subseq signature 32 64)))
         (recovery-id (aref signature 64)))
    (when high-s-p
      (setf s (- ethereum-lisp.crypto::+secp256k1-n+ s)
            recovery-id (- 1 recovery-id)))
    (make-legacy-transaction
     :nonce (legacy-transaction-nonce transaction)
     :gas-price (legacy-transaction-gas-price transaction)
     :gas-limit (legacy-transaction-gas-limit transaction)
     :to (legacy-transaction-to transaction)
     :value (legacy-transaction-value transaction)
     :data (legacy-transaction-data transaction)
     :v (if chain-id (+ 35 (* 2 chain-id) recovery-id) (+ 27 recovery-id))
     :r r
     :s s)))

(defun premerge-test-sender ()
  "The address *PREMERGE-TEST-PRIVATE-KEY* signs for, recovered from an
ordinary low-s signature."
  (transaction-sender
   (premerge-test-sign (make-legacy-transaction :nonce 0 :gas-price 1
                                                :gas-limit 21000
                                                :to *premerge-test-recipient*
                                                :value 0))))

(defun premerge-test-genesis-store (alloc &key (gas-limit 8000000) codes)
  "A store holding a proof-of-work genesis whose state is ALLOC, a list of
(ADDRESS . STATE-ACCOUNT), with CODES, a list of (ADDRESS . CODE) for accounts
of ALLOC; returns it and the genesis block."
  (let ((store (make-engine-payload-memory-store))
        (state (make-state-db)))
    (loop for (address . account) in alloc
          do (state-db-set-account state address account))
    (loop for (address . code) in codes
          do (state-db-set-code state address code))
    (let ((genesis
            (make-block
             :header
             (make-block-header
              :parent-hash (zero-hash32)
              :ommers-hash +empty-ommers-hash+
              :beneficiary (zero-address)
              :state-root (state-db-root state)
              :difficulty #x20000
              :number 0
              :gas-limit gas-limit
              :timestamp 0
              :extra-data (make-byte-vector 0)
              :mix-hash (zero-hash32)
              :nonce (make-byte-vector 8)))))
      (engine-payload-store-put-block store genesis :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash genesis) state)
      (values store genesis))))

(defun premerge-test-child
    (store config parent
     &key transactions ommers (beneficiary *premerge-test-miner*)
          (extra-data (make-byte-vector 0)) (seconds 13))
  "Execute a proof-of-work child of PARENT (in STORE) carrying TRANSACTIONS and
OMMERS, with the Ethash difficulty CONFIG expects; return the sealed block and
its post-state. Nothing is imported."
  (let* ((parent-header (block-header parent))
         (timestamp (+ seconds (block-header-timestamp parent-header)))
         (state (state-db-copy
                 (chain-store-state-db store (block-hash parent)))))
    (values
     (execute-signed-block
      state transactions
      :expected-chain-id (chain-config-chain-id config)
      :header (make-block-header
               :parent-hash (block-hash parent)
               :ommers-hash (ommers-hash ommers)
               :beneficiary beneficiary
               :difficulty (expected-ethash-difficulty
                            config timestamp parent-header)
               :number (1+ (block-header-number parent-header))
               :gas-limit (block-header-gas-limit parent-header)
               :timestamp timestamp
               :extra-data extra-data
               :mix-hash (zero-hash32)
               :nonce (make-byte-vector 8))
      :chain-config config
      :ommers ommers
      :apply-block-rewards-p t)
     state)))

(defun premerge-test-import (store config block)
  "Import BLOCK as a candidate, with the seal unchecked as geth's NoProof
fixtures run; return BLOCK."
  (let ((*ethash-seal-verifier* (constantly t)))
    (import-block-candidate store block config)
    block))

(defun premerge-test-refusal (thunk)
  "The report of the validation error THUNK signals, or NIL."
  (handler-case (progn (funcall thunk) nil)
    ((or block-validation-error
         ethereum-lisp.execution:transaction-validation-error)
        (condition)
      (princ-to-string condition))))

(defun premerge-test-balance (state address)
  (let ((account (state-db-get-account state address)))
    (and account (state-account-balance account))))

;;; (1) Frontier signatures with a high s

(deftest premerge-frontier-signer-accepts-a-high-s-signature
  ;; go-ethereum v1.17.6 core/types/transaction_signing.go: MakeSigner picks
  ;; FrontierSigner before Homestead, whose Sender calls recoverPlain with
  ;; homestead false, so crypto.ValidateSignatureValues does not apply EIP-2's
  ;; s <= n/2 bound. HomesteadSigner passes true and refuses the same bytes.
  (let* ((sender (premerge-test-sender))
         (transaction
           (premerge-test-sign
            (make-legacy-transaction :nonce 0 :gas-price 1 :gas-limit 21000
                                     :to *premerge-test-recipient* :value 7)
            :high-s-p t))
         (frontier (premerge-test-config))
         (homestead (premerge-test-config :homestead-block 0)))
    (is (> (legacy-transaction-s transaction)
           ethereum-lisp.crypto::+secp256k1-half-n+))
    ;; The ordinary low-s recovery refuses it at every fork.
    (is (null (transaction-sender transaction)))
    (multiple-value-bind (store genesis)
        (premerge-test-genesis-store
         (list (cons sender (make-state-account :balance (expt 10 18)))))
      (multiple-value-bind (block state)
          (premerge-test-child store frontier genesis
                               :transactions (list transaction))
        (is (= 7 (premerge-test-balance state *premerge-test-recipient*)))
        (is (eq block (premerge-test-import store frontier block)))))
    ;; Homestead refuses the same signature, at execution and at import.
    (multiple-value-bind (store genesis)
        (premerge-test-genesis-store
         (list (cons sender (make-state-account :balance (expt 10 18)))))
      (let ((refusal (premerge-test-refusal
                      (lambda ()
                        (premerge-test-child store homestead genesis
                                             :transactions
                                             (list transaction))))))
        (is refusal)
        (is (search "Invalid transaction signature" refusal))))))

;;; (2) EIP-155 protected signatures before EIP-155

(deftest premerge-protected-signature-is-refused-before-eip155
  ;; Before EIP-155, HomesteadSigner.Sender hands the raw V to recoverPlain,
  ;; which accepts only 27 and 28: a chain-id-protected V (37 or 38 for chain
  ;; 1) is ErrInvalidSig. The same block is valid where EIP-155 is active.
  (let* ((sender (premerge-test-sender))
         (transaction
           (premerge-test-sign
            (make-legacy-transaction :nonce 0 :gas-price 1 :gas-limit 21000
                                     :to *premerge-test-recipient* :value 7)
            :chain-id 1))
         (alloc (list (cons sender (make-state-account :balance (expt 10 18)))))
         ;; Identical difficulty, gas and state rules; only the signer differs.
         (with-eip155 (premerge-test-config :homestead-block 0 :eip150-block 0
                                            :eip155-block 0))
         (before-eip155 (premerge-test-config :homestead-block 0
                                              :eip150-block 0)))
    (is (member (legacy-transaction-v transaction) '(37 38)))
    (multiple-value-bind (store genesis) (premerge-test-genesis-store alloc)
      (let ((block (premerge-test-child store with-eip155 genesis
                                        :transactions (list transaction))))
        ;; Positive control: the EIP-155 chain imports it.
        (is (eq block (premerge-test-import store with-eip155 block)))
        ;; The pre-EIP-155 chain refuses the identical block at admission.
        (multiple-value-bind (other-store other-genesis)
            (premerge-test-genesis-store alloc)
          (is (hash32= (block-hash genesis) (block-hash other-genesis)))
          (let ((refusal (premerge-test-refusal
                          (lambda ()
                            (premerge-test-import other-store before-eip155
                                                  block)))))
            (is refusal)
            (is (search "sender" refusal))))))
    ;; Execution under the pre-EIP-155 rules names it an invalid signature.
    (multiple-value-bind (store genesis) (premerge-test-genesis-store alloc)
      (let ((refusal (premerge-test-refusal
                      (lambda ()
                        (premerge-test-child store before-eip155 genesis
                                             :transactions
                                             (list transaction))))))
        (is refusal)
        (is (search "Invalid transaction signature" refusal))))))

;;; (3) EIP-170 only from Spurious Dragon

(defparameter *premerge-test-oversized-initcode*
  ;; PUSH2 0x6001 PUSH1 0 RETURN: 24,577 zero bytes of runtime code, one over
  ;; params.MaxCodeSize.
  (hex-to-bytes "0x6160016000f3"))

(defun premerge-test-created-code-length (config)
  "Deploy the oversized code by a creation transaction under CONFIG; return
the deployed code length (0 when refused)."
  (let* ((sender (premerge-test-sender))
         (create-tx (premerge-test-sign
                     (make-legacy-transaction
                      :nonce 0 :gas-price 1 :gas-limit 6000000 :to nil
                      :value 0 :data *premerge-test-oversized-initcode*))))
    (multiple-value-bind (store genesis)
        (premerge-test-genesis-store
         (list (cons sender (make-state-account :balance (expt 10 18))))
         :gas-limit 20000000)
      (multiple-value-bind (block state)
          (premerge-test-child store config genesis
                               :transactions (list create-tx))
        (premerge-test-import store config block)
        (length (state-db-get-code
                 state
                 (ethereum-lisp.execution::execution-create-address
                  sender 0)))))))

(defun premerge-test-create-opcode-code-length (config)
  "Deploy the oversized code by CREATE from a preallocated factory under
CONFIG; return the deployed code length (0 when refused)."
  (let* ((sender (premerge-test-sender))
         (factory (address-from-hex
                   "0x00000000000000000000000000000000000000fa"))
         ;; PUSH6 <initcode> PUSH1 0 MSTORE PUSH1 6 PUSH1 26 PUSH1 0 CREATE
         ;; PUSH1 0 SSTORE STOP: the created address (0 on failure) in slot 0.
         (factory-code (hex-to-bytes
                        "0x656160016000f36000526006601a6000f060005500"))
         (call-tx (premerge-test-sign
                   (make-legacy-transaction
                    :nonce 0 :gas-price 1 :gas-limit 6000000 :to factory
                    :value 0))))
    (multiple-value-bind (store genesis)
        (premerge-test-genesis-store
         (list (cons sender (make-state-account :balance (expt 10 18)))
               (cons factory (make-state-account)))
         :gas-limit 20000000
         :codes (list (cons factory factory-code)))
      (multiple-value-bind (block state)
          (premerge-test-child store config genesis
                               :transactions (list call-tx))
        (premerge-test-import store config block)
        (let ((slot (state-db-get-storage state factory (zero-hash32))))
          (if (zerop slot)
              0
              (length (state-db-get-code
                       state
                       (make-address
                        (subseq (ethereum-lisp.crypto::integer-to-fixed-bytes
                                 slot 32)
                                12))))))))))

(defun premerge-test-oversized-code-outcomes (config)
  "The deployed code lengths of the transaction and the CREATE path."
  (list (premerge-test-created-code-length config)
        (premerge-test-create-opcode-code-length config)))


(deftest premerge-eip170-code-size-limit-starts-at-spurious-dragon
  ;; go-ethereum v1.17.6 core/vm/common.go CheckMaxCodeSize checks nothing
  ;; before IsEIP158, and core/vm/evm.go initNewContract calls it on both the
  ;; transaction and the CREATE path.
  (is (equal '(24577 24577)
             (premerge-test-oversized-code-outcomes
              (premerge-test-config :homestead-block 0 :eip150-block 0
                                    :eip155-block 0))))
  ;; Positive control: from Spurious Dragon both deployments fail.
  (is (equal '(0 0)
             (premerge-test-oversized-code-outcomes
              (premerge-test-config :homestead-block 0 :eip150-block 0
                                    :eip155-block 0 :eip158-block 0)))))

;;; (5) Single-flag rule sets read the Spurious Dragon rules cumulatively

(deftest premerge-single-flag-rules-imply-spurious-dragon
  ;; Production rules are cumulative (CHAIN-CONFIG-RULES), but RPC and focused
  ;; callers may name only the latest fork. :CANCUN-P alone must still give a
  ;; created contract nonce 1 (EIP-161), delete a touched empty account and
  ;; price EXP's exponent at 50 gas a byte (EIP-160).
  (let* ((rules (make-chain-rules :cancun-p t))
         (sender (premerge-test-sender))
         (empty (address-from-hex "0x00000000000000000000000000000000000000ee"))
         (exp-contract
           (address-from-hex "0x00000000000000000000000000000000000000e8"))
         ;; PUSH1 0xff PUSH1 2 EXP STOP: a one-byte exponent.
         (exp-code (hex-to-bytes "0x60ff60020a00"))
         (state (make-state-db)))
    (state-db-set-account state sender (make-state-account
                                        :balance (expt 10 18)))
    (state-db-set-account state empty (make-state-account))
    (state-db-set-account state exp-contract (make-state-account))
    (state-db-set-code state exp-contract exp-code)
    (let ((create (premerge-test-sign
                   (make-legacy-transaction :nonce 0 :gas-price 1
                                            :gas-limit 100000 :to nil :value 0
                                            :data (hex-to-bytes "0x00"))
                   :chain-id 1))
          (touch (premerge-test-sign
                  (make-legacy-transaction :nonce 1 :gas-price 1
                                           :gas-limit 21000 :to empty
                                           :value 0)
                  :chain-id 1))
          (exponent (premerge-test-sign
                     (make-legacy-transaction :nonce 2 :gas-price 1
                                              :gas-limit 100000
                                              :to exp-contract :value 0)
                     :chain-id 1)))
      (apply-signed-message state create :expected-chain-id 1
                                         :chain-rules rules)
      (let ((created (state-db-get-account
                      state
                      (ethereum-lisp.execution::execution-create-address
                       sender 0))))
        (is created)
        (is (= 1 (state-account-nonce created))))
      (apply-signed-message state touch :expected-chain-id 1
                                        :chain-rules rules)
      (is (null (state-db-get-account state empty)))
      ;; 21,000 + PUSH1 3 + PUSH1 3 + EXP (10 + 50 x 1 byte).
      (is (= 21066
             (receipt-cumulative-gas-used
              (apply-signed-message state exponent :expected-chain-id 1
                                                   :chain-rules rules)))))))

;;; (4) eth/68 Status total difficulty

(defparameter *premerge-test-genesis-json*
  "{\"config\":{\"chainId\":1337,\"homesteadBlock\":0,\"terminalTotalDifficulty\":1000000000000000000000},\"nonce\":\"0x0\",\"timestamp\":\"0x0\",\"extraData\":\"0x\",\"gasLimit\":\"0x1c9c380\",\"difficulty\":\"0x20000\",\"mixHash\":\"0x0000000000000000000000000000000000000000000000000000000000000000\",\"coinbase\":\"0x0000000000000000000000000000000000000000\",\"alloc\":{}}"
  "A proof-of-work genesis with a TTD its chain has not reached.")

(deftest premerge-eth-status-advertises-the-head-total-difficulty
  ;; go-ethereum v1.14.13 eth/handler.go runEthPeer: td =
  ;; h.chain.GetTd(hash, number) of the current header goes into the eth/68
  ;; Status. Our Status sent the configured TTD whatever the head was.
  (let ((node (ethereum-lisp.cli:make-devnet-node
               :genesis-json *premerge-test-genesis-json* :port 0)))
    (flet ((status-total-difficulty (status)
             (ethereum-lisp.eth-wire:eth-status-total-difficulty status)))
      (is (= #x20000
             (status-total-difficulty
              (ethereum-lisp.cli::devnet-peer-sync-status node))))
      ;; The view inbound handshakes read without the store guard agrees.
      (ethereum-lisp.cli::devnet-node-publish-status-view node)
      (is (= #x20000
             (status-total-difficulty
              (ethereum-lisp.cli::devnet-peer-published-sync-status node))))
      ;; A store that cannot know the total (a chain entered at a pivot)
      ;; still advertises the TTD, as before.
      (clrhash
       (ethereum-lisp.chain-store.state:memory-chain-store-total-difficulties
        (ethereum-lisp.chain-store.state:chain-store-require-memory-store
         (ethereum-lisp.cli:devnet-node-store node))))
      (is (= (expt 10 21)
             (status-total-difficulty
              (ethereum-lisp.cli::devnet-peer-sync-status node)))))
    ;; A configuration that fixes the Merge (TTD zero, as Hoodi's netsplit
    ;; block 0 does) keeps advertising its TTD whatever the head's total.
    (let ((fixed (ethereum-lisp.cli:make-devnet-node
                  :genesis-json
                  "{\"config\":{\"chainId\":1337,\"homesteadBlock\":0,\"terminalTotalDifficulty\":0},\"nonce\":\"0x0\",\"timestamp\":\"0x0\",\"extraData\":\"0x\",\"gasLimit\":\"0x1c9c380\",\"difficulty\":\"0x20000\",\"mixHash\":\"0x0000000000000000000000000000000000000000000000000000000000000000\",\"coinbase\":\"0x0000000000000000000000000000000000000000\",\"alloc\":{}}"
                  :port 0)))
      (is (= 0 (ethereum-lisp.eth-wire:eth-status-total-difficulty
                (ethereum-lisp.cli::devnet-peer-sync-status fixed)))))))

;;; (6) The DAO drain and ommer rewards on a synthetic chain

(defun premerge-test-dao-drain-addresses ()
  (mapcar #'address-from-hex
          ethereum-lisp.execution::+dao-drain-address-hexes+))

(deftest premerge-dao-fork-block-drains-into-the-refund-contract
  ;; go-ethereum v1.17.6 core/state_processor.go Process applies
  ;; consensus/misc/dao.go ApplyDAOHardFork at exactly DAOForkBlock, before the
  ;; transactions: the refund contract is created when absent, and every
  ;; drain-list account's balance moves into it. Its AddBalance/SubBalance
  ;; create each absent drain account (getOrNewStateObject); before EIP-158
  ;; nothing deletes those empty accounts, so they are in the state root.
  (let* ((config (premerge-test-config :homestead-block 0 :dao-fork-block 3
                                       :dao-fork-support t))
         (drains (premerge-test-dao-drain-addresses))
         (refund (address-from-hex
                  "0xbf4ed7b27f1d666546e30d74d50d173d20bca754"))
         (dao-extra (ascii-to-bytes "dao-hard-fork"))
         (block-reward 5000000000000000000))
    (is (= 116 (length drains)))
    (multiple-value-bind (store genesis)
        (premerge-test-genesis-store
         (list (cons (first drains) (make-state-account :balance 7))
               (cons (second drains) (make-state-account :balance 11
                                                         :nonce 3))))
      (let* ((block-1 (premerge-test-import
                       store config
                       (premerge-test-child store config genesis)))
             (block-2 (premerge-test-import
                       store config
                       (premerge-test-child store config block-1)))
             (state-2 (chain-store-state-db store (block-hash block-2))))
        ;; Nothing moves before the fork block.
        (is (null (state-db-get-account state-2 refund)))
        (is (= 7 (premerge-test-balance state-2 (first drains))))
        (is (null (state-db-get-account state-2 (third drains))))
        ;; The fork block must carry the extra data (positive control that
        ;; the header rule is on), and then drains.
        (let ((refusal (premerge-test-refusal
                        (lambda ()
                          (premerge-test-import
                           store config
                           (premerge-test-child store config block-2))))))
          (is refusal)
          (is (search "dao-hard-fork" refusal)))
        (let* ((block-3 (premerge-test-import
                         store config
                         (premerge-test-child store config block-2
                                              :extra-data dao-extra)))
               (state-3 (chain-store-state-db store (block-hash block-3))))
          (is (= 18 (premerge-test-balance state-3 refund)))
          (is (= 0 (premerge-test-balance state-3 (first drains))))
          (is (= 0 (premerge-test-balance state-3 (second drains))))
          (is (= 3 (state-account-nonce
                    (state-db-get-account state-3 (second drains)))))
          ;; Every absent drain account now exists, empty.
          (is (every (lambda (address)
                       (let ((account (state-db-get-account state-3 address)))
                         (and account
                              (zerop (state-account-balance account))
                              (zerop (state-account-nonce account)))))
                     (cddr drains)))
          (is (= (* 3 block-reward)
                 (premerge-test-balance state-3 *premerge-test-miner*)))
          ;; The drain is a one-block transition: block 4 moves nothing.
          (let* ((block-4 (premerge-test-import
                           store config
                           (premerge-test-child store config block-3
                                                :extra-data dao-extra)))
                 (state-4 (chain-store-state-db store (block-hash block-4))))
            (is (= 18 (premerge-test-balance state-4 refund)))))))))

(defun premerge-test-ommer-chain (config)
  "Import genesis -> B1 -> B2 (ommer U1, a sibling of B1) -> B3 (ommers U2, a
sibling of B2, and U3, another sibling of B1) under CONFIG; return the state
after B3 and the three ommer beneficiaries."
  (let ((u1 (address-from-hex "0x00000000000000000000000000000000000000d1"))
        (u2 (address-from-hex "0x00000000000000000000000000000000000000d2"))
        (u3 (address-from-hex "0x00000000000000000000000000000000000000d3")))
    (multiple-value-bind (store genesis) (premerge-test-genesis-store '())
      (let* ((b1 (premerge-test-import
                  store config (premerge-test-child store config genesis)))
             (ommer-1 (block-header
                       (premerge-test-child store config genesis
                                            :beneficiary u1 :seconds 14)))
             (ommer-3 (block-header
                       (premerge-test-child store config genesis
                                            :beneficiary u3 :seconds 15)))
             (b2 (premerge-test-import
                  store config
                  (premerge-test-child store config b1
                                       :ommers (list ommer-1))))
             (ommer-2 (block-header
                       (premerge-test-child store config b1
                                            :beneficiary u2 :seconds 14)))
             (b3 (premerge-test-import
                  store config
                  (premerge-test-child store config b2
                                       :ommers (list ommer-2 ommer-3)))))
        (values (chain-store-state-db store (block-hash b3)) u1 u2 u3)))))

(deftest premerge-ommer-rewards-follow-accumulate-rewards
  ;; go-ethereum v1.17.6 consensus/ethash/consensus.go accumulateRewards: the
  ;; base reward R is 5 ETH (Frontier), 3 (Byzantium) or 2 (Constantinople);
  ;; each ommer U of block N pays U.Coinbase (U.Number + 8 - N) * R / 8, and
  ;; the miner gets R plus R / 32 per ommer.
  (dolist (case (list (list (premerge-test-config) 5000000000000000000)
                      (list (premerge-test-config :homestead-block 0
                                                  :eip150-block 0
                                                  :eip155-block 0
                                                  :eip158-block 0
                                                  :byzantium-block 0)
                            3000000000000000000)
                      (list (premerge-test-config :homestead-block 0
                                                  :eip150-block 0
                                                  :eip155-block 0
                                                  :eip158-block 0
                                                  :byzantium-block 0
                                                  :constantinople-block 0
                                                  :petersburg-block 0)
                            2000000000000000000)))
    (destructuring-bind (config reward) case
      (multiple-value-bind (state u1 u2 u3) (premerge-test-ommer-chain config)
        (flet ((ommer-reward (ommer-number block-number)
                 (ash (* (- (+ ommer-number 8) block-number) reward) -3)))
          (is (= (+ reward
                    (+ reward (ash reward -5))
                    (+ reward (* 2 (ash reward -5))))
                 (premerge-test-balance state *premerge-test-miner*)))
          (is (= (ommer-reward 1 2) (premerge-test-balance state u1)))
          (is (= (ommer-reward 2 3) (premerge-test-balance state u2)))
          (is (= (ommer-reward 1 3) (premerge-test-balance state u3))))))))

;;; (7) Public RPC recovers a stored transaction's sender with its block's
;;; signer, and a pooled one's with the head's

(defun premerge-test-rpc (store config method &rest params)
  "The response object of METHOD with PARAMS (Lisp JSON values) on STORE."
  (engine-rpc-handle-request
   (list (cons "jsonrpc" "2.0") (cons "id" 1)
         (cons "method" method) (cons "params" params))
   store
   config))

(defun premerge-test-field (object &rest path)
  "The value at PATH in OBJECT: a string names an object member, an integer a
sequence element."
  (dolist (step path object)
    (setf object (if (integerp step)
                     (elt object step)
                     (cdr (assoc step object :test #'string=))))))

(deftest premerge-rpc-recovers-a-frontier-high-s-sender-with-the-block-signer
  ;; go-ethereum v1.17.6 internal/ethapi/api.go newRPCTransaction recovers
  ;; `from` with types.MakeSigner(config, blockNumber, blockTime); so do
  ;; GetBlockReceipts, eth/tracers and eth/gasprice. RED at 05bbd4c5: every
  ;; view asked the latest signer, which refuses a Frontier block's high-s
  ;; signature, so each lookup below answered -32602 "sender recovery
  ;; failed" and the raw lookup answered null.
  (let* ((sender (premerge-test-sender))
         (sender-hex (address-to-hex sender))
         (transaction
           (premerge-test-sign
            (make-legacy-transaction :nonce 0 :gas-price 1 :gas-limit 21000
                                     :to *premerge-test-recipient* :value 7)
            :high-s-p t))
         (hash-hex (hash32-to-hex (transaction-hash transaction)))
         (frontier (premerge-test-config))
         (homestead (premerge-test-config :homestead-block 0)))
    (is (null (transaction-sender transaction)))
    (multiple-value-bind (store genesis)
        (premerge-test-genesis-store
         (list (cons sender (make-state-account :balance (expt 10 18)))))
      (let* ((block (premerge-test-import
                     store frontier
                     (premerge-test-child store frontier genesis
                                          :transactions (list transaction))))
             (block-hash-hex (hash32-to-hex (block-hash block))))
        (ethereum-lisp.canonical-chain:chain-store-set-canonical-head
         store (block-hash block) :expected-chain-id 1 :chain-config frontier)
        (flet ((rpc (&rest call)
                 (apply #'premerge-test-rpc store frontier call)))
          (is (equal sender-hex
                     (premerge-test-field
                      (rpc "eth_getTransactionByHash" hash-hex)
                      "result" "from")))
          (is (equal sender-hex
                     (premerge-test-field
                      (rpc "eth_getTransactionByBlockHashAndIndex"
                           block-hash-hex "0x0")
                      "result" "from")))
          (is (equal sender-hex
                     (premerge-test-field
                      (rpc "eth_getBlockByNumber" "0x1" t)
                      "result" "transactions" 0 "from")))
          (is (equal sender-hex
                     (premerge-test-field
                      (rpc "eth_getTransactionReceipt" hash-hex)
                      "result" "from")))
          (is (equal sender-hex
                     (premerge-test-field
                      (rpc "eth_getBlockReceipts" "0x1")
                      "result" 0 "from")))
          (is (equal (bytes-to-hex (transaction-encoding transaction))
                     (premerge-test-field
                      (rpc "eth_getRawTransactionByHash" hash-hex)
                      "result")))
          (is (equal sender-hex
                     (premerge-test-field
                      (rpc "debug_traceTransaction" hash-hex)
                      "result" "from"))))
        ;; Control: a configuration that puts the block after Homestead
        ;; selects HomesteadSigner, which refuses the same signature.
        (is (= -32602
               (premerge-test-field
                (premerge-test-rpc store homestead
                                   "eth_getTransactionByHash" hash-hex)
                "error" "code")))))))

(deftest premerge-rpc-lists-a-pooled-transaction-under-the-pool-signer
  ;; A pooled transaction keeps the signer the pool admitted it with, the
  ;; latest (geth's txpool uses types.LatestSigner). geth v1.17.6
  ;; NewRPCPendingTransaction renders it with the head's MakeSigner but still
  ;; lists one that signer cannot recover (with a zero `from`); since our
  ;; pool views list only recoverable senders, the head's signer would hide
  ;; an EIP-155 protected transaction under a pre-EIP-155 head that geth
  ;; lists. Pins the listing under such a head.
  (let* ((sender (premerge-test-sender))
         (pooled
           (premerge-test-sign
            (make-legacy-transaction :nonce 0 :gas-price 1 :gas-limit 21000
                                     :to *premerge-test-recipient* :value 9)
            :chain-id 1))
         (frontier (premerge-test-config)))
    (multiple-value-bind (store genesis)
        (premerge-test-genesis-store
         (list (cons sender (make-state-account :balance (expt 10 18)))))
      (ethereum-lisp.canonical-chain:chain-store-set-canonical-head
       store (block-hash genesis) :expected-chain-id 1 :chain-config frontier)
      (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
       store pooled)
      (is (equal (address-to-hex sender)
                 (premerge-test-field
                  (premerge-test-rpc store frontier "eth_pendingTransactions")
                  "result" 0 "from")))
      (is (equal "0x1"
                 (premerge-test-field
                  (premerge-test-rpc store frontier "txpool_status")
                  "result" "pending"))))))

;;; (8) Single-flag rule sets read every fork predicate cumulatively

(defparameter *premerge-test-mainnet-fork-flags*
  '((:frontier)
    (:homestead :homestead-p)
    (:tangerine-whistle :eip150-p)
    (:spurious-dragon :eip155-p :eip158-p)
    (:byzantium :byzantium-p)
    (:constantinople :constantinople-p)
    (:petersburg :petersburg-p)
    (:istanbul :istanbul-p)
    (:berlin :berlin-p)
    (:london :london-p)
    (:shanghai :shanghai-p)
    (:cancun :cancun-p)
    (:prague :prague-p)
    (:osaka :osaka-p)
    (:bpo1 :bpo1-p)
    (:bpo2 :bpo2-p)
    (:amsterdam :amsterdam-p))
  "Mainnet's fork order (Paris sets no rule flag) with the MAKE-CHAIN-RULES
flags each fork sets, then Amsterdam.")

(defun premerge-test-fork-rules (index &key cumulative-p)
  "Rules for the fork at INDEX of *PREMERGE-TEST-MAINNET-FORK-FLAGS*: that
fork's flags alone, or with CUMULATIVE-P every flag up to it."
  (apply #'make-chain-rules
         (loop for (nil . flags)
                 in (if cumulative-p
                        (subseq *premerge-test-mainnet-fork-flags* 0 (1+ index))
                        (list (nth index *premerge-test-mainnet-fork-flags*)))
               append (loop for flag in flags append (list flag t)))))

(defun premerge-test-ordered-config ()
  "A configuration activating the fork at index I of
*PREMERGE-TEST-MAINNET-FORK-FLAGS* at block I and, from Shanghai, at time I."
  (make-chain-config :chain-id 1
                     :homestead-block 1 :eip150-block 2 :eip155-block 3
                     :eip158-block 3 :byzantium-block 4 :constantinople-block 5
                     :petersburg-block 6 :istanbul-block 7 :berlin-block 8
                     :london-block 9 :shanghai-time 10 :cancun-time 11
                     :prague-time 12 :osaka-time 13 :bpo1-time 14 :bpo2-time 15
                     :amsterdam-time 16))

(defun premerge-test-typed-transaction (type)
  "A transaction of envelope TYPE; only its type is read."
  (ecase type
    (1 (make-access-list-transaction :chain-id 1))
    (2 (make-dynamic-fee-transaction :chain-id 1))
    (3 (make-blob-transaction :chain-id 1))
    (4 (make-set-code-transaction :chain-id 1))))

(deftest premerge-fork-predicates-are-cumulative-over-the-mainnet-order
  ;; go-ethereum v1.17.6 params/config.go IsHomestead, IsEIP155, IsEIP158,
  ;; IsLondon and IsShanghai are "activated at or after", and those forks are
  ;; mandatory in CheckConfigForkOrder, so ChainConfig.Rules sets them for
  ;; every later fork; MakeSigner (core/types/transaction_signing.go) picks the
  ;; latest of the Prague, Cancun, London and Berlin signers, each accepting
  ;; its own envelope type and every earlier one. A rule set naming only its
  ;; latest fork (:CANCUN-P alone) must answer each predicate as the
  ;; cumulative set and CHAIN-CONFIG-RULES do. RED at 05bbd4c5: initcode
  ;; metering and the 0xEF prefix read only :SHANGHAI-P and :LONDON-P, an
  ;; envelope type only its own fork's flag, and the expanded blob schedule
  ;; missed Amsterdam.
  (let ((config (premerge-test-ordered-config))
        (checks
          (list
           (list :homestead
                 #'ethereum-lisp.chain-config:chain-rules-homestead-active-p)
           (list :spurious-dragon
                 #'ethereum-lisp.chain-config:chain-rules-eip155-active-p)
           (list :spurious-dragon
                 #'ethereum-lisp.chain-config:chain-rules-eip158-active-p)
           (list :spurious-dragon
                 #'ethereum-lisp.chain-config:chain-rules-code-size-limited-p)
           (list :london #'chain-rules-code-prefix-restricted-p)
           (list :shanghai #'chain-rules-initcode-metering-p)
           (list :prague #'chain-rules-expanded-blob-schedule-p)
           (list :berlin (lambda (rules)
                           (chain-rules-transaction-type-supported-p
                            rules (premerge-test-typed-transaction 1))))
           (list :london (lambda (rules)
                           (chain-rules-transaction-type-supported-p
                            rules (premerge-test-typed-transaction 2))))
           (list :cancun (lambda (rules)
                           (chain-rules-transaction-type-supported-p
                            rules (premerge-test-typed-transaction 3))))
           (list :prague (lambda (rules)
                           (chain-rules-transaction-type-supported-p
                            rules (premerge-test-typed-transaction 4)))))))
    (loop for (fork) in *premerge-test-mainnet-fork-flags*
          for index from 0
          for single = (premerge-test-fork-rules index)
          for cumulative = (premerge-test-fork-rules index :cumulative-p t)
          for configured = (chain-config-rules config index index)
          do (loop for (activation predicate) in checks
                   for expected = (>= index
                                      (position activation
                                                *premerge-test-mainnet-fork-flags*
                                                :key #'first))
                   for answers = (mapcar (lambda (rules)
                                           (not (null (funcall predicate rules))))
                                         (list single cumulative configured))
                   do (unless (every (lambda (answer) (eq expected answer))
                                     answers)
                        (error "~A predicate at ~A: expected ~A, single, ~
                                cumulative and configured answered ~S"
                               activation fork expected answers))))
    ;; NIL rules are the latest fork for every predicate above.
    (loop for (nil predicate) in checks
          do (is (funcall predicate nil)))))
