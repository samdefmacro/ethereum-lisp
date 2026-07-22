(in-package #:ethereum-lisp.rpc-http)

(defconstant +engine-rpc-jwt-expiry-seconds+ 60)

(defparameter +engine-rpc-base64url-alphabet+
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

(defun engine-rpc-base64url-encode (bytes)
  (let ((bytes (ensure-byte-vector bytes)))
    (with-output-to-string (stream)
      (loop for index from 0 below (length bytes) by 3
            for remaining = (- (length bytes) index)
            for b0 = (aref bytes index)
            for b1 = (if (>= remaining 2) (aref bytes (1+ index)) 0)
            for b2 = (if (>= remaining 3) (aref bytes (+ index 2)) 0)
            for value = (logior (ash b0 16) (ash b1 8) b2)
            do (write-char
                (aref +engine-rpc-base64url-alphabet+
                      (ldb (byte 6 18) value))
                stream)
               (write-char
                (aref +engine-rpc-base64url-alphabet+
                      (ldb (byte 6 12) value))
                stream)
               (when (>= remaining 2)
                 (write-char
                  (aref +engine-rpc-base64url-alphabet+
                        (ldb (byte 6 6) value))
                  stream))
               (when (>= remaining 3)
                 (write-char
                  (aref +engine-rpc-base64url-alphabet+
                        (ldb (byte 6 0) value))
                  stream))))))

(defun engine-rpc-base64url-value (char)
  (let ((position (position char +engine-rpc-base64url-alphabet+)))
    (unless position
      (block-validation-fail "JWT contains invalid base64url data"))
    position))

(defun engine-rpc-base64url-decode (string)
  (when (= (mod (length string) 4) 1)
    (block-validation-fail "JWT contains invalid base64url length"))
  (let ((bytes '())
        (accumulator 0)
        (bits 0))
    (loop for char across string
          for value = (engine-rpc-base64url-value char)
          do (setf accumulator (logior (ash accumulator 6) value)
                   bits (+ bits 6))
             (loop while (>= bits 8)
                   do (decf bits 8)
                      (push (logand #xff (ash accumulator (- bits))) bytes)))
    (ensure-byte-vector (nreverse bytes))))

(defun engine-rpc-hmac-sha256 (key message)
  (hmac-sha256 key message))

(defun engine-rpc-constant-time-bytes= (left right)
  (constant-time-bytes= left right))

(defun engine-rpc-jwt-signature (secret signing-input)
  (engine-rpc-base64url-encode
   (engine-rpc-hmac-sha256 secret (ascii-to-bytes signing-input))))

(defun engine-rpc-make-jwt-token (secret issued-at &key expires-at)
  (unless (and (byte-vector-p secret) (= 32 (length secret)))
    (block-validation-fail "Engine JWT secret must be 32 bytes"))
  (let* ((header (engine-rpc-base64url-encode
                  (ascii-to-bytes "{\"alg\":\"HS256\",\"typ\":\"JWT\"}")))
         (payload
           (engine-rpc-base64url-encode
            (ascii-to-bytes
             (if expires-at
                 (format nil "{\"iat\":~D,\"exp\":~D}" issued-at expires-at)
                 (format nil "{\"iat\":~D}" issued-at)))))
         (signing-input (concatenate 'string header "." payload))
         (signature (engine-rpc-jwt-signature secret signing-input)))
    (concatenate 'string signing-input "." signature)))

(defun engine-rpc-token-parts (token)
  (let* ((first-dot (position #\. token))
         (second-dot (and first-dot (position #\. token :start (1+ first-dot)))))
    (unless (and first-dot second-dot
                 (not (position #\. token :start (1+ second-dot))))
      (block-validation-fail "JWT must contain three parts"))
    (values (subseq token 0 first-dot)
            (subseq token (1+ first-dot) second-dot)
            (subseq token (1+ second-dot)))))

(defun engine-rpc-jwt-object (part label)
  (let ((decoded (bytes-to-ascii (engine-rpc-base64url-decode part))))
    (handler-case
        (let ((object (parse-json decoded)))
          (unless (json-object-p object)
            (block-validation-fail "JWT ~A must be a JSON object" label))
          object)
      (error ()
        (block-validation-fail "JWT ~A is not valid JSON" label)))))

(defun engine-rpc-required-jwt-field (object name)
  (unless (json-object-field-present-p object name)
    (block-validation-fail "JWT field ~A is missing" name))
  (json-object-field object name))

(defun engine-rpc-validate-jwt-token (token secret now)
  (unless (and (byte-vector-p secret) (= 32 (length secret)))
    (block-validation-fail "Engine JWT secret must be 32 bytes"))
  (multiple-value-bind (header-part payload-part signature-part)
      (engine-rpc-token-parts token)
    (let* ((header (engine-rpc-jwt-object header-part "header"))
           (payload (engine-rpc-jwt-object payload-part "payload"))
           (algorithm (engine-rpc-required-jwt-field header "alg"))
           (issued-at (engine-rpc-required-jwt-field payload "iat"))
           (expires-at (json-object-field payload "exp"))
           (signing-input (concatenate 'string header-part "." payload-part))
           (expected-signature
             (engine-rpc-base64url-decode
              (engine-rpc-jwt-signature secret signing-input)))
           (actual-signature
             (engine-rpc-base64url-decode signature-part)))
      (unless (string= algorithm "HS256")
        (block-validation-fail "JWT algorithm must be HS256"))
      (unless (integerp issued-at)
        (block-validation-fail "JWT issued-at must be an integer"))
      (when (and expires-at
                 (or (not (integerp expires-at))
                     (< expires-at now)))
        (block-validation-fail "JWT is expired"))
      (when (> (- now issued-at) +engine-rpc-jwt-expiry-seconds+)
        (block-validation-fail "JWT is stale"))
      (when (> (- issued-at now) +engine-rpc-jwt-expiry-seconds+)
        (block-validation-fail "JWT is from the future"))
      (unless (engine-rpc-constant-time-bytes=
               expected-signature actual-signature)
        (block-validation-fail "JWT signature is invalid"))
      t)))

(defun engine-rpc-http-authorized-p (authorization secret now)
  (unless authorization
    (block-validation-fail "missing token"))
  (unless (string-prefix-p "Bearer " authorization)
    (block-validation-fail "missing token"))
  (engine-rpc-validate-jwt-token
   (subseq authorization (length "Bearer "))
   secret
   now))
