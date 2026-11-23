#!r6rs
;; Every import a suite may have: (rnrs ...), (srfi :64), (srfi :19), the
;; library, and the libraries under tests/, through wrappers.
(import (rnrs)
        (srfi :64)
        (only (srfi :19) current-time)
        (only (unique-id) f)
        (prefix (unique-id-testing) t:)
        (rename (rnrs lists) (filter keep)))
(display (f (t:g 1)))
