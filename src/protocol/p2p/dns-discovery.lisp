(in-package #:ethereum-lisp.p2p)

;;;; Authenticated node discovery via DNS (EIP-1459).
;;;;
;;;; This is intentionally a narrow DNS client, not a general resolver. It asks
;;;; the system-configured recursive resolvers for bounded TXT responses and
;;;; then authenticates every byte through the EIP-1459 root signature and
;;;; Merkle labels. DNS can withhold data, but it cannot inject a dial target.

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets))

(defconstant +eip1459-max-dns-packet-bytes+ 4096)
(defconstant +eip1459-max-txt-bytes+ 512)
(defconstant +eip1459-max-queries+ 512)
(defconstant +eip1459-max-enrs+ 256)
(defconstant +eip1459-max-depth+ 32)
(defconstant +eip1459-max-branch-entries+ 16)

(defparameter +eip1459-base32-alphabet+ "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
(defparameter +eip1459-base64url-alphabet+
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

(defun eip1459-split (string separator)
  (loop with start = 0
        for end = (position separator string :start start)
        collect (subseq string start end)
        while end
        do (setf start (1+ end))))

(defun eip1459-whitespace-words (string)
  (let ((length (length string))
        (position 0)
        (words '())
        (whitespace '(#\Space #\Tab #\Return #\Newline)))
    (loop while (< position length)
          do (loop while (and (< position length)
                              (member (char string position) whitespace))
                   do (incf position))
             (when (< position length)
               (let ((end (or (position-if
                               (lambda (character)
                                 (member character whitespace))
                               string :start position)
                              length)))
                 (push (subseq string position end) words)
                 (setf position end))))
    (nreverse words)))

(defun eip1459-ascii-bytes (string)
  (let ((bytes (make-byte-vector (length string))))
    (loop for character across string
          for i from 0
          for code = (char-code character)
          do (when (> code 127)
               (error "EIP-1459 text must be ASCII"))
             (setf (aref bytes i) code))
    bytes))

(defun eip1459-base-value (character alphabet)
  (or (position character alphabet :test #'char=)
      (error "Invalid base-encoded character ~S" character)))

(defun eip1459-decode-bits (string alphabet bits-per-character)
  (let* ((total-bits (* (length string) bits-per-character))
         (byte-count (floor total-bits 8))
         (result (make-byte-vector byte-count))
         (accumulator 0)
         (available 0)
         (out 0))
    (loop for character across string
          do (setf accumulator
                   (logior (ash accumulator bits-per-character)
                           (eip1459-base-value character alphabet)))
             (incf available bits-per-character)
             (loop while (>= available 8)
                   do (decf available 8)
                      (when (< out byte-count)
                        (setf (aref result out)
                              (ldb (byte 8 available) accumulator))
                        (incf out)))
             (setf accumulator (ldb (byte available 0) accumulator)))
    (unless (or (zerop available) (zerop accumulator))
      (error "Non-canonical non-zero base-encoding padding bits"))
    result))

(defun eip1459-base32-decode (string)
  (when (or (zerop (length string)) (find #\= string))
    (error "EIP-1459 base32 must be non-empty and unpadded"))
  (eip1459-decode-bits (string-upcase string)
                       +eip1459-base32-alphabet+ 5))

(defun eip1459-base32-encode (bytes)
  (let ((bytes (ensure-byte-vector bytes))
        (accumulator 0)
        (available 0))
    (with-output-to-string (stream)
      (loop for octet across bytes
            do (setf accumulator (logior (ash accumulator 8) octet))
               (incf available 8)
               (loop while (>= available 5)
                     do (decf available 5)
                        (write-char
                         (aref +eip1459-base32-alphabet+
                               (ldb (byte 5 available) accumulator))
                         stream))
               (setf accumulator (ldb (byte available 0) accumulator)))
      (when (plusp available)
        (write-char (aref +eip1459-base32-alphabet+
                          (ldb (byte 5 0) (ash accumulator (- 5 available))))
                    stream)))))

(defun eip1459-base64url-decode (string)
  (when (or (= 1 (mod (length string) 4)) (find #\= string))
    (error "EIP-1459 base64url must be canonically unpadded"))
  (eip1459-decode-bits string +eip1459-base64url-alphabet+ 6))

(defun eip1459-base64url-encode (bytes)
  (let ((bytes (ensure-byte-vector bytes))
        (accumulator 0)
        (available 0))
    (with-output-to-string (stream)
      (loop for octet across bytes
            do (setf accumulator (logior (ash accumulator 8) octet))
               (incf available 8)
               (loop while (>= available 6)
                     do (decf available 6)
                        (write-char
                         (aref +eip1459-base64url-alphabet+
                               (ldb (byte 6 available) accumulator))
                         stream))
               (setf accumulator (ldb (byte available 0) accumulator)))
      (when (plusp available)
        (write-char (aref +eip1459-base64url-alphabet+
                          (ldb (byte 6 0) (ash accumulator (- 6 available))))
                    stream)))))

(defun dns-encode-name (name)
  (when (or (zerop (length name)) (> (length name) 253))
    (error "DNS name has invalid length"))
  (let ((labels (eip1459-split (string-right-trim "." name) #\.))
        (bytes (make-array 0 :element-type '(unsigned-byte 8)
                            :adjustable t :fill-pointer 0)))
    (dolist (label labels)
      (when (or (zerop (length label)) (> (length label) 63)
                (char= #\- (char label 0))
                (char= #\- (char label (1- (length label))))
                (find-if-not (lambda (character)
                               (and (<= (char-code character) 127)
                                    (or (alphanumericp character)
                                        (char= character #\-))))
                             label))
        (error "Invalid DNS label ~S" label))
      (vector-push-extend (length label) bytes)
      (loop for character across label
            do (vector-push-extend (char-code (char-downcase character)) bytes)))
    (vector-push-extend 0 bytes)
    (ensure-byte-vector bytes)))

(defun dns-u16 (bytes offset end)
  (when (> (+ offset 2) end) (error "Truncated DNS uint16"))
  (logior (ash (aref bytes offset) 8) (aref bytes (1+ offset))))

(defun dns-u32 (bytes offset end)
  (when (> (+ offset 4) end) (error "Truncated DNS uint32"))
  (logior (ash (aref bytes offset) 24)
          (ash (aref bytes (+ offset 1)) 16)
          (ash (aref bytes (+ offset 2)) 8)
          (aref bytes (+ offset 3))))

(defun dns-write-u16 (bytes offset value)
  (setf (aref bytes offset) (ldb (byte 8 8) value)
        (aref bytes (1+ offset)) (ldb (byte 8 0) value)))

(defun dns-skip-name (bytes offset end)
  (loop with labels = 0
        do (when (>= offset end) (error "Truncated DNS name"))
           (let ((length (aref bytes offset)))
             (cond
               ((zerop length) (return (1+ offset)))
               ((= #xc0 (logand length #xc0))
                (when (> (+ offset 2) end)
                  (error "Truncated DNS compression pointer"))
                (return (+ offset 2)))
               ((plusp (logand length #xc0))
                (error "Invalid DNS label prefix"))
               ((> length 63) (error "Oversized DNS label"))
               (t
                (incf labels)
                (when (> labels 127) (error "Too many DNS labels"))
                (incf offset (1+ length))
                (when (> offset end) (error "Truncated DNS label")))))))

(defun dns-decode-txt-rdata (bytes offset end)
  (when (> (- end offset) +eip1459-max-txt-bytes+)
    (error "DNS TXT record exceeds ~D bytes" +eip1459-max-txt-bytes+))
  (with-output-to-string (stream)
    (loop while (< offset end)
          for length = (aref bytes offset)
          do (incf offset)
             (when (> (+ offset length) end)
               (error "Truncated DNS TXT character-string"))
             (loop repeat length
                   for octet = (aref bytes offset)
                   do (when (> octet 127) (error "DNS TXT is not ASCII"))
                      (write-char (code-char octet) stream)
                      (incf offset)))))

(defun dns-decode-txt-response (packet expected-id)
  (let* ((packet (ensure-byte-vector packet))
         (end (length packet)))
    (when (or (< end 12) (> end +eip1459-max-dns-packet-bytes+))
      (error "DNS response has invalid size"))
    (unless (= expected-id (dns-u16 packet 0 end))
      (error "DNS transaction ID does not match"))
    (let* ((flags (dns-u16 packet 2 end))
           (questions (dns-u16 packet 4 end))
           (answers (dns-u16 packet 6 end))
           (authorities (dns-u16 packet 8 end))
           (additional (dns-u16 packet 10 end))
           (offset 12))
      (unless (plusp (logand flags #x8000)) (error "DNS response bit is absent"))
      (when (plusp (logand flags #x0200)) (error "Truncated DNS response"))
      (unless (zerop (logand flags #x000f))
        (error "DNS resolver returned error code ~D" (logand flags #x000f)))
      (when (or (> questions 4) (> answers 32) (> authorities 32)
                (> additional 32) (> (+ answers authorities additional) 64))
        (error "DNS response section count exceeds policy"))
      (dotimes (i questions)
        (declare (ignore i))
        (setf offset (dns-skip-name packet offset end))
        (when (> (+ offset 4) end) (error "Truncated DNS question"))
        (incf offset 4))
      (let ((texts '()))
        (dotimes (i (+ answers authorities additional))
          (declare (ignore i))
          (setf offset (dns-skip-name packet offset end))
          (when (> (+ offset 10) end) (error "Truncated DNS resource record"))
          (let* ((type (dns-u16 packet offset end))
                 (class (dns-u16 packet (+ offset 2) end))
                 (ttl (dns-u32 packet (+ offset 4) end))
                 (length (dns-u16 packet (+ offset 8) end))
                 (data-start (+ offset 10))
                 (data-end (+ data-start length)))
            (declare (ignore ttl))
            (when (> data-end end) (error "Truncated DNS RDATA"))
            (when (and (= type 16) (= class 1))
              (push (dns-decode-txt-rdata packet data-start data-end) texts))
            (setf offset data-end)))
        (nreverse texts)))))

(defun dns-resolver-addresses (&optional (path #p"/etc/resolv.conf"))
  (let ((addresses '()))
    (when (probe-file path)
      (with-open-file (stream path :direction :input)
        (loop for line = (read-line stream nil nil)
              while line
              for words = (eip1459-whitespace-words line)
              when (and (>= (length words) 2)
                        (string= "nameserver" (first words)))
                do (let ((address (second words)))
                     ;; The current transport is IPv4. Ignore IPv6 resolvers;
                     ;; another configured resolver may still be usable.
                     (when (ignore-errors
                             (= 4 (length (sb-bsd-sockets:make-inet-address
                                           address))))
                       (pushnew address addresses :test #'string=))))))
    (nreverse addresses)))

(defun dns-make-txt-query (name id)
  (let* ((encoded-name (dns-encode-name name))
         ;; One eleven-byte EDNS(0) OPT pseudo-record advertises the same 4096
         ;; byte UDP ceiling enforced by our receive buffer. Without it, a
         ;; resolver may truncate an otherwise small TXT answer because the
         ;; answer plus authority data crosses the legacy 512-byte DNS limit.
         (packet (make-byte-vector (+ 12 (length encoded-name) 4 11))))
    (dns-write-u16 packet 0 id)
    (dns-write-u16 packet 2 #x0100) ; recursion desired
    (dns-write-u16 packet 4 1)
    (dns-write-u16 packet 10 1) ; one additional OPT record
    (replace packet encoded-name :start1 12)
    (let ((tail (+ 12 (length encoded-name))))
      (dns-write-u16 packet tail 16) ; TXT
      (dns-write-u16 packet (+ tail 2) 1) ; IN
      (let ((opt (+ tail 4)))
        ;; Root owner name, TYPE=OPT, advertised UDP payload=4096. Extended
        ;; RCODE/version/flags and RDLEN remain their zero-initialized values.
        (setf (aref packet opt) 0)
        (dns-write-u16 packet (+ opt 1) 41)
        (dns-write-u16 packet (+ opt 3) +eip1459-max-dns-packet-bytes+)))
    packet))

(defun dns-query-txt (name &key (timeout-seconds 2) (attempts 2)
                                (resolvers (dns-resolver-addresses)))
  "Return verified-wire TXT strings for NAME from a system resolver.

The cryptographic EIP-1459 layer authenticates their content. This transport is
bounded and fails closed on truncation, malformed compression, oversized
records, or resolver errors."
  #-sbcl
  (declare (ignore name timeout-seconds attempts resolvers))
  #-sbcl
  (error "DNS discovery requires SBCL sockets")
  #+sbcl
  (let ((last-error nil))
    (unless resolvers (error "No IPv4 DNS resolver is configured"))
    (loop repeat attempts
          do (dolist (resolver resolvers)
               (let* ((id (random 65536))
                      (query (dns-make-txt-query name id))
                      (socket (make-instance 'sb-bsd-sockets:inet-socket
                                             :type :datagram :protocol :udp)))
                 (unwind-protect
                      (handler-case
                          (progn
                            (sb-bsd-sockets:socket-send
                             socket query (length query)
                             :address
                             (list (sb-bsd-sockets:make-inet-address resolver) 53))
                            (if (sb-sys:wait-until-fd-usable
                                 (sb-bsd-sockets:socket-file-descriptor socket)
                                 :input timeout-seconds)
                                (let ((buffer
                                        (make-byte-vector
                                         +eip1459-max-dns-packet-bytes+)))
                                  (multiple-value-bind (received size)
                                      (sb-bsd-sockets:socket-receive
                                       socket buffer nil)
                                    (declare (ignore received))
                                    (if (and size (plusp size))
                                        (return-from dns-query-txt
                                          (dns-decode-txt-response
                                           (subseq buffer 0 size) id))
                                        (setf last-error "empty response"))))
                                (setf last-error "timed out")))
                        (error (condition)
                          (setf last-error (princ-to-string condition))))
                   (ignore-errors (sb-bsd-sockets:socket-close socket)))))
          finally
             (error "DNS TXT query for ~A exhausted its bounded retries: ~A"
                    name (or last-error "no response")))))

(defun eip1459-valid-hash-label-p (label)
  (and (= 26 (length label))
       (handler-case (= 16 (length (eip1459-base32-decode label)))
         (error () nil))))

(defun eip1459-parse-url (url)
  "Parse ENRTREE://PUBLIC-KEY@DOMAIN, returning key bytes and domain."
  (let ((prefix "enrtree://"))
    (unless (and (stringp url)
                 (<= (length prefix) (length url))
                 (string-equal prefix url :end2 (length prefix)))
      (error "Invalid EIP-1459 URL"))
    (let* ((at (position #\@ url :start (length prefix)))
           (key-text (and at (subseq url (length prefix) at)))
           (domain (and at (subseq url (1+ at)))))
      (unless (and at key-text domain (not (find #\@ domain)))
        (error "Invalid EIP-1459 URL authority"))
      (dns-encode-name domain)
      (let ((key (eip1459-base32-decode key-text)))
        (unless (and (= 33 (length key))
                     (member (aref key 0) '(2 3))
                     (secp256k1-decompress-public-key key))
          (error "EIP-1459 URL carries an invalid compressed public key"))
        (values key (string-downcase (string-right-trim "." domain)))))))

(defun eip1459-root-field (token name)
  (let ((prefix (concatenate 'string name "=")))
    (unless (and (<= (length prefix) (length token))
                 (string= prefix token :end2 (length prefix)))
      (error "Malformed EIP-1459 root field ~A" name))
    (subseq token (length prefix))))

(defun eip1459-parse-root (text compressed-key previous-sequence)
  (when (> (length text) +eip1459-max-txt-bytes+)
    (error "EIP-1459 root exceeds TXT policy"))
  (let ((parts (eip1459-split text #\Space)))
    (unless (and (= 5 (length parts))
                 (string= "enrtree-root:v1" (first parts)))
      (error "Malformed EIP-1459 root"))
    (let* ((enr-root (eip1459-root-field (second parts) "e"))
           (link-root (eip1459-root-field (third parts) "l"))
           (sequence-text (eip1459-root-field (fourth parts) "seq"))
           (signature-text (eip1459-root-field (fifth parts) "sig"))
           (sequence
             (progn
               (unless (and (<= 1 (length sequence-text) 20)
                            (every #'digit-char-p sequence-text)
                            (or (= 1 (length sequence-text))
                                (char/= #\0 (char sequence-text 0))))
                 (error "EIP-1459 root sequence is not canonical decimal"))
               (parse-integer sequence-text :junk-allowed nil)))
           (signature (eip1459-base64url-decode signature-text))
           (signed-end (search " sig=" text :from-end t))
           (public-key (secp256k1-decompress-public-key compressed-key)))
      (unless (and (eip1459-valid-hash-label-p enr-root)
                   (eip1459-valid-hash-label-p link-root))
        (error "EIP-1459 root contains an invalid subtree hash"))
      (unless (and (<= 0 sequence #xffffffffffffffff)
                   (or (null previous-sequence)
                       (>= sequence previous-sequence)))
        (error "EIP-1459 root sequence rolled back"))
      (unless (and signed-end (= 65 (length signature))
                   (member (aref signature 64) '(0 1))
                   public-key
                   (secp256k1-verify
                    (keccak-256 (eip1459-ascii-bytes (subseq text 0 signed-end)))
                    (bytes-to-integer (subseq signature 0 32))
                    (bytes-to-integer (subseq signature 32 64))
                    public-key))
        (error "EIP-1459 root signature does not verify"))
      (values enr-root sequence))))

(defun eip1459-entry-matches-label-p (label text)
  (let ((hash (eip1459-base32-decode label))
        (digest (keccak-256 (eip1459-ascii-bytes text))))
    (and (<= (length hash) (length digest))
         (bytes= hash (subseq digest 0 (length hash))))))

(defun eip1459-enr-enode (text)
  (unless (and (> (length text) 4) (string= "enr:" text :end2 4))
    (error "Malformed EIP-1459 ENR leaf"))
  (let* ((bytes (eip1459-base64url-decode (subseq text 4)))
         (record (decode-enr bytes))
         (public-key (enr-public-key record))
         (ip (enr-value record "ip"))
         (tcp (enr-value record "tcp")))
    (values
     (when (and public-key ip tcp (= 4 (length ip)))
       (let ((port (bytes-to-integer (ensure-byte-vector tcp))))
         (when (<= 1 port 65535)
           (enode-url public-key
                      (format nil "~D.~D.~D.~D"
                              (aref ip 0) (aref ip 1)
                              (aref ip 2) (aref ip 3))
                      port))))
     record)))

(defun eip1459-resolve-enodes
    (url &key (query-function #'dns-query-txt) previous-sequence record-filter
              (max-queries +eip1459-max-queries+)
              (max-enrs +eip1459-max-enrs+)
              (max-depth +eip1459-max-depth+))
  "Resolve URL's authenticated ENR subtree.

Returns (VALUES ENODE-URLS ROOT-SEQUENCE STATS). The traversal is bounded,
deduplicated, signature/hash verified, and restricted to IPv4 records with a
TCP endpoint. RECORD-FILTER, when supplied, receives each already verified ENR."
  (unless (and (integerp max-queries) (<= 1 max-queries +eip1459-max-queries+)
               (integerp max-enrs) (<= 1 max-enrs +eip1459-max-enrs+)
               (integerp max-depth) (<= 1 max-depth +eip1459-max-depth+))
    (error "EIP-1459 traversal bounds exceed policy"))
  (multiple-value-bind (compressed-key domain) (eip1459-parse-url url)
    (let* ((roots (funcall query-function domain))
           (root-records
             (remove-if-not
              (lambda (text)
                (and (stringp text)
                     (<= 15 (length text))
                     (string= "enrtree-root:v1" text :end2 15)))
              roots)))
      (unless (= 1 (length root-records))
        (error "DNS name ~A did not return exactly one EIP-1459 root" domain))
      (multiple-value-bind (enr-root sequence)
          (eip1459-parse-root (first root-records) compressed-key previous-sequence)
        (let ((queue (list (cons enr-root 0)))
              (seen (make-hash-table :test #'equalp))
              (node-ids (make-hash-table :test #'equalp))
              (enodes '())
              ;; The authenticated root lookup is part of the total DNS query
              ;; budget, not a free uncounted request.
              (queries 1)
              (records 0)
              (matches 0)
              (mismatches 0))
          (loop while queue
                do (let* ((item (pop queue))
                          (label (car item))
                          (depth (cdr item)))
                     (unless (gethash label seen)
                       (setf (gethash label seen) t)
                       (when (> depth max-depth)
                         (error "EIP-1459 tree exceeds depth policy"))
                       (when (>= queries max-queries)
                         (error "EIP-1459 tree exceeds query policy"))
                       (incf queries)
                       (let* ((name (format nil "~A.~A" label domain))
                              (texts (funcall query-function name)))
                         (unless (= 1 (length texts))
                           (error "EIP-1459 entry ~A is missing or ambiguous" name))
                         (let ((text (first texts)))
                           (unless (and (stringp text)
                                        (<= (length text) +eip1459-max-txt-bytes+)
                                        (eip1459-entry-matches-label-p
                                         label text))
                             (error "EIP-1459 entry hash does not match ~A" label))
                           (cond
                             ((and (<= 15 (length text))
                                   (string= "enrtree-branch:" text :end2 15))
                              (let ((children
                                      (eip1459-split (subseq text 15) #\,)))
                                (when (or (null children)
                                          (> (length children)
                                             +eip1459-max-branch-entries+)
                                          (some (lambda (child)
                                                  (not (eip1459-valid-hash-label-p
                                                        child)))
                                                children))
                                  (error "Malformed EIP-1459 branch"))
                                (dolist (child children)
                                  (push (cons child (1+ depth)) queue))))
                             ((and (> (length text) 4)
                                   (string= "enr:" text :end2 4))
                              (incf records)
                              (multiple-value-bind (enode record)
                                  (eip1459-enr-enode text)
                                (if (and enode
                                         (or (null record-filter)
                                             (funcall record-filter record)))
                                    (let ((id (nth-value 0
                                                (parse-enode-url enode))))
                                      (unless (gethash id node-ids)
                                        (when (>= (length enodes) max-enrs)
                                          (error "EIP-1459 tree exceeds ENR policy"))
                                        (setf (gethash id node-ids) t)
                                        (push enode enodes)
                                        (incf matches)))
                                    (incf mismatches))))
                             (t (error "Unexpected entry in EIP-1459 ENR subtree"))))))))
          (values (nreverse enodes) sequence
                  (list (cons "queries" queries)
                        (cons "records" records)
                        (cons "matched" matches)
                        (cons "mismatched" mismatches))))))))
