;;; -*- mode:lisp; package:repl -*-

;; Copyright (c) 2012  Yousuke Ushiki
;;
;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to deal
;; in the Software without restriction, including without limitation the rights
;; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;; copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:
;;
;; The above copyright notice and this permission notice shall be included in
;; all copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
;; THE SOFTWARE.

;; :usage
;; (require "xl-repl")
;; M-x start-repl

(provide "xl-repl")


(in-package :editor)
(export '(start-repl lisp-repl-mode))

(in-package :lisp)
(eval-when (:compile-toplevel :load-toplevel :execute)
  (export '(** *** // /// ++ +++)))

(defpackage :repl
  (:use :lisp :editor))

(in-package :repl)
(export '(*buffer-name*
	  *keymap*
	  *prompt*
	  *prompt-style*
	  *error-style*
	  *startup-hook*))

(defvar *buffer-name* "*REPL*")
(defvar *prompt* "%p>")
(defvar *prompt-style* '(:foreground 12 :bold t))
(defvar *error-style* '(:foreground 1))
(defvar *startup-hook* nil)
(defvar *startup-package* "user")
(defvar *commands* nil)

(defparameter *keymap* (copy-keymap ed::*lisp-mode-map*))
(define-key *keymap* #\RET 'newline-or-eval-input)
(define-key *keymap* '(#\C-c #\C-l) 'clear-buffer)
(define-key *keymap* #\C-h 'repl-backward-delete-char)
(define-key *keymap* #\Delete 'repl-delete-char-or-selection)
(define-key *keymap* #\C-d 'repl-delete-char-or-selection)
(define-key *keymap* #\C-l 'clear-repl)

(defvar-local *input-history* nil)

;;; utilities
(defmacro iflet (var test then else)
  `(let ((,var ,test)) (if ,var ,then ,else)))

(defmacro whenlet (var test &body body)
  `(let ((,var ,test)) (when ,var ,@body)))

(defmacro whilet (var test &body body)
  `(do ((,var ,test ,test)) ((not ,var) nil) ,@body))

(defmacro nth-value (n form)
  `(nth ,n (multiple-value-list ,form)))

(defun read-all-from-string (str)
  (let ((forms nil)
	(eos '#:eos))
    (with-input-from-string (is str)
      (do ((s #0=(read is nil eos) #0#))
	  ((eq s eos) (nreverse forms))
	(push s forms)))))


(defun format-prompt ()
  (with-output-to-string (os)
    (with-input-from-string (is *prompt*)
      (whilet c (read-char is nil nil)
	(princ
	 (if (char= c #\%)
	     (let ((post (read-char is nil nil)))
	       (if (null post) c
		 (case (char-downcase post)
		   (#\p *buffer-package*)
		   (#\d (default-directory))
		   (#\u (user-name))
		   (#\m (machine-name))
		   (#\o (os-platform))
		   (#\v (software-version))
		   (#\n (software-type))
		   (t post))))
	   c) os)))))

(defun show-prompt (&optional default)
  (goto-char (point-max))
  (unless (bolp) (insert "\n") (forward-char))
  (let ((p (point)))
    (insert (format-prompt) #\SPC)
    (apply #'set-text-attribute p (point-max) 'prompt *prompt-style*)
    #0=(goto-char (point-max))
    (when default (insert default))
    #0#))

(defmacro previous-prompt-point ()
  `(find-text-attribute 'prompt :end (point) :from-end t))

(defmacro next-prompt-point ()
  `(find-text-attribute 'prompt :start (point)))

(defun repl-backward-delete-char (&optional (n 1))
  (interactive "p")
  (let ((p (point)))
    (multiple-value-bind (from to) (previous-prompt-point)
      (if (<= from p (1- to))
	  (goto-char to)
	(backward-delete-char-untabify-or-selection (min n (- p to)))))))

(defun repl-delete-char-or-selection (&optional (n 1))
  (interactive "p")
  (let ((p (point)))
    (multiple-value-bind (from to) (previous-prompt-point)
      (unless (<= from p (1- to))
	(delete-char-or-selection n)))))


(defun get-input ()
  (multiple-value-bind (from to) (previous-prompt-point)
    (save-excursion
      (goto-eol)
      (buffer-substring to (point)))))

(defun input-complete-p ()
  (save-excursion
    (let ((from (nth-value 1 (previous-prompt-point))))
      (goto-eol)
      (while (and (>= (point) from)
		  (ignore-errors (backward-sexp)))
	(skip-chars-backward " \t\n"))
      (<= (point) from))))

(defun eval-and-print (input)
  (let ((*package* (or (find-package *buffer-package*)
		       (find-package "user"))))
    (handler-case
	(let ((forms (read-all-from-string input)))
	  (with-output-to-buffer ((selected-buffer) (point-max))
	    (iflet com (and (keywordp (car forms)) (getf *commands* (car forms)))
	      (apply com (cdr forms))
	      (dolist (expr forms)
		(setq - expr)
		(let ((results (save-excursion
				 (multiple-value-list (eval expr)))))
		  (setq *** ** ** * * (car results)
			+++ ++ ++ + + expr
			/// // // / / (if (cdr results) results *)
			*buffer-package* (package-name *package*))
		  (format t "~{~S~^ ;~%~}~%~%" results))))))
      (error (c)
	(let ((start (point-max)))
	  (with-output-to-buffer ((selected-buffer) start)
	    (format t "~A~%~%" (si:*condition-string c)))
	  (apply #'set-text-attribute start (- (point-max) 2) 'error
		 *error-style*))))))

(defun newline-or-eval-input ()
  (interactive)
  (if (input-complete-p)
      (let ((input (get-input)))
	(if (next-prompt-point)
	    (show-prompt input)
	  (goto-eol))
	(newline)
	(eval-and-print input)
	(show-prompt))
    (lisp-newline-and-indent)))

(defun clear-repl ()
  (interactive)
  (delete-region (point-min) (point-max))
  (show-prompt))


;;; repl command
(defmacro define-repl-command (name args &body body)
  (let ((kw (intern (string name) :keyword)))
    `(progn
       (setf (getf *commands* ,kw) (lambda ,args ,@body))
       ,kw)))

(define-repl-command require (name)
  (let ((*load-path* (cons (default-directory) *load-path*)))
    (eval-and-print (format nil "(require \"~A\")" name))))

(define-repl-command load (name)
  (let ((*load-path* (cons (default-directory) *load-path*)))
    (eval-and-print (format nil "(load-library \"~A\")" name))))

(define-repl-command dir (&optional wild)
  (let* ((dir (default-directory))
	 (files (directory dir :wild (or wild "*"))))
    (format t "[~A]~%~{~A~%~}~%" dir files)))

(define-repl-command cd (dir)
  (let ((path (merge-pathnames dir (default-directory))))
    (set-default-directory dir)
    (format t "[~A]~%~%" path)))

(define-repl-command mkpkg (name &rest options)
  (let ((pkg (find-package name)))
    (when pkg
      (format t "~S already exists.~%~%" pkg))
    (let ((p (or pkg (apply #'make-package name options))))
      (in-package p)
      (setq *buffer-package* (package-name p))
      (format t "~S~%~%" p))))

(define-repl-command rmpkg (name)
  (when (string-match "lisp\\|ed\\|editor\\|user\\|repl" (string name))
    (error "don't delete package: ~A" name))
  (format t "~S~%~%" (delete-package name))
  (setq *buffer-package* (package-name *package*)))


;;; major mode
(defun ed::lisp-repl-mode ()
  (interactive)
  (lisp-mode)
  (setq buffer-mode 'ed::lisp-repl-mode
	mode-name "REPL")
  (use-keymap *keymap*)
  (unless (file-visited-p)
    (make-local-variable 'need-not-save)
    (make-local-variable 'auto-save)
    (setq need-not-save t
	  auto-save nil))
  (mapc #'make-local-variable '(* ** *** / // /// + ++ +++ -))
  (setq *buffer-package* *startup-package*)
  (set-buffer-fold-type-window)
  (run-hooks '*startup-hook*))


;;; launcher
(defun ed::start-repl ()
  (interactive)
  (let ((buf (get-buffer-create *buffer-name*)))
    (set-buffer buf)
    (when (eq buffer-mode 'ed::lisp-repl-mode)
      (return-from ed::start-repl))
    (ed::lisp-repl-mode)
    (insert ";;; xyzzy lisp REPL\n")
    (show-prompt)))


;;; for edit
(setf
 (get 'iflet #0='ed:lisp-indent-hook) 1
 (get 'whenlet #0#) 2
 (get 'whilet #0#) 2
 (get 'define-repl-command #0#) 2)
