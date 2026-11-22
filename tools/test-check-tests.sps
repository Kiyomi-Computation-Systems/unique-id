#!r6rs
;;; make check-tests: (unique-id-checks)'s suite-tree-complaints on each
;;; fixture under tools/fixtures/suite-trees/, each a tests/ tree and, where
;;; it needs one, a src/ tree, then tools/check-tests.sps run as a child, for
;;; its output and its exit status.
;;;
;;; The assertions name every (path rule) pair complained of, in order, so a
;;; check that complained of the wrong file or rule, or of too much, fails as
;;; surely as one that said nothing. `legal` holds every kind of import a
;;; suite may have, so a check that refused one of them fails there.
(import (rnrs)
        (srfi :64)
        (unique-id-testing)
        (unique-id-checks))

(define runner (test-runner-simple))
(test-runner-current runner)

(define dir "tools/fixtures/suite-trees/")

(define (tests-of name) (string-append dir name "/tests"))
(define (src-of name) (string-append dir name "/src"))

;; complaints : String -> (U (Listof Complaint) (List 'raised String))
;; What suite-tree-complaints answers for the fixture NAME, or what it raised.
(define (complaints name)
  (guard (e (#t (list 'raised (describe e))))
    (suite-tree-complaints (tests-of name) (src-of name))))

;; complained : String -> (U (Listof (List String Symbol)) (List 'raised String))
;; Each (path rule) the fixture NAME is complained of, in order.
(define (complained name)
  (guard (e (#t (list 'raised (describe e))))
    (map (lambda (c) (list (car c) (cadr c))) (complaints name))))

(define not-allowed
  "; a file under tests/ imports only (rnrs ...), (srfi :64), (unique-id ...) and the libraries under tests/")

(test-begin "check-tests")

;; --- the rules --------------------------------------------------------------

(test-equal "legal: (rnrs ...), (srfi :64), the library and tests/' own, through wrappers"
  '() (complained "legal"))

(test-equal "legal: the library and the suite are both counted"
  '("test-a.sps" "unique-id-testing.sls")
  (guard (e (#t (list 'raised (describe e))))
    (suite-tree-files (tests-of "legal"))))

(test-equal "names: STEM.guile.sls, STEM.chezscheme.sls, STEM.ss, other dots and a (unique-id) library"
  '(("helper.chezscheme.sls" file-name) ("notes.txt" file-name) ("test-a.guile.sps" file-name)
    ("unique-id-testing.guile.sls" file-name) ("unique-id.sls" shadow) ("x.ss" file-name))
  (complained "names"))

(test-equal "names: the shadow complaint names the library"
  "its path names it (unique-id); a (unique-id ...) library belongs under src/"
  (guard (e (#t (list 'raised (describe e))))
    (let ((found (filter (lambda (c) (eq? (cadr c) 'shadow)) (complaints "names"))))
      (if (= (length found) 1) (caddr (car found)) (list 'found found)))))

(test-equal "imports: another SRFI, Chez, a missing library, eval, the audits' library, SRFI-19"
  (list (list "test-a.sps" 'import (string-append "it imports (srfi :1)" not-allowed))
        (list "test-a.sps" 'import (string-append "it imports (chezscheme)" not-allowed))
        (list "test-a.sps" 'import "it imports (unique-id nope), which no file under src/ holds")
        (list "test-a.sps" 'import
              "it imports (rnrs eval), whose environment reaches any library at run time")
        (list "test-a.sps" 'import (string-append "it imports (unique-id-checks)" not-allowed))
        (list "test-a.sps" 'import (string-append "it imports (srfi :19)" not-allowed)))
  (complaints "imports"))

(test-equal "programs: a library's rules hold under tests/, and a program's own"
  '(("foo.sls" name) ("test-a.sps" program-form) ("test-b.sps" header) ("test-c.sps" hash-bang)
    ("test-d.sps" unreadable) ("test-e.sps" program-form))
  (complained "programs"))

(test-equal "no-src: with no src/ tree, (unique-id) is a missing library"
  '(("test-a.sps" import)) (complained "no-src"))

(test-equal "a missing tests tree is no directory"
  '(("." not-a-directory)) (complained "no-such-tree"))

;; --- the program ------------------------------------------------------------

(define (check . args)
  (guard (e (#t (list 'raised (describe e))))
    (run-check "tools/check-tests.sps" args)))

(test-equal "check-tests.sps: exit 0 and a count when every file is plain"
  '(0 "check-tests: every file under tools/fixtures/suite-trees/legal/tests is plain R6RS and imports only what it may (2 checked)\n" "")
  (check (tests-of "legal") (src-of "legal")))

(test-equal "check-tests.sps: exit 1 and one line per complaint, the root's own by its name"
  '(1 ""
    "check-tests: tools/fixtures/suite-trees/no-src/tests/test-a.sps: it imports (unique-id), which no file under src/ holds\n")
  (check (tests-of "no-src") (src-of "no-src")))

(test-equal "check-tests.sps: one directory named is a usage error, exit 2"
  '(2 "" "usage: check-tests.sps TESTS SRC\n")
  (check (tests-of "legal")))

(test-equal "check-tests.sps: three directories named is a usage error, exit 2"
  '(2 "" "usage: check-tests.sps TESTS SRC\n")
  (check (tests-of "legal") (src-of "legal") (src-of "legal")))

(test-end "check-tests")

(exit (suite-exit-status runner))
