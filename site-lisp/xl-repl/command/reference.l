;;; -*- mode:lisp; package:repl.command.reference -*-

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require "xl-repl/repl-mode"))

(defpackage :repl.command.reference
  (:use :lisp :editor :repl.util))

(in-package :repl.command.reference)

(export '(find-chapter
	  index
	  lookup
	  lookup-regexp
	  full-text-search))

(defvar *reference-directory* "~/reference")
(defvar *reference* nil)
(defvar *title-index* nil)
(defvar *loaded-references* nil)

(defconstant +msxml-domdoc-progid+ "Msxml2.DOMDocument.6.0")

;;; utilities
(defmacro $ (oleobj &rest chain)
  (flet ((mkform (obj arg)
	   (let ((a (if (listp arg) arg (list arg))))
	     `(ole-method ,obj ',(car a) ,@(cdr a)))))
    (reduce #'mkform chain :initial-value oleobj)))

(defun mapcol (func col)
  (let ((result nil))
    (ole-for-each (e col)
      (push (funcall func e) result))
    (nreverse result)))

;;; msxml
(defun create-ole-xmldoc ()
  (let ((xmldom (ole-create-object +msxml-domdoc-progid+)))
    (setf ($ xmldom validateOnParse) nil)
    ($ xmldom (setProperty "ProhibitDTD" nil))
    xmldom))

(defun load-xml (path)
  (let ((doc (create-ole-xmldoc)))
    (if ($ doc (load path))
	doc
      (let ((perr ($ doc parseError)))
	(error "~A~%ParseError at line ~D, column ~D~%~S~%~A"
	       path ($ perr line) ($ perr linepos)
	       ($ perr srcText) ($ perr reason))))))

(defun find-nodes (dom xpath)
  (delete #'null (mapcol #'dom->sexp ($ dom (selectNodes xpath)))))

(defun find-1node (dom xpath)
  (dom->sexp ($ dom (selectSingleNode xpath))))

(defun dom->sexp (dom)
  (case ($ dom NodeType)
    (1 (cons (intern ($ dom NodeName) "keyword")
	     (delete #'null (mapcol #'dom->sexp ($ dom ChildNodes)))))
    (2 (cons (intern ($ dom Name) "keyword") ($ dom Value)))
    ((3 4 6) ($ dom NodeValue))
    (9 (delete #'null (mapcol #'dom->sexp ($ dom ChildNodes))))
    (t nil)))


;;; load all reference files
(defun load-all-references (&optional reload)
  (when (and *reference* (typep *reference* 'oledata) (not reload))
    (return-from load-all-references))
  (let ((files (directory *reference-directory* :absolute t :wild "*.xml" :recursive t))
	(failed nil))
    (unless files
      (error "ファイルが見つかりません : ~A/*.xml" *reference-directory*))
    (setf *reference* (create-ole-xmldoc)
	  *title-index* nil
	  *loaded-references* nil
	  ($ *reference* documentElement) ($ *reference* (createElement "book")))
    (dolist (xml files)
      (handler-case (load-reference xml)
	(error (c) (push (si:*condition-string c) failed))))
    (if failed
	(message-box (format nil "以下のファイルはロードされませんでした。~{~%~A~}" failed)
		     "quick-reference")
      (message "load-all-references: done"))
    t))

(defun load-reference (xmlfile &aux (name (pathname-name xmlfile)))
  (when (find name *loaded-references* :test #'string=)
    (return-from load-reference))
  (unless (file-exist-p xmlfile)
    (error "ファイルが見つかりません : ~A" xmlfile))
  (let* ((root ($ *reference* documentElement))
	 (chapters ($ (load-xml xmlfile) (selectNodes "book/chapter")))
	 (count ($ chapters Length)))
    (when (> count 0)
      (ole-for-each (c chapters)
	(whenlet title ($ c (selectSingleNode "title"))
	  (push (cadr (dom->sexp title)) *title-index*))
	($ root (appendChild c)))
      (push name *loaded-references*)
      (message "~A : ~D chapters" name count))))

(defun index (&optional reload)
  (when (and (not reload) *title-index*)
    (return-from index *title-index*))
  (load-all-references t)
  *title-index*)


;;; exports
(defun find-chapter (&key title package section file type partial-match)
  (let ((xpath (format nil "/book/chapter~@?"
		       (if partial-match
			   "~{[contains(~A, '~A')]~}"
			 "~{[~A = '~A']~}")
		       (append (and title `(:title ,title))
			       (and package `(:package ,package))
			       (and section `(:section ,section))
			       (and file `(:file ,file))
			       (and type `(:type ,type))))))
    (mapcar #'cdr (find-nodes *reference* xpath))))

(defun lookup (title &key partial-match)
  (load-all-references)
  (find-chapter :title title :partial-match partial-match))

(defun lookup-regexp (regexp)
  (load-all-references)
  (accum a
    (dolist (title *title-index*)
      (when (string-match regexp title)
	(mapc #'a (lookup title))))))

(defun full-text-search (word)
  (load-all-references)
  (let ((xpath (format nil "/book/chapter[contains(., '~A')]" word)))
    (mapcar #'cdr (find-nodes *reference* xpath))))


;;; repl command
(defun repl.command::reference (word &rest options)
  "リファレンスを検索して表示します。
    ; [オプション]
    ; :part - 部分一致検索
    ; :regexp - 正規表現検索
    ; :fts  - 本文を含めた全文検索"
  (setq word (format nil "~A" word))
  (let ((refs (cond ((find :fts options)
		     (full-text-search (format nil "~A" word)))
		    ((find :regexp options)
		     (lookup-regexp word))
		    ((find :part options)
		     (lookup word :partial-match t))
		    (t (lookup word)))))
    (unless refs
      (error "見つかりません : ~S" word))
    (defer
      (let ((buf (get-buffer-create "*reference*"))
	    (wc (current-window-configuration))
	    (km (make-keymap)))
	(erase-buffer buf)
	(with-output-to-buffer (buf)
	  (dolist (ref refs)
	    (format t "~50@{=~}~%" t)
	    (dolist (k '(:title :package :file :section))
	      (format t "~{~10A:~^ ~A~}~%" (assoc k ref)))
	    (format t "~50@{-~}~A~%~%" (cadr (assoc :description ref)))))
	(flet ((quit-refe ()
		 (interactive)
		 (delete-buffer buf)
		 (set-window-configuration wc)))
	  (define-key km #\q #'quit-refe)
	  (pop-to-buffer buf t t)
	  (kill-all-local-variables)
	  (make-local-variable 'keyword-hash-table)
	  (setq keyword-hash-table (or ed::*lisp-keyword-hash-table*
				       (load-keyword-file "lisp")))
	  (use-syntax-table ed::*lisp-mode-syntax-table*)
	  (use-keymap km))))))


(provide "xl-repl/command/reference")
