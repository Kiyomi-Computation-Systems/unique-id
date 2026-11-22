#!r6rs
;; In (unique-id system), (srfi :19) passes; another SRFI, and a library
;; inside (srfi :19 ...), do not.
(library (unique-id system)
  (export now)
  (import (rnrs) (srfi :19) (srfi :1) (only (srfi :19 time) current-time))
  (define (now) (current-time)))
