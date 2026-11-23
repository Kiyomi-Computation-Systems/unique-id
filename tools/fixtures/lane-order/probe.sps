#!r6rs
;;; Exits 0 when (unique-id) is the library under src/. Where the stand-in
;;; under tools/fixtures/lane-order/shadow/ wins instead, uuid? and nil-uuid
;;; are unbound, and the Scheme refuses the program with a non-zero exit.
(import (rnrs) (unique-id))

(exit (if (uuid? nil-uuid) 0 1))
