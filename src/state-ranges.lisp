(in-package #:ethereum-lisp.state)

(defun state-db-sorted-hash-keys (table)
  (let (keys)
    (maphash (lambda (key value)
               (declare (ignore value))
               (push key keys))
             table)
    (sort keys #'string<)))

(defun state-object-storage-entries (object)
  (loop for slot in (state-db-sorted-hash-keys (state-object-storage object))
        collect (cons (hash32-from-hex slot)
                      (gethash slot (state-object-storage object)))))

(defun state-proof-key-id (key)
  (bytes-to-hex (if (hash32-p key)
                    (hash32-bytes key)
                    (ensure-byte-vector key))
                :prefix nil))

(defun state-proof-key-in-range-p (proof-key start end)
  (let ((key-id (state-proof-key-id proof-key))
        (start-id (and start (state-proof-key-id start)))
        (end-id (and end (state-proof-key-id end))))
    (and (or (null start-id)
             (not (string< key-id start-id)))
         (or (null end-id)
             (string< key-id end-id)))))

(defun state-db-account-range-entry (address object)
  (let ((proof-key (state-db-account-proof-key address)))
    (make-state-account-range-entry
     :proof-key proof-key
     :address address
     :account (account-with-storage-root object)
     :code (copy-seq (state-object-code object))
     :storage-entries (state-object-storage-entries object))))

(defun state-db-account-range (state &key start end)
  (let (entries)
    (maphash (lambda (address-key object)
               (let* ((address (address-from-hex address-key))
                      (entry (state-db-account-range-entry address object)))
                 (when (state-proof-key-in-range-p
                        (state-account-range-entry-proof-key entry)
                        start
                        end)
                   (push entry entries))))
             (state-db-objects state))
    (sort entries
          #'string<
          :key (lambda (entry)
                 (state-proof-key-id
                  (state-account-range-entry-proof-key entry))))))

(defun state-db-storage-range-entry (slot value)
  (make-state-storage-range-entry
   :proof-key (state-db-storage-proof-key slot)
   :slot slot
   :value value))

(defun state-db-storage-range (state address &key start end)
  (let ((object (state-db-get-object state address))
        entries)
    (when object
      (maphash (lambda (slot-key value)
                 (let ((entry
                         (state-db-storage-range-entry
                          (hash32-from-hex slot-key)
                          value)))
                   (when (state-proof-key-in-range-p
                          (state-storage-range-entry-proof-key entry)
                          start
                          end)
                     (push entry entries))))
               (state-object-storage object)))
    (sort entries
          #'string<
          :key (lambda (entry)
                 (state-proof-key-id
                  (state-storage-range-entry-proof-key entry))))))

(defun state-db-for-each-account (state function)
  (dolist (address-key (state-db-sorted-hash-keys (state-db-objects state)))
    (let* ((object (gethash address-key (state-db-objects state)))
           (address (address-from-hex address-key))
           (account (account-with-storage-root object))
           (code (copy-seq (state-object-code object)))
           (storage-entries (state-object-storage-entries object)))
      (funcall function address account code storage-entries)))
  state)
