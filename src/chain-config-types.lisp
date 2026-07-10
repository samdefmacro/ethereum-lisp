(in-package #:ethereum-lisp.chain-config)

(defconstant +blob-gas-per-blob+ 131072)
(defconstant +target-blobs-per-block+ 3)
(defconstant +max-blobs-per-block+ 6)
(defconstant +osaka-target-blobs-per-block+ 6)
(defconstant +osaka-max-blobs-per-block+ 9)
(defconstant +bpo1-target-blobs-per-block+ 10)
(defconstant +bpo1-max-blobs-per-block+ 15)
(defconstant +bpo2-target-blobs-per-block+ 14)
(defconstant +bpo2-max-blobs-per-block+ 21)
(defconstant +bpo3-target-blobs-per-block+ 21)
(defconstant +bpo3-max-blobs-per-block+ 32)
(defconstant +bpo4-target-blobs-per-block+ 14)
(defconstant +bpo4-max-blobs-per-block+ 21)
(defconstant +blob-base-fee-update-fraction+ 3338477)
(defconstant +osaka-blob-base-fee-update-fraction+ 5007716)
(defconstant +bpo1-blob-base-fee-update-fraction+ 8346193)
(defconstant +bpo2-blob-base-fee-update-fraction+ 11684671)
(defconstant +bpo3-blob-base-fee-update-fraction+ 20609697)
(defconstant +bpo4-blob-base-fee-update-fraction+ 13739630)

(defstruct (blob-schedule-entry
            (:constructor make-blob-schedule-entry
                (&key timestamp target-blobs max-blobs update-fraction)))
  timestamp
  target-blobs
  max-blobs
  update-fraction)

(defstruct (chain-config (:constructor make-chain-config
                             (&key (chain-id 1)
                                   homestead-block
                                   dao-fork-block
                                   dao-fork-support
                                   eip150-block
                                   eip155-block
                                   eip158-block
                                   byzantium-block
                                   constantinople-block
                                   petersburg-block
                                   istanbul-block
                                   muir-glacier-block
                                   berlin-block
                                   london-block
                                   arrow-glacier-block
                                   gray-glacier-block
                                   shanghai-time
                                   cancun-time
                                   prague-time
                                   osaka-time
                                   bpo1-time
                                   bpo2-time
                                   bpo3-time
                                   bpo4-time
                                   bpo5-time
                                   amsterdam-time
                                   ubt-time
                                   enable-ubt-at-genesis-p
                                   terminal-total-difficulty
                                   terminal-total-difficulty-passed
                                   terminal-block-hash
                                   terminal-block-number
                                   merge-netsplit-block
                                   deposit-contract-address
                                   custom-blob-schedule)))
  (chain-id 1 :type (integer 0 *))
  homestead-block
  dao-fork-block
  dao-fork-support
  eip150-block
  eip155-block
  eip158-block
  byzantium-block
  constantinople-block
  petersburg-block
  istanbul-block
  muir-glacier-block
  berlin-block
  london-block
  arrow-glacier-block
  gray-glacier-block
  shanghai-time
  cancun-time
  prague-time
  osaka-time
  bpo1-time
  bpo2-time
  bpo3-time
  bpo4-time
  bpo5-time
  amsterdam-time
  ubt-time
  enable-ubt-at-genesis-p
  terminal-total-difficulty
  terminal-total-difficulty-passed
  terminal-block-hash
  terminal-block-number
  merge-netsplit-block
  deposit-contract-address
  custom-blob-schedule)

(defstruct (chain-rules (:constructor make-chain-rules
                            (&key (chain-id 1)
                                  homestead-p
                                  eip150-p
                                  eip155-p
                                  eip158-p
                                  byzantium-p
                                  constantinople-p
                                  petersburg-p
                                  istanbul-p
                                  berlin-p
                                  london-p
                                  shanghai-p
                                  cancun-p
                                  prague-p
                                  osaka-p
                                  bpo1-p
                                  bpo2-p
                                  bpo3-p
                                  bpo4-p
                                  bpo5-p
                                  amsterdam-p
                                  ubt-p
                                  blob-schedule-target-gas
                                  blob-schedule-max-gas
                                  blob-schedule-update-fraction)))
  (chain-id 1 :type (integer 0 *))
  homestead-p
  eip150-p
  eip155-p
  eip158-p
  byzantium-p
  constantinople-p
  petersburg-p
  istanbul-p
  berlin-p
  london-p
  shanghai-p
  cancun-p
  prague-p
  osaka-p
  bpo1-p
  bpo2-p
  bpo3-p
  bpo4-p
  bpo5-p
  amsterdam-p
  ubt-p
  blob-schedule-target-gas
  blob-schedule-max-gas
  blob-schedule-update-fraction)
