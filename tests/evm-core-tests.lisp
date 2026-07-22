(in-package #:ethereum-lisp.test)

(defun byte-prefix-padded (bytes size)
  (let* ((bytes (ensure-byte-vector bytes))
         (result (make-byte-vector size))
         (available (min size (length bytes))))
    (replace result bytes :end2 available)
    result))

(defun assert-symbol-owned-only-by (name owner &rest non-owners)
  (multiple-value-bind (symbol status)
      (find-symbol name owner)
    (is (eq :external status))
    (is (eq owner (symbol-package symbol))))
  (dolist (package non-owners)
    (multiple-value-bind (symbol status)
        (find-symbol name package)
      (declare (ignore symbol))
      (is (not (eq :external status))))))

(defun ethereum-lisp-project-package-p (package)
  (let ((name (package-name package)))
    (or (string= name "ETHEREUM-LISP")
        (and (> (length name) (length "ETHEREUM-LISP."))
             (string= name "ETHEREUM-LISP."
                      :end1 (length "ETHEREUM-LISP."))))))

(defun ethereum-lisp-source-paths ()
  (let* ((source-root (merge-pathnames #P"src/" *repository-root*))
         (pattern
           (make-pathname
            :directory (append (pathname-directory source-root)
                               (list :wild-inferiors))
            :name :wild
            :type "lisp"
            :defaults source-root)))
    (sort (directory pattern) #'string< :key #'namestring)))

(defun ethereum-lisp-asdf-source-paths ()
  (labels ((collect-source-paths (component)
             (cond
               ((typep component 'asdf:cl-source-file)
                (list (truename (asdf:component-pathname component))))
               ((typep component 'asdf:module)
                (mapcan #'collect-source-paths
                        (asdf:component-children component)))
               (t
                '()))))
    (sort (collect-source-paths (asdf:find-system '#:ethereum-lisp))
          #'string<
          :key #'namestring)))

(defun ethereum-lisp-form-package-dependencies (form owner)
  (let ((dependencies '()))
    (labels ((walk (value)
               (cond
                 ((symbolp value)
                  (let ((home (symbol-package value)))
                    (when (and home
                               (not (eq home owner))
                               (ethereum-lisp-project-package-p home))
                      (pushnew home dependencies))))
                 ((consp value)
                  (walk (car value))
                  (walk (cdr value)))
                 ((vectorp value)
                  (map nil #'walk value)))))
      (walk form))
    dependencies))

(defun ethereum-lisp-source-dependency-table ()
  (let ((dependencies (make-hash-table :test 'eq)))
    (dolist (path (ethereum-lisp-source-paths))
      (with-open-file (stream path :direction :input)
        (let ((*package* (find-package '#:cl-user))
              (owner nil))
          (loop for form = (read stream nil stream)
                until (eq form stream)
                do (if (and (consp form)
                            (symbolp (car form))
                            (string= "IN-PACKAGE" (symbol-name (car form))))
                       (let ((package (find-package (second form))))
                         (unless package
                           (error "Unknown package ~S in ~A" (second form) path))
                         (setf owner package
                               *package* package))
                       (when (and owner
                                  (ethereum-lisp-project-package-p owner))
                         (dolist (dependency
                                  (ethereum-lisp-form-package-dependencies
                                   form owner))
                           (pushnew dependency
                                    (gethash owner dependencies)))))))))
    dependencies))

(defvar *ethereum-lisp-source-dependency-table* nil)

(defun ethereum-lisp-project-dependencies (package)
  (unless *ethereum-lisp-source-dependency-table*
    (setf *ethereum-lisp-source-dependency-table*
          (ethereum-lisp-source-dependency-table)))
  (remove-duplicates
   (append
    (remove-if-not #'ethereum-lisp-project-package-p
                   (package-use-list package))
    (gethash package *ethereum-lisp-source-dependency-table*))
   :test #'eq))

(defun ethereum-lisp-package-dependency-cycle-p (package &optional path)
  (if (member package path)
      t
      (some (lambda (dependency)
              (ethereum-lisp-package-dependency-cycle-p
               dependency
               (cons package path)))
            (ethereum-lisp-project-dependencies package))))

(deftest evm-adds-two-numbers
  (let ((result (execute-bytecode #(96 2 96 3 1 0))))
    (is (eq :stopped (evm-result-status result)))
    (is (= 5 (first (evm-result-stack result))))
    (is (= 9 (evm-result-gas-used result)))))

(deftest evm-public-package-is-a-thin-facade
  (let ((public (find-package '#:ethereum-lisp.evm))
        (internal (find-package '#:ethereum-lisp.evm.internal)))
    (dolist (name '("EVM-CONTEXT"
                    "EVM-RESULT"
                    "EVM-STEP-LIMIT-ERROR"
                    "EVM-STEP-LIMIT-ERROR-LIMIT"
                    "EVM-STEP-LIMIT-ERROR-STEPS"
                    "EVM-STEP-LIMIT-ERROR-PC"
                    "EXECUTE-BYTECODE"))
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

(deftest project-package-dependency-graph-is-acyclic
  (dolist (package (list-all-packages))
    (when (ethereum-lisp-project-package-p package)
      (is (not (ethereum-lisp-package-dependency-cycle-p package))))))

(deftest production-asdf-covers-every-source-file-exactly-once
  (let ((source-paths (mapcar #'truename (ethereum-lisp-source-paths)))
        (asdf-paths (ethereum-lisp-asdf-source-paths)))
    (is (= (length asdf-paths)
           (length (remove-duplicates asdf-paths :test #'equal))))
    (is (equal source-paths asdf-paths))))

(deftest production-asdf-expresses-source-layer-dependencies
  (let* ((system (asdf:find-system '#:ethereum-lisp))
         (source-module
           (find "src"
                 (asdf:component-children system)
                 :test #'string=
                 :key #'asdf:component-name))
         (modules (asdf:component-children source-module)))
    (is (equal
         (mapcar (lambda (component)
                   (cons (asdf:component-name component)
                         (asdf:component-sideway-dependencies component)))
                 modules)
         '(("packages")
           ("foundation" "packages")
           ("protocol" "foundation")
           ("runtime-core" "protocol")
           ("storage-core" "protocol")
           ("application-services" "runtime-core" "storage-core")
           ("networking" "application-services")
           ("persistence-adapters" "application-services")
           ("api" "application-services")
           ("transport" "api")
           ("app" "transport" "persistence-adapters" "networking"))))))

(deftest project-package-dependency-graph-includes-source-references
  (let ((validation (find-package '#:ethereum-lisp.validation))
        (types (find-package '#:ethereum-lisp.types))
        (rlp (find-package '#:ethereum-lisp.rlp))
        (cli (find-package '#:ethereum-lisp.cli))
        (persistence (find-package '#:ethereum-lisp.node-store.persistence)))
    (is (member types (ethereum-lisp-project-dependencies validation)))
    (is (member rlp (ethereum-lisp-project-dependencies validation)))
    (is (member persistence (ethereum-lisp-project-dependencies cli)))))

(deftest domain-packages-own-their-external-symbols
  (let ((facades (mapcar #'find-package
                         '(#:ethereum-lisp
                           #:ethereum-lisp.core
                           #:ethereum-lisp.evm))))
    (dolist (package (list-all-packages))
      (when (and (ethereum-lisp-project-package-p package)
                 (not (member package facades)))
        (do-external-symbols (symbol package)
          (is (eq package (symbol-package symbol))))))))

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
      (assert-symbol-owned-only-by name genesis-state state))
    (assert-symbol-owned-only-by
     "STATE-PROOF-RESULT-RPC-OBJECT" state-proof-json state)
    (assert-symbol-owned-only-by
     "TRANSACTION-INTRINSIC-GAS" execution state)
    (dolist (name '("CHAIN-STORE-STATE-DB"
                    "EXECUTE-AND-COMMIT-ENGINE-PAYLOAD"))
      (assert-symbol-owned-only-by name execution-service execution))))

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
      ;; EIP-198 has no minimum charge: three zero declared lengths cost 0.
      (is (zerop gas))
      (is active-p))))
