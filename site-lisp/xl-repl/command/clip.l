(defpackage repl.command.clip
  (:use :lisp :editor :repl))

(in-package :repl.command.clip)

(defmacro clip-stdout (form)
  `(let* ((#0=#:ostr (make-string-output-stream))
	  (#1=*standard-output* (make-broadcast-stream #1# #0#)))
     (let ((results (multiple-value-list ,form)))
       (copy-to-clipboard (get-output-stream-string #0#))
       (values-list results))))

(defun repl.command::clip (form)
  "formを評価し、*standard-output*への出力をクリップボードへコピー"
  (repl::eval-and-print (write-to-string `(clip-stdout ,form))))

