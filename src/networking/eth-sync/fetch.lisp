(in-package #:ethereum-lisp.eth-sync)

;;;; Block download over an eth peer.
;;;;
;;;; eth/66 wraps every request and its reply in a request id, so a reply can be
;;;; matched to the request that asked for it. These helpers send a request and
;;;; then read eth messages until the reply with the matching id arrives,
;;;; skipping unsolicited announcements (and, thanks to the transport, answering
;;;; base-protocol keepalives) in between.

(defconstant +eth-max-skipped-messages+ 256
  "How many unrelated eth messages to skip while awaiting a matching reply
before giving up.")

(defun eth-peer-await (peer expected-eth-id request-id decoder)
  "Read eth messages from PEER until one of EXPECTED-ETH-ID whose DECODER result
matches REQUEST-ID, and return the decoded payload.

DECODER is applied to the message payload and must return (VALUES ID RESULT);
RESULT is returned once ID equals REQUEST-ID. Messages of other kinds, and
replies to other requests, are skipped up to a bound."
  (dotimes (i +eth-max-skipped-messages+
              (error "no reply of eth id ~D for request id ~D after ~D messages"
                     expected-eth-id request-id +eth-max-skipped-messages+))
    (multiple-value-bind (eth-id payload) (eth-peer-read peer)
      (when (= eth-id expected-eth-id)
        (multiple-value-bind (id result) (funcall decoder payload)
          (when (= id request-id)
            (return result)))))))

(defun eth-peer-get-block-headers
    (peer &key origin-number origin-hash (amount 1) (skip 0) reverse
               (request-id (eth-peer-next-request-id peer)))
  "Request block headers from PEER and return the decoded header list.

The origin is a hash when ORIGIN-HASH is given, otherwise the block number
ORIGIN-NUMBER; AMOUNT, SKIP, and REVERSE follow the eth GetBlockHeaders
semantics."
  (eth-peer-send peer +eth-message-get-block-headers+
                 (encode-eth-get-block-headers
                  (make-eth-get-block-headers
                   :request-id request-id
                   :origin-number origin-number
                   :origin-hash origin-hash
                   :amount amount :skip skip :reverse reverse)))
  (eth-peer-await peer +eth-message-block-headers+ request-id
                  #'decode-eth-block-headers))

(defun eth-peer-get-block-bodies
    (peer hashes &key (request-id (eth-peer-next-request-id peer)))
  "Request the block bodies for HASHES from PEER and return the decoded bodies."
  (eth-peer-send peer +eth-message-get-block-bodies+
                 (encode-eth-get-block-bodies request-id hashes))
  (eth-peer-await peer +eth-message-block-bodies+ request-id
                  #'decode-eth-block-bodies))
