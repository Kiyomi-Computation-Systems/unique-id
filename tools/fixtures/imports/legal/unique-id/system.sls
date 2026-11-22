#!r6rs
;; (unique-id system) alone may import (srfi :19), through any wrapper.
(library (unique-id system)
  (export now)
  (import (rnrs)
          (srfi :19)
          (only (srfi :19) current-time time-utc)
          (prefix (srfi :19) s19:))
  (define (now) (current-time time-utc)))
