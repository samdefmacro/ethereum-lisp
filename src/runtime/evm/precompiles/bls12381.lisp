(in-package #:ethereum-lisp.evm.internal)

;;;; EIP-2537 BLS12-381 precompiles at addresses 0x0b..0x11.
;;;;
;;;; This file owns input framing and gas. Point validity, subgroup membership,
;;;; and the group arithmetic itself belong to the backend installed through
;;;; ETHEREUM-LISP.BLS12381, so an absent backend makes the operations fail
;;;; rather than answer incorrectly.

(defun bls12381-msm-discount (discounts pair-count)
  "Return the MSM discount for PAIR-COUNT pairs.

Counts beyond the tabulated range reuse the final entry, which EIP-2537 defines
as the maximum discount."
  (let ((limit (length discounts)))
    (cond
      ((<= pair-count 0) (aref discounts 0))
      ((> pair-count limit) (aref discounts (1- limit)))
      (t (aref discounts (1- pair-count))))))

(defun bls12381-msm-gas (input pair-size multiplication-gas discounts)
  "Price an MSM call over INPUT.

The pair count is floored so a malformed input length still carries a price,
matching how the BN254 pairing precompile reports its failures."
  (let ((pair-count (floor (length input) pair-size)))
    (if (zerop pair-count)
        0
        (floor (* pair-count
                  multiplication-gas
                  (bls12381-msm-discount discounts pair-count))
               +bls12381-msm-discount-multiplier+))))

(defun bls12381-g1-msm-gas (input)
  (bls12381-msm-gas input
                    +bls12381-g1-msm-pair-size+
                    +bls12381-g1-msm-multiplication-gas+
                    +bls12381-g1-msm-discounts+))

(defun bls12381-g2-msm-gas (input)
  (bls12381-msm-gas input
                    +bls12381-g2-msm-pair-size+
                    +bls12381-g2-msm-multiplication-gas+
                    +bls12381-g2-msm-discounts+))

(defun bls12381-pairing-gas (input)
  (+ +bls12381-pairing-base-gas+
     (* +bls12381-pairing-per-pair-gas+
        (floor (length input) +bls12381-pairing-set-size+))))

(defun call-bls12381-backend (operation input gas output-size)
  "Run OPERATION over INPUT, returning (VALUES OUTPUT GAS).

Only a definite verdict that the input is invalid becomes a precompile failure
that burns the call's gas — that outcome is deterministic and every node agrees.
A backend that cannot be consulted signals BLS12381-UNAVAILABLE-ERROR, which is
NOT caught here: converting it into a precompile failure would fabricate a
verdict a node with a working backend would not share, so it propagates and the
node refuses to validate instead."
  (let ((output (handler-case (run-bls12381-operation operation input)
                  (bls12381-input-error (condition)
                    (fail-precompile gas "~A" condition)))))
    (unless (= (length output) output-size)
      (bls12381-unavailable-error
       "BLS12-381 backend returned ~D bytes, expected ~D"
       (length output) output-size))
    (values output gas)))

(defun run-bls12381-fixed-length-precompile
    (operation input gas input-size output-size description)
  (let ((input (ensure-byte-vector input)))
    (unless (= (length input) input-size)
      (fail-precompile gas "Invalid BLS12-381 ~A input size" description))
    (call-bls12381-backend operation input gas output-size)))

(defun run-bls12381-variable-length-precompile
    (operation input gas unit-size output-size description)
  "Run a precompile whose input is a non-empty whole number of UNIT-SIZE blocks."
  (let ((input (ensure-byte-vector input)))
    (when (zerop (length input))
      (fail-precompile gas "Empty BLS12-381 ~A input" description))
    (unless (zerop (mod (length input) unit-size))
      (fail-precompile gas "Invalid BLS12-381 ~A input size" description))
    (call-bls12381-backend operation input gas output-size)))

(defun run-bls12381-g1-add-precompile (input)
  (run-bls12381-fixed-length-precompile :g1-add
                                        input
                                        +bls12381-g1-add-gas+
                                        +bls12381-g1-add-input-size+
                                        +bls12381-g1-point-size+
                                        "G1 addition"))

(defun run-bls12381-g2-add-precompile (input)
  (run-bls12381-fixed-length-precompile :g2-add
                                        input
                                        +bls12381-g2-add-gas+
                                        +bls12381-g2-add-input-size+
                                        +bls12381-g2-point-size+
                                        "G2 addition"))

(defun run-bls12381-map-fp-to-g1-precompile (input)
  (run-bls12381-fixed-length-precompile :map-fp-to-g1
                                        input
                                        +bls12381-map-fp-to-g1-gas+
                                        +bls12381-fp-size+
                                        +bls12381-g1-point-size+
                                        "Fp-to-G1 map"))

(defun run-bls12381-map-fp2-to-g2-precompile (input)
  (run-bls12381-fixed-length-precompile :map-fp2-to-g2
                                        input
                                        +bls12381-map-fp2-to-g2-gas+
                                        +bls12381-fp2-size+
                                        +bls12381-g2-point-size+
                                        "Fp2-to-G2 map"))

(defun run-bls12381-g1-msm-precompile (input)
  (let ((input (ensure-byte-vector input)))
    (run-bls12381-variable-length-precompile :g1-msm
                                             input
                                             (bls12381-g1-msm-gas input)
                                             +bls12381-g1-msm-pair-size+
                                             +bls12381-g1-point-size+
                                             "G1 MSM")))

(defun run-bls12381-g2-msm-precompile (input)
  (let ((input (ensure-byte-vector input)))
    (run-bls12381-variable-length-precompile :g2-msm
                                             input
                                             (bls12381-g2-msm-gas input)
                                             +bls12381-g2-msm-pair-size+
                                             +bls12381-g2-point-size+
                                             "G2 MSM")))

(defun run-bls12381-pairing-check-precompile (input)
  (let ((input (ensure-byte-vector input)))
    (run-bls12381-variable-length-precompile :pairing-check
                                             input
                                             (bls12381-pairing-gas input)
                                             +bls12381-pairing-set-size+
                                             32
                                             "pairing check")))
