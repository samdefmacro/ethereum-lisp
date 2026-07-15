(in-package #:ethereum-lisp.genesis-state)

(defun apply-genesis-account (state account)
  (let ((address (genesis-account-address account)))
    (state-db-set-account
     state address
     (make-state-account :nonce (genesis-account-nonce account)
                         :balance (genesis-account-balance account)))
    (when (plusp (length (genesis-account-code account)))
      (state-db-set-code state address (genesis-account-code account)))
    (dolist (entry (genesis-account-storage account))
      (state-db-set-storage state address (car entry) (cdr entry)))
    state))

(defun apply-genesis-alloc (state alloc)
  (dolist (account alloc state)
    (apply-genesis-account state account)))

(defun state-db-from-genesis-alloc (alloc)
  (apply-genesis-alloc (make-state-db) alloc))

(defun state-db-from-genesis-json-string (string)
  (state-db-from-genesis-alloc
   (genesis-alloc-from-genesis-json-string string)))

(defun state-db-from-genesis-json-file (path)
  (state-db-from-genesis-alloc
   (genesis-alloc-from-genesis-json-file path)))

(defun genesis-state-root-from-genesis-alloc (alloc)
  (state-db-root (state-db-from-genesis-alloc alloc)))

(defun genesis-state-root-from-genesis-json-string (string)
  (genesis-state-root-from-genesis-alloc
   (genesis-alloc-from-genesis-json-string string)))

(defun genesis-state-root-from-genesis-json-file (path)
  (genesis-state-root-from-genesis-alloc
   (genesis-alloc-from-genesis-json-file path)))

(defun validate-genesis-state-root (computed-root expected-root)
  (unless (hash32-p computed-root)
    (error 'block-validation-error
           :message "Computed genesis state root must be a hash32"))
  (unless (hash32-p expected-root)
    (error 'block-validation-error
           :message "Expected genesis state root must be a hash32"))
  (unless (bytes= (hash32-bytes computed-root) (hash32-bytes expected-root))
    (error 'block-validation-error :message "Genesis state root mismatch"))
  t)

(defun validate-genesis-json-state-root (string)
  (let* ((genesis-object (parse-json string))
         (expected-root
           (genesis-expected-state-root-from-genesis-object genesis-object)))
    (unless expected-root
      (error 'block-validation-error :message "Genesis stateRoot is missing"))
    (validate-genesis-state-root
     (genesis-state-root-from-genesis-alloc
      (genesis-alloc-from-genesis-object genesis-object))
     expected-root)))

(defun genesis-header-from-state-genesis-object (object &key config)
  (let* ((computed-root
           (genesis-state-root-from-genesis-alloc
            (genesis-alloc-from-genesis-object object)))
         (expected-root
           (genesis-expected-state-root-from-genesis-object object)))
    (when expected-root
      (validate-genesis-state-root computed-root expected-root))
    (genesis-header-from-genesis-object object
                                        :state-root computed-root
                                        :config config)))

(defun genesis-header-from-state-genesis-json-string (string &key config)
  (genesis-header-from-state-genesis-object (parse-json string) :config config))

(defun genesis-header-from-state-genesis-json-file (path &key config)
  (genesis-header-from-state-genesis-json-string
   (with-open-file (stream path :direction :input)
     (let ((string (make-string (file-length stream))))
       (read-sequence string stream)
       string))
   :config config))

(defun genesis-block-from-state-genesis-object (object &key config)
  (genesis-block-from-genesis-header
   (genesis-header-from-state-genesis-object object :config config)))

(defun genesis-block-from-state-genesis-json-string (string &key config)
  (genesis-block-from-state-genesis-object (parse-json string) :config config))

(defun genesis-block-from-state-genesis-json-file (path &key config)
  (genesis-block-from-state-genesis-json-string
   (with-open-file (stream path :direction :input)
     (let ((string (make-string (file-length stream))))
       (read-sequence string stream)
       string))
   :config config))
