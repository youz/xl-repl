;;; -*- mode:lisp; package:user -*-

(in-package :lisp)
(eval-when (:compile-toplevel :load-toplevel :execute)
  (export '(** *** // /// ++ +++)))

(in-package :user)
(defpackage :repl.util
  (:use :lisp :editor))

(defpackage :repl
  (:use :lisp :editor :repl.util))

(defpackage :repl.command)
(eval-when (:compile-toplevel :load-toplevel :execute)
  (unuse-package :lisp :repl.command))

(provide "xl-repl/package")
