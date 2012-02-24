;;; -*- mode:lisp; package:repl -*-

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require "xl-repl/repl-mode"))

(in-package :repl)

;; load�n
(defun repl.command::require (name)
  "*load-path*��default-directory���܂߂�(require 'name)��]��"
  (let ((*load-path* (cons (default-directory) *load-path*)))
    (princ (require name))))

(defun repl.command::load (name)
  "*load-path*��default-directory���܂߂�(load-library 'name)��]��"
  (let ((*load-path* (cons (default-directory) *load-path*)))
    (princ (load-library name))))

;; package�n
(defun repl.command::lspkg (&optional pattern)
  "�p�b�P�[�W�����"
  (let ((pkgs (mapcar #'(lambda (p) (cons (package-name p) (package-nicknames p)))
		      (list-all-packages))))
    (when pattern
      (let* ((pat (string pattern))
	     (pred (lambda (nm) (string-match pat nm))))
	(setq pkgs (delete-if-not (lambda (p) (some pred p)) pkgs))))
    (setq pkgs (sort pkgs #'string< :key #'car))
    (dolist (pkg pkgs pkgs)
      (format t "~A~@[  (~{~A~^ ~})~]~%" (car pkg) (cdr pkg)))))

(defun repl.command::package (name)
  "(in-package 'name)��]��"
  (let ((pkg (in-package name)))
    (setq *buffer-package* (package-name pkg))
    (princ pkg)))

(defun repl.command::mkpkg (name &rest options)
  "(make-package 'name [options])��]�����A*package*���쐬�����p�b�P�[�W�ɕύX"
  (let ((pkg (find-package name)))
    (when pkg
      (format t "�����̃p�b�P�[�W�ł�~%" pkg))
    (let ((p (or pkg (apply #'make-package name options))))
      (in-package p)
      (setq *buffer-package* (package-name p))
      (princ p))))

;; symbol����
(defun repl.command::ls (&optional pat (pkg *package*))
  "�p�b�P�[�W���̕ϐ�/�萔/�֐��V���{�����"
  (mapc #'(lambda (sym)
	    (show-variable-description sym nil)
	    (show-function-description sym nil))
	(list-symbols (find-package pkg) :pattern pat)))

(defun repl.command::lsext (&optional pattern (pkg *package*))
  "�p�b�P�[�W���export����Ă���ϐ�/�萔/�֐��V���{�����"
  (mapc #'(lambda (sym)
	    (show-variable-description sym nil)
	    (show-function-description sym nil))
	(list-symbols (find-package pkg) :pattern pattern :internal nil)))

(defun repl.command::lsall (&optional pattern)
  "�S�p�b�P�[�W�̕ϐ�/�萔/�֐��V���{�����"
  (mapc #'(lambda (sym)
	    (show-variable-description sym nil)
	    (show-function-description sym nil))
	(list-symbols nil :pattern pattern)))

;; misc
(defun repl.command::time (form)
  "form��]�����A���s����(�b)��\��"
  (let ((start (get-internal-real-time)))
    (eval-and-print (write-to-string form) t)
    (buffer-stream-set-point *standard-output* (point-max))
    (format t "~&----------~%~,3F sec.~%"
	    (/ (- (get-internal-real-time) start) 1000))))

(defun repl.command::expand (form)
  "form��macroexpand���ĕ\��"
  (let ((start (point)))
    (format t "~S" (macroexpand form))
    (prettify-region start (point-max))))


(provide "xl-repl/command/lisputil")