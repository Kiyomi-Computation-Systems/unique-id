#!r6rs
;; Every wrapper an import spec may use, around (rnrs ...) and (unique-id ...).
(library (unique-id)
  (export f)
  (import (rnrs)
          (rnrs base (6))
          (only (rnrs lists) filter)
          (except (rnrs) cdr)
          (prefix (unique-id private) p:)
          (rename (rnrs) (car first))
          (for (rnrs syntax-case) expand)
          (for (only (unique-id private) helper) run expand)
          (library (rnrs control)))
  (define (f x) (p:helper x)))
