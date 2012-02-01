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

(defpackage :repl.command)
(eval-when (:compile-toplevel :load-toplevel :execute)
  (unuse-package :lisp :repl.command))

(in-package :repl)
(export '(*buffer-name*
	  *greeting*
	  *keymap*
	  *prompt*
	  *prompt-style*
	  *error-style*
	  *startup-hook*))

(defvar *buffer-name* "*REPL*")
(defvar *greeting* ";;; xyzzy lisp REPL")
(defvar *prompt* "%p>")
(defvar *prompt-style* '(:foreground 12 :bold t))
(defvar *error-style* '(:foreground 1))
(defvar *startup-hook* nil)
(defvar *startup-package* "user")
(defvar *locked-packages* '(:system :lisp :editor :user :repl :repl.command))

(defparameter *keymap* (copy-keymap ed::*lisp-mode-map*))
(define-key *keymap* #\RET 'newline-or-eval-input)
(define-key *keymap* #\C-h 'repl-backward-delete-char)
(define-key *keymap* #\Delete 'repl-delete-char-or-selection)
(define-key *keymap* #\C-d 'repl-delete-char-or-selection)
(define-key *keymap* #\C-l 'clear-repl)
(define-key *keymap* #\M-C-a 'beginning-of-input)
(define-key *keymap* #\M-C-e 'end-of-input)

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

(defun beginning-of-input ()
  (interactive)
  (whenlet p (nth-value 1 (previous-prompt-point))
    (goto-char p)))

(defun end-of-input ()
  (interactive)
  (goto-char (or (next-prompt-point) (point-max))))


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

(defun repl-command-p (x)
  (when (keywordp x)
    (iflet s (find-symbol (symbol-name x) :repl.command)
      (and (fboundp s) s)
      (let* ((syms nil)
	     (re (format nil "^~A" (symbol-name x))))
	(do-symbols (s :repl.command)
	  (when (and (string-match re (symbol-name s))
		     (fboundp s))
	    (push s syms)))
	(when (= (length syms) 1)
	  (car syms))))))

(defun eval-and-print (input)
  (let ((*package* (or (find-package *buffer-package*) (find-package "user")))
	(*standard-input* ed:*cooked-mode-input-stream*)
	(*error-output* (if si:*trace-on-error* (make-string-output-stream) *error-output*))
	(replbuf (selected-buffer)))
    (handler-case
	(let ((forms (read-all-from-string input)))
	  (with-output-to-buffer (replbuf (point-max))
	    (iflet com (repl-command-p (car forms))
	      (progn
		(apply com (cdr forms))
		(format t "~&~%"))
	      (dolist (expr forms)
		(save-excursion (set-buffer replbuf) (setq - expr))
		(let ((results (multiple-value-list (eval expr))))
		  (save-excursion
		    (set-buffer replbuf)
		    (setq *** ** ** * * (car results) +++ ++ ++ + + expr
			  /// // // / / (if (cdr results) results *)
			  *buffer-package* (package-name *package*))
		    (format t "~{~S~^ ;~%~}~%~%" results)))))))
      (error (c)
	(set-buffer replbuf)
	(let ((start (point-max)))
	  (with-output-to-buffer (replbuf start)
	    (if si:*trace-on-error*
		(let ((lines (nreverse (split-string (get-output-stream-string *error-output*) #\LFD))))
		  (format t "~{~A~%~}~A~%~%"
			  (nreverse (member-if (lambda (l) (string-match "^>CALL STACK +[0-9]+: (eval " l)) lines))
			  (car lines)))
	      (format t "~A~%~%" (si:*condition-string c))))
	  (apply #'set-text-attribute start (- (point-max) 2) 'error *error-style*))))))

(defun newline-or-eval-input ()
  (interactive)
  (if (input-complete-p)
      (let ((buf (selected-buffer))
	    (input (get-input)))
	(if (next-prompt-point)
	    (show-prompt input)
	  (goto-eol))
	(newline)
	(eval-and-print input)
	(if (eq buf (selected-buffer))
	    #0=(show-prompt)
	  (save-excursion (set-buffer buf) #0#)))
    (lisp-newline-and-indent)))

(defun clear-repl ()
  (interactive)
  (delete-region (point-min) (point-max))
  (insert *greeting* #\LFD)
  (show-prompt))


;;; repl command
(defun repl.command::require (name)
  "default-directoryを*load-path*に含めて(require 'name)を評価"
  (let ((*load-path* (cons (default-directory) *load-path*)))
    (princ (require name))))

(defun repl.command::load (name)
  "default-directoryを*load-path*に含めて(load-library 'name)を評価"
  (let ((*load-path* (cons (default-directory) *load-path*)))
    (princ (load-library name))))

(defun repl.command::dir (&optional wildcard)
  "default-directoryのファイルを列挙"
  (let* ((dir (default-directory))
	 (files (directory dir :wild (or wildcard "*"))))
    (format t "[~A]~%~{~A~%~}" dir files)))

(defun repl.command::cd (&optional dir)
  "default-directoryをdirへ移動 (dir省略時はdefault-directoryを表示)"
  (if dir
      (let ((path (merge-pathnames dir (default-directory))))
	(when (set-default-directory path)
	  (princ path)))
    (princ (default-directory))))

;; package系
(defun repl.command::lspkg (&optional pattern)
  "パッケージ名を列挙"
  (let ((pkgs (mapcar #'package-name (list-all-packages))))
    (when pattern
      (let ((re (string pattern)))
	(setq pkgs (remove-if-not #'(lambda (p) (string-match re p)) pkgs))))
    (format t "~{~A~%~}" (sort pkgs #'string<))))

(defun repl.command::package (name)
  "(in-package 'name)を評価"
  (let ((pkg (in-package name)))
    (princ pkg)
    (setq *buffer-package* (package-name pkg))))

(defun repl.command::mkpkg (name &rest options)
  "(defpackage 'name [options])を評価し、*package*を作成したパッケージに変更"
  (let ((pkg (find-package name)))
    (when pkg
      (format t "既存のパッケージです~%" pkg))
    (let ((p (or pkg (apply #'make-package name options))))
      (in-package p)
      (setq *buffer-package* (package-name p))
      (princ p))))

(defun repl.command::rmpkg (name)
  "(delete-apckage 'name)を評価"
  (let ((pkg (find-package name)))
    (unless pkg
      (error "パッケージが存在しません: ~S" name))
    (when (find (package-name pkg) *locked-packages* :test 'string=)
      (error "削除すべきではありません: ~S" pkg))
    (when (eq pkg *package*)
      (error "カレントパッケージです: ~S" pkg))
    (when (delete-package name)
      (format t "パッケージを削除しました: ~A" name))))

(defun list-symbols (pkg &optional pat)
  (let ((syms nil))
    (do-symbols (s pkg)
      (when (and (eq (symbol-package s) pkg)
		 (or (boundp s) (fboundp s))
		 (or (null pat) (string-match (string pat) (symbol-name s))))
	(push s syms)))
    (sort syms #'string< :key #'symbol-name)))

(defun repl.command::ls (&optional pat (pkg *package*))
  "パッケージ内の変数/定数/関数シンボルを列挙"
  (format t "~{~S~%~}" (list-symbols (find-package pkg) pat)))

;; help系
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


(defun show-function-document (funcsym)
  (whenlet fun (symbol-function funcsym)
    (let* ((pkg (symbol-package funcsym))
	   (name (symbol-name funcsym))
	   (exported? (eq :external (nth-value 1 (find-symbol name pkg))))
	   (builtin? (si:*builtin-function-p fun))
	   (macro? (not (null (macro-function funcsym))))
	   (doc (or (documentation funcsym 'function)
		    "not documented"))
	   (arg (cond (builtin? (get funcsym 'si::builtin-function-argument))
		      (macro? (cadr fun))
		      (t (cadr (si:closure-body fun))))))
      (format t "<~A> ~A:~:[:~;~]~A ~A~%~4T; ~A~%"
	      (cond ((special-form-p funcsym) "Special Operator")
		    ((macro-function funcsym) "Macro")
		    ((commandp funcsym) "Command Function")
		    (t (if builtin? "Builtin Function" "Function")))
	      (package-name pkg) exported? name (or arg "()")
	      (substitute-string doc "\n" "\n    ;")))))

(defun show-variable-document (varsym)
  (when (boundp varsym)
    (let* ((pkg (symbol-package varsym))
	   (name (symbol-name varsym))
	   (exported? (eq :external (nth-value 1 (find-symbol name pkg))))
	   (doc (or (documentation varsym 'variable)
		    "not documented"))
	   (const? (constantp varsym)))
      (format t "<~:[Special~;Constant~] Variable> ~A:~:[:~;~]~A~%~4T; ~A~%"
	      const? (package-name pkg) exported? name doc))))

(defun repl.command::desc (sym)
  "変数/定数/関数のdocstringを表示"
  (when (fboundp sym)
    (show-function-document sym))
  (when (boundp sym)
    (show-variable-document sym)))


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
    (clear-repl)))


;;; for edit
(setf
 (get 'iflet #0='ed:lisp-indent-hook) 1
 (get 'whenlet #0#) 2
 (get 'whilet #0#) 2)
