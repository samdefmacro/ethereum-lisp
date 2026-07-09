(in-package #:ethereum-lisp.test)

(defconstant +devnet-cli-genesis-fixture+
  "tests/fixtures/execution-spec-tests/phase-a-shanghai-genesis.json")

(defconstant +devnet-cli-jwt-secret+
  "1111111111111111111111111111111111111111111111111111111111111111")

(defconstant +devnet-cli-txpool-private-key+ 1)
(defconstant +devnet-cli-txpool-balance+ 1000000000000000000)
(defconstant +devnet-cli-txpool-gas-price+ 200)
(defconstant +devnet-cli-txpool-pending-gas-price+ 1000000000)
(defconstant +devnet-cli-txpool-basefee-gas-price+ 0)
(defconstant +devnet-cli-txpool-gas-limit+ 21000)
(defconstant +devnet-cli-txpool-value+ 1)
(defconstant +devnet-cli-txpool-recipient+
  "0x0000000000000000000000000000000000003001")

(defparameter +devnet-side-reorg-smoke-case-names+
  '("shanghai-one-transfer-with-withdrawal"
    "shanghai-two-legacy-transfers-with-withdrawal"
    "shanghai-log-contract-call-with-withdrawal"))

(defvar *devnet-cli-temp-counter* 0)

(defun devnet-cli-current-process-id ()
  #+sbcl
  (sb-unix:unix-getpid)
  #-sbcl
  nil)

(defun devnet-cli-current-process-id-string ()
  (let ((process-id (devnet-cli-current-process-id)))
    (if process-id
        (write-to-string process-id)
        "")))

(defun devnet-cli-txpool-sender-address ()
  (fixture-private-key-address +devnet-cli-txpool-private-key+))

(defun devnet-cli-txpool-transaction
    (config nonce gas-price &key
       (private-key +devnet-cli-txpool-private-key+)
       (gas-limit +devnet-cli-txpool-gas-limit+))
  (fixture-sign-legacy-transaction
   (make-legacy-transaction
    :nonce nonce
    :gas-price gas-price
    :gas-limit gas-limit
    :to (address-from-hex +devnet-cli-txpool-recipient+)
    :value +devnet-cli-txpool-value+)
   private-key
   (chain-config-chain-id config)))

(defun devnet-cli-transaction-raw (transaction)
  (bytes-to-hex (transaction-encoding transaction)))

(defun devnet-cli-transaction-nonce-key (transaction)
  (format nil "~D" (transaction-nonce transaction)))

(defun devnet-cli-transaction-summary (transaction)
  (let ((to (transaction-to transaction)))
    (format nil "~A: ~D wei + ~D gas x ~D wei"
            (if to
                (address-to-hex to)
                "contract creation")
            (transaction-value transaction)
            (transaction-gas-limit transaction)
            (transaction-max-fee-per-gas transaction))))

(defun devnet-cli-empty-json-array-p (value)
  (and (vectorp value)
       (zerop (length value))))

(defun devnet-cli-empty-json-array-or-lossy-null-p (value)
  (or (null value)
      (devnet-cli-empty-json-array-p value)))

(defun devnet-cli-temp-token ()
  (format nil "~A-~D-~A"
          (or (devnet-cli-current-process-id) "nopid")
          (incf *devnet-cli-temp-counter*)
          (gensym)))

(defun devnet-cli-temp-path (name type)
  (merge-pathnames
   (make-pathname :name (format nil "~A-~A" name (devnet-cli-temp-token))
                  :type type)
   #P"/private/tmp/"))

(defun devnet-cli-write-temp-file (path contents)
  (with-open-file (stream path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-string contents stream)))

(defun devnet-cli-make-executable (path)
  (uiop:run-program (list "chmod" "755" (namestring path))
                    :output nil
                    :error-output nil)
  path)

(defun devnet-cli-file-string (path)
  (with-open-file (stream path :direction :input)
    (let ((string (make-string (file-length stream))))
      (read-sequence string stream)
      string)))

(defun devnet-cli-funded-txpool-genesis-json
    (&key config-fields gas-limit
       (private-keys (list +devnet-cli-txpool-private-key+)))
  (let* ((genesis (parse-json
                   (devnet-cli-file-string +devnet-cli-genesis-fixture+)))
         (state (state-db-from-genesis-json-file
                 +devnet-cli-genesis-fixture+))
         (config (fixture-object-field genesis "config"))
         (alloc (fixture-object-field genesis "alloc"))
         (accounts nil))
    (dolist (private-key private-keys)
      (let ((sender (fixture-private-key-address private-key))
            (account
              (list (cons "balance"
                          (quantity-to-hex +devnet-cli-txpool-balance+))
                    (cons "nonce" "0x0"))))
        (state-db-set-account
         state
         sender
         (make-state-account :nonce 0
                             :balance +devnet-cli-txpool-balance+))
        (push (cons (address-to-hex sender) account) accounts)))
    (setf (cdr (assoc "stateRoot" genesis :test #'string=))
          (hash32-to-hex (state-db-root state)))
    (dolist (field config-fields)
      (let ((cell (assoc (car field) config :test #'string=)))
        (if cell
            (setf (cdr cell) (cdr field))
            (setf config (append config (list field))))))
    (when gas-limit
      (setf (cdr (assoc "gasLimit" genesis :test #'string=))
            (quantity-to-hex gas-limit)))
    (setf (cdr (assoc "config" genesis :test #'string=)) config)
    (setf (cdr (assoc "alloc" genesis :test #'string=))
          (append alloc (nreverse accounts)))
    (json-encode genesis)))

(defun devnet-cli-pid-file-process-id (path)
  (parse-integer
   (string-trim '(#\Space #\Tab #\Newline #\Return)
                (devnet-cli-file-string path))
   :junk-allowed nil))

(defun devnet-cli-file-forms (path)
  (with-open-file (stream path :direction :input)
    (loop for form = (read stream nil :eof)
          until (eq form :eof)
          collect form)))

