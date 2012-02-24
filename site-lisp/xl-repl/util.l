;;; -*- mode:lisp; packaeg:repl.util -*-

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require "xl-repl/package"))

(in-package :repl.util)
(export '(iflet whenlet whilet nth-value read-all-from-string
	  list-symbols
	  show-package-description
	  show-function-description
	  show-variable-description
	  prettify-region))


(defmacro iflet (var test then else)
  `(let ((,var ,test)) (if ,var ,then ,else)))

(defmacro whenlet (var test &body body)
  `(let ((,var ,test)) (when ,var ,@body)))

(defmacro whilet (var test &body body)
  `(do ((,var ,test ,test)) ((not ,var) nil) ,@body))

(setf (get 'iflet #0='ed:lisp-indent-hook) 1
      (get 'whenlet #0#) 2
      (get 'whilet #0#) 2)

(defmacro nth-value (n form)
  `(nth ,n (multiple-value-list ,form)))

(defun read-all-from-string (str)
  (let ((forms nil)
	(eos '#:eos))
    (with-input-from-string (is str)
      (do ((s #0=(read is nil eos) #0#))
	  ((eq s eos) (nreverse forms))
	(push s forms)))))

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


(defun indent-hook (sym)
  (when (symbolp sym)
    (let ((i (get sym 'ed::lisp-indent-hook))
	  (m (macro-function sym)))
      (cond ((numberp i) i)
	    ((and i (symbolp i))
	     (if (string= i "defun") 2 0))
	    (m (position '&body (cadr m)))))))

(defun prettify-region (from to)
  (interactive "r")
  (save-restriction
    (narrow-to-region from to)
    (goto-char from)
    (while (scan-buffer "(\\(\\_s+\\) " :regexp t)
      (forward-char)
      (unless (parse-point-syntax)
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


(provide "xl-repl/util")
