#!r6rs
;;; make reference's generator: (unique-id-reference) on each tree under
;;; tools/fixtures/reference/, then tools/reference.sps run as a child, for its
;;; output and its exit status, then the real page.
;;;
;;; Each tree is complained of, or turned into a page, and the assertions
;;; name the whole answer: every (path export rule) of a breach, in order,
;;; and every byte of a page, so a generator that read the wrong comment,
;;; dropped a paragraph or reordered an entry fails as surely as one that
;;; wrote nothing.
;;;
;;; The last tests read the real src/ and docs/reference.md: the page must be
;;; what the generator writes. This is the one suite that reads code comments,
;;; because that is what keeps the page from going stale.
(import (rnrs)
        (srfi :64)
        (unique-id-testing)
        (unique-id-checks)
        (unique-id-reference))

(define runner (test-runner-simple))
(test-runner-current runner)

(define dir "tools/fixtures/reference/")

;; slurp : String -> String
;; The UTF-8 text of the file at PATH.
(define (slurp path)
  (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                        (make-transcoder (utf-8-codec)))
    (lambda (p)
      (let ((s (get-string-all p)))
        (if (eof-object? s) "" s)))))

(define head-text (string-append "# Head\n\nFixture head.\n"))

;; breached : String -> (U (Listof (List String Symbol Symbol)) (List 'raised String))
;; What reference-breaches answers for the tree NAME, or what it raised.
(define (breached name)
  (guard (e (#t (list 'raised (describe e))))
    (reference-breaches (string-append dir name))))

;; page-of : String -> (U String (List 'raised String))
;; The page for the tree NAME under the fixture head, or what it raised.
(define (page-of name)
  (guard (e (#t (list 'raised (describe e))))
    (reference-page (string-append dir name) head-text)))

(define good-page
  (string-append
   "# Head\n\nFixture head.\n"
   "\n## (a)\n"
   "\nThe first library, in two lines.\n"
   "\nA paragraph after the table.\n"
   "\n### `alpha`\n"
   "\n```text\n(alpha x y)\nalpha : Nat Nat -> Nat\n```\n"
   "\nThe sum of X and Y, which is a Nat, and the first paragraph spans three lines.\n"
   "\n### `beta`\n"
   "\n```text\n(beta)\nbeta : -> Boolean\n```\n"
   "\nAlways true.\n"
   "\n### `gamma`\n"
   "\n```text\ngamma : Nat\n```\n"
   "\nThe number seven.\n"
   "\n### `alp`\n"
   "\n```text\n(alp)\nalp : -> Nat\n```\n"
   "\nOne; its name starts alpha's.\n"
   "\n## (a b)\n"
   "\nThe second library.\n"
   "\n### `delta`\n"
   "\n```text\n(delta first rest ...)\ndelta : Nat (Listof Nat) -> (Pair Nat (Listof Nat))\n```\n"
   "\nThe pair of FIRST and REST.\n"
   "\n### `eps`\n"
   "\n```text\n(eps all ...)\neps : (Listof Any) -> Nat\n```\n"
   "\nThe length of ALL.\n"))

(define order-page
  (string-append
   "# Head\n\nFixture head.\n"
   "\n## (o)\n"
   "\nExports listed in an order unlike their definitions.\n"
   "\n### `c`\n\n```text\nc : Nat\n```\n\nThe third defined.\n"
   "\n### `a`\n\n```text\na : Nat\n```\n\nThe first defined.\n"
   "\n### `b`\n\n```text\nb : Nat\n```\n\nThe second defined.\n"))

(test-begin "unique-id-reference")

;; --- the page ---------------------------------------------------------------

(test-equal "good: the whole page, two libraries in path order, every shape of entry"
  good-page (page-of "good"))

(test-equal "good: no breach"
  '() (breached "good"))

(test-equal "order: the page follows the export list, not the definitions"
  order-page (page-of "order"))

(test-equal "order: no breach"
  '() (breached "order"))

;; --- the breaches -----------------------------------------------------------

(test-equal "no-comment: an export with no comment, a ;;; note directly above it not being one"
  '(("x.sls" g no-comment)) (breached "no-comment"))

(test-equal "blank-gap: a blank line between the comment and the definition"
  '(("x.sls" f no-comment)) (breached "blank-gap"))

(test-equal "wrong-name: a signature that names another export"
  '(("x.sls" f signature)) (breached "wrong-name"))

(test-equal "no-colon: a first line with no colon"
  '(("x.sls" f signature)) (breached "no-colon"))

(test-equal "empty-type: a signature `f : ` with nothing after the colon"
  '(("x.sls" f signature)) (breached "empty-type"))

(test-equal "no-prose: a signature alone, and a signature then a blank line"
  '(("x.sls" f no-prose) ("x.sls" g no-prose)) (breached "no-prose"))

(test-equal "undefined: an export no definition holds, a comment alone not being one"
  '(("x.sls" f no-definition)) (breached "undefined"))

(test-equal "many: file order, then export-list order"
  '(("m.sls" q no-comment) ("m.sls" p no-comment) ("m/n.sls" s no-prose))
  (breached "many"))

(test-equal "a breach makes no page: reference-page raises"
  'raised
  (guard (e ((assertion-violation? e) 'raised))
    (reference-page (string-append dir "no-comment") head-text)))

(test-equal "breach-line: the path, the export and a sentence"
  "m.sls: q: its definition has no comment directly above it"
  (guard (e (#t (list 'raised (describe e))))
    (breach-line '("m.sls" q no-comment))))

;; --- the program ------------------------------------------------------------

(define (reference . args)
  (guard (e (#t (list 'raised (describe e))))
    (run-check "tools/reference.sps" args)))

(test-equal "reference.sps: exit 0, the page on stdout, nothing on stderr"
  (list 0 good-page "")
  (reference (string-append dir "good") (string-append dir "head.md")))

(test-equal "reference.sps: exit 1, nothing on stdout, a line for the breach on stderr"
  '(1 "" "x.sls: g: its definition has no comment directly above it\n")
  (reference (string-append dir "no-comment") (string-append dir "head.md")))

(test-equal "reference.sps: one line per breach, in order"
  '(1 ""
      "m.sls: q: its definition has no comment directly above it\nm.sls: p: its definition has no comment directly above it\nm/n.sls: s: its comment says nothing after the signature\n")
  (reference (string-append dir "many") (string-append dir "head.md")))

(test-equal "reference.sps: an export no definition holds"
  '(1 "" "x.sls: f: no top-level definition of it is found\n")
  (reference (string-append dir "undefined") (string-append dir "head.md")))

(test-equal "reference.sps: a signature that is not NAME : TYPE"
  '(1 "" "x.sls: f: the first line of its comment is not `f : TYPE`\n")
  (reference (string-append dir "no-colon") (string-append dir "head.md")))

(test-equal "reference.sps: an empty type"
  '(1 "" "x.sls: f: the first line of its comment is not `f : TYPE`\n")
  (reference (string-append dir "empty-type") (string-append dir "head.md")))

(test-equal "reference.sps: no arguments is a usage error, exit 2"
  '(2 "" "usage: reference.sps SRC-DIR HEAD-FILE\n")
  (reference))

(test-equal "reference.sps: one argument is a usage error, exit 2"
  '(2 "" "usage: reference.sps SRC-DIR HEAD-FILE\n")
  (reference (string-append dir "good")))

(test-equal "reference.sps: three arguments are a usage error, exit 2"
  '(2 "" "usage: reference.sps SRC-DIR HEAD-FILE\n")
  (reference (string-append dir "good") (string-append dir "head.md") "extra"))

;; --- the real thing ---------------------------------------------------------

(define (real-page)
  (reference "src" "tools/reference-head.md"))

(define (read-library-form path)
  (read (open-string-input-port (slurp path))))

;; library-forms : -> (Listof Sexp)
;; The library form of each file under src/, in the generator's order, read here.
(define (library-forms)
  (map (lambda (path) (read-library-form (string-append "src/" path)))
       (library-files "src")))

(define (lines-of text)
  (let loop ((chars (string->list text)) (line '()) (acc '()))
    (cond ((null? chars) (reverse (if (null? line) acc (cons (list->string (reverse line)) acc))))
          ((char=? (car chars) #\newline)
           (loop (cdr chars) '() (cons (list->string (reverse line)) acc)))
          (else (loop (cdr chars) (cons (car chars) line) acc)))))

(define (prefixed? prefix line)
  (and (>= (string-length line) (string-length prefix))
       (string=? prefix (substring line 0 (string-length prefix)))))

(test-equal "the real page: docs/reference.md is what reference.sps writes from src/"
  (let ((page (real-page)))
    (if (and (pair? page) (eqv? (car page) 0))
        (list 0 (cadr page) "")
        page))
  (guard (e (#t (list 'raised (describe e))))
    (list 0 (slurp "docs/reference.md") "")))

(test-equal "the real page: its library and export headings are src/'s, read as data"
  (apply append
         (map (lambda (form)
                (cons (string-append "## " (written (cadr form)))
                      (map (lambda (name) (string-append "### `" (symbol->string name) "`"))
                           (cdr (caddr form)))))
              (library-forms)))
  (guard (e (#t (list 'raised (describe e))))
    (let* ((head (slurp "tools/reference-head.md"))
           (page (slurp "docs/reference.md"))
           (rest (if (and (>= (string-length page) (string-length head))
                          (string=? head (substring page 0 (string-length head))))
                     (substring page (string-length head) (string-length page))
                     page)))
      (filter (lambda (line) (or (prefixed? "## " line) (prefixed? "### " line)))
              (lines-of rest)))))

(test-equal "the real page: 24 entries in all"
  24
  (guard (e (#t (list 'raised (describe e))))
    (length (filter (lambda (line) (prefixed? "### `" line))
                    (lines-of (slurp "docs/reference.md"))))))

(test-equal "the real page: it starts with the head"
  (guard (e (#t (list 'raised (describe e))))
    (slurp "tools/reference-head.md"))
  (guard (e (#t (list 'raised (describe e))))
    (let ((head (slurp "tools/reference-head.md"))
          (page (slurp "docs/reference.md")))
      (substring page 0 (min (string-length page) (string-length head))))))

(test-end "unique-id-reference")

(exit (suite-exit-status runner))
