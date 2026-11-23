#!r6rs
;;; Render the docs directory into static HTML. `make site` prepares its
;;; dependencies. SITE_DOCS names the docs directory, SITE_REF the ref that
;;; ../ links point at, and SITE_OUT the output directory.
(import (rnrs) (only (chezscheme) getenv) (site io) (site render))

(define ref (or (getenv "SITE_REF") "main"))
(define out (or (getenv "SITE_OUT") "build/site"))

(let ((result (render-site (read-site-inputs) ref)))
  (write-site result out)
  (display "site: wrote ") (display (length (site-result-pages result)))
  (display " pages to ") (display out) (newline))
