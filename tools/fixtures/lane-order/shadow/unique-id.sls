#!r6rs
;;; A stand-in (unique-id) for make check-lane-order. It exports nothing the
;;; probe uses, so the probe cannot be expanded where this library wins.
(library (unique-id)
  (export shadow-marker)
  (import (rnrs))

  ;; shadow-marker : Symbol
  ;; The one name this stand-in exports.
  (define shadow-marker 'shadow))
