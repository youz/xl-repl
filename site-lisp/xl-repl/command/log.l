;;; -*- mode:lisp; package:repl.command.log -*-
(provide "xl-repl/command/log")

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require "xl-repl/repl-mode"))

(defpackage :repl.command.log
  (:use :lisp :editor :repl :repl.util))
(in-package :repl.command.log)


(defun make-log-stream (&optional (bufname "*log*"))
  (let* ((buf (get-buffer-create (format nil "~A" bufname)))
	 (bs (make-buffer-stream buf))
	 other-buf
	 (km (make-sparse-keymap)))
    (setup-temp-buffer buf)
    (define-key km #\q (lambda () (interactive)
			 (kill-buffer buf)
			 (if other-buf
			     (set-buffer other-buf)
			   (delete-window))))
    (save-excursion
      (set-buffer buf)
      (buffer-stream-set-point bs (point-max))
      (use-keymap km))
    (flet ((writer (str)
	     (unless (deleted-buffer-p buf)
	       (let ((sw (selected-window)))
		 (unwind-protect
		     (progn
		       (iflet win (get-buffer-window buf)
			 (set-window win)
			 (progn
			   (if (= (count-windows) 1)
			       (split-window)
			     (progn
			       (other-window)
			       (setq other-buf (selected-buffer))))
			   (set-buffer buf)))
		       (princ str bs)
		       (goto-char (point-max)))
		   (set-window sw))
		 (refresh-screen)))))
      (ed::make-general-output-stream #'writer))))


(defun repl.command::log (form)
  "ログ取り用バッファストリームをレキシカル変数*log*に束縛してformを評価"
  (let ((expr (format nil "(let ((*log* (~S))) ~S)" 'make-log-stream form)))
    (repl::eval-and-print expr t)))


#| usage
user> :log (let ((n 10))
	     (labels ((f ()
			(when (= (decf n) 0)
			  (stop-timer #'f))
			(format *log* "~D~%" n)))
	       (start-timer 1 #'f)))
|#
