;;; -*- mode:lisp; package:repl -*-

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require "xl-repl/repl-mode"))

(in-package :repl)

(defun repl.command::dir (&optional wildcard)
  "default-directoryのファイルを列挙"
  (let* ((dir (default-directory))
	 (files (directory dir :wild (if wildcard (string wildcard) "*"))))
    (format t "[~A]~%~{~A~%~}" dir files)
    files))

(defun repl.command::cd (&optional dir)
  "default-directoryをdirへ移動 (dir省略時はdefault-directoryを表示)"
  (if dir
      (let ((path (merge-pathnames dir (default-directory))))
	(when (set-default-directory path)
	  (princ path)))
    (princ (default-directory))))


(provide "xl-repl/command/path")
