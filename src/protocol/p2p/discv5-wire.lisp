(in-package #:ethereum-lisp.discv5)

;;;; Node Discovery Protocol v5.1 packet and message codec.
;;;;
;;;; The codec owns session keys and outstanding WHOAREYOU challenges. It does
;;;; no I/O and keys all mutable state by both node ID and observed UDP endpoint,
;;;; preventing a session learned at one address from authenticating another.

(defconstant +discv5-max-packet-size+ 1280)
(defconstant +discv5-min-packet-size+ 63)
(defconstant +discv5-static-header-size+ 23)
(defconstant +discv5-message-ping+ 1)
(defconstant +discv5-message-pong+ 2)
(defconstant +discv5-message-findnode+ 3)
(defconstant +discv5-message-nodes+ 4)

(defparameter +discv5-protocol-id+
  (make-array 6 :element-type '(unsigned-byte 8)
                :initial-contents '(100 105 115 99 118 53)))

(defstruct (discv5-ping
            (:constructor make-discv5-ping (&key request-id enr-seq)))
  request-id
  enr-seq)

(defstruct (discv5-pong
            (:constructor make-discv5-pong
                (&key request-id enr-seq recipient-ip recipient-port)))
  request-id
  enr-seq
  recipient-ip
  recipient-port)

(defstruct (discv5-findnode
            (:constructor make-discv5-findnode (&key request-id distances)))
  request-id
  distances)

(defstruct (discv5-nodes
            (:constructor make-discv5-nodes (&key request-id total records)))
  request-id
  total
  records)

(defstruct (discv5-session
            (:constructor make-discv5-session
                (&key read-key write-key remote-record (nonce-counter 0))))
  read-key
  write-key
  remote-record
  nonce-counter)

(defstruct (discv5-whoareyou
            (:constructor make-discv5-whoareyou
                (&key request-nonce id-nonce record-seq challenge-data
                      remote-record)))
  request-nonce
  id-nonce
  record-seq
  challenge-data
  remote-record)

(defstruct (discv5-codec
            (:constructor %make-discv5-codec
                (private-key record node-id sessions challenges)))
  private-key
  record
  node-id
  sessions
  challenges)

(defun make-discv5-codec (private-key record)
  "Create a codec for PRIVATE-KEY and its signed ENR bytes."
  (let* ((record (ensure-byte-vector record))
         (decoded (decode-enr record))
         (public-key (enr-public-key decoded))
         (expected (secp256k1-private-key-public-key private-key)))
    (unless (and public-key (equalp public-key expected))
      (error "discv5 local ENR does not belong to the private key"))
    (%make-discv5-codec
     private-key record (discv5-node-id public-key)
     (make-hash-table :test #'equal)
     (make-hash-table :test #'equal))))

(defun discv5-state-key (node-id endpoint)
  (format nil "~A@~A" (bytes-to-integer (ensure-byte-vector node-id)) endpoint))

(defun discv5-codec-session (codec node-id endpoint)
  (gethash (discv5-state-key node-id endpoint)
           (discv5-codec-sessions codec)))

(defun discv5-codec-install-session
    (codec node-id endpoint read-key write-key &key remote-record)
  (let ((session
          (make-discv5-session
           :read-key (ensure-byte-vector read-key)
           :write-key (ensure-byte-vector write-key)
           :remote-record remote-record)))
    (setf (gethash (discv5-state-key node-id endpoint)
                   (discv5-codec-sessions codec))
          session)
    session))

(defun discv5-request-id (request-id)
  (let ((request-id (ensure-byte-vector request-id)))
    (when (> (length request-id) 8)
      (error "discv5 request ID exceeds 8 bytes"))
    request-id))

(defun encode-discv5-message (message)
  "Encode MESSAGE as message-type || RLP message-data."
  (etypecase message
    (discv5-ping
     (concat-bytes
      (make-array 1 :element-type '(unsigned-byte 8)
                    :initial-element +discv5-message-ping+)
      (rlp-encode
       (make-rlp-list
        (discv5-request-id (discv5-ping-request-id message))
        (integer-to-minimal-bytes (discv5-ping-enr-seq message))))))
    (discv5-pong
     (let ((port (discv5-pong-recipient-port message)))
       (unless (<= 1 port 65535)
         (error "discv5 PONG recipient port must be in [1, 65535]"))
       (concat-bytes
        (make-array 1 :element-type '(unsigned-byte 8)
                      :initial-element +discv5-message-pong+)
        (rlp-encode
         (make-rlp-list
          (discv5-request-id (discv5-pong-request-id message))
          (integer-to-minimal-bytes (discv5-pong-enr-seq message))
          (ensure-byte-vector (discv5-pong-recipient-ip message))
          (integer-to-minimal-bytes port))))))
    (discv5-findnode
     (let ((distances (discv5-findnode-distances message)))
       (unless (and (listp distances)
                    (<= (length distances) 256)
                    (every (lambda (distance)
                             (and (integerp distance) (<= 0 distance 256)))
                           distances)
                    (= (length distances)
                       (length (remove-duplicates distances))))
         (error "discv5 FINDNODE distances must be unique integers in [0, 256]"))
       (concat-bytes
        (make-array 1 :element-type '(unsigned-byte 8)
                      :initial-element +discv5-message-findnode+)
        (rlp-encode
         (make-rlp-list
          (discv5-request-id (discv5-findnode-request-id message))
          (apply #'make-rlp-list
                 (mapcar #'integer-to-minimal-bytes distances)))))))
    (discv5-nodes
     (let ((total (discv5-nodes-total message))
           (records (discv5-nodes-records message)))
       (unless (<= 1 total 255)
         (error "discv5 NODES total must be in [1, 255]"))
       (concat-bytes
        (make-array 1 :element-type '(unsigned-byte 8)
                      :initial-element +discv5-message-nodes+)
        (rlp-encode
         (make-rlp-list
          (discv5-request-id (discv5-nodes-request-id message))
          (integer-to-minimal-bytes total)
          (apply #'make-rlp-list
                 (mapcar (lambda (record)
                           (rlp-decode (ensure-byte-vector record)))
                         records)))))))))

(defun decode-discv5-message (plaintext)
  (let* ((plaintext (ensure-byte-vector plaintext))
         (type (and (plusp (length plaintext)) (aref plaintext 0))))
    (unless type
      (error "discv5 encrypted message has no type"))
    (unless (member type (list +discv5-message-ping+
                               +discv5-message-pong+
                               +discv5-message-findnode+
                               +discv5-message-nodes+))
      (error "unsupported discv5 message type ~D" type))
    (let* ((items (rlp-list-items (rlp-decode (subseq plaintext 1))))
           (expected-count (case type ((1 3) 2) (2 4) (4 3)))
           (request-id (discv5-request-id (first items))))
      (unless (= expected-count (length items))
        (error "discv5 message type ~D has ~D fields, expected ~D"
               type (length items) expected-count))
      (case type
        (1
         (make-discv5-ping
          :request-id request-id
          :enr-seq (bytes-to-integer (ensure-byte-vector (second items)))))
        (2
         (let ((ip (ensure-byte-vector (third items)))
               (port (bytes-to-integer (ensure-byte-vector (fourth items)))))
           (unless (member (length ip) '(4 16))
             (error "discv5 PONG recipient IP must be 4 or 16 bytes"))
           (unless (<= 1 port 65535)
             (error "discv5 PONG recipient port must be in [1, 65535]"))
           (make-discv5-pong
            :request-id request-id
            :enr-seq (bytes-to-integer (ensure-byte-vector (second items)))
            :recipient-ip ip :recipient-port port)))
        (3
         (let ((distances
                 (mapcar (lambda (value)
                           (bytes-to-integer (ensure-byte-vector value)))
                         (rlp-list-items (second items)))))
           (unless (and (<= (length distances) 256)
                        (every (lambda (distance) (<= 0 distance 256))
                               distances)
                        (= (length distances)
                           (length (remove-duplicates distances))))
             (error "discv5 FINDNODE distances are invalid"))
           (make-discv5-findnode
            :request-id request-id :distances distances)))
        (4
         (make-discv5-nodes
          :request-id request-id
          :total (bytes-to-integer (ensure-byte-vector (second items)))
          :records (mapcar #'rlp-encode
                           (rlp-list-items (third items)))))
        (otherwise (error "unsupported discv5 message type ~D" type))))))

(defun discv5-random-bytes (size supplied)
  (if supplied
      (let ((bytes (ensure-byte-vector supplied)))
        (unless (= size (length bytes))
          (error "discv5 random field must be ~D bytes" size))
        bytes)
      (secure-random-bytes size)))

(defun discv5-static-header (flag nonce auth-size)
  (concat-bytes +discv5-protocol-id+
                (discv5-fixed-bytes 1 2)
                (make-array 1 :element-type '(unsigned-byte 8)
                              :initial-element flag)
                nonce
                (discv5-fixed-bytes auth-size 2)))

(defun discv5-mask-header (destination-node-id masking-iv header)
  (aes-ctr (subseq (ensure-byte-vector destination-node-id) 0 16)
           masking-iv header))

(defun discv5-frame-packet
    (destination-node-id flag nonce authdata message
     &key masking-iv encryption-key)
  (let* ((masking-iv (discv5-random-bytes 16 masking-iv))
         (static (discv5-static-header flag nonce (length authdata)))
         (header (concat-bytes static authdata))
         (authenticated-data (concat-bytes masking-iv header))
         (body (if encryption-key
                   (discv5-aes-gcm-encrypt
                    encryption-key nonce message authenticated-data)
                   (ensure-byte-vector message)))
         (packet
           (concat-bytes masking-iv
                         (discv5-mask-header
                          destination-node-id masking-iv header)
                         body)))
    (when (> (length packet) +discv5-max-packet-size+)
      (error "discv5 packet exceeds 1280 bytes"))
    (values packet authenticated-data)))

(defun discv5-next-nonce (session supplied)
  (if supplied
      (discv5-random-bytes 12 supplied)
      (progn
        (incf (discv5-session-nonce-counter session))
        (concat-bytes
         (discv5-fixed-bytes (discv5-session-nonce-counter session) 4)
         (secure-random-bytes 8)))))

(defun discv5-encode-random-packet
    (codec destination-node-id &key nonce masking-iv random-message)
  "Encode the undecryptable probe which initiates a handshake."
  (let ((nonce (discv5-random-bytes 12 nonce)))
    (values
     (discv5-frame-packet
      destination-node-id 0 nonce (discv5-codec-node-id codec)
      (discv5-random-bytes 20 random-message)
      :masking-iv masking-iv)
     nonce)))

(defun discv5-encode-whoareyou-packet
    (codec destination-node-id endpoint request-nonce
     &key known-record record-seq id-nonce masking-iv)
  "Challenge an undecryptable packet and remember the exact unmasked header."
  (let* ((id-nonce (discv5-random-bytes 16 id-nonce))
         (known (and known-record (decode-enr known-record)))
         (record-seq (or record-seq (and known (enr-seq known)) 0))
         (authdata (concat-bytes id-nonce (discv5-fixed-bytes record-seq 8))))
    (multiple-value-bind (packet challenge-data)
        (discv5-frame-packet
         destination-node-id 1 (ensure-byte-vector request-nonce)
         authdata (make-byte-vector 0) :masking-iv masking-iv)
      (let ((challenge
              (make-discv5-whoareyou
               :request-nonce request-nonce :id-nonce id-nonce
               :record-seq record-seq :challenge-data challenge-data
               :remote-record known-record)))
        (setf (gethash (discv5-state-key destination-node-id endpoint)
                       (discv5-codec-challenges codec))
              challenge)
        (values packet challenge)))))

(defun discv5-encode-message-packet
    (codec destination-node-id endpoint message &key nonce masking-iv)
  (let ((session (discv5-codec-session codec destination-node-id endpoint)))
    (unless session
      (error "no discv5 session for destination endpoint"))
    (let ((nonce (discv5-next-nonce session nonce)))
      (discv5-frame-packet
       destination-node-id 0 nonce (discv5-codec-node-id codec)
       (encode-discv5-message message)
       :masking-iv masking-iv
       :encryption-key (discv5-session-write-key session)))))

(defun discv5-encode-handshake-packet
    (codec destination-node-id endpoint challenge message remote-record
     &key ephemeral-key nonce masking-iv)
  "Answer CHALLENGE, install initiator-side keys, and carry MESSAGE."
  (let* ((remote (decode-enr remote-record))
         (remote-public (enr-public-key remote))
         (remote-id (discv5-node-id remote-public)))
    (unless (equalp remote-id destination-node-id)
      (error "discv5 handshake destination ENR has the wrong node ID"))
    (let* ((ephemeral-key (or ephemeral-key (secp256k1-random-private-key)))
           (ephemeral-public
             (secp256k1-compress-public-key
              (secp256k1-private-key-public-key ephemeral-key)))
           (signature
             (discv5-id-signature
              (discv5-codec-private-key codec)
              (discv5-whoareyou-challenge-data challenge)
              ephemeral-public destination-node-id))
           (local-decoded (decode-enr (discv5-codec-record codec)))
           (included-record
             (if (> (enr-seq local-decoded)
                    (discv5-whoareyou-record-seq challenge))
                 (discv5-codec-record codec)
                 (make-byte-vector 0)))
           (authdata
             (concat-bytes
              (discv5-codec-node-id codec)
              (make-array 2 :element-type '(unsigned-byte 8)
                            :initial-contents '(64 33))
              signature ephemeral-public included-record)))
      (multiple-value-bind (initiator-key recipient-key)
          (discv5-derive-session-keys
           ephemeral-key
           (secp256k1-compress-public-key remote-public)
           (discv5-codec-node-id codec) destination-node-id
           (discv5-whoareyou-challenge-data challenge))
        (let* ((session
                 (discv5-codec-install-session
                  codec destination-node-id endpoint
                  recipient-key initiator-key :remote-record remote-record))
               (nonce (discv5-next-nonce session nonce)))
          (discv5-frame-packet
           destination-node-id 2 nonce authdata
           (encode-discv5-message message)
           :masking-iv masking-iv :encryption-key initiator-key))))))

(defun discv5-unmask-packet (codec packet)
  (let ((packet (ensure-byte-vector packet)))
    (when (or (< (length packet) +discv5-min-packet-size+)
              (> (length packet) +discv5-max-packet-size+))
      (error "discv5 packet size is outside [63, 1280]"))
    (let* ((iv (subseq packet 0 16))
           (masked-static (subseq packet 16 (+ 16 +discv5-static-header-size+)))
           (static
             (discv5-mask-header
              (discv5-codec-node-id codec) iv masked-static)))
      (unless (equalp +discv5-protocol-id+ (subseq static 0 6))
        (error "discv5 protocol ID mismatch"))
      (unless (= 1 (bytes-to-integer (subseq static 6 8)))
        (error "unsupported discv5 wire version"))
      (let* ((flag (aref static 8))
             (nonce (subseq static 9 21))
             (auth-size (bytes-to-integer (subseq static 21 23)))
             (auth-start (+ 16 +discv5-static-header-size+))
             (auth-end (+ auth-start auth-size)))
        (unless (member flag '(0 1 2))
          (error "unsupported discv5 packet flag ~D" flag))
        (when (and (/= flag 1)
                   (< (- (length packet)
                         (+ 16 +discv5-static-header-size+))
                      48))
          (error "discv5 message packet is below its minimum size"))
        (when (> auth-end (length packet))
          (error "discv5 authdata size exceeds packet"))
        (let* ((masked-auth (subseq packet auth-start auth-end))
               (masked-header (concat-bytes masked-static masked-auth))
               (header
                 (discv5-mask-header
                  (discv5-codec-node-id codec) iv masked-header))
               (authdata (subseq header +discv5-static-header-size+))
               (authenticated-data (concat-bytes iv header))
               (message (subseq packet auth-end)))
          (values flag nonce authdata message authenticated-data))))))

(defun discv5-handshake-record (challenge source-id record-bytes)
  (let ((record
          (cond
            ((plusp (length record-bytes)) record-bytes)
            ((discv5-whoareyou-remote-record challenge)
             (discv5-whoareyou-remote-record challenge))
            (t (error "discv5 handshake omitted a required ENR")))))
    (let* ((decoded (decode-enr record))
           (record-id (discv5-node-id (enr-public-key decoded))))
      (unless (equalp record-id source-id)
        (error "discv5 handshake ENR has the wrong node ID"))
      record)))

(defun discv5-decode-packet
    (codec packet endpoint &key expected-node-id)
  "Decode PACKET. Returns (VALUES KIND MESSAGE SOURCE-ID AUX).

KIND is :UNKNOWN, :WHOAREYOU, or :MESSAGE. AUX is :HANDSHAKE for the first
authenticated message of a new session and NIL otherwise."
  (multiple-value-bind (flag nonce authdata encrypted authenticated-data)
      (discv5-unmask-packet codec packet)
    (case flag
      (1
       (unless (= 24 (length authdata))
         (error "discv5 WHOAREYOU authdata must be 24 bytes"))
       (unless (zerop (length encrypted))
         (error "discv5 WHOAREYOU must not carry a message"))
       (let ((challenge
               (make-discv5-whoareyou
                :request-nonce nonce
                :id-nonce (subseq authdata 0 16)
                :record-seq (bytes-to-integer (subseq authdata 16 24))
                :challenge-data authenticated-data)))
         (values :whoareyou challenge expected-node-id nil)))
      (0
       (unless (= 32 (length authdata))
         (error "discv5 message authdata must be 32 bytes"))
       (let* ((source-id authdata)
              (session (discv5-codec-session codec source-id endpoint))
              (plaintext
                (and session
                     (handler-case
                         (discv5-aes-gcm-decrypt
                          (discv5-session-read-key session)
                          nonce encrypted authenticated-data)
                       (error () nil)))))
         (if plaintext
             (values :message (decode-discv5-message plaintext) source-id nil)
             (values :unknown nonce source-id nil))))
      (2
       (when (< (length authdata) 34)
         (error "discv5 handshake authdata is truncated"))
       (let* ((source-id (subseq authdata 0 32))
              (signature-size (aref authdata 32))
              (public-key-size (aref authdata 33))
              (signature-start 34)
              (public-key-start (+ signature-start signature-size))
              (record-start (+ public-key-start public-key-size)))
         (when (> record-start (length authdata))
           (error "discv5 handshake variable authdata is truncated"))
         (unless (and (= signature-size 64) (= public-key-size 33))
           (error "discv5 v4 handshake requires 64-byte signature and 33-byte key"))
         (let* ((key (discv5-state-key source-id endpoint))
                (challenge (gethash key (discv5-codec-challenges codec))))
           (unless challenge
             (error "unexpected discv5 handshake"))
           ;; A failed proof consumes the challenge too, preventing replay.
           (remhash key (discv5-codec-challenges codec))
           (let* ((signature
                    (subseq authdata signature-start public-key-start))
                  (ephemeral-public
                    (subseq authdata public-key-start record-start))
                  (record
                    (discv5-handshake-record
                     challenge source-id (subseq authdata record-start)))
                  (decoded (decode-enr record))
                  (static-public (enr-public-key decoded)))
             (unless (discv5-verify-id-signature
                      signature static-public
                      (discv5-whoareyou-challenge-data challenge)
                      ephemeral-public (discv5-codec-node-id codec))
               (error "discv5 identity proof signature is invalid"))
             (multiple-value-bind (initiator-key recipient-key)
                 (discv5-derive-session-keys
                  (discv5-codec-private-key codec) ephemeral-public
                  source-id (discv5-codec-node-id codec)
                  (discv5-whoareyou-challenge-data challenge))
               (let ((plaintext
                       (discv5-aes-gcm-decrypt
                        initiator-key nonce encrypted authenticated-data)))
                 (discv5-codec-install-session
                  codec source-id endpoint initiator-key recipient-key
                  :remote-record record)
                 (values :message (decode-discv5-message plaintext)
                         source-id :handshake)))))))
      (otherwise (error "unsupported discv5 packet flag ~D" flag)))))
