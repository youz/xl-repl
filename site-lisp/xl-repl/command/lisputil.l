;;; -*- mode:lisp; package:repl -*-

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require "xl-repl/repl-mode"))

(in-package :repl)

;; load系
(defun repl.command::require (name)
  "*load-path*にdefault-directoryを含めて(require 'name)を評価"
  (let ((*load-path* (cons (default-directory) *load-path*)))
    (princ (require name))))

(defun repl.command::load (name)
  "*load-path*にdefault-directoryを含めて(load-library 'name)を評価"
  (let ((*load-path* (cons (default-directory) *load-path*)))
    (princ (load-library name))))

;; package系
(defun repl.command::lspkg (&optional pattern)
  "パッケージ名を列挙"
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
  "(in-package 'name)を評価"
  (let ((pkg (in-package name)))
    (setq *buffer-package* (package-name pkg))
    (princ pkg)))

(defun repl.command::mkpkg (name &rest options)
  "(make-package 'name [options])を評価し、*package*を作成したパッケージに変更"
  (let ((pkg (find-package name)))
    (when pkg
      (format t "既存のパッケージです~%" pkg))
    (let ((p (or pkg (apply #'make-package name options))))
      (in-package p)
      (setq *buffer-package* (package-name p))
      (princ p))))

;; symbol検索
(defun repl.command::ls (&optional pat (pkg *package*))
  "パッケージ内の変数/定数/関数シンボルを列挙"
  (mapc #'(lambda (sym)
	    (show-variable-description sym nil)
	    (show-function-description sym nil))
	(list-symbols (find-package pkg) :pattern pat)))

(defun repl.command::lsext (&optional pattern (pkg *package*))
  "パッケージよりexportされている変数/定数/関数シンボルを列挙"
  (mapc #'(lambda (sym)
	    (show-variable-description sym nil)
	    (show-function-description sym nil))
	(list-symbols (find-package pkg) :pattern pattern :internal nil)))

(defun repl.command::lsall (&optional pattern)
  "全パッケージの変数/定数/関数シンボルを列挙"
  (mapc #'(lambda (sym)
	    (show-variable-description sym nil)
	    (show-function-description sym nil))
	(list-symbols nil :pattern pattern)))

;; misc
(defun repl.command::time (form)
  "formを評価し、実行時間(秒)を表示"
  (let ((start (get-internal-real-time)))
    (eval-and-print (write-to-string form) t)
    (buffer-stream-set-point *standard-output* (point-max))
    (format t "~&----------~%~,3F sec.~%"
	    (/ (- (get-internal-real-time) start) 1000))))

(defun repl.command::expand (form)
  "formをmacroexpandして表示"
  (let ((start (point)))
    (format t "~S" (macroexpand form))
    (prettify-region start (point-max))))


(provide "xl-repl/command/lisputil")
