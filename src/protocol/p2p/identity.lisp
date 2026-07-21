(in-package #:ethereum-lisp.p2p)

;;;; devp2p node identity and enode URLs.
;;;;
;;;; A node identity is the 64-byte uncompressed secp256k1 public key body of
;;;; the node key. An enode URL names that identity together with the address
;;;; peers should dial:
;;;;
;;;;   enode://<128 hex chars>@<host>:<tcp-port>[?discport=<udp-port>]
;;;;
;;;; The discport query parameter is present only when discovery listens on a
;;;; different port from the TCP endpoint, matching go-ethereum.

(defconstant +node-id-size+ 64)

(defun node-id-from-private-key (private-key)
  "Return the 64-byte node identity for a secp256k1 PRIVATE-KEY scalar."
  (secp256k1-private-key-public-key private-key))

(defun node-id-to-hex (node-id)
  "Return NODE-ID as 128 lowercase hex characters, without a 0x prefix.

enode URLs carry the identity unprefixed, unlike every other hex value in the
JSON-RPC surface."
  (let ((bytes (ensure-byte-vector node-id)))
    (unless (= +node-id-size+ (length bytes))
      (error "Node identity must be ~D bytes" +node-id-size+))
    (subseq (bytes-to-hex bytes) 2)))

(defun node-id-from-hex (text)
  "Parse 128 hex characters, with or without a 0x prefix, into a node identity."
  (unless (stringp text)
    (error "Node identity must be a string"))
  (let* ((body (if (and (>= (length text) 2)
                        (string-equal "0x" (subseq text 0 2)))
                   (subseq text 2)
                   text))
         (bytes (handler-case (hex-to-bytes body)
                  (error () (error "Node identity is not valid hex")))))
    (unless (= +node-id-size+ (length bytes))
      (error "Node identity must be ~D bytes" +node-id-size+))
    bytes))

(defun enode-url (node-id host tcp-port &key discovery-port)
  "Compose the enode URL for NODE-ID reachable at HOST and TCP-PORT."
  (unless (and (integerp tcp-port) (<= 0 tcp-port 65535))
    (error "enode TCP port must be a port number"))
  (unless (or (null discovery-port)
              (and (integerp discovery-port) (<= 0 discovery-port 65535)))
    (error "enode discovery port must be a port number"))
  (format nil "enode://~A@~A:~D~@[?discport=~D~]"
          (node-id-to-hex node-id)
          host
          tcp-port
          ;; Omitted when discovery shares the TCP port, as go-ethereum does.
          (and discovery-port
               (/= discovery-port tcp-port)
               discovery-port)))

(defun parse-enode-url (url)
  "Parse URL into (VALUES NODE-ID HOST TCP-PORT DISCOVERY-PORT).

DISCOVERY-PORT is the TCP port when no discport parameter is present. Signals an
error when URL is not a well-formed enode URL."
  (unless (stringp url)
    (error "enode URL must be a string"))
  (let ((prefix "enode://"))
    (unless (and (> (length url) (length prefix))
                 (string-equal prefix (subseq url 0 (length prefix))))
      (error "enode URL must start with enode://"))
    (let* ((rest (subseq url (length prefix)))
           (at (position #\@ rest)))
      (unless at
        (error "enode URL must contain an @ separating identity from address"))
      (let* ((node-id (node-id-from-hex (subseq rest 0 at)))
             (address (subseq rest (1+ at)))
             (query (position #\? address))
             (endpoint (if query (subseq address 0 query) address))
             (parameters (and query (subseq address (1+ query))))
             ;; Split on the last colon so IPv6 literals survive.
             (colon (position #\: endpoint :from-end t)))
        (unless colon
          (error "enode URL must contain a host and port"))
        (let ((host (subseq endpoint 0 colon))
              (tcp-port (parse-enode-port (subseq endpoint (1+ colon))
                                          "enode TCP port"))
              (discovery-port nil))
          (when (zerop (length host))
            (error "enode URL host must not be empty"))
          (when parameters
            (setf discovery-port (parse-enode-discovery-parameter parameters)))
          (values node-id host tcp-port (or discovery-port tcp-port)))))))

(defun parse-enode-port (text label)
  (let ((port (handler-case (parse-integer text)
                (error () (error "~A must be an integer" label)))))
    (unless (<= 0 port 65535)
      (error "~A must be a port number" label))
    port))

(defun parse-enode-discovery-parameter (parameters)
  "Return the discport value carried by an enode query string, or NIL."
  (let ((prefix "discport="))
    (loop for start = 0 then (1+ separator)
          for separator = (position #\& parameters :start start)
          for parameter = (subseq parameters start (or separator (length parameters)))
          when (and (> (length parameter) (length prefix))
                    (string-equal prefix (subseq parameter 0 (length prefix))))
            do (return (parse-enode-port (subseq parameter (length prefix))
                                         "enode discovery port"))
          while separator)))
