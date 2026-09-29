(in-package #:ethereum-lisp.public-api)

;;;; Per-request work budgets of the public API: --rpc.gascap, --rpc.evmtimeout
;;;; and --rpc.txfeecap.
;;;;
;;;; Each is a special bound for the duration of one request from the RPC
;;;; context that serves it (ethereum-lisp.rpc RPC-BUDGETS), so two listeners,
;;;; or two nodes in one process, can carry different budgets. The defaults are
;;;; geth's (node/defaults.go, eth/ethconfig/config.go at 38271784), and zero
;;;; means "no limit", as it does in geth. Each is checked before the work it
;;;; bounds is done: the gas cap before a call executes, the EVM deadline while
;;;; it executes, the fee cap before a transaction reaches the pool.

(defconstant +eth-rpc-default-call-gas-limit+ 50000000
  "geth's default RPCGasCap: the gas cap for eth_call, eth_estimateGas,
eth_createAccessList, eth_simulateV1 and debug_traceCall.")

(defconstant +eth-rpc-uncapped-call-gas+ (floor (1- (expt 2 64)) 2)
  "The gas a call without a gas field is given when there is no cap: geth's
math.MaxUint64 / 2 (internal/ethapi/transaction_args.go CallDefaults).")

(defvar *eth-rpc-gas-cap* +eth-rpc-default-call-gas-limit+
  "--rpc.gascap: the most gas one call may use. 0 means no cap.")

(defvar *eth-rpc-evm-timeout-seconds* 5
  "--rpc.evmtimeout: how long eth_call and eth_simulateV1 may execute, in
seconds (geth's default is 5 s). 0 means no deadline.")

(defvar *eth-rpc-tx-fee-cap-wei* (expt 10 18)
  "--rpc.txfeecap, in wei: the largest fee (gas price times gas limit) a
transaction submitted through eth_sendRawTransaction may offer. geth's default
is 1 ether. 0 means no cap.")

(defun eth-rpc-gas-cap ()
  "The call gas cap, or NIL when there is none."
  (let ((cap *eth-rpc-gas-cap*))
    (and cap (plusp cap) cap)))

(defun eth-rpc-apply-gas-cap (gas)
  "GAS, lowered to the call gas cap."
  (let ((cap (eth-rpc-gas-cap)))
    (if cap (min gas cap) gas)))

(defun call-with-eth-rpc-evm-timeout (thunk)
  "Call THUNK with the EVM stopped at the --rpc.evmtimeout deadline, answering
geth's -32000 \"execution aborted (timeout = 5s)\" when it is reached."
  (let ((seconds *eth-rpc-evm-timeout-seconds*))
    (handler-case (call-with-evm-deadline seconds thunk)
      (evm-execution-deadline-error ()
        (engine-rpc-fail
         -32000
         (format nil "execution aborted (timeout = ~As)" seconds))))))

(defun eth-rpc-check-transaction-fee-cap (transaction)
  "Refuse TRANSACTION when its fee cap times its gas limit exceeds
--rpc.txfeecap, with geth's -32000 message (internal/ethapi/api.go checkTxFee):
the fee is priced at the transaction's max fee per gas, its gas price for a
legacy transaction."
  (let ((cap *eth-rpc-tx-fee-cap-wei*))
    (when (and cap (plusp cap))
      (let ((fee (* (transaction-max-fee-per-gas transaction)
                    (transaction-gas-limit transaction))))
        (when (> fee cap)
          (engine-rpc-fail
           -32000
           (format nil "tx fee (~,2F ether) exceeds the configured cap (~,2F ether)"
                   (/ fee 1d18) (/ cap 1d18))))))))
