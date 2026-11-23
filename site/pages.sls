#!r6rs
;; PURE. Imports no library that loads a shared object.
(library (site pages)
  (export pages page-file-name)
  (import (rnrs))

  ;; Page is (Pair String String): a Markdown file's name in docs/, and the
  ;; label the navigation and the page's title show for it.

  ;; pages : (Listof Page)
  ;; The navigation's single source of order and labels. The site check holds
  ;; this file set against docs/*.md.
  (define pages
    '(("README.md"          . "Home")
      ("getting-started.md" . "Getting started")
      ("quickstart.md"      . "Quickstart")
      ("ids.md"             . "Ids")
      ("generators.md"      . "Generators")
      ("system.md"          . "The system library")
      ("hashing.md"         . "Hash tables")
      ("errors.md"          . "Errors")
      ("reference.md"       . "API reference")))

  ;; page-file-name : String -> String
  ;; README.md is the site's home page, index.html; every other Markdown
  ;; source becomes an adjacent HTML file.
  (define (page-file-name name)
    (if (string=? name "README.md")
        "index.html"
        (string-append (substring name 0 (- (string-length name) 3)) ".html"))))
