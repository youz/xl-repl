;;; -*- mode:lisp; package:repl.command.std -*-

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require "xl-repl/repl-mode"))

(in-package :repl)

(defun repl.command::help (&optional pattern)
  "REPLコマンドの説明を表示"
  (let ((coms nil)
	(pat (string pattern)))
    (do-symbols (s :repl.command)
      (when (fboundp s)
	(let ((name (symbol-name s)))
	  (when (or (null pattern) (string-match pat name))
	    (push s coms)))))
    (dolist (com (sort coms #'string< :key #'symbol-name))
      (let ((args (cadr (si:closure-body (symbol-function com)))))
	(format t ":~A ~@[~A~]~%~4T; ~A~%" com args
		(or (documentation com 'function)
		    "not documented"))))))

(defun repl.command::describe (#0=symbol-or-package-name)
  "パッケージ/変数/定数/関数の説明を表示"
  (show-package-description #0#)
  (when (and (symbolp #0#) (not (keywordp #0#)))
    (show-function-description #0#)
    (show-variable-description #0#)))


(provide "xl-repl/command/help")
