(in-package #:ethereum-lisp.test)

(defun rlp-hex (value)
  (bytes-to-hex (rlp-encode value)))

(defun rlp-test-deep-list-bytes (depth)
  "Build DEPTH nested RLP lists iteratively, without recursing in the test."
  (let ((payload-length 1)
        (prefixes '()))
    (loop repeat depth
          for prefix = (ethereum-lisp.rlp::encode-length #xc0 payload-length)
          do (push prefix prefixes)
             (incf payload-length (length prefix)))
    (let ((result (make-byte-vector payload-length))
          (position 0))
      (dolist (prefix prefixes)
        (replace result prefix :start1 position)
        (incf position (length prefix)))
      (setf (aref result position) #xc0)
      result)))

(deftest rlp-ethereum-examples
  (is (string= "0x83646f67" (rlp-hex "dog")))
  (is (string= "0xc88363617483646f67" (rlp-hex '("cat" "dog"))))
  (is (string= "0x80" (rlp-hex "")))
  (is (string= "0xc0" (rlp-hex '())))
  (is (string= "0x0f" (rlp-hex 15)))
  (is (string= "0x820400" (rlp-hex 1024)))
  (is (string= "0xc7c0c1c0c3c0c1c0"
               (rlp-hex (list '() (list '()) (list '() (list '())))))))

(deftest rlp-byte-item-list-writer-preserves-canonical-boundaries-and-inline-items
  (:layer :unit :module :rlp)
  (let* ((inner-object
           (make-rlp-list (make-byte-vector 0) (make-byte-vector 1)))
         (inner-encoded (rlp-encode inner-object))
         (raw-items
           (vector (make-byte-vector 0)
                   (make-byte-vector 1 :initial-element #x7f)
                   (make-byte-vector 55 :initial-element #x81)
                   (make-byte-vector 56 :initial-element #x82)
                   (make-byte-vector 256 :initial-element #x83)
                   inner-encoded))
         (expected
           (rlp-encode
            (make-rlp-list
             (aref raw-items 0)
             (aref raw-items 1)
             (aref raw-items 2)
             (aref raw-items 3)
             (aref raw-items 4)
             inner-object)))
         (actual
           (ethereum-lisp.rlp::rlp-encode-byte-items
            raw-items :preencoded-mask (ash 1 5))))
    (is (bytes= expected actual))))

#+sbcl
(deftest rlp-list-encoding-does-not-stage-a-complete-payload-copy
  (:layer :unit :module :rlp)
  (let* ((items
           (loop repeat 17
                 collect (make-byte-vector 64 :initial-element 7)))
         (started (sb-ext:get-bytes-consed)))
    (dotimes (index 10000)
      (declare (ignore index))
      (rlp-encode items))
    ;; The former payload-then-result implementation consumes about 94 MB for
    ;; this fixed workload on the pinned SBCL; direct final-buffer copies stay
    ;; comfortably below the bound while preserving the same canonical bytes.
    (is (< (- (sb-ext:get-bytes-consed) started) 88000000))))

(deftest rlp-long-string-example
  (let ((text "Lorem ipsum dolor sit amet, consectetur adipisicing elit"))
    (is (string= "0xb8384c6f72656d20697073756d20646f6c6f722073697420616d65742c20636f6e7365637465747572206164697069736963696e6720656c6974"
                 (rlp-hex text)))))

(deftest rlp-decode-examples
  (is (string= "dog" (bytes-to-ascii (rlp-decode-one (hex-to-bytes "0x83646f67")))))
  (let ((decoded (rlp-decode-one (hex-to-bytes "0xc88363617483646f67"))))
    (is (rlp-list-p decoded))
    (is (string= "cat" (bytes-to-ascii (first (rlp-list-items decoded)))))
    (is (string= "dog" (bytes-to-ascii (second (rlp-list-items decoded)))))))

(deftest rlp-rejects-non-canonical-forms
  (signals rlp-error (rlp-decode-one (hex-to-bytes "0x8101")))
  (signals rlp-error (rlp-decode-one (hex-to-bytes "0xb80100")))
  (signals rlp-error (rlp-decode-one (hex-to-bytes "0xf801c0"))))

(deftest rlp-rejects-excessive-nesting-with-rlp-error
  (let ((nested (make-rlp-list)))
    (loop repeat 66
          do (setf nested (make-rlp-list nested)))
    (let ((encoded (rlp-encode nested)))
      (signals rlp-error (rlp-decode-one encoded))
      (is (rlp-list-p (rlp-decode encoded :maximum-depth 66))))))

(deftest rlp-rejects-excessive-list-depth
  (:layer :unit :module :rlp)
  (signals rlp-error
    (rlp-decode-one
     (rlp-test-deep-list-bytes
      (1+ ethereum-lisp.rlp:+rlp-max-depth+)))))

(deftest rlp-enforces-a-per-list-item-cap-before-returning-a-value
  (:layer :unit :module :rlp)
  (let ((encoded
          (rlp-encode
           (apply #'make-rlp-list
                  (loop repeat 5 collect (make-byte-vector 0))))))
    (signals rlp-error
      (rlp-decode-one encoded :max-list-items 4))
    (is (= 5
           (length
            (rlp-list-items
             (rlp-decode-one encoded :max-list-items 5)))))))

(deftest rlp-checks-a-list-cap-before-decoding-the-rejected-child
  (:layer :unit :module :rlp)
  (let* ((too-deep
           (rlp-test-deep-list-bytes
            (1+ ethereum-lisp.rlp:+rlp-max-depth+)))
         (encoded
           (rlp-encode
            (make-rlp-list
             (make-byte-vector 0)
             (rlp-decode-one too-deep
                             :maximum-depth
                             (1+ ethereum-lisp.rlp:+rlp-max-depth+))))))
    (handler-case
        (progn
          (rlp-decode-one encoded :max-list-items 1)
          (is nil))
      (rlp-error (condition)
        (is (search "more than 1 items"
                    (ethereum-lisp.rlp::rlp-error-message condition)))))))

(deftest rlp-enforces-one-total-item-budget-across-nested-lists
  (:layer :unit :module :rlp)
  (let ((encoded
          (rlp-encode
           (make-rlp-list
            (make-rlp-list (make-byte-vector 0) (make-byte-vector 0))))))
    (signals rlp-error
      (rlp-decode-one encoded :max-list-items 3 :max-total-items 3))
    (is (rlp-list-p
         (rlp-decode-one encoded :max-list-items 3 :max-total-items 4)))))

(deftest rlp-rejects-an-oversized-string-before-copying-its-payload
  (:layer :unit :module :rlp)
  (let ((encoded (rlp-encode (make-byte-vector 5))))
    (signals rlp-error
      (rlp-decode-one encoded :max-string-bytes 4))
    (is (= 5 (length (rlp-decode-one encoded :max-string-bytes 5))))))
