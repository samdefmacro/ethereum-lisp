(in-package #:ethereum-lisp.chain-config)

(defun unparameterized-blob-schedule-fork (name)
  "Refuse to price blobs for a fork whose parameters this build does not carry.

Only BPO1 and BPO2 have canonical mainnet parameters; later BPO slots exist in
the config schema without agreed target/max/update-fraction values. Falling
through to the previous fork's schedule would silently produce a different
excess blob gas than other clients, so an activated but unparameterized fork is
an explicit capability boundary. A genesis `blobSchedule` entry overrides this."
  (error "~A is active but this build has no blob schedule for it; ~
supply an explicit blobSchedule entry in the chain config"
         name))

(defun blob-schedule-values (target-blobs max-blobs update-fraction)
  (values (* target-blobs +blob-gas-per-blob+)
          (* max-blobs +blob-gas-per-blob+)
          update-fraction))

(defun validate-blob-schedule-entry (entry)
  (unless (typep entry 'blob-schedule-entry)
    (block-validation-fail "Blob schedule entry is malformed"))
  (unless (and (integerp (blob-schedule-entry-timestamp entry))
               (not (minusp (blob-schedule-entry-timestamp entry))))
    (block-validation-fail
     "Blob schedule timestamp must be a non-negative integer"))
  (unless (and (integerp (blob-schedule-entry-target-blobs entry))
               (not (minusp (blob-schedule-entry-target-blobs entry))))
    (block-validation-fail
     "Blob schedule target must be a non-negative integer"))
  (unless (and (integerp (blob-schedule-entry-max-blobs entry))
               (not (minusp (blob-schedule-entry-max-blobs entry))))
    (block-validation-fail "Blob schedule max must be a non-negative integer"))
  (unless (and (integerp (blob-schedule-entry-update-fraction entry))
               (plusp (blob-schedule-entry-update-fraction entry)))
    (block-validation-fail "Blob schedule update fraction must be positive"))
  t)

(defun active-custom-blob-schedule-entry (config timestamp)
  (let ((active-entry nil))
    (dolist (entry (chain-config-custom-blob-schedule config) active-entry)
      (validate-blob-schedule-entry entry)
      (when (and timestamp
                 (<= (blob-schedule-entry-timestamp entry) timestamp)
                 (or (null active-entry)
                     (> (blob-schedule-entry-timestamp entry)
                        (blob-schedule-entry-timestamp active-entry))))
        (setf active-entry entry)))))

(defun custom-blob-schedule-entry-values (entry)
  (blob-schedule-values (blob-schedule-entry-target-blobs entry)
                        (blob-schedule-entry-max-blobs entry)
                        (blob-schedule-entry-update-fraction entry)))

(defun chain-rules-blob-schedule (rules)
  (if (and (chain-rules-blob-schedule-target-gas rules)
           (chain-rules-blob-schedule-max-gas rules)
           (chain-rules-blob-schedule-update-fraction rules))
      (values (chain-rules-blob-schedule-target-gas rules)
              (chain-rules-blob-schedule-max-gas rules)
              (chain-rules-blob-schedule-update-fraction rules))
      (cond
        ((chain-rules-bpo5-p rules) (unparameterized-blob-schedule-fork "BPO5"))
        ((chain-rules-bpo4-p rules)
         (blob-schedule-values +bpo4-target-blobs-per-block+
                               +bpo4-max-blobs-per-block+
                               +bpo4-blob-base-fee-update-fraction+))
        ((chain-rules-bpo3-p rules)
         (blob-schedule-values +bpo3-target-blobs-per-block+
                               +bpo3-max-blobs-per-block+
                               +bpo3-blob-base-fee-update-fraction+))
        ((chain-rules-bpo2-p rules)
         (blob-schedule-values +bpo2-target-blobs-per-block+
                               +bpo2-max-blobs-per-block+
                               +bpo2-blob-base-fee-update-fraction+))
        ((chain-rules-bpo1-p rules)
         (blob-schedule-values +bpo1-target-blobs-per-block+
                               +bpo1-max-blobs-per-block+
                               +bpo1-blob-base-fee-update-fraction+))
        ((chain-rules-expanded-blob-schedule-p rules)
         (blob-schedule-values +osaka-target-blobs-per-block+
                               +osaka-max-blobs-per-block+
                               +osaka-blob-base-fee-update-fraction+))
        (t
         (blob-schedule-values +target-blobs-per-block+
                               +max-blobs-per-block+
                               +blob-base-fee-update-fraction+)))))

(defun chain-config-blob-schedule (config block-number timestamp)
  (let ((custom-entry (active-custom-blob-schedule-entry config timestamp)))
    (if custom-entry
        (custom-blob-schedule-entry-values custom-entry)
        (cond
          ((chain-config-bpo5-p config block-number timestamp)
           (unparameterized-blob-schedule-fork "BPO5"))
          ((chain-config-bpo4-p config block-number timestamp)
           (blob-schedule-values +bpo4-target-blobs-per-block+
                                 +bpo4-max-blobs-per-block+
                                 +bpo4-blob-base-fee-update-fraction+))
          ((chain-config-bpo3-p config block-number timestamp)
           (blob-schedule-values +bpo3-target-blobs-per-block+
                                 +bpo3-max-blobs-per-block+
                                 +bpo3-blob-base-fee-update-fraction+))
          ((chain-config-bpo2-p config block-number timestamp)
           (blob-schedule-values +bpo2-target-blobs-per-block+
                                 +bpo2-max-blobs-per-block+
                                 +bpo2-blob-base-fee-update-fraction+))
          ((chain-config-bpo1-p config block-number timestamp)
           (blob-schedule-values +bpo1-target-blobs-per-block+
                                 +bpo1-max-blobs-per-block+
                                 +bpo1-blob-base-fee-update-fraction+))
          ((chain-config-expanded-blob-schedule-p config block-number timestamp)
           (blob-schedule-values +osaka-target-blobs-per-block+
                                 +osaka-max-blobs-per-block+
                                 +osaka-blob-base-fee-update-fraction+))
          (t
           (blob-schedule-values +target-blobs-per-block+
                                 +max-blobs-per-block+
                                 +blob-base-fee-update-fraction+))))))
