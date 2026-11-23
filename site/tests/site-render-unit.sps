#!r6rs
;;; The Markdown-to-document pipeline. It needs chez-cmark-gfm and is run by
;;; `make check-site`, separately from the portable generator suite.
(import (rnrs) (srfi :64) (unique-id-testing)
        (site render) (site serializer))

;; page-html : SiteResult String -> String
;; The HTML of the page NAME.
(define (page-html result name)
  (sxml->html
   (cond ((assoc name (site-result-pages result)) => cdr)
         (else (assertion-violation 'site-render-unit "missing page" name)))))

;; contains? : String String -> Boolean
;; Whether TEXT holds NEEDLE.
(define (contains? text needle)
  (let ((text-length (string-length text)) (needle-length (string-length needle)))
    (let loop ((at 0))
      (cond ((> (+ at needle-length) text-length) #f)
            ((string=? needle (substring text at (+ at needle-length))) #t)
            (else (loop (+ at 1)))))))

;; hrefs : String -> (Listof String)
;; The value of every href attribute in HTML, in document order.
(define (hrefs html)
  (let ((marker "href=\"") (len (string-length html)))
    (let loop ((at 0) (out '()))
      (cond ((> (+ at 6) len) (reverse out))
            ((string=? marker (substring html at (+ at 6)))
             (let find ((end (+ at 6)))
               (if (char=? (string-ref html end) #\")
                   (loop end (cons (substring html (+ at 6) end) out))
                   (find (+ end 1)))))
            (else (loop (+ at 1) out))))))

;; spans : String String String -> (Listof String)
;; Every piece of HTML that starts at PREFIX and ends with the next CLOSE,
;; both included, in document order.
(define (spans html prefix close)
  (let ((len (string-length html)) (n (string-length prefix)) (m (string-length close)))
    (let loop ((at 0) (out '()))
      (cond ((> (+ at n) len) (reverse out))
            ((string=? prefix (substring html at (+ at n)))
             (let find ((end (+ at n)))
               (cond ((> (+ end m) len) (reverse out))
                     ((string=? close (substring html end (+ end m)))
                      (loop (+ end m) (cons (substring html at (+ end m)) out)))
                     (else (find (+ end 1))))))
            (else (loop (+ at 1) out))))))

(define result
  (render-site
   '(("README.md" . "# Home\n\nSee [the reference](reference.md#entries) and [the readme](../README.org).\n")
     ("reference.md" . "# Reference\n\n## Entries\n\nText.\n"))
   "main"))

(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "site-render-unit")

(test-equal "one output page is produced for each input in order"
  '("README.md" "reference.md")
  (map car (site-result-pages result)))
(test-equal "every heading, including h1, enters the anchor registry"
  '("reference" "entries")
  (cond ((assoc "reference.md" (site-result-registry result)) => cdr)
        (else 'missing)))
(test-equal "a valid cross-page Markdown anchor does not leak"
  '() (site-result-leaked result))
(test-equal "every link of the home page, in order"
  '("style.css"
    "https://github.com/Kiyomi-Computation-Systems/unique-id"
    "index.html"
    "getting-started.html" "quickstart.html" "ids.html" "generators.html"
    "system.html" "hashing.html" "errors.html" "reference.html"
    "reference.html#entries"
    "https://github.com/Kiyomi-Computation-Systems/unique-id/blob/main/README.org")
  (hrefs (page-html result "README.md")))
(test-equal "../README.org renders as unique-id's blob URL"
  "https://github.com/Kiyomi-Computation-Systems/unique-id/blob/main/README.org"
  (let ((all (hrefs (page-html result "README.md"))))
    (list-ref all (- (length all) 1))))
(test-eq "the home page does not appear in its own side navigation" 'absent
  (if (contains? (page-html result "README.md") ">Home</a>") 'present 'absent))

(test-equal "a link to a missing page leaks, with its page and target"
  '(("README.md" . "nope.md"))
  (site-result-leaked
   (render-site '(("README.md" . "# Home\n\n[x](nope.md)\n")) "main")))
(test-equal "a ../ link is pinned to the ref the site is built at"
  "https://github.com/Kiyomi-Computation-Systems/unique-id/blob/v0.1.0/README.org"
  (let ((all (hrefs (page-html
                     (render-site '(("README.md" . "# Home\n\n[x](../README.org)\n")) "v0.1.0")
                     "README.md"))))
    (list-ref all (- (length all) 1))))

(test-equal "the home page's description meta tag"
  '("<meta name=\"description\" content=\"UUIDs, versions 4 and 7, for R6RS Scheme\">")
  (spans (page-html result "README.md") "<meta name=\"description\"" ">"))
(test-equal "the home page's keywords meta tag"
  '("<meta name=\"keywords\" content=\"uuid uuidv7 rfc9562 scheme r6rs\">")
  (spans (page-html result "README.md") "<meta name=\"keywords\"" ">"))
(test-equal "the home page's wordmark links home and reads unique-id"
  '("<a class=\"mark\" href=\"index.html\">unique-id</a>")
  (spans (page-html result "README.md") "<a class=\"mark\"" "</a>"))

(test-end "site-render-unit")

(exit (suite-exit-status runner))
