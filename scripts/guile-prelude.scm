;;; Loaded by make before each suite it runs on Guile, as `guile -l`.
;;;
;;; A suite's (import (rnrs) ...) runs in Guile's guile-user module, where
;;; (rnrs)'s display, newline and the rest replace Guile's own core bindings,
;;; and Guile writes a warning for each to stderr. Without warn-override-core
;;; the imported binding still wins, as `last` picks it, and nothing is
;;; written. Without `warn`, as well, Guile says nothing when two imported
;;; libraries export one name, and takes the last; keeping `warn` would bring
;;; back the core warnings, which it writes too. Chez refuses such a clash
;;; outright, so the Chez lane still catches it.
(default-duplicate-binding-handler '(replace last))
