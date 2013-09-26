;;; -*- mode:lisp; package:repl-mode -*-

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require "xl-repl/repl-mode"))

(in-package :repl)

(defun repl.command::cmd (&rest args)
  "shellコマンド実行"
  (let* ((p (position :>> args)))
    (cond ((null p)
	   (let* ((buf (create-new-buffer " *cmdout*"))
		  (proc #0=(make-process (format nil "cmd.exe /C ~{~A~^ ~}" args)
					 :output buf
					 :exec-directory (default-directory)
					 :show :hide)))
	     #1=(unwind-protect
		    (while (eq (process-status proc) :run)
		      (sleep-for 0.1))
		  (kill-process proc))
	     (format t "~A~%" (save-excursion
				(set-buffer buf)
				(buffer-substring 0 (point-max))))
	     (kill-buffer buf)))
	  (t
	   (let* ((buf (get-buffer-create (format nil "~{~A~^ ~}" (subseq args (1+ p)))))
		  (args (subseq args 0 p))
		  (proc #0#))
	     #1#
	     (repl.util:defer (pop-to-buffer buf)))))))

(provide "xl-repl/command/shell")
