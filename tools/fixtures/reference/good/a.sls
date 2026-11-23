#!r6rs
;;; (a): The first library,
;;; in two lines.
;;;
;;;   alpha  beta        two procedures
;;;   gamma              a value, which
;;;                      takes two lines
;;;
;;; A paragraph after
;;; the table.
(library (a)
  (export alpha beta gamma alp)
  (import (rnrs))

  ;; alpha : Nat Nat -> Nat
  ;; The sum of X and Y, which is
  ;; a Nat, and the first
  ;; paragraph spans three lines.
  ;;
  ;; A second paragraph, a note for whoever changes the code.
  (define (alpha x y) (+ x y))

;;; A section note at column 0, which is no part of the header.

  ;; beta : -> Boolean
  ;; Always true.
  (define (beta) #t)

  ;; gamma : Nat
  ;; The number seven.
  (define gamma 7)

  ;;; A note directly above a comment, which is no part of it.
  ;; alp : -> Nat
  ;; One; its name starts alpha's.
  (define (alp) 1))
