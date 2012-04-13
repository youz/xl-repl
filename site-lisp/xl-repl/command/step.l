;;; -*- mode:lisp; package:repl.command.step -*-
(provide "xl-repl/command/step")

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require "xl-repl/repl-mode"))

(defpackage :repl.command.step
  (:use :lisp :editor :repl :repl.util))
(in-package :repl.command.step)

(defvar *skip-all* nil)
(defvar *repl-buffer* nil)
(defvar *depth* 0)

(defun step-eval (form)
  (let ((*skip-all* nil)
	(*evalhook* #'repl-step-evalhook)
	(*depth* 0))
    (eval form)))

(defun printf (fmt &rest args)
  (let ((pbuf (selected-buffer)))
    (with-print-to-buffer (*repl-buffer* :tag 'repl::cmdout)
      (apply #'format t fmt args))
    (set-buffer *repl-buffer*)
    (goto-char (point-max))
    (refresh-screen)
    (set-buffer pbuf)))

(defun read-keyinput (prompt acceptable-chars &optional use-minibuffer)
  (if use-minibuffer
      (minibuffer-prompt prompt)
    (progn
      (minibuffer-message "")
      (printf "~A" prompt)))
  (whilet c (read-char *keyboard* nil nil)
    (case c
      (#\C-d (return-from read-keyinput))
      (#\C-g (quit))
      (t (cond ((find c acceptable-chars)
		(unless use-minibuffer
		  (printf "~A" c))
		(return-from read-keyinput c))
	       (t (message "無効なキー : ~A" c)))))))


(defun repl-step-evalhook (form env)
  (printf "~&~V@{| ~}Form: ~:[~S~;[byte-code]~]~%" *depth*
	  (and (consp form) (eq (car form) 'si:*byte-code)) form)
  (handler-case
      (let ((values (multiple-value-list
		     (let ((*depth* (1+ *depth*)))
		       (evalhook form #'repl-step-evalhook nil env)))))
	(printf "~&~V@{| ~}+-Values:~{ ~S~}~%" *depth* values)
	(unless *skip-all*
	  (save-excursion
	    (set-buffer *repl-buffer*)
	    (case (read-keyinput "[n] next step / [s] skip-all ? " '(#\n #\s) t)
	      (#\n nil)
	      (#\s (setq *skip-all* t))
	      (t (quit)))))
	(values-list values))
    (error (c)
      (case (read-keyinput
	     (with-output-to-string (os)
	       (format os "~&*** Error - ~A~%~A~%"
		       (si::*structure-definition-name
			(si::*structure-definition c))
		       (si:*condition-string c))
	       (format os "restarts:~%[0] use-value~%[1] ignore (use-value nil)~%[2] abort~%"))
	     '(#\0 #\1 #\2))
	(#\0 (let ((vals (repl.util:read-all-from-string (read-string "values: "))))
	       (printf "~&use-value :~{ ~A~}~%" vals)
	       (return-from repl-step-evalhook (values-list vals))))
	(#\1 (return-from repl-step-evalhook nil))
	(#\2 (error 'silent-quit))
	(t (quit))))))

(defun repl.command::step (form)
  "formをステップ実行"
  (let ((*repl-buffer* (selected-buffer))
	(expr (format nil "(repl.command.step::step-eval '~S)" form)))
    (repl::eval-and-print expr t)))
