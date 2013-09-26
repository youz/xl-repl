;;; -*- mode:lisp; package:repl -*-

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require "xl-repl/package")
  (require "xl-repl/util"))

(in-package :editor)
(export '(start-repl lisp-repl-mode))

(in-package :repl)
(export '(*buffer-name*
	  *greeting*
	  *keymap*
	  *prompt*
	  *prompt-style*
	  *stdout-style*
	  *values-style*
	  *error-style*
	  *startup-hook*
	  *return-behavior*))

(defvar *buffer-name* "*repl*")
(defvar *greeting* ";;; xyzzy lisp REPL")
(defvar *prompt* "%p>")
(defvar *prompt-style* '(:foreground 12 :bold t))
(defvar *stdout-style* '(:foreground 11))
(defvar *values-style* '(:foreground 4))
(defvar *error-style* '(:foreground 1))
(defvar *startup-hook* nil)
(defvar *startup-package* "user")
(defvar *return-behavior* :send-if-complete
  "Return押下時の挙動
* :send-if-complete - カーソルが式の途中にあっても式が完成していれば実行
* :send-only-if-after-complete - カーソルが式の後ろにある場合のみ実行")

(defvar *keymap* (copy-keymap ed::*lisp-mode-map*))
(define-key *keymap* #\RET 'newline-or-eval-input)
(define-key *keymap* #\LFD 'lisp-newline-and-indent)
(define-key *keymap* #\C-h 'repl-backward-delete-char)
(define-key *keymap* #\Delete 'repl-delete-char-or-selection)
(define-key *keymap* #\C-d 'repl-delete-char-or-selection)
(define-key *keymap* #\C-a 'repl-goto-bol)
(define-key *keymap* #\Home 'repl-goto-bol)
(define-key *keymap* #\C-l 'clear-repl)
(define-key *keymap* #\M-C-a 'beginning-of-input)
(define-key *keymap* #\M-C-e 'end-of-input)
(define-key *keymap* #\M-n 'next-input)
(define-key *keymap* #\M-p 'previous-input)
(define-key *keymap* '(#\C-c #\C-u) 'kill-current-input)
(define-key *keymap* '(#\C-c #\C-n) 'goto-next-prompt)
(define-key *keymap* '(#\C-c #\C-p) 'goto-previous-prompt)

(defvar-local *input-history* nil)
(defvar-local *input-history-index* nil)


(defun format-prompt ()
  (with-output-to-string (os)
    (with-input-from-string (is *prompt*)
      (whilet c (read-char is nil nil)
	(princ
	 (if (char= c #\%)
	     (let ((post (read-char is nil nil)))
	       (if (null post) c
		 (case (char-downcase post)
		   (#\P *buffer-package*)
		   (#\p (package-minimum-name *buffer-package*))
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

(defmacro previous-prompt-point (&optional p)
  `(find-text-attribute 'prompt :end ,(or p '(point)) :from-end t))

(defmacro next-prompt-point (&optional p)
  `(find-text-attribute 'prompt :start ,(or p '(point))))

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

(defun repl-goto-bol ()
  (interactive)
  (goto-bol)
  (multiple-value-bind (from to tag) (find-text-attribute-point (point))
    (when (eql tag 'prompt)
      (goto-char to))))

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

(defun kill-current-input ()
  (interactive)
  (whenlet p (and (not (next-prompt-point))
		  (nth-value 1 (previous-prompt-point)))
    (kill-region p (point-max))))

(defun beginning-of-input ()
  (interactive)
  (whenlet p (nth-value 1 (previous-prompt-point))
    (goto-char p)))

(defun end-of-input ()
  (interactive)
  (goto-char (or (next-prompt-point) (point-max))))

(defun goto-previous-prompt ()
  (interactive "p")
  (whenlet c (previous-prompt-point)
    (whenlet p (nth-value 1 (previous-prompt-point c))
      (goto-char p))))

(defun goto-next-prompt ()
  (interactive)
  (whenlet n (nth-value 1 (next-prompt-point))
    (goto-char n)))


(defun get-input ()
  (multiple-value-bind (from to) (previous-prompt-point)
    (when to
      (iflet np (next-prompt-point)
	(let ((p (find-text-attribute-if
		  (lambda (tag) (find tag '(stdout cmdout values error)))
		  :start to :end np)))
	  (buffer-substring to (1- (or p np))))
	(buffer-substring to (point-max))))))

(defun copy-to-last-input (str &optional append)
  (goto-char (point-max))
  (let ((pp (nth-value 1 (previous-prompt-point))))
    (if  append
	(when (< pp (point))
	  (insert #\SPC))
      (delete-region (nth-value 1 (previous-prompt-point)) (point-max)))
    (insert str)))

(defun input-complete-p ()
  (save-excursion
    (unless (eq *return-behavior* :send-only-if-after-complete)
      (goto-char (point-max)))
    (let ((start (nth-value 1 (previous-prompt-point))))
      (while (and (> (point) start)
		  (ignore-errors (backward-sexp)))
	(skip-chars-backward " \t\n"))
      (<= (point) start))))

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
  (iflet redirect (position :> args)
    (set (nth (1+ redirect) args) (apply com (subseq args 0 redirect)))
    (apply com args)))

(defun eval-and-print (input &optional do-not-record)
  (let ((*package* (or (find-package *buffer-package*) (find-package "user")))
	(*standard-input* ed:*cooked-mode-input-stream*)
	(*standard-output* *standard-output*)
	(*error-output* *error-output*)
	(estr nil)
	(*print-circle* t)
	(replbuf (selected-buffer)))
    (when si:*trace-on-error*
      (setq estr (make-string-output-stream)
	    *error-output* (make-broadcast-stream *error-output* estr)))
    (unless do-not-record
      (save-input-history input))
    (handler-case
	(let ((forms (read-all-from-string input)))
	  (iflet com (repl-command-p (car forms))
	    (with-print-to-buffer (replbuf :tag 'cmdout)
	      (invoke-repl-command com (cdr forms)))
	    (dolist (expr forms)
	      (save-excursion (set-buffer replbuf) (setq - expr))
	      (let ((results (with-print-to-buffer (replbuf :tag 'stdout :style *stdout-style*)
			       (multiple-value-list (eval expr)))))
		(save-excursion
		  (set-buffer replbuf)
		  (setq *** ** ** * * (car results) +++ ++ ++ + + expr
			/// // // / / results
			*buffer-package* (or (package-name *package*) "user"))
		  (with-print-to-buffer (replbuf :tag 'values :style *values-style*)
		    (while results
		      (let ((v (pop results)))
			(format t "~&~:[~S~;~A~]~@[ ;~]"
				(and (si:*structurep v)
				     (si:*structure-definition-print-function
				      (si:*structure-definition v)))
				v results)))))))))
      ((or error quit) (c)
       (with-print-to-buffer (replbuf :tag 'error :style *error-style*)
	 (if si:*trace-on-error*
	     (let ((lines (nreverse (split-string (get-output-stream-string estr) #\LFD))))
	       (format t "~{~A~%~}~A~%~%"
		       (nreverse (member-if (lambda (l) (string-match "^>CALL STACK +[0-9]+: (eval " l)) lines))
		       (car lines)))
	   (format t "~A~%~%" (si:*condition-string c))))))))


(defun newline-or-eval-input ()
  (interactive)
  (multiple-value-bind (from to tag)
      (find-text-attribute-point (point))
    (cond ((find tag '(stdout cmdout prompt error)) nil)
	  ((eql tag 'values)
	   (goto-eol)
	   (backward-sexp)
	   (let ((val (buffer-substring (point) (progn (forward-sexp) (point)))))
	     (copy-to-last-input val t)))
	  ((null tag)
	   (iflet input (get-input)
	     (cond ((next-prompt-point)
		    (copy-to-last-input input t))
		   ((input-complete-p)
		    (let ((buf (selected-buffer)))
		      (goto-char (point-max))
		      (newline)
		      (eval-and-print input)
		      (if (eq buf (selected-buffer))
			  #1=(show-prompt)
			(save-excursion (set-buffer buf) #1#))))
		   (t (lisp-newline-and-indent)))
	     (clear-repl))))))

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


(provide "xl-repl/repl-mode")
