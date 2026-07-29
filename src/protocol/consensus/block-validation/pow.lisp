(in-package #:ethereum-lisp.consensus)

;;;; Historical Ethash validation. The default light backend reconstructs
;;;; requested dataset items from an epoch cache, avoiding the multi-gigabyte
;;;; full DAG; the verifier hook remains replaceable by an accelerated backend.

(defconstant +ethash-minimum-difficulty+ 131072)
(defconstant +ethash-difficulty-bound-divisor+ 2048)
(defconstant +ethash-exponential-period+ 100000)

(defvar *ethash-seal-verifier* nil)

(defun ethash-seal-verification-available-p ()
  (functionp *ethash-seal-verifier*))

(defun verify-ethash-seal (header)
  (unless (ethash-seal-verification-available-p)
    (block-validation-fail
     "Ethash seal verification is unavailable; configure an Ethash backend"))
  (unless (funcall *ethash-seal-verifier* header)
    (block-validation-fail "Invalid Ethash proof-of-work seal"))
  t)

(defconstant +ethash-word-bytes+ 4)
(defconstant +ethash-hash-bytes+ 64)
(defconstant +ethash-mix-bytes+ 128)
(defconstant +ethash-epoch-length+ 30000)
(defconstant +ethash-cache-bytes-init+ (ash 1 24))
(defconstant +ethash-cache-bytes-growth+ (ash 1 17))
(defconstant +ethash-dataset-bytes-init+ (ash 1 30))
(defconstant +ethash-dataset-bytes-growth+ (ash 1 23))
(defconstant +ethash-dataset-parents+ 256)
(defconstant +ethash-cache-rounds+ 3)
(defconstant +ethash-accesses+ 64)
(defconstant +ethash-fnv-prime+ #x01000193)

(defvar *ethash-light-caches* '())

(defun ethash-prime-p (number)
  (cond
    ((< number 2) nil)
    ((= number 2) t)
    ((evenp number) nil)
    (t
     (loop for divisor from 3 by 2
           while (<= (* divisor divisor) number)
           never (zerop (mod number divisor))))))

(defun ethash-largest-prime-at-most (upper)
  (loop for candidate downfrom (if (evenp upper) (1- upper) upper) by 2
        when (ethash-prime-p candidate)
          return candidate))

(defun ethash-cache-size (epoch)
  (* +ethash-hash-bytes+
     (ethash-largest-prime-at-most
      (+ (floor +ethash-cache-bytes-init+ +ethash-hash-bytes+)
         (* epoch
            (floor +ethash-cache-bytes-growth+ +ethash-hash-bytes+))))))

(defun ethash-dataset-size (epoch)
  (* +ethash-mix-bytes+
     (ethash-largest-prime-at-most
      (+ (floor +ethash-dataset-bytes-init+ +ethash-mix-bytes+)
         (* epoch
            (floor +ethash-dataset-bytes-growth+ +ethash-mix-bytes+))))))

(defun ethash-little-endian-u32 (bytes offset)
  (logior (aref bytes offset)
          (ash (aref bytes (+ offset 1)) 8)
          (ash (aref bytes (+ offset 2)) 16)
          (ash (aref bytes (+ offset 3)) 24)))

(defun ethash-store-little-endian-u32 (value bytes offset)
  (dotimes (index 4 bytes)
    (setf (aref bytes (+ offset index))
          (ldb (byte 8 (* index 8)) value))))

(defun ethash-bytes-to-words (bytes)
  (let ((words
          (make-array (floor (length bytes) 4)
                      :element-type '(unsigned-byte 32))))
    (dotimes (index (length words) words)
      (setf (aref words index)
            (ethash-little-endian-u32 bytes (* index 4))))))

(defun ethash-words-to-bytes (words)
  (let ((bytes (make-byte-vector (* 4 (length words)))))
    (dotimes (index (length words) bytes)
      (ethash-store-little-endian-u32
       (aref words index) bytes (* index 4)))))

(defun ethash-fnv (first second)
  (ldb (byte 32 0)
       (logxor (* first +ethash-fnv-prime+) second)))

(defun ethash-seed-hash (epoch)
  (let ((seed (make-byte-vector 32)))
    (dotimes (index epoch seed)
      (declare (ignore index))
      (setf seed (keccak-256 seed)))))

(defun make-ethash-light-cache (epoch)
  (let* ((size (ethash-cache-size epoch))
         (count (floor size +ethash-hash-bytes+))
         (cache (make-byte-vector size))
         (item (keccak-512 (ethash-seed-hash epoch))))
    (replace cache item)
    (loop for index from 1 below count
          do (setf item (keccak-512 item))
             (replace cache item
                      :start1 (* index +ethash-hash-bytes+)))
    (dotimes (round +ethash-cache-rounds+)
      (declare (ignore round))
      (dotimes (index count)
        (let* ((offset (* index +ethash-hash-bytes+))
               (previous-offset
                 (* (mod (1- index) count) +ethash-hash-bytes+))
               (selected
                 (mod (ethash-little-endian-u32 cache offset) count))
               (selected-offset (* selected +ethash-hash-bytes+))
               (mixed (make-byte-vector +ethash-hash-bytes+)))
          (dotimes (byte +ethash-hash-bytes+)
            (setf (aref mixed byte)
                  (logxor (aref cache (+ previous-offset byte))
                          (aref cache (+ selected-offset byte)))))
          (replace cache (keccak-512 mixed) :start1 offset))))
    cache))

(defun ethash-light-cache (epoch)
  (let ((entry (assoc epoch *ethash-light-caches*)))
    (if entry
        (progn
          (setf *ethash-light-caches*
                (cons entry (remove entry *ethash-light-caches* :test #'eq)))
          (cdr entry))
        (let* ((cache (make-ethash-light-cache epoch))
               (new-entry (cons epoch cache)))
          (push new-entry *ethash-light-caches*)
          (when (> (length *ethash-light-caches*) 2)
            (setf *ethash-light-caches*
                  (subseq *ethash-light-caches* 0 2)))
          cache))))

(defun ethash-cache-item-words (cache index)
  (let* ((count (floor (length cache) +ethash-hash-bytes+))
         (offset (* (mod index count) +ethash-hash-bytes+))
         (bytes (subseq cache offset (+ offset +ethash-hash-bytes+))))
    (ethash-bytes-to-words bytes)))

(defun ethash-dataset-item (cache index)
  (let* ((count (floor (length cache) +ethash-hash-bytes+))
         (mix (ethash-cache-item-words cache index)))
    (setf (aref mix 0) (logxor (aref mix 0) index)
          mix (ethash-bytes-to-words
               (keccak-512 (ethash-words-to-bytes mix))))
    (dotimes (parent +ethash-dataset-parents+)
      (let ((item
              (ethash-cache-item-words
               cache
               (mod (ethash-fnv
                     (logxor index parent)
                     (aref mix (mod parent 16)))
                    count))))
        (dotimes (word 16)
          (setf (aref mix word)
                (ethash-fnv (aref mix word) (aref item word))))))
    (ethash-bytes-to-words
     (keccak-512 (ethash-words-to-bytes mix)))))

(defun ethash-hashimoto-light (header)
  (let* ((epoch (floor (block-header-number header)
                       +ethash-epoch-length+))
         (cache (ethash-light-cache epoch))
         (dataset-size (ethash-dataset-size epoch))
         (nonce (block-header-nonce header))
         (mix-hash (block-header-mix-hash header)))
    (unless (and nonce mix-hash)
      (return-from ethash-hashimoto-light (values nil nil)))
    (let* ((seed
             (keccak-512
              (hash32-bytes (block-header-seal-hash header))
              (reverse (ensure-byte-vector nonce))))
           (seed-words (ethash-bytes-to-words seed))
           (mix (make-array 32 :element-type '(unsigned-byte 32)))
           (rows (floor dataset-size +ethash-mix-bytes+)))
      (dotimes (index 32)
        (setf (aref mix index) (aref seed-words (mod index 16))))
      (dotimes (access +ethash-accesses+)
        (let* ((page
                 (* 2
                    (mod (ethash-fnv
                          (logxor access (aref seed-words 0))
                          (aref mix (mod access 32)))
                         rows)))
               (data (make-array 32
                                 :element-type '(unsigned-byte 32))))
          (replace data (ethash-dataset-item cache page))
          (replace data (ethash-dataset-item cache (1+ page))
                   :start1 16)
          (dotimes (word 32)
            (setf (aref mix word)
                  (ethash-fnv (aref mix word) (aref data word))))))
      (let ((compressed
              (make-array 8 :element-type '(unsigned-byte 32))))
        (dotimes (index 8)
          (let ((offset (* index 4)))
            (setf (aref compressed index)
                  (ethash-fnv
                   (ethash-fnv
                    (ethash-fnv (aref mix offset)
                                (aref mix (+ offset 1)))
                    (aref mix (+ offset 2)))
                   (aref mix (+ offset 3))))))
        (let ((digest (ethash-words-to-bytes compressed)))
          (values digest (keccak-256 seed digest)))))))

(defun verify-ethash-seal-light (header)
  (multiple-value-bind (digest result) (ethash-hashimoto-light header)
    (and digest
         (bytes= digest (hash32-bytes (block-header-mix-hash header)))
         (<= (bytes-to-integer result)
             (floor (ash 1 256)
                    (block-header-difficulty header))))))

(unless *ethash-seal-verifier*
  (setf *ethash-seal-verifier* #'verify-ethash-seal-light))

(defun ethash-difficulty-bomb (period-count)
  (if (> period-count 1)
      (ash 1 (- period-count 2))
      0))

(defun ethash-frontier-difficulty (timestamp parent-header)
  (let* ((parent-difficulty (block-header-difficulty parent-header))
         (adjustment (floor parent-difficulty
                            +ethash-difficulty-bound-divisor+))
         (duration (- timestamp (block-header-timestamp parent-header)))
         (without-bomb
           (max +ethash-minimum-difficulty+
                (if (< duration 13)
                    (+ parent-difficulty adjustment)
                    (- parent-difficulty adjustment))))
         (period-count
           (floor (1+ (block-header-number parent-header))
                  +ethash-exponential-period+)))
    (+ without-bomb (ethash-difficulty-bomb period-count))))

(defun ethash-homestead-difficulty (timestamp parent-header)
  (let* ((parent-difficulty (block-header-difficulty parent-header))
         (adjustment-factor
           (max (- 1
                   (floor (- timestamp
                             (block-header-timestamp parent-header))
                          10))
                -99))
         (without-bomb
           (max +ethash-minimum-difficulty+
                (+ parent-difficulty
                   (* (floor parent-difficulty
                             +ethash-difficulty-bound-divisor+)
                      adjustment-factor))))
         (period-count
           (floor (1+ (block-header-number parent-header))
                  +ethash-exponential-period+)))
    (+ without-bomb (ethash-difficulty-bomb period-count))))

(defun ethash-byzantium-difficulty (timestamp parent-header bomb-delay)
  (let* ((parent-difficulty (block-header-difficulty parent-header))
         (parent-has-ommers-p
           (not (hash32= (or (block-header-ommers-hash parent-header)
                             +empty-ommers-hash+)
                         +empty-ommers-hash+)))
         (adjustment-factor
           (max (- (if parent-has-ommers-p 2 1)
                   (floor (- timestamp
                             (block-header-timestamp parent-header))
                          9))
                -99))
         (without-bomb
           (max +ethash-minimum-difficulty+
                (+ parent-difficulty
                   (* (floor parent-difficulty
                             +ethash-difficulty-bound-divisor+)
                      adjustment-factor))))
         (bomb-delay-from-parent (1- bomb-delay))
         (fake-parent-number
           (max 0 (- (block-header-number parent-header)
                     bomb-delay-from-parent)))
         (period-count
           (floor fake-parent-number +ethash-exponential-period+)))
    (+ without-bomb (ethash-difficulty-bomb period-count))))

(defun expected-ethash-difficulty (config timestamp parent-header)
  (let ((number (1+ (block-header-number parent-header))))
    (cond
      ((fork-block-active-p (chain-config-gray-glacier-block config) number)
       (ethash-byzantium-difficulty timestamp parent-header 11400000))
      ((fork-block-active-p (chain-config-arrow-glacier-block config) number)
       (ethash-byzantium-difficulty timestamp parent-header 10700000))
      ((chain-config-london-p config number)
       (ethash-byzantium-difficulty timestamp parent-header 9700000))
      ((fork-block-active-p (chain-config-muir-glacier-block config) number)
       (ethash-byzantium-difficulty timestamp parent-header 9000000))
      ((chain-config-constantinople-p config number)
       (ethash-byzantium-difficulty timestamp parent-header 5000000))
      ((chain-config-byzantium-p config number)
       (ethash-byzantium-difficulty timestamp parent-header 3000000))
      ((chain-config-homestead-p config number)
       (ethash-homestead-difficulty timestamp parent-header))
      (t
       (ethash-frontier-difficulty timestamp parent-header)))))

(defun validate-ethash-header (parent-header header config)
  (let ((expected
          (expected-ethash-difficulty
           config (block-header-timestamp header) parent-header)))
    (unless (= expected (block-header-difficulty header))
      (block-validation-fail
       "Invalid Ethash difficulty: have ~D, want ~D"
       (block-header-difficulty header)
       expected)))
  (verify-ethash-seal header))

