;;; -*- mode:lisp; package:repl.command.reference -*-

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require "ole")
  (require "xl-repl/repl-mode"))

(defpackage :repl.command.reference
  (:use :lisp :editor :repl.util))

(in-package :repl.command.reference)

(export '(find-chapter
	  index
	  lookup
	  lookup-regexp
	  full-text-search
	  *reference-mode-map*))

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
  "OLE��Collection�̑S�v�f�ɑ΂���func��K�p���A���ʂ����X�g�ɂ��ĕԂ�"
  (let ((result nil))
    (ole-for-each (e col)
      (push (funcall func e) result))
    (nreverse result)))

;;; msxml
(defun create-ole-xmldoc ()
  "���DOMDocument�I�u�W�F�N�g�𐶐�����"
  (let ((xmldom (ole-create-object +msxml-domdoc-progid+)))
    (setf ($ xmldom validateOnParse) nil)
    ($ xmldom (setProperty "ProhibitDTD" nil))
    xmldom))

(defun load-xml (path)
  "DOMDocument�I�u�W�F�N�g�𐶐����A�w�肵��xml�t�@�C����ǂݍ���"
  (let ((doc (create-ole-xmldoc)))
    (if ($ doc (load path))
	doc
      (let ((perr ($ doc parseError)))
	(error "~A~%ParseError at line ~D, column ~D~%~S~%~A"
	       path ($ perr line) ($ perr linepos)
	       ($ perr srcText) ($ perr reason))))))

(defun find-nodes (dom xpath)
  "DOM�I�u�W�F�N�g����XPath�ɓK������S�m�[�h��lisp�f�[�^�ɂ��ĕԂ�"
  (delete #'null (mapcol #'dom->sexp ($ dom (selectNodes xpath)))))

(defun find-1node (dom xpath)
  "DOM�I�u�W�F�N�g����XPath�ɓK������ŏ��̃m�[�h��lisp�f�[�^�ɕϊ����ĕԂ�"
  (dom->sexp ($ dom (selectSingleNode xpath))))

(defun dom->sexp (dom)
  "DOM�I�u�W�F�N�g��lisp�f�[�^(�؍\�����X�g)�ɕϊ� (�Q�l: xhr::dom->sexp)"
  (case ($ dom NodeType)
    (1 (cons (intern ($ dom NodeName) "keyword")
	     (delete #'null (mapcol #'dom->sexp ($ dom ChildNodes)))))
    (2 (cons (intern ($ dom Name) "keyword") ($ dom Value)))
    ((3 4 6) ($ dom NodeValue))
    (9 (delete #'null (mapcol #'dom->sexp ($ dom ChildNodes))))
    (t nil)))


;;; load xml files
(defun load-all-references (&optional reload)
  "*reference-directory*���̑S�Ă�xml�t�@�C�������[�h���A�Schapter��
��������*reference*�ɁAchapter title�̃��X�g��*title-index*�Ɋi�["
  (when (and *reference* (typep *reference* 'oledata) (not reload))
    (return-from load-all-references))
  (let ((files (directory *reference-directory* :absolute t :wild "*.xml" :recursive t))
	(failed nil))
    (unless files
      (error "�t�@�C����������܂��� : ~A/*.xml" *reference-directory*))
    (setf *reference* (create-ole-xmldoc)
	  *title-index* nil
	  *loaded-references* nil
	  ($ *reference* documentElement) ($ *reference* (createElement "book")))
    (dolist (xml files)
      (handler-case (load-reference xml)
	(error (c) (push (si:*condition-string c) failed))))
    (if failed
	(message-box (format nil "�ȉ��̃t�@�C���̓��[�h����܂���ł����B~{~%~A~}" failed)
		     "quick-reference")
      (message "load-all-references: done"))
    t))

(defun load-reference (xmlfile &aux (name (pathname-name xmlfile)))
  "xyzzy���t�@�����X�`����XML�t�@�C�������[�h���đS�Ă�chapter�m�[�h��
*reference*�ɁAchapter title��*title-index*�ɒǉ�����"
  (when (find name *loaded-references* :test #'string=)
    (return-from load-reference))
  (unless (file-exist-p xmlfile)
    (error "�t�@�C����������܂��� : ~A" xmlfile))
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
  "�w���������XPath�𐶐�����*reference*��茟��"
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
  "chapter title�̊��S��v/������v����"
  (load-all-references)
  (find-chapter :title title :partial-match partial-match))

(defun lookup-regexp (regexp)
  "chapter title�̐��K�\��"
  (load-all-references)
  (accum a
    (dolist (title *title-index*)
      (when (string-match regexp title)
	(mapc #'a (lookup title))))))

(defun full-text-search (word)
  "�S������"
  (load-all-references)
  (let ((xpath (format nil "/book/chapter[contains(., '~A')]" word)))
    (mapcar #'cdr (find-nodes *reference* xpath))))


;;; reference mode
(defvar *reference-mode-map* nil)
(defvar *reference-history* nil)
(defvar *reference-history-index* nil)
(unless *reference-mode-map*
  (setq *reference-mode-map* (make-sparse-keymap))
  (define-key *reference-mode-map* #\j 'next-line)
  (define-key *reference-mode-map* #\k 'previous-line)
  (define-key *reference-mode-map* #\J 'next-chapter)
  (define-key *reference-mode-map* #\K 'previous-chapter)
  (define-key *reference-mode-map* #\RET 'jump)
  (define-key *reference-mode-map* #\C-h 'backward-history)
  (define-key *reference-mode-map* #\M-Left 'backward-history)
  (define-key *reference-mode-map* #\M-Right 'forward-history)
  (define-key *reference-mode-map* #\LBtnDown 'mouse-left-click))

(defun next-chapter ()
  (interactive)
  (when (scan-buffer "^=+$" :regexp t :no-dup t)
    (recenter 0)))

(defun previous-chapter ()
  (interactive)
  (when (scan-buffer "^=+$" :regexp t :no-dup t :reverse t)
    (recenter 0)))

(defun add-reference-history (word options)
  (let ((page (cons word options)))
    (cond ((null *reference-history*)
	   (setq *reference-history* (list page)
		 *reference-history-index* 0))
	  ((not (equal page (nth *reference-history-index* *reference-history*)))
	   (setq *reference-history* (cons page (nthcdr *reference-history-index* *reference-history*))
		 *reference-history-index* 0)))))

(defun forward-history ()
  (interactive)
  (when (> *reference-history-index* 0)
    (apply #'repl.command::reference
	   (nth (decf *reference-history-index*) *reference-history*))))

(defun backward-history ()
  (interactive)
  (when (< *reference-history-index* (1- (length *reference-history*)))
    (apply #'repl.command::reference
	   (nth (incf *reference-history-index*) *reference-history*))))

(defun mouse-left-click ()
  (interactive)
  (goto-last-mouse-point)
  (jump))

(defun jump ()
  (interactive)
  (multiple-value-bind (from to tag) (find-text-attribute-point (point))
    (if tag
	(repl.command::reference (cadr tag))
      (whenlet word (find (ed::get-winhelp-topic) *title-index* :test #'string-equal)
	(repl.command::reference word)))))

(defun print-reference (buf refs)
  (save-excursion
    (set-buffer buf)
    (setq buffer-read-only nil)
    (erase-buffer buf)
    (with-output-to-buffer (buf)
      (dolist (ref refs)
	(format t "~V@{=~}~%  ~A~%" (min 60 (window-columns))
		(cadr (assoc :title ref)))
	(dolist (k '(:type :arguments :package :file :section))
	  (whenlet v (assoc k ref)
	    (format t "~{~10A:~^ ~A~}~%" v)))
	(format t "~V@{-~}~A" (min 60 (window-columns))
		(cadr (assoc :description ref)))
	(whenlet seealso
	    (remove-if #'null (mapcar #'cadr (remove :seealso ref :test-not 'eq :key 'car)))
	  (dolist (w seealso)
	    (format t "~%seealso: ~A" w)
	    (let ((p (point-max)))
	      (set-text-attribute (- p (length w)) p `(:seealso ,w) :foreground 4))))
	(princ "\n\n")))))


;;; repl command
(defun repl.command::reference (word &rest options)
  "���t�@�����X��\��
    ; [�I�v�V����]
    ; :part - ������v����
    ; :regexp - ���K�\������
    ; :fts  - �{�����܂߂��S������"
  (setq word (format nil "~A" word))
  (let ((refs (cond ((find :fts options)
		     (full-text-search (format nil "~A" word)))
		    ((find :regexp options)
		     (lookup-regexp word))
		    ((find :part options)
		     (lookup word :partial-match t))
		    (t (lookup word)))))
    (unless refs
      (error "������܂��� : ~S" word))
    (add-reference-history word options)
    (defer
      (let ((buf (get-buffer-create "*reference*"))
	    (wc (current-window-configuration))
	    (km (copy-keymap *reference-mode-map*)))
	(print-reference buf refs)
	(flet ((quit-refe ()
		 (interactive)
		 (delete-buffer buf)
		 (set-window-configuration wc)))
	  (define-key km #\q #'quit-refe)
	  (pop-to-buffer buf t t)
	  (kill-all-local-variables)
	  (setq need-not-save t buffer-read-only t)
	  (make-local-variable 'keyword-hash-table)
	  (setq keyword-hash-table (or ed::*lisp-keyword-hash-table*
				       (load-keyword-file "lisp")))
	  (use-syntax-table ed::*lisp-mode-syntax-table*)
	  (use-keymap km))))))


(provide "xl-repl/command/reference")