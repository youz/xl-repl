;;; -*- mode:lisp; package:repl -*-
(provide "xl-repl/command/calc")

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require "xl-repl/repl-mode"))

(in-package :repl)

(defun repl.command::calc (&rest exprs)
  "exprs‚ðcalc-mode‚ÌŒvŽZŽ®‚Æ‚µ‚Ä•]‰¿"
  (let ((result (ed::calc-string (format nil "~{~A~^ ~}" exprs))))
    (eval-and-print (format nil "~A" result) t)))
