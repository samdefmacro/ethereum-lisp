(in-package #:ethereum-lisp.test)

(defun byte-prefix-padded (bytes size)
  (let* ((bytes (ensure-byte-vector bytes))
         (result (make-byte-vector size))
         (available (min size (length bytes))))
    (replace result bytes :end2 available)
    result))

(deftest evm-adds-two-numbers
  (let ((result (execute-bytecode #(96 2 96 3 1 0))))
    (is (eq :stopped (evm-result-status result)))
    (is (= 5 (first (evm-result-stack result))))
    (is (= 9 (evm-result-gas-used result)))))

(deftest evm-public-package-is-a-thin-facade
  (let ((public (find-package '#:ethereum-lisp.evm))
        (internal (find-package '#:ethereum-lisp.evm.internal)))
    (dolist (name '("EVM-CONTEXT" "EVM-RESULT" "EXECUTE-BYTECODE"))
      (multiple-value-bind (public-symbol public-status)
          (find-symbol name public)
        (multiple-value-bind (internal-symbol internal-status)
            (find-symbol name internal)
          (is (eq :external public-status))
          (is (eq :external internal-status))
          (is (eq public-symbol internal-symbol)))))
    (multiple-value-bind (symbol status)
        (find-symbol "RUN-PRECOMPILE" public)
      (is (null symbol))
      (is (null status)))
    (is (not (member (find-package '#:ethereum-lisp.core)
                     (package-use-list public))))
    (is (not (member (find-package '#:ethereum-lisp.state)
                     (package-use-list public))))))

(deftest runtime-domain-packages-do-not-depend-on-core
  (let ((core (find-package '#:ethereum-lisp.core))
        (state (find-package '#:ethereum-lisp.state))
        (json (find-package '#:ethereum-lisp.json))
        (state-proof-json
          (find-package '#:ethereum-lisp.state-proof-json))
        (genesis (find-package '#:ethereum-lisp.genesis))
        (genesis-state (find-package '#:ethereum-lisp.genesis-state))
        (evm-internal (find-package '#:ethereum-lisp.evm.internal))
        (execution (find-package '#:ethereum-lisp.execution))
        (execution-service
          (find-package '#:ethereum-lisp.execution-service))
        (accounts (find-package '#:ethereum-lisp.accounts))
        (chain-store (find-package '#:ethereum-lisp.chain-store)))
    (dolist (package (list state state-proof-json genesis-state evm-internal
                           execution execution-service))
      (is (not (member core (package-use-list package)))))
    (is (member accounts (package-use-list state)))
    (is (not (member json (package-use-list state))))
    (is (member state (package-use-list state-proof-json)))
    (is (not (member genesis (package-use-list state))))
    (is (member genesis (package-use-list genesis-state)))
    (is (member state (package-use-list genesis-state)))
    (is (member state (package-use-list evm-internal)))
    (is (member state (package-use-list execution)))
    (is (not (member chain-store (package-use-list execution))))
    (is (member chain-store (package-use-list execution-service)))
    (is (member execution (package-use-list execution-service)))
    (dolist (name '("STATE-DB-FROM-GENESIS-ALLOC"
                    "GENESIS-BLOCK-FROM-STATE-GENESIS-JSON-STRING"))
      (multiple-value-bind (owner-symbol owner-status)
          (find-symbol name genesis-state)
        (multiple-value-bind (compatibility-symbol compatibility-status)
            (find-symbol name state)
          (is (eq :external owner-status))
          (is (eq :external compatibility-status))
          (is (eq owner-symbol compatibility-symbol))
          (is (eq genesis-state (symbol-package owner-symbol))))))
    (multiple-value-bind (owner-symbol owner-status)
        (find-symbol "STATE-PROOF-RESULT-RPC-OBJECT" state-proof-json)
      (multiple-value-bind (compatibility-symbol compatibility-status)
          (find-symbol "STATE-PROOF-RESULT-RPC-OBJECT" state)
        (is (eq :external owner-status))
        (is (eq :external compatibility-status))
        (is (eq owner-symbol compatibility-symbol))
        (is (eq state-proof-json (symbol-package owner-symbol)))))
    (multiple-value-bind (owner-symbol owner-status)
        (find-symbol "TRANSACTION-INTRINSIC-GAS" execution)
      (multiple-value-bind (compatibility-symbol compatibility-status)
          (find-symbol "TRANSACTION-INTRINSIC-GAS" state)
        (is (eq :external owner-status))
        (is (eq :external compatibility-status))
        (is (eq owner-symbol compatibility-symbol))
        (is (eq execution (symbol-package owner-symbol)))))
    (dolist (name '("CHAIN-STORE-STATE-DB"
                    "EXECUTE-AND-COMMIT-ENGINE-PAYLOAD"))
      (multiple-value-bind (owner-symbol owner-status)
          (find-symbol name execution-service)
        (multiple-value-bind (compatibility-symbol compatibility-status)
            (find-symbol name execution)
          (is (eq :external owner-status))
          (is (eq :external compatibility-status))
          (is (eq owner-symbol compatibility-symbol))
          (is (eq execution-service (symbol-package owner-symbol))))))))

(deftest evm-context-carries-chain-rules
  (let* ((rules (make-chain-rules :chain-id 1 :london-p t :prague-p t))
         (context (make-evm-context :chain-id 1 :chain-rules rules)))
    (is (eq rules (evm-context-chain-rules context)))
    (is (chain-rules-london-p (evm-context-chain-rules context)))
    (is (chain-rules-prague-p (evm-context-chain-rules context)))))

(deftest evm-chain-rules-gate-fork-opcodes
  (let* ((pre-shanghai
           (make-evm-context :chain-rules
                             (make-chain-rules :chain-id 1 :london-p t)))
         (shanghai
           (make-evm-context :chain-rules
                             (make-chain-rules :chain-id 1
                                               :london-p t
                                               :shanghai-p t)))
         (pre-cancun
           (make-evm-context :chain-rules
                             (make-chain-rules :chain-id 1
                                               :london-p t
                                               :shanghai-p t)))
         (cancun
           (make-evm-context :chain-rules
                             (make-chain-rules :chain-id 1
                                               :london-p t
                                               :shanghai-p t
                                               :cancun-p t)
                             :blob-base-fee 7)))
    (signals evm-error
      (execute-bytecode #(#x5f 0) :context pre-shanghai))
    (is (= 0 (first (evm-result-stack
                     (execute-bytecode #(#x5f 0) :context shanghai)))))
    (signals evm-error
      (execute-bytecode #(96 0 96 0 96 0 #x5e 0) :context pre-cancun))
    (signals evm-error
      (execute-bytecode #(96 0 #x5c 0) :context pre-cancun))
    (signals evm-error
      (execute-bytecode #(96 2 96 1 #x5d 0) :context pre-cancun))
    (signals evm-error
      (execute-bytecode #(96 0 #x49 0) :context pre-cancun))
    (signals evm-error
      (execute-bytecode #(#x4a 0) :context pre-cancun))
    (is (eq :stopped
            (evm-result-status
             (execute-bytecode #(96 0 96 0 96 0 #x5e 0)
                               :context cancun))))
    (is (= 0 (first (evm-result-stack
                     (execute-bytecode #(96 0 #x5c 0) :context cancun)))))
    (is (= 7 (first (evm-result-stack
                     (execute-bytecode #(#x4a 0) :context cancun)))))))

(deftest evm-chain-rules-gate-environment-opcodes
  (let* ((state (make-state-db))
         (address (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (pre-istanbul
           (make-evm-context :state state
                             :address address
                             :chain-id 7
                             :base-fee 11
                             :chain-rules
                             (make-chain-rules :chain-id 7
                                               :constantinople-p t)))
         (istanbul
           (make-evm-context :state state
                             :address address
                             :chain-id 7
                             :base-fee 11
                             :chain-rules
                             (make-chain-rules :chain-id 7
                                               :constantinople-p t
                                               :istanbul-p t)))
         (london
           (make-evm-context :state state
                             :address address
                             :chain-id 7
                             :base-fee 11
                             :chain-rules
                             (make-chain-rules :chain-id 7
                                               :constantinople-p t
                                               :istanbul-p t
                                               :berlin-p t
                                               :london-p t))))
    (state-db-add-balance state address 13)
    (signals evm-error
      (execute-bytecode #(#x46 0) :context pre-istanbul))
    (signals evm-error
      (execute-bytecode #(#x47 0) :context pre-istanbul))
    (signals evm-error
      (execute-bytecode #(#x48 0) :context istanbul))
    (is (= 7 (first (evm-result-stack
                     (execute-bytecode #(#x46 0) :context istanbul)))))
    (let ((selfbalance (execute-bytecode #(#x47 0) :context istanbul)))
      (is (= 13 (first (evm-result-stack selfbalance))))
      (is (= 5 (evm-result-gas-used selfbalance))))
    (is (= 11 (first (evm-result-stack
                      (execute-bytecode #(#x48 0) :context london)))))))

(deftest evm-chain-rules-gate-legacy-fork-opcodes
  (let* ((state (make-state-db))
         (address (address-from-hex "0x00000000000000000000000000000000000000aa"))
         (frontier (make-evm-context :state state
                                     :address address
                                     :chain-rules
                                     (make-chain-rules :chain-id 1)))
         (homestead (make-evm-context :state state
                                      :address address
                                      :chain-rules
                                      (make-chain-rules :chain-id 1
                                                        :homestead-p t)))
         (pre-byzantium
           (make-evm-context :state state
                             :address address
                             :chain-rules
                             (make-chain-rules :chain-id 1
                                               :homestead-p t
                                               :eip150-p t
                                               :eip158-p t)))
         (byzantium
           (make-evm-context :state state
                             :address address
                             :chain-rules
                             (make-chain-rules :chain-id 1
                                               :homestead-p t
                                               :eip150-p t
                                               :eip158-p t
                                               :byzantium-p t)))
         (pre-constantinople byzantium)
         (constantinople
           (make-evm-context :state state
                             :address address
                             :chain-rules
                             (make-chain-rules :chain-id 1
                                               :homestead-p t
                                               :eip150-p t
                                               :eip158-p t
                                               :byzantium-p t
                                               :constantinople-p t))))
    (signals evm-error
      (execute-bytecode #(96 0 96 0 96 0 96 0 96 0 96 0 #xf4 0)
                        :context frontier))
    (is (eq :stopped
            (evm-result-status
             (execute-bytecode #(96 0 96 0 96 0 96 0 96 0 96 0 #xf4 0)
                               :context homestead))))
    (dolist (code (list #(#x3d 0)
                        #(96 0 96 0 96 0 #x3e 0)
                        #(96 0 96 0 #xfd)
                        #(96 0 96 0 96 0 96 0 96 0 96 0 #xfa 0)))
      (signals evm-error
        (execute-bytecode code :context pre-byzantium)))
    (is (= 0 (first (evm-result-stack
                     (execute-bytecode #(#x3d 0) :context byzantium)))))
    (is (eq :stopped
            (evm-result-status
             (execute-bytecode #(96 0 96 0 96 0 #x3e 0)
                               :context byzantium))))
    (is (eq :reverted
            (evm-result-status
             (execute-bytecode #(96 0 96 0 #xfd) :context byzantium))))
    (is (eq :stopped
            (evm-result-status
             (execute-bytecode #(96 0 96 0 96 0 96 0 96 0 96 0 #xfa 0)
                               :context byzantium))))
    (dolist (code (list #(96 1 96 1 #x1b 0)
                        #(96 1 96 2 #x1c 0)
                        #(96 1 96 2 #x1d 0)
                        #(96 0 #x3f 0)
                        #(96 0 96 0 96 0 96 0 #xf5 0)))
      (signals evm-error
        (execute-bytecode code :context pre-constantinople)))
    (is (= 2 (first (evm-result-stack
                     (execute-bytecode #(96 1 96 1 #x1b 0)
                                       :context constantinople)))))
    (is (eq :stopped
            (evm-result-status
             (execute-bytecode #(96 0 #x3f 0) :context constantinople))))
    (is (eq :stopped
            (evm-result-status
            (execute-bytecode #(96 0 96 0 96 0 96 0 #xf5 0)
                               :context constantinople))))))

(deftest evm-chain-rules-gate-active-precompiles
  (let* ((frontier-rules (make-chain-rules :chain-id 1))
         (byzantium-rules (make-chain-rules :chain-id 1 :byzantium-p t))
         (istanbul-rules (make-chain-rules :chain-id 1
                                           :byzantium-p t
                                           :istanbul-p t))
         (cancun-rules (make-chain-rules :chain-id 1
                                         :byzantium-p t
                                         :istanbul-p t
                                         :berlin-p t
                                         :london-p t
                                         :shanghai-p t
                                         :cancun-p t))
         (frontier-context (make-evm-context :chain-rules frontier-rules))
         (cancun-context (make-evm-context :chain-rules cancun-rules))
         (frontier-accesses (evm-context-accessed-addresses frontier-context))
         (cancun-accesses (evm-context-accessed-addresses cancun-context)))
    (is (ethereum-lisp.evm.internal::active-precompile-address-number-p 4
                                                              frontier-rules))
    (is (not (ethereum-lisp.evm.internal::active-precompile-address-number-p
              5 frontier-rules)))
    (is (ethereum-lisp.evm.internal::active-precompile-address-number-p 5
                                                              byzantium-rules))
    (is (not (ethereum-lisp.evm.internal::active-precompile-address-number-p
              9 byzantium-rules)))
    (is (ethereum-lisp.evm.internal::active-precompile-address-number-p 9
                                                              istanbul-rules))
    (is (ethereum-lisp.evm.internal::active-precompile-address-number-p 10
                                                              cancun-rules))
    (is (gethash (address-bytes (ethereum-lisp.evm.internal::precompile-address 4))
                 frontier-accesses))
    (is (not (gethash (address-bytes (ethereum-lisp.evm.internal::precompile-address 5))
                      frontier-accesses)))
    (is (gethash (address-bytes (ethereum-lisp.evm.internal::precompile-address 10))
                 cancun-accesses))
    (multiple-value-bind (output gas active-p)
        (ethereum-lisp.evm.internal::run-precompile
         (ethereum-lisp.evm.internal::precompile-address 5) #() frontier-rules)
      (is (null output))
      (is (= 0 gas))
      (is (not active-p)))
    (multiple-value-bind (output gas active-p)
        (ethereum-lisp.evm.internal::run-precompile
         (ethereum-lisp.evm.internal::precompile-address 5) #() byzantium-rules)
      (is (byte-vector-p output))
      (is (plusp gas))
      (is active-p))))
