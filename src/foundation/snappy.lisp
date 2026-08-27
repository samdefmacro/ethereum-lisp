(in-package #:ethereum-lisp.snappy)

;;;; Snappy block compression (the raw format, not the framing format).
;;;;
;;;; devp2p compresses every message after Hello with Snappy. This is the raw
;;;; block format: a decoded-length varint followed by literal and copy tags.

(cffi:define-foreign-library libsnappy
  ;; Keep the runtime SONAME first. SAVE-LISP-AND-DIE records the resolved
  ;; namestring, and the reviewed image deliberately carries no -dev symlink.
  (:unix (:or "libsnappy.so.1" "libsnappy.so"))
  (t (:default "libsnappy")))

(cffi:use-foreign-library libsnappy)

(cffi:defcfun ("snappy_uncompressed_length" %snappy-uncompressed-length) :int
  (compressed :pointer) (compressed-length :size) (result :pointer))
(cffi:defcfun ("snappy_uncompress" %snappy-uncompress) :int
  (compressed :pointer) (compressed-length :size)
  (uncompressed :pointer) (uncompressed-length :pointer))
(cffi:defcfun ("snappy_max_compressed_length" %snappy-max-compressed-length)
    :size
  (source-length :size))
(cffi:defcfun ("snappy_compress" %snappy-compress) :int
  (input :pointer) (input-length :size)
  (compressed :pointer) (compressed-length :pointer))

(defconstant +snappy-status-ok+ 0)

(defconstant +snappy-max-decoded-length+ (* 16 1024 1024)
  "Largest uncompressed size accepted, matching the RLPx message limit.")

(defun snappy-read-varint (bytes start)
  "Read a little-endian base-128 varint from BYTES at START.

Returns (VALUES value next-index)."
  (let ((result 0) (shift 0) (index start))
    (loop
      (when (>= index (length bytes))
        (error "Snappy varint is truncated"))
      (when (> shift 28)
        (error "Snappy varint is too long"))
      (let ((byte (aref bytes index)))
        (incf index)
        (setf result (logior result (ash (logand byte #x7f) shift)))
        (incf shift 7)
        (when (zerop (logand byte #x80))
          (return (values result index)))))))

(defun snappy-decompress-lisp (input)
  "Decompress a Snappy INPUT block into its original bytes."
  (let ((input (ensure-byte-vector input)))
    (multiple-value-bind (decoded-length position) (snappy-read-varint input 0)
      (when (> decoded-length +snappy-max-decoded-length+)
        (error "Snappy decoded length ~D exceeds the ~D limit"
               decoded-length +snappy-max-decoded-length+))
      (let ((output (make-byte-vector decoded-length))
            (out 0))
        (labels ((take (count)
                   (when (> (+ position count) (length input))
                     (error "Snappy input is truncated"))
                   (prog1 position (incf position count)))
                 (next ()
                   (aref input (take 1)))
                 (little-endian (count)
                   (let ((start (take count)) (value 0))
                     (dotimes (i count value)
                       (setf value (logior value (ash (aref input (+ start i))
                                                      (* 8 i)))))))
                 (emit-literal (length)
                   (let ((start (take length)))
                     (when (> (+ out length) decoded-length)
                       (error "Snappy literal overflows the output"))
                     (replace output input :start1 out
                                           :start2 start :end2 (+ start length))
                     (incf out length)))
                 (emit-copy (length offset)
                   (when (or (zerop offset) (> offset out))
                     (error "Snappy copy offset ~D is out of range" offset))
                   (when (> (+ out length) decoded-length)
                     (error "Snappy copy overflows the output"))
                   ;; Copy byte by byte so an offset smaller than the length
                   ;; repeats correctly.
                   (dotimes (i length)
                     (setf (aref output out) (aref output (- out offset)))
                     (incf out))))
          (loop while (< position (length input))
                for tag = (next)
                do (ecase (logand tag 3)
                     (0
                      (let ((indicator (ash tag -2)))
                        (emit-literal
                         (cond ((< indicator 60) (1+ indicator))
                               (t (1+ (little-endian (- indicator 59))))))))
                     (1
                      (emit-copy (+ 4 (logand (ash tag -2) 7))
                                 (logior (ash (logand (ash tag -5) 7) 8) (next))))
                     (2
                      (emit-copy (1+ (ash tag -2)) (little-endian 2)))
                     (3
                      (emit-copy (1+ (ash tag -2)) (little-endian 4))))))
        (unless (= out decoded-length)
          (error "Snappy output length does not match its header"))
        output))))

(defun snappy-write-varint (value out)
  (let ((n value))
    (loop
      (if (< n #x80)
          (progn (vector-push-extend n out) (return))
          (progn (vector-push-extend (logior (logand n #x7f) #x80) out)
                 (setf n (ash n -7)))))))

(defun snappy-emit-literal (input start end out)
  (let* ((length (- end start))
         (stored (1- length)))
    (when (plusp length)
      (cond
        ((< stored 60)
         (vector-push-extend (ash stored 2) out))
        (t
         (let ((count (cond ((< stored #x100) 1)
                            ((< stored #x10000) 2)
                            ((< stored #x1000000) 3)
                            (t 4))))
           (vector-push-extend (ash (+ 59 count) 2) out)
           (dotimes (i count)
             (vector-push-extend
              (logand (ash stored (* -8 i)) #xff) out)))))
      (loop for index from start below end
            do (vector-push-extend (aref input index) out)))))

(defun snappy-emit-copy (length offset out)
  "Emit COPY_2 tags. OFFSET is bounded to 16 bits by the matcher."
  (loop while (plusp length)
        for chunk = (min length 64)
        do (vector-push-extend
            (logior (ash (1- chunk) 2) 2) out)
           (vector-push-extend (logand offset #xff) out)
           (vector-push-extend (ldb (byte 8 8) offset) out)
           (decf length chunk)))

(defun snappy-load-word (input position)
  (logior (aref input position)
          (ash (aref input (+ position 1)) 8)
          (ash (aref input (+ position 2)) 16)
          (ash (aref input (+ position 3)) 24)))

(defun snappy-hash-word (word)
  (ldb (byte 14 18) (* word #x1e35a7bd)))

(defun snappy-four-equal-p (input left right)
  (and (= (aref input left) (aref input right))
       (= (aref input (+ left 1)) (aref input (+ right 1)))
       (= (aref input (+ left 2)) (aref input (+ right 2)))
       (= (aref input (+ left 3)) (aref input (+ right 3)))))

(defun snappy-compress-lisp (input)
  "Compress INPUT to a Snappy raw block with literal and COPY_2 tags."
  (let* ((input (ensure-byte-vector input))
         (length (length input))
         (out (make-array (+ 32 length) :element-type '(unsigned-byte 8)
                                         :fill-pointer 0 :adjustable t))
         (table (make-array (ash 1 14) :element-type 'fixnum
                                        :initial-element -1))
         (anchor 0)
         (position 0))
    (snappy-write-varint length out)
    (loop while (<= (+ position 4) length)
          for word = (snappy-load-word input position)
          for slot = (snappy-hash-word word)
          for candidate = (aref table slot)
          do (setf (aref table slot) position)
             (if (and (>= candidate 0)
                      (<= (- position candidate) #xffff)
                      (snappy-four-equal-p input candidate position))
                 (let* ((offset (- position candidate))
                        (match-length
                          (loop for count from 4
                                while (and (< (+ position count) length)
                                           (= (aref input (+ candidate count))
                                              (aref input (+ position count))))
                                finally (return count))))
                   (snappy-emit-literal input anchor position out)
                   (snappy-emit-copy match-length offset out)
                   (let ((next (+ position match-length)))
                     ;; Seed the hash table inside the match so a following
                     ;; sequence can refer to the newest occurrence.
                     (loop for update from (1+ position) below next
                           while (<= (+ update 4) length)
                           do (setf (aref table
                                         (snappy-hash-word
                                          (snappy-load-word input update)))
                                    update))
                     (setf position next
                           anchor next)))
                 (incf position)))
    (snappy-emit-literal input anchor length out)
    (coerce out '(simple-array (unsigned-byte 8) (*)))))

(defmacro with-snappy-bytes ((pointer length bytes) &body body)
  `(let* ((data (ensure-byte-vector ,bytes))
          (,length (length data)))
     (cffi:with-pointer-to-vector-data (,pointer data)
       ,@body)))

(defun snappy-decompress (input)
  "Decompress one bounded raw Snappy block with libsnappy's C API."
  (with-snappy-bytes (input-pointer input-length input)
    (cffi:with-foreign-object (decoded-length :size)
      (unless (= +snappy-status-ok+
                 (%snappy-uncompressed-length
                  input-pointer input-length decoded-length))
        (error "Snappy input has an invalid decoded-length prefix"))
      (let ((length (cffi:mem-ref decoded-length :size)))
        (when (> length +snappy-max-decoded-length+)
          (error "Snappy decoded length ~D exceeds the ~D limit"
                 length +snappy-max-decoded-length+))
        (let ((output (make-byte-vector length)))
          (cffi:with-pointer-to-vector-data (output-pointer output)
            (setf (cffi:mem-ref decoded-length :size) length)
            (unless (= +snappy-status-ok+
                       (%snappy-uncompress
                        input-pointer input-length output-pointer
                        decoded-length))
              (error "Snappy input is malformed"))
            (unless (= length (cffi:mem-ref decoded-length :size))
              (error "Snappy output length does not match its header")))
          output)))))

(defun snappy-compress (input)
  "Compress one bounded raw Snappy block with libsnappy's C API."
  (with-snappy-bytes (input-pointer input-length input)
    (when (> input-length +snappy-max-decoded-length+)
      (error "Snappy input length ~D exceeds the ~D limit"
             input-length +snappy-max-decoded-length+))
    (let* ((capacity (%snappy-max-compressed-length input-length))
           (output (make-byte-vector capacity)))
      (cffi:with-foreign-object (compressed-length :size)
        (setf (cffi:mem-ref compressed-length :size) capacity)
        (cffi:with-pointer-to-vector-data (output-pointer output)
          (unless (= +snappy-status-ok+
                     (%snappy-compress
                      input-pointer input-length output-pointer
                      compressed-length))
            (error "libsnappy refused a bounded compression request")))
        (let ((length (cffi:mem-ref compressed-length :size)))
          (if (= length capacity) output (subseq output 0 length)))))))
