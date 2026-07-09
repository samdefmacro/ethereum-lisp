(defun smoke-gate-main ()
  (let* ((args (smoke-gate-arguments))
         (help-p (smoke-gate-help-p args)))
    (if help-p
        (smoke-gate-print-help)
        (let* ((pinned-p (smoke-gate-pinned-v5.4.0-p args))
               (devnet-p (smoke-gate-devnet-p args))
               (drift-map-p (smoke-gate-drift-map-p args))
               (json-p (smoke-gate-json-p args))
               (root-argument (smoke-gate-argument-root args)))
          (load (merge-pathnames "tests/load-tests.lisp"
                                 *ethereum-lisp-smoke-gate-root*))
          (let* ((suite-root (smoke-gate-suite-root root-argument pinned-p))
                 (report (smoke-gate-report
                          suite-root
                          pinned-p
                          :devnet-p devnet-p
                          :drift-map-p drift-map-p)))
            (if json-p
                (format t "~&~A~%" (smoke-gate-json-encode report))
                (smoke-gate-print-text report)))))))

(smoke-gate-main)
