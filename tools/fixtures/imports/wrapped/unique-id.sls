#!r6rs
;; Each spec hides a library outside (rnrs ...) and (unique-id ...) in a wrapper.
(library (unique-id)
  (export f)
  (import (rnrs)
          (only (chezscheme) printf)
          (for (srfi :1) run)
          (library (chezscheme))
          (prefix (rename (except (chezscheme) sort) (list-sort ls)) c:)
          (only))
  (define (f x) x))
