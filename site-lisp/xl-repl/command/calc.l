;;; -*- mode:lisp; package:repl -*-
(provide "xl-repl/command/calc")

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require "xl-repl/repl-mode"))

(in-package :repl)

(defun repl.command::calc (&rest exprs)
  "exprs‚ðcalc-mode‚ÌŒvŽZŽ®‚Æ‚µ‚Ä•]‰¿"
  (if exprs
      (let ((result (ed::calc-string (format nil "~{~A~^ ~}" exprs))))
	(eval-and-print (format nil "~A" result) t))
    (enter-calc-mode)))

(defun enter-calc-mode ()
  (defer
    (insert "; calc-mode (press C-l to quit)")
    (let ((km (copy-keymap *calc-mode-map*)))
      (define-key km #\C-l (flet ((exit-calc-mode () (interactive) (lisp-repl-mode)))
			     #'exit-calc-mode))
      (let ((*calc-mode-hook* (list (lambda () (use-keymap km)))))
	(calc-mode)))))
