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
	  *stdout-style*
	  *values-style*
	  *error-style*
	  *startup-hook*))

(defvar *buffer-name* "*repl*")
(defvar *greeting* ";;; xyzzy lisp REPL")
(defvar *prompt* "%p>")
(defvar *prompt-style* '(:foreground 12 :bold t))
(defvar *stdout-style* '(:foreground 11))
(defvar *values-style* '(:foreground 4))
(defvar *error-style* '(:foreground 1))
(defvar *startup-hook* nil)
(defvar *startup-package* "user")
(defvar *locked-packages* '(:system :lisp :editor :user :repl :repl.command))

(defparameter *keymap* (copy-keymap ed::*lisp-mode-map*))
(define-key *keymap* #\RET 'newline-or-eval-input)
(define-key *keymap* #\LFD 'lisp-newline-and-indent)
(define-key *keymap* #\C-h 'repl-backward-delete-char)
(define-key *keymap* #\Delete 'repl-delete-char-or-selection)
(define-key *keymap* #\C-d 'repl-delete-char-or-selection)
(define-key *keymap* #\C-l 'clear-repl)
(define-key *keymap* #\M-C-a 'beginning-of-input)
(define-key *keymap* #\M-C-e 'end-of-input)
(define-key *keymap* #\C-p 'previous-input)
(define-key *keymap* #\C-n 'next-input)

(defvar-local *input-history* nil)
(defvar-local *input-history-index* nil)


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

(defun clear-repl ()
  (interactive)
  (delete-region (point-min) (point-max))
  (insert *greeting* #\LFD)
  (show-prompt))

(defun clear-current-input ()
  (interactive)
  (let ((p (nth-value 1 (previous-prompt-point))))
    (if (or (not p) (next-prompt-point))
	(show-prompt)
      (delete-region p (point-max)))))


(defun beginning-of-input ()
  (interactive)
  (whenlet p (nth-value 1 (previous-prompt-point))
    (goto-char p)))

(defun end-of-input ()
  (interactive)
  (goto-char (or (next-prompt-point) (point-max))))

(defun get-input ()
  (save-excursion
    (multiple-value-bind (from to tag)
	(find-text-attribute-point (point))
      (cond ((find tag '(stdout prompt)) nil)
	    ((eq tag 'values)
	     (goto-eol)
	     (backward-sexp)
	     (let ((p (point)))
	       (forward-sexp)
	       (buffer-substring p (point))))
	    ((null tag)
	     (multiple-value-bind (from to) (previous-prompt-point)
	       (iflet np (next-prompt-point)
		 (let ((outp (find-text-attribute 'stdout :start to :end np))
		       (valp (find-text-attribute 'values :start to :end np)))
		   (buffer-substring to (1- (or outp valp np))))
		 (buffer-substring to (point-max)))))))))

(defun input-complete-p ()
  (save-excursion
    (goto-char (nth-value 1 (previous-prompt-point)))
    (let ((pmax (point-max)))
      (while (and (< (point) pmax)
		  (ignore-errors (forward-sexp)))
	(skip-chars-backward " \t\n"))
      (eq (point) pmax))))

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

(defun invoke-repl-command (com args)
  (let ((out (member-if #'(lambda (s) (and (symbolp s) (string= (symbol-name s) ">")))
			args)))
    (if out
	(let ((args (subseq args 0 (position '> args :test #'string=))))
	  (set (cadr out) #0=(apply com args)))
      #0#)))

(defun eval-and-print (input &optional do-not-record)
  (let ((*package* (or (find-package *buffer-package*) (find-package "user")))
	(*standard-input* ed:*cooked-mode-input-stream*)
	(*standard-output* *standard-output*)
	(*error-output* (if si:*trace-on-error* (make-string-output-stream) *error-output*))
	(*print-circle* t)
	(replbuf (selected-buffer)))
    (unless do-not-record
      (save-input-history input))
    (handler-case
	(let ((forms (read-all-from-string input))
	      (stdout-start (point-max)))
	  (with-output-to-buffer (replbuf stdout-start)
	    (iflet com (repl-command-p (car forms))
	      (progn
		(invoke-repl-command com (cdr forms))
		(format t "~&~%"))
	      (dolist (expr forms)
		(save-excursion (set-buffer replbuf) (setq - expr))
		(let ((results (multiple-value-list (eval expr))))
		  (save-excursion
		    (set-buffer replbuf)
		    (when (> (point-max) stdout-start)
		      (apply #'set-text-attribute stdout-start (point-max)
			     'stdout *stdout-style*))
		    (setq *** ** ** * * (car results) +++ ++ ++ + + expr
			  /// // // / / results
			  *buffer-package* (or (package-name *package*) "user"))
		    (let ((values-start (point-max)))
		      (while results
			(let ((v (pop results)))
			  (format t "~&~:[~S~;~A~]~@[ ;~]"
				  (and (si:*structurep v)
				       (si:*structure-definition-print-function
					(si:*structure-definition v)))
				  v results)))
		      (terpri)
		      (apply #'set-text-attribute values-start (point-max)
			     'values *values-style*))))))))
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
  (cond ((next-prompt-point)
	 (whenlet input (get-input)
	   (goto-char (point-max))
	   (delete-region (nth-value 1 (previous-prompt-point))
			  (point-max))
	   (insert input)))
	((input-complete-p)
	 (let ((buf (selected-buffer))
	       (input (get-input)))
	   (goto-char (point-max))
	   (newline)
	   (eval-and-print input)
	   (if (eq buf (selected-buffer))
	       #0=(show-prompt)
	     (save-excursion (set-buffer buf) #0#))))
	(t (lisp-newline-and-indent))))


;;; input history
(defun save-input-history (input)
  (when (or (null *input-history*)
	    (string/= input (nth *input-history-index* *input-history*)))
    (push input *input-history*)
    (setq *input-history-index* 0)))

(defun previous-input ()
  (interactive)
  (when *input-history*
    (when (find *last-command* '(previous-input next-input))
      (setq *input-history-index* (mod (1+ *input-history-index*) (length *input-history*))))
    (clear-current-input)
    (insert (nth *input-history-index* *input-history*))))

(defun next-input ()
  (interactive)
  (when *input-history*
    (when (find *last-command* '(previous-input next-input))
      (setq *input-history-index* (mod (1- *input-history-index*) (length *input-history*))))
    (clear-current-input)
    (insert (nth *input-history-index* *input-history*))))


;;; repl command
(defun repl.command::require (name)
  "*load-path*にdefault-directoryを含めて(require 'name)を評価"
  (let ((*load-path* (cons (default-directory) *load-path*)))
    (princ (require name))))

(defun repl.command::load (name)
  "*load-path*にdefault-directoryを含めて(load-library 'name)を評価"
  (let ((*load-path* (cons (default-directory) *load-path*)))
    (princ (load-library name))))

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

(defun list-symbols (pkg &key pattern (external t) (internal t))
  (let ((syms nil))
    (with-package-iterator (iter (or pkg (list-all-packages)) :external :internal)
      (loop
	(multiple-value-bind (f sym stype spkg) (iter)
	  (unless f (return))
	  (when (and (or (null pkg) (eq spkg pkg))
		     (or (boundp sym) (fboundp sym))
		     (or (and external (eq stype :external))
			 (and internal (eq stype :internal)))
		     (or (null pattern) (string-match (string pattern) (symbol-name sym))))
	    (push sym syms)))))
    (sort syms #'string< :key #'symbol-name)))

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

;; utility
(defun repl.command::time (form)
  "formを評価し、実行時間(秒)を表示"
  (let ((start (get-internal-real-time)))
    (eval-and-print (write-to-string form) t)
    (buffer-stream-set-point *standard-output* (point-max))
    (format t "~&----------~%~,3F sec.~%"
	    (/ (- (get-internal-real-time) start) 1000))))

(defun indent-hook (sym)
  (let ((i (get sym 'ed::lisp-indent-hook))
	(m (macro-function sym)))
    (cond ((eq i 'defun) 2)
	  (i i)
	  (m (position '&body (cadr m))))))

(defun prettify-region (from to)
  (interactive)
  (save-restriction
    (narrow-to-region from to)
    (goto-char from)
    (while (scan-buffer "(\\(\\_s+\\) " :regexp t)
      (unless (parse-point-syntax)
	(forward-char)
	(whenlet i (indent-hook (read-from-string (match-string 1)))
	  (forward-sexp i)
	  (save-excursion
	    (while (ignore-errors (forward-sexp))
	      (when (char/= (char-after (point)) #\))
		(insert #\LFD)))))))
    (goto-char (point-min))
    (while (scan-buffer "))+" :tail t :regexp t)
      (unless (or (parse-point-syntax) (char= (char-after (point)) #\LFD))
	(insert #\LFD)))
    (indent-region (point-min) (point-max))))

(defun repl.command::expand (form)
  "formをmacroexpandして表示"
  (let ((start (point)))
    (format t "~S" (macroexpand form))
    (prettify-region start (point-max))))

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

(defun show-package-description (pkgname)
  (whenlet pkg (find-package pkgname)
    (let ((name (package-name pkgname))
	  (nicknames (package-nicknames pkg))
	  (use-list (mapcar #'package-name (package-use-list pkg)))
	  (used-by (mapcar #'package-name (package-used-by-list pkg)))
	  (shadows (package-shadowing-symbols pkg))
	  (exports (list-symbols pkg :external t :internal nil)))
      (format t "<Package> ~A~%" name)
      (format t "~@[Nicknames: ~{~A~^, ~}~%~]" nicknames)
      (format t "~@[Use-list: ~{~A~^, ~}~%~]" use-list)
      (format t "~@[Used-by-list: ~{~A~^, ~}~%~]" used-by)
      (format t "~@[Shadows: ~{~A~^, ~}~%~]" shadows)
      (format t "~@[Exports: ~{~A~^, ~}~%~]" exports))
    (terpri)))

(defun show-function-description (funcsym &optional (detail t))
  (whenlet fun (and (fboundp funcsym) (symbol-function funcsym))
    (let* ((pkg (symbol-package funcsym))
	   (name (symbol-name funcsym))
	   (external? (eq :external (nth-value 1 (find-symbol name pkg))))
	   (builtin? (si:*builtin-function-p fun))
	   (macro? (macro-function funcsym))
	   (doc (or (documentation funcsym 'function) "not documented"))
	   (arg (cond (builtin? (get funcsym 'si::builtin-function-argument))
		      ((or macro? (and (listp fun) (eq (car fun) 'lambda)))
		       (cadr fun))
		      ((si:*closurep fun) (cadr (si:closure-body fun)))
		      (t nil))))
      (format t "~@[<~A> ~]~A:~:[:~;~]~A ~A~%~@[  ; ~A~%~]"
	      (when detail
		(cond ((special-form-p funcsym) "Special Operator")
		      (macro? "Macro")
		      (builtin? "Builtin Function")
		      ((commandp funcsym) "Command Function")
		      (t  "Function")))
	      (package-name pkg) external? name (or arg "()")
	      (when detail (substitute-string doc "\n" "\n    ;"))))))

(defun show-variable-description (varsym &optional (detail t))
  (when (boundp varsym)
    (let* ((pkg (symbol-package varsym))
	   (name (symbol-name varsym))
	   (external? (eq :external (nth-value 1 (find-symbol name pkg))))
	   (doc (or (documentation varsym 'variable) "not documented"))
	   (type (if (constantp varsym) "Constant" "Special")))
      (format t "~@[<~A Variable> ~]~A:~:[:~;~]~A~%~@[  ; ~A~%~]"
	      (when detail type) (package-name pkg) external? name
	      (when detail doc)))))

(defun repl.command::describe (#0=symbol-or-package-name)
  "パッケージ/変数/定数/関数の説明を表示"
  (show-package-description #0#)
  (when (and (symbolp #0#) (not (keywordp #0#)))
    (show-function-description #0#)
    (show-variable-description #0#)))


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
  (goto-char (point-max))
  (insert *greeting* #\LFD)
  (show-prompt)
  (run-hooks '*startup-hook*))


;;; launcher
(defun ed::start-repl (&optional alt)
  (interactive "p")
  (let* ((name (if alt (read-string "REPL Buffer Name: " :default *buffer-name*)
		 *buffer-name*))
	 (buf (get-buffer-create name)))
    (set-buffer buf)
    (when (eq buffer-mode 'ed::lisp-repl-mode)
      (return-from ed::start-repl))
    (ed::lisp-repl-mode)))


;;; for edit
(setf
 (get 'iflet #0='ed:lisp-indent-hook) 1
 (get 'whenlet #0#) 2
 (get 'whilet #0#) 2)
