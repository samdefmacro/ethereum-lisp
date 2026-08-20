(in-package #:ethereum-lisp.test)

(defun eip1459-test-fixture (&key (sequence 7))
  (let* ((key #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (compressed
           (ethereum-lisp.crypto:secp256k1-compress-public-key
            (secp256k1-private-key-public-key key)))
         (record
           (ethereum-lisp.p2p:encode-enr
            key 1
            (list (cons "ip" (hex-to-bytes "0xc0000209"))
                  (cons "tcp" (integer-to-minimal-bytes 30303))
                  (cons "udp" (integer-to-minimal-bytes 30303)))))
         (leaf
           (concatenate
            'string "enr:"
            (ethereum-lisp.p2p::eip1459-base64url-encode record)))
         (other-leaf
           (concatenate
            'string "enr:"
            (ethereum-lisp.p2p::eip1459-base64url-encode
             (ethereum-lisp.p2p:encode-enr
              key 2
              (list (cons "ip" (hex-to-bytes "0xc0000209"))
                    (cons "tcp" (integer-to-minimal-bytes 30304)))))))
         (leaf-label
           (ethereum-lisp.p2p::eip1459-base32-encode
            (subseq (keccak-256
                     (ethereum-lisp.p2p::eip1459-ascii-bytes leaf))
                    0 16)))
         (unsigned-root
           (format nil "enrtree-root:v1 e=~A l=~A seq=~D"
                   leaf-label leaf-label sequence))
         (signature
           (secp256k1-sign
            (keccak-256
             (ethereum-lisp.p2p::eip1459-ascii-bytes unsigned-root))
            key))
         (root
           (format nil "~A sig=~A" unsigned-root
                   (ethereum-lisp.p2p::eip1459-base64url-encode signature)))
         (domain "nodes.example.org")
         (url
           (format nil "enrtree://~A@~A"
                   (ethereum-lisp.p2p::eip1459-base32-encode compressed)
                   domain)))
    (list :key key :domain domain :url url :root root :leaf leaf
          :other-leaf other-leaf
          :leaf-label leaf-label)))

(defun eip1459-test-query-function (fixture &key wrong-hash-leaf)
  (lambda (name)
    (cond
      ((string= name (getf fixture :domain))
       (list (getf fixture :root)))
      ((string= name
                (format nil "~A.~A" (getf fixture :leaf-label)
                        (getf fixture :domain)))
       (list (if wrong-hash-leaf
                 (getf fixture :other-leaf)
                 (getf fixture :leaf))))
      (t '()))))

(defun eip1459-test-errors-p (thunk)
  ;; SIGNALS ERROR cannot distinguish the form's error from its own
  ;; "not signaled" assertion because that assertion is itself an ERROR.
  (handler-case (progn (funcall thunk) nil)
    (error () t)))

(deftest eip1459-verifies-root-leaf-and-enr-before-returning-an-enode
  (:layer :unit :module :p2p)
  (let* ((fixture (eip1459-test-fixture))
         (calls 0))
    (flet ((query (name)
             (incf calls)
             (funcall (eip1459-test-query-function fixture) name)))
      (multiple-value-bind (enodes sequence stats)
          (ethereum-lisp.p2p:eip1459-resolve-enodes
           (getf fixture :url) :query-function #'query)
        (is (= 2 calls))
        (is (= 7 sequence))
        (is (= 1 (length enodes)))
        (multiple-value-bind (id host tcp-port)
            (parse-enode-url (first enodes))
          (is (bytes= (node-id-from-private-key (getf fixture :key)) id))
          (is (string= "192.0.2.9" host))
          (is (= 30303 tcp-port)))
        (is (= 1 (cdr (assoc "records" stats :test #'string=))))
        (is (= 1 (cdr (assoc "matched" stats :test #'string=))))))))

(deftest eip1459-rejects-tampering-and-sequence-rollback
  (:layer :unit :module :p2p)
  (let ((fixture (eip1459-test-fixture)))
    (is (eip1459-test-errors-p
         (lambda ()
           (ethereum-lisp.p2p:eip1459-resolve-enodes
            (getf fixture :url)
            :query-function
            (eip1459-test-query-function fixture :wrong-hash-leaf t)))))
    (is (eip1459-test-errors-p
         (lambda ()
           (ethereum-lisp.p2p:eip1459-resolve-enodes
            (getf fixture :url)
            :previous-sequence 8
            :query-function (eip1459-test-query-function fixture)))))
    (let* ((tampered (copy-seq (getf fixture :root)))
           (position (+ 4 (search "seq=7" tampered))))
      (setf (char tampered position) #\8)
      (setf (getf fixture :root) tampered)
      (is (eip1459-test-errors-p
           (lambda ()
             (ethereum-lisp.p2p:eip1459-resolve-enodes
              (getf fixture :url)
              :query-function (eip1459-test-query-function fixture))))))))

(deftest eip1459-rejects-noncanonical-root-fields
  (:layer :unit :module :p2p)
  (let* ((fixture (eip1459-test-fixture))
         (root (getf fixture :root)))
    (labels ((reject-root (replacement)
               (let ((copy (copy-list fixture)))
                 (setf (getf copy :root) replacement)
                 (is (eip1459-test-errors-p
                      (lambda ()
                        (ethereum-lisp.p2p:eip1459-resolve-enodes
                         (getf copy :url)
                         :query-function
                         (eip1459-test-query-function copy))))))))
      ;; Even a newly signed root must use the canonical decimal spelling.
      (reject-root
       (let* ((sequence-position (search "seq=7" root))
              (signed-end (search " sig=" root :from-end t))
              (unsigned
                (format nil "~Aseq=07~A"
                        (subseq root 0 sequence-position)
                        (subseq root (+ sequence-position 5) signed-end)))
              (signature
                (secp256k1-sign
                 (keccak-256
                  (ethereum-lisp.p2p::eip1459-ascii-bytes
                   unsigned))
                 (getf fixture :key))))
         (format nil "~A sig=~A" unsigned
                 (ethereum-lisp.p2p::eip1459-base64url-encode signature))))
      ;; The recovery byte is part of EIP-1459's canonical 65-byte signature.
      (let* ((separator (search " sig=" root :from-end t))
             (signature
               (ethereum-lisp.p2p::eip1459-base64url-decode
                (subseq root (+ separator 5)))))
        (setf (aref signature 64) 2)
        (reject-root
         (format nil "~A sig=~A" (subseq root 0 separator)
                 (ethereum-lisp.p2p::eip1459-base64url-encode signature)))))))

(deftest eip1459-applies-filter-and-hard-traversal-bounds
  (:layer :unit :module :p2p)
  (let ((fixture (eip1459-test-fixture)))
    (multiple-value-bind (enodes sequence stats)
        (ethereum-lisp.p2p:eip1459-resolve-enodes
         (getf fixture :url)
         :query-function (eip1459-test-query-function fixture)
         :record-filter (constantly nil))
      (declare (ignore sequence))
      (is (null enodes))
      (is (= 1 (cdr (assoc "mismatched" stats :test #'string=)))))
    ;; The root and leaf both count toward the hard DNS-query budget.
    (is (= 1
           (length
            (ethereum-lisp.p2p:eip1459-resolve-enodes
             (getf fixture :url)
             :max-queries 2
             :query-function (eip1459-test-query-function fixture)))))
    (is (eip1459-test-errors-p
         (lambda ()
           (ethereum-lisp.p2p:eip1459-resolve-enodes
            (getf fixture :url) :max-queries 1
            :query-function (eip1459-test-query-function fixture)))))))

(deftest dns-txt-decoder-concatenates-character-strings-without-separators
  (:layer :unit :module :p2p)
  ;; A TXT RDATA may contain several character-strings. EIP-1459 hashes their
  ;; concatenation; inserting a dot (as a hostname decoder would) breaks it.
  (let ((data (ensure-byte-vector #(3 97 98 99 3 100 101 102))))
    (is (string= "abcdef"
                 (ethereum-lisp.p2p::dns-decode-txt-rdata
                  data 0 (length data))))))
