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
    (let* ((dog-proof (mpt-get-proof trie (ascii-to-bytes "dog")))
           (padded-proof
             (reverse
              (append dog-proof
                      (mpt-get-proof trie (ascii-to-bytes "horse"))))))
      (multiple-value-bind (value present-p)
          (mpt-verify-proof
           (mpt-root-hash trie)
           (ascii-to-bytes "dog")
           padded-proof)
        (is present-p)
        (is (bytes= (ascii-to-bytes "puppy") value))))))

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

(deftest trie-rehashes-only-the-updated-path
  ;; The initial root is the positive control: every node must be encoded. Once
  ;; caches are warm, changing one leaf must not make work scale with 512
  ;; retained entries.
  (let ((trie (make-mpt))
        (initial-encodings 0)
        (update-encodings 0))
    (dotimes (index 512)
      (mpt-put trie
               (vector (ldb (byte 8 8) index)
                       (ldb (byte 8 0) index))
               (integer-to-minimal-bytes (1+ index))))
    (let ((ethereum-lisp.trie::*node-encoding-count* 0))
      (mpt-root-hash trie)
      (setf initial-encodings
            ethereum-lisp.trie::*node-encoding-count*))
    (mpt-put trie (vector 0 0) (integer-to-minimal-bytes 999))
    (let ((ethereum-lisp.trie::*node-encoding-count* 0))
      (mpt-root-hash trie)
      (setf update-encodings
            ethereum-lisp.trie::*node-encoding-count*))
    (is (< 512 initial-encodings))
    (is (< update-encodings 16))))

(deftest trie-root-hash-caches-every-hashed-dirty-child
  (:layer :unit :module :trie)
  (let ((trie (make-mpt)))
    ;; Large values make each leaf and every ancestor a hashed reference. Once
    ;; the root has recursively encoded those references, collecting durable
    ;; records must not hash the same nodes for a second time.
    (dotimes (index 128)
      (mpt-put trie
               (vector (ldb (byte 8 8) index)
                       (ldb (byte 8 0) index))
               (make-byte-vector 64 :initial-element (logand index #xff))))
    (let ((ethereum-lisp.trie::*node-hash-computation-count* 0))
      (mpt-root-hash trie)
      (let ((root-hash-computations
              ethereum-lisp.trie::*node-hash-computation-count*))
        (is (< 1 root-hash-computations))
        ;; NODE-HASH owns the root hash while child references own descendant
        ;; hashes. Both directions must share the same cache.
        (ethereum-lisp.trie::node-reference (mpt-root-node trie))
        (is (= root-hash-computations
               ethereum-lisp.trie::*node-hash-computation-count*))
        (ethereum-lisp.trie:mpt-dirty-node-records trie)
        (is (= root-hash-computations
               ethereum-lisp.trie::*node-hash-computation-count*))))))

(deftest trie-rehash-cost-is-independent-of-trie-size
  ;; The test above bounds the update at a single size, which a rebuild that
  ;; happened to stay under the bound would also satisfy. The contract is that
  ;; the bound does not move with the entry count, and only two sizes can show
  ;; that, so measure an octave apart and compare.
  (flet ((measure (entry-count)
           (let ((trie (make-mpt))
                 (cold 0)
                 (warm 0))
             (dotimes (index entry-count)
               (mpt-put trie
                        (vector (ldb (byte 8 8) index)
                                (ldb (byte 8 0) index))
                        (integer-to-minimal-bytes (1+ index))))
             (let ((ethereum-lisp.trie::*node-encoding-count* 0))
               (mpt-root-hash trie)
               (setf cold ethereum-lisp.trie::*node-encoding-count*))
             (mpt-put trie (vector 0 0) (integer-to-minimal-bytes 999))
             (let ((ethereum-lisp.trie::*node-encoding-count* 0))
               (mpt-root-hash trie)
               (setf warm ethereum-lisp.trie::*node-encoding-count*))
             (cons cold warm))))
    (let ((small (measure 512))
          (large (measure 4096)))
      ;; Positive control: the cold build really is linear in the entry count,
      ;; so the warm comparison below is measuring a live quantity rather than
      ;; a counter that stopped being incremented.
      (is (< (* 4 (car small)) (car large)))
      ;; Eight times the entries must not cost more than the one extra level of
      ;; trie depth they add.
      (is (< (cdr large) (* 2 (cdr small))))
      (is (< (cdr large) 16)))))

(deftest trie-node-store-persists-root-and-descendants
  (let ((trie (make-mpt))
        (database (make-memory-key-value-database)))
    (mpt-put trie #(1) #(10))
    (mpt-put trie #(2) #(20))
    (let ((root (mpt-persist database trie)))
      (is (ethereum-lisp.types:hash32=
           root (make-hash32 (mpt-root-hash trie))))
      (multiple-value-bind (encoded present-p)
          (trie-node-store-get database root)
        (is present-p)
        (is (bytes= encoded
                    (ethereum-lisp.trie::encoded-node
                     (mpt-root-node trie))))))))

(deftest persisted-trie-opens-lazily-and-writes-only-dirty-paths
  (let ((trie (make-mpt))
        (database (make-memory-key-value-database)))
    (dotimes (index 512)
      (mpt-put trie
               (vector (ldb (byte 8 8) index)
                       (ldb (byte 8 0) index))
               (integer-to-minimal-bytes (1+ index))))
    (let* ((old-root (mpt-persist database trie))
           (stored-node-count
             (length (kv-chain-record-entries database :trie-node)))
           (resolved-count 0)
           (lazy
             (make-persisted-mpt
              old-root
              (lambda (hash)
                (incf resolved-count)
                (trie-node-store-get database hash)))))
      ;; Positive control: the source really has a large persisted node set.
      (is (> stored-node-count 100))
      (is (= 0 resolved-count))
      (multiple-value-bind (value present-p) (mpt-get lazy #(1 1))
        (is present-p)
        (is (bytes= value (integer-to-minimal-bytes 258))))
      (is (< resolved-count (/ stored-node-count 4)))
      (mpt-put lazy #(1 1) (integer-to-minimal-bytes 9999))
      (let ((encoded-count 0)
            (new-root nil))
        (let ((ethereum-lisp.trie::*node-encoding-count* 0))
          (setf new-root (mpt-persist database lazy)
                encoded-count ethereum-lisp.trie::*node-encoding-count*))
        ;; A full rewrite would encode hundreds of nodes. The changed leaf and
        ;; its ancestors are the only cache misses on the durable write path.
        (is (< encoded-count 32))
        (is (not (ethereum-lisp.types:hash32= old-root new-root)))
        (let ((reopened
                (make-persisted-mpt
                 new-root
                 (lambda (hash)
                   (trie-node-store-get database hash)))))
          (multiple-value-bind (changed present-p) (mpt-get reopened #(1 1))
            (is present-p)
            (is (bytes= changed (integer-to-minimal-bytes 9999))))
          (multiple-value-bind (untouched present-p) (mpt-get reopened #(0 7))
            (is present-p)
            (is (bytes= untouched (integer-to-minimal-bytes 8)))))))))

(deftest trie-iterator-resumes-after-cursor
  (let ((trie (make-mpt)))
    (dolist (entry '((#(1) . #(10)) (#(2) . #(20)) (#(3) . #(30))))
      (mpt-put trie (car entry) (cdr entry)))
    (let ((iterator (make-mpt-iterator trie)))
      (multiple-value-bind (key value cursor present-p)
          (funcall iterator)
        (is present-p)
        (is (bytes= #(1) key))
        (is (bytes= #(10) value))
        (let ((resumed (make-mpt-iterator trie :after cursor)))
          (multiple-value-bind (next-key next-value next-cursor next-present-p)
              (funcall resumed)
            (declare (ignore next-cursor))
            (is next-present-p)
            (is (bytes= #(2) next-key))
            (is (bytes= #(20) next-value))))))))

(deftest trie-range-proof-rejects-omission
  (let ((trie (make-mpt)))
    (dotimes (index 5)
      (mpt-put trie (vector index) (vector (+ 10 index))))
    (multiple-value-bind (entries proof)
        (mpt-get-range-proof trie :start #(1) :end #(4))
      (multiple-value-bind (verified-p reconstructed)
          (mpt-verify-range-proof
           (mpt-root-hash trie) entries proof :start #(1) :end #(4))
        (is verified-p)
        (is reconstructed)
        (is (bytes= (mpt-root-hash trie)
                    (mpt-root-hash reconstructed)))
        (is (find (mpt-root-hash trie)
                  (mpt-dirty-node-records reconstructed)
                  :key #'car :test #'bytes=)))
      (signals error
        (mpt-verify-range-proof
         (mpt-root-hash trie) (rest entries) proof
         :start #(1) :end #(4))))))

(deftest trie-proven-absent-insert-matches-ordinary-insert
  (let ((ordinary (make-mpt))
        (range-built (make-mpt)))
    (loop for key across #(#(1) #(2) #(16) #(255))
          for value across #(#(11) #(22) #(33) #(44))
          do (mpt-put ordinary key value)
             (mpt-put-proven-absent range-built key value))
    (is (bytes= (mpt-root-hash ordinary) (mpt-root-hash range-built)))
    (signals error
      (mpt-put-proven-absent range-built #(3) #()))))

(deftest trie-range-proof-is-compact-and-rejects-range-tampering
  (let ((trie (make-mpt)))
    (dotimes (index 100)
      (mpt-put trie (vector index) (vector (1+ index))))
    (multiple-value-bind (entries proof)
        (mpt-get-range-proof trie :start #(25) :end #(75) :limit 20)
      (is (= 20 (length entries)))
      (is (< (length
              (ethereum-lisp.trie::mpt-range-proof-nodes proof))
             (length (mpt-entry-pairs trie))))
      (is (mpt-verify-range-proof
           (mpt-root-hash trie) entries proof
           :start #(25) :end #(75) :limit 20))
      (let ((altered
              (mapcar (lambda (entry)
                        (cons (copy-seq (car entry)) (copy-seq (cdr entry))))
                      entries)))
        (setf (cdr (nth 7 altered)) #(255))
        (signals error
          (mpt-verify-range-proof
           (mpt-root-hash trie) altered proof
           :start #(25) :end #(75) :limit 20)))
      (signals error
        (mpt-verify-range-proof
         (mpt-root-hash trie) (reverse entries) proof
         :start #(25) :end #(75) :limit 20)))))

(deftest trie-range-proof-verifies-an-empty-tail-and-rejects-a-false-empty-range
  (let ((trie (make-mpt)))
    (dotimes (index 100)
      (mpt-put trie (vector index) (vector (1+ index))))
    (multiple-value-bind (entries proof)
        (mpt-get-range-proof trie :start #(200) :end #(220))
      (is (null entries))
      (is (mpt-verify-range-proof
           (mpt-root-hash trie) entries proof
           :start #(200) :end #(220))))
    (multiple-value-bind (entries proof)
        (mpt-get-range-proof trie :start #(50) :end #(60))
      (declare (ignore entries))
      (signals error
        (mpt-verify-range-proof
         (mpt-root-hash trie) nil proof
         :start #(50) :end #(60))))))
