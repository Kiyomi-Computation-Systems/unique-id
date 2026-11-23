#!r6rs
;;; Pure contracts for the documentation-site generator. This runs without
;;; chez-cmark-gfm, so it keeps page naming, anchor generation and link
;;; rewriting portable.
(import (rnrs) (srfi :64) (unique-id-testing) (site pages) (site slug)
        (site links))

(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "site-unit")

(test-equal "README.md writes as the home page" "index.html"
  (page-file-name "README.md"))
(test-equal "other Markdown files write beside it as HTML" "reference.html"
  (page-file-name "reference.md"))
(test-equal "a hyphenated name keeps its hyphens" "getting-started.html"
  (page-file-name "getting-started.md"))
(test-equal "the nav names every page, in order, with its label"
  '(("README.md"          . "Home")
    ("getting-started.md" . "Getting started")
    ("quickstart.md"      . "Quickstart")
    ("ids.md"             . "Ids")
    ("generators.md"      . "Generators")
    ("system.md"          . "The system library")
    ("hashing.md"         . "Hash tables")
    ("errors.md"          . "Errors")
    ("reference.md"       . "API reference"))
  pages)

(test-equal "heading anchors follow GitHub's lower-case spelling"
  "lambda-forms" (slugify "Lambda forms"))
(test-equal "heading anchors drop punctuation and keep hyphens"
  "uuid-v7-ids" (slugify "UUID v7 ids?"))
(test-equal "a repeated heading is numbered from 1, as GitHub does"
  '("errors" "errors-1" "errors-2")
  (let* ((slug (make-slugger))
         (a (slug "Errors"))
         (b (slug "Errors"))
         (c (slug "Errors")))
    (list a b c)))

(test-equal "a ../ link points at this repository, at the ref"
  "https://github.com/Kiyomi-Computation-Systems/unique-id/blob/"
  repo-blob)

;; The rewriting of one link: the body is `a` with an href, the registry
;; knows two pages, and the answer is the rewritten body and the dangling
;; links.
(define registry
  '(("README.md" "home")
    ("reference.md" "reference" "entries")))

(define (rewrite target)
  (let-values (((out dangling)
                (rewrite-links `(p (a (^ (href ,target)) "x"))
                               registry "README.md" "v1.2.3")))
    (list out dangling)))

(test-equal "a ../ link becomes the repository's blob URL at the ref"
  '((p (a (^ (href "https://github.com/Kiyomi-Computation-Systems/unique-id/blob/v1.2.3/README.org")) "x"))
    ())
  (rewrite "../README.org"))
(test-equal "a page link becomes its HTML file"
  '((p (a (^ (href "reference.html#entries")) "x")) ())
  (rewrite "reference.md#entries"))
(test-equal "a link to the home page becomes index.html"
  '((p (a (^ (href "index.html")) "x")) ())
  (rewrite "README.md"))
(test-equal "a link to a page that does not exist dangles"
  '((p (a (^ (href "nope.html")) "x")) (("README.md" . "nope.md")))
  (rewrite "nope.md"))
(test-equal "a link to an anchor that does not exist dangles"
  '((p (a (^ (href "reference.html#nope")) "x"))
    (("README.md" . "reference.md#nope")))
  (rewrite "reference.md#nope"))
(test-equal "an absolute URL passes through"
  '((p (a (^ (href "https://example.org/a.md")) "x")) ())
  (rewrite "https://example.org/a.md"))

(test-end "site-unit")

(exit (suite-exit-status runner))
