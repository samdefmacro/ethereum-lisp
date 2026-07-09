(in-package #:ethereum-lisp.test)

(deftest trie-empty-root
  (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
               (mpt-root-hex (make-mpt)))))

(deftest trie-single-leaf-root-is-deterministic
  (let ((trie (make-mpt)))
    (mpt-put trie (ascii-to-bytes "dog") (ascii-to-bytes "puppy"))
    (is (string= (mpt-root-hex trie) (mpt-root-hex trie)))
    (is (bytes= (ascii-to-bytes "puppy")
                (mpt-get trie (ascii-to-bytes "dog"))))))

(deftest trie-insertion-order-independent
  (let ((left (make-mpt))
        (right (make-mpt)))
    (dolist (pair '(("do" . "verb") ("dog" . "puppy") ("doge" . "coin") ("horse" . "stallion")))
      (mpt-put left (ascii-to-bytes (car pair)) (ascii-to-bytes (cdr pair))))
    (dolist (pair '(("horse" . "stallion") ("doge" . "coin") ("dog" . "puppy") ("do" . "verb")))
      (mpt-put right (ascii-to-bytes (car pair)) (ascii-to-bytes (cdr pair))))
    (is (string= (mpt-root-hex left) (mpt-root-hex right)))))

(deftest trie-entry-pairs-rebuild-root
  (let ((trie (make-mpt))
        (rebuilt (make-mpt)))
    (dolist (pair '(("dog" . "puppy") ("do" . "verb") ("horse" . "stallion")))
      (mpt-put trie (ascii-to-bytes (car pair)) (ascii-to-bytes (cdr pair))))
    (dolist (entry (mpt-entry-pairs trie))
      (mpt-put rebuilt (car entry) (cdr entry)))
    (is (string= (mpt-root-hex trie) (mpt-root-hex rebuilt)))
    (is (equal '("646f" "646f67" "686f727365")
               (mapcar (lambda (entry)
                         (bytes-to-hex (car entry) :prefix nil))
                       (mpt-entry-pairs trie))))))

(deftest trie-entry-range-uses-half-open-lexicographic-bounds
  (let ((trie (make-mpt)))
    (dolist (pair '(("apple" . "fruit1")
                    ("apricot" . "fruit2")
                    ("banana" . "fruit3")
                    ("cherry" . "fruit4")
                    ("date" . "fruit5")
                    ("fig" . "fruit6")
                    ("grape" . "fruit7")))
      (mpt-put trie
               (ascii-to-bytes (car pair))
               (ascii-to-bytes (cdr pair))))
    (is (equal '("banana" "cherry" "date")
               (mapcar (lambda (entry)
                         (bytes-to-ascii (car entry)))
                       (mpt-entry-range
                        trie
                        :start (ascii-to-bytes "banana")
                        :end (ascii-to-bytes "fig")))))
    (is (equal '("apple" "apricot")
               (mapcar (lambda (entry)
                         (bytes-to-ascii (car entry)))
                       (mpt-entry-range
                        trie
                        :end (ascii-to-bytes "banana")))))
    (is (equal '("fig" "grape")
               (mapcar (lambda (entry)
                         (bytes-to-ascii (car entry)))
                       (mpt-entry-range
                        trie
                        :start (ascii-to-bytes "fig")))))
    (is (null (mpt-entry-range
               trie
               :start (ascii-to-bytes "banana")
               :end (ascii-to-bytes "banana"))))))

(deftest trie-delete-removes-key-and-collapses-to-empty-root
  (let ((trie (make-mpt)))
    (mpt-put trie (ascii-to-bytes "dog") (ascii-to-bytes "puppy"))
    (is (bytes= (ascii-to-bytes "puppy")
                (mpt-get trie (ascii-to-bytes "dog"))))
    (mpt-delete trie (ascii-to-bytes "dog"))
    (is (null (mpt-get trie (ascii-to-bytes "dog"))))
    (is (string= "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
                 (mpt-root-hex trie)))))

(deftest trie-proof-verifies-present-and-missing-keys
  (let ((trie (make-mpt)))
    (mpt-put trie (ascii-to-bytes "do") (ascii-to-bytes "verb"))
    (mpt-put trie (ascii-to-bytes "dog") (ascii-to-bytes "puppy"))
    (mpt-put trie (ascii-to-bytes "horse") (ascii-to-bytes "stallion"))
    (multiple-value-bind (value present-p)
        (mpt-verify-proof
         (make-hash32 (mpt-root-hash trie))
         (ascii-to-bytes "dog")
         (mpt-get-proof trie (ascii-to-bytes "dog")))
      (is present-p)
      (is (bytes= (ascii-to-bytes "puppy") value)))
    (multiple-value-bind (value present-p)
        (mpt-verify-proof
         (mpt-root-hash trie)
         (ascii-to-bytes "cat")
         (mpt-get-proof trie (ascii-to-bytes "cat")))
      (is (null present-p))
      (is (null value)))
    (signals error
      (mpt-verify-proof
       (hash32-bytes (zero-hash32))
       (ascii-to-bytes "dog")
       (mpt-get-proof trie (ascii-to-bytes "dog"))))
    (signals error
      (mpt-verify-proof
       (mpt-root-hash trie)
       (ascii-to-bytes "dog")
       (append (mpt-get-proof trie (ascii-to-bytes "dog"))
               (mpt-get-proof trie (ascii-to-bytes "horse")))))))

(deftest trie-proof-rejects-tampered-referenced-node
  (let ((trie (make-mpt)))
    (mpt-put trie (ascii-to-bytes "key1") (hex-to-bytes "0x63636363"))
    (mpt-put trie
             (ascii-to-bytes "key2")
             (hex-to-bytes
              "0x0101010101010101010101010101010101010101010101010101010101010101"))
    (let* ((proof (mpt-get-proof trie (ascii-to-bytes "key2")))
           (tampered-node (copy-seq (second proof)))
           (tampered-proof (copy-list proof)))
      (is (>= (length proof) 2))
      (setf (aref tampered-node 0)
            (logxor (aref tampered-node 0) #x01))
      (setf (second tampered-proof) tampered-node)
      (signals error
        (mpt-verify-proof
         (mpt-root-hash trie)
         (ascii-to-bytes "key2")
         tampered-proof)))))

(deftest trie-proof-verifies-empty-root-absence
  (multiple-value-bind (value present-p)
      (mpt-verify-proof
       (hash32-bytes +empty-trie-hash+)
       (ascii-to-bytes "dog")
       (mpt-get-proof (make-mpt) (ascii-to-bytes "dog")))
    (is (null present-p))
    (is (null value))))

