(in-package #:ethereum-lisp.test)

(defun snap-test-hash (byte)
  (make-array 32 :element-type '(unsigned-byte 8) :initial-element byte))

(defun snap-test-round-trip (message-id packet)
  (ethereum-lisp.snap:decode-snap-message
   message-id
   (ethereum-lisp.snap:encode-snap-message message-id packet)))

(deftest snap-one-wire-messages-round-trip
  (:layer :unit :module :p2p)
  (let* ((root (snap-test-hash 1))
         (origin (snap-test-hash 2))
         (limit (snap-test-hash 3))
         (account (ethereum-lisp.snap:make-snap-account-data
                   (snap-test-hash 4)
                   (make-rlp-list
                    (ensure-byte-vector #(1))
                    (ensure-byte-vector #(2))
                    (ensure-byte-vector #(3))
                    (ensure-byte-vector #(4)))))
         (slot (ethereum-lisp.snap:make-snap-storage-data
                (snap-test-hash 5) #(6 7))))
    (let ((decoded
            (snap-test-round-trip
             ethereum-lisp.snap:+snap-message-get-account-range+
             (ethereum-lisp.snap:make-snap-get-account-range
              11 root origin limit 1024))))
      (is (= 11 (ethereum-lisp.snap:snap-get-account-range-id decoded)))
      (is (bytes= root
                  (ethereum-lisp.snap:snap-get-account-range-root decoded))))
    (let ((decoded
            (snap-test-round-trip
             ethereum-lisp.snap:+snap-message-account-range+
             (ethereum-lisp.snap:make-snap-account-range
              11 (list account) (list #(8 9))))))
      (is (= 1 (length
                (ethereum-lisp.snap:snap-account-range-accounts decoded))))
      (is (= 1 (length
                (ethereum-lisp.snap:snap-account-range-proof decoded)))))
    (let ((decoded
            (snap-test-round-trip
             ethereum-lisp.snap:+snap-message-get-storage-ranges+
             (ethereum-lisp.snap:make-snap-get-storage-ranges
              12 root (list (snap-test-hash 4)) #(1) #(2) 2048))))
      (is (= 12
             (ethereum-lisp.snap:snap-get-storage-ranges-id decoded)))
      (is (= 1
             (length
              (ethereum-lisp.snap:snap-get-storage-ranges-accounts decoded)))))
    (let ((decoded
            (snap-test-round-trip
             ethereum-lisp.snap:+snap-message-storage-ranges+
             (ethereum-lisp.snap:make-snap-storage-ranges
              12 (list (list slot)) (list #(10))))))
      (is (= 1 (length
                (first
                 (ethereum-lisp.snap:snap-storage-ranges-slots decoded))))))
    (let ((decoded
            (snap-test-round-trip
             ethereum-lisp.snap:+snap-message-get-bytecodes+
             (ethereum-lisp.snap:make-snap-get-bytecodes
              13 (list (snap-test-hash 6)) 4096))))
      (is (= 13 (ethereum-lisp.snap:snap-get-bytecodes-id decoded))))
    (let ((decoded
            (snap-test-round-trip
             ethereum-lisp.snap:+snap-message-bytecodes+
             (ethereum-lisp.snap:make-snap-bytecodes
              13 (list #(1 2 3) #(4 5))))))
      (is (= 2 (length (ethereum-lisp.snap:snap-bytecodes-codes decoded)))))
    (let ((decoded
            (snap-test-round-trip
             ethereum-lisp.snap:+snap-message-get-trie-nodes+
             (ethereum-lisp.snap:make-snap-get-trie-nodes
              14 root (list (list #(1 2) #(3))) 8192))))
      (is (= 2
             (length
              (first
               (ethereum-lisp.snap:snap-get-trie-nodes-paths decoded))))))
    (let ((decoded
            (snap-test-round-trip
             ethereum-lisp.snap:+snap-message-trie-nodes+
             (ethereum-lisp.snap:make-snap-trie-nodes
              14 (list #(1 2 3))))))
      (is (= 1
             (length (ethereum-lisp.snap:snap-trie-nodes-nodes decoded)))))))

(deftest snap-state-backend-is-an-injected-boundary
  (:layer :unit :module :p2p)
  (let* ((root (snap-test-hash 1))
         (backend
           (ethereum-lisp.snap:make-snap-state-backend
            :account-range
            (lambda (request)
              (ethereum-lisp.snap:make-snap-account-range
               (ethereum-lisp.snap:snap-get-account-range-id request)
               '() '()))))
         (payload
           (ethereum-lisp.snap:encode-snap-message
            ethereum-lisp.snap:+snap-message-get-account-range+
            (ethereum-lisp.snap:make-snap-get-account-range
             99 root (snap-test-hash 0) (snap-test-hash 255) 1024))))
    (multiple-value-bind (message-id response)
        (ethereum-lisp.snap:snap-serve-request
         backend ethereum-lisp.snap:+snap-message-get-account-range+ payload)
      (is (= ethereum-lisp.snap:+snap-message-account-range+ message-id))
      (is (= 99
             (ethereum-lisp.snap:snap-account-range-id
              (ethereum-lisp.snap:decode-snap-message
               message-id response)))))
    (signals error
      (ethereum-lisp.snap:snap-serve-request
       backend
       ethereum-lisp.snap:+snap-message-get-bytecodes+
       (ethereum-lisp.snap:encode-snap-message
        ethereum-lisp.snap:+snap-message-get-bytecodes+
        (ethereum-lisp.snap:make-snap-get-bytecodes 1 '() 1024))))))

(deftest snap-wire-rejects-unbounded-or-malformed-fields
  (:layer :unit :module :p2p)
  (signals rlp-error
    (ethereum-lisp.snap:decode-snap-message
     ethereum-lisp.snap:+snap-message-bytecodes+
     (rlp-encode
      (make-rlp-list
       (integer-to-minimal-bytes 1)
       (apply #'make-rlp-list
              (loop repeat
                    (1+ ethereum-lisp.snap:+snap-max-list-items+)
                    collect (make-byte-vector 0)))))))
  (signals error
    (ethereum-lisp.snap:decode-snap-message
     ethereum-lisp.snap:+snap-message-get-account-range+
     (rlp-encode
      (make-rlp-list
       (integer-to-minimal-bytes 1)
       (make-byte-vector 33)
       (snap-test-hash 0)
       (snap-test-hash 255)
       (integer-to-minimal-bytes 1024))))))
