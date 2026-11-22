#!r6rs
;;; make check-imports: (unique-id-checks)'s import-complaints on each tree
;;; under tools/fixtures/imports/, then tools/check-imports.sps run as a
;;; child, for its output and its exit status.
;;;
;;; Each tree breaks some rules, or none, and the assertions name every
;;; (path rule) pair complained of, in order, so a check that complained of
;;; the wrong file or rule, or of too much, fails as surely as one that said
;;; nothing. `legal` holds every wrapper an import spec may use, so a check
;;; that refused one of them fails there.
(import (rnrs)
        (srfi :64)
        (unique-id-testing)
        (unique-id-checks))

(define runner (test-runner-simple))
(test-runner-current runner)

(define dir "tools/fixtures/imports/")

;; complained : String -> (U (Listof (List String Symbol)) (List 'raised String))
;; Each (path rule) the tree NAME is complained of, in order, or what
;; checking it raised.
(define (complained name)
  (guard (e (#t (list 'raised (describe e))))
    (map (lambda (c) (list (car c) (cadr c)))
         (import-complaints (string-append dir name)))))

(test-begin "check-imports")

;; --- the rules --------------------------------------------------------------

(test-equal "legal: (rnrs ...) and (unique-id ...) through every wrapper, and (srfi :19) in (unique-id system)"
  '() (complained "legal"))

(test-equal "legal: all three libraries are counted"
  '("unique-id.sls" "unique-id/private.sls" "unique-id/system.sls")
  (guard (e (#t (list 'raised (describe e))))
    (library-files (string-append dir "legal"))))

(test-equal "chezscheme: a plain (chezscheme) import"
  '(("unique-id.sls" import)) (complained "chezscheme"))

(test-equal "wrapped: only, for, library, prefix-rename-except, and an unreadable spec"
  '(("unique-id.sls" import) ("unique-id.sls" import) ("unique-id.sls" import)
    ("unique-id.sls" import) ("unique-id.sls" import))
  (complained "wrapped"))

(test-equal "wrapped: each import complaint names what it found"
  '("it imports (chezscheme); a library under src/ imports only (rnrs ...) and (unique-id ...), and (unique-id system) (srfi :19) too"
    "it imports (srfi :1); a library under src/ imports only (rnrs ...) and (unique-id ...), and (unique-id system) (srfi :19) too"
    "it imports (chezscheme); a library under src/ imports only (rnrs ...) and (unique-id ...), and (unique-id system) (srfi :19) too"
    "it imports (chezscheme); a library under src/ imports only (rnrs ...) and (unique-id ...), and (unique-id system) (srfi :19) too"
    "it cannot read the import spec (only)")
  (guard (e (#t (list 'raised (describe e))))
    (map caddr (import-complaints (string-append dir "wrapped")))))

(test-equal "srfi: (srfi :19) outside (unique-id system); another SRFI, and (srfi :19 time), inside it"
  '(("unique-id.sls" import) ("unique-id/system.sls" import) ("unique-id/system.sls" import))
  (complained "srfi"))

(test-equal "srfi: each import complaint names what it found"
  '("it imports (srfi :19), which only (unique-id system) may import"
    "it imports (srfi :1); a library under src/ imports only (rnrs ...) and (unique-id ...), and (unique-id system) (srfi :19) too"
    "it imports (srfi :19 time); a library under src/ imports only (rnrs ...) and (unique-id ...), and (unique-id system) (srfi :19) too")
  (guard (e (#t (list 'raised (describe e))))
    (map caddr (import-complaints (string-append dir "srfi")))))

(test-equal "elsewhere: a (unique-id ...) import no file under the root holds"
  '(("unique-id.sls" import)) (complained "elsewhere"))

(test-equal "eval: (rnrs eval), plainly and through only with a version"
  '(("unique-id.sls" import) ("unique-id.sls" import)) (complained "eval"))

(test-equal "lookalikes: (unique-id-testing) and (rnrs-extra) are neither"
  '(("unique-id.sls" import) ("unique-id.sls" import)) (complained "lookalikes"))

(test-equal "the details of a missing (unique-id ...) library and of (rnrs eval)"
  '("it imports (unique-id chez), which no file under src/ holds"
    "it imports (rnrs eval), whose environment reaches any library at run time"
    "it imports (rnrs eval (6)), whose environment reaches any library at run time")
  (guard (e (#t (list 'raised (describe e))))
    (map caddr (append (import-complaints (string-append dir "elsewhere"))
                       (import-complaints (string-append dir "eval"))))))

(test-equal "header-missing: no #!r6rs line"
  '(("unique-id.sls" header)) (complained "header-missing"))

(test-equal "header-later: #!r6rs on the second line is no header, and a #! after the first"
  '(("unique-id.sls" header) ("unique-id.sls" hash-bang)) (complained "header-later"))

(test-equal "header-tail: a first line that only starts with #!r6rs is no header"
  '(("unique-id.sls" header)) (complained "header-tail"))

(test-equal "midline: #! in the middle of a later line"
  '(("unique-id.sls" hash-bang)) (complained "midline"))

(test-equal "hash-bang: #!chezscheme inside the library"
  '(("unique-id.sls" hash-bang)) (complained "hash-bang"))

(test-equal "file-names: a README, STEM.chezscheme.sls, STEM.guile.sls and STEM.ss"
  '(("README" file-name) ("private.chezscheme.sls" file-name) ("private.guile.sls" file-name)
    ("private.ss" file-name))
  (complained "file-names"))

(test-equal "litter: dot files, a lock link, an #autosave# and a backup~ are passed over, a dot directory is not"
  '((".config/x.ss" file-name))
  (complained "litter"))

(test-equal "litter: none of it counts as a library"
  '("unique-id.sls")
  (guard (e (#t (list 'raised (describe e))))
    (library-files (string-append dir "litter"))))

(test-equal "names: a version on the name, and a name its path does not give"
  '(("unique-id.sls" name) ("unique-id/foo.sls" name)) (complained "names"))

(test-equal "names: each name complaint says which it is"
  '("its name (unique-id (1 0)) carries a version; name it (unique-id)"
    "it declares (unique-id bar), but its path makes it (unique-id foo)")
  (guard (e (#t (list 'raised (describe e))))
    (map caddr (import-complaints (string-append dir "names")))))

(test-equal "forms: no library, no datum, two libraries, export after import, exports"
  '(("a.sls" library-form) ("b.sls" library-form) ("c.sls" library-form)
    ("d.sls" library-form) ("e.sls" library-form))
  (complained "forms"))

(test-equal "unreadable: bytes that are no UTF-8, and an unclosed form"
  '(("bad-utf8.sls" unreadable) ("unique-id.sls" unreadable)) (complained "unreadable"))

(test-equal "no-library: a tree with no file named as a library"
  '(("notes.txt" file-name) ("." no-library)) (complained "no-library"))

(test-equal "link: a link is not followed, and leaves no library"
  '(("unique-id.sls" not-regular) ("." no-library)) (complained "link"))

(test-equal "a file given as the root is no directory"
  '(("." not-a-directory)) (complained "legal/unique-id.sls"))

(test-equal "a missing root is no directory"
  '(("." not-a-directory)) (complained "no-such-tree"))

;; --- the program ------------------------------------------------------------

(define (check . args)
  (guard (e (#t (list 'raised (describe e))))
    (run-check "tools/check-imports.sps" args)))

(test-equal "check-imports.sps: exit 0 and a count when every library is plain"
  '(0 "check-imports: every library under tools/fixtures/imports/legal is plain R6RS and imports only what it may (3 checked)\n" "")
  (check (string-append dir "legal")))

(test-equal "check-imports.sps: exit 1 and one line per complaint, the root's own by its name"
  '(1 ""
    "check-imports: tools/fixtures/imports/no-library/notes.txt: a file under src/ is named STEM.sls, with no other dot\ncheck-imports: tools/fixtures/imports/no-library: it holds no file named as a library\n")
  (check (string-append dir "no-library")))

(test-equal "check-imports.sps: no directory named is a usage error, exit 2"
  '(2 "" "usage: check-imports.sps DIR\n")
  (check))

(test-equal "check-imports.sps: two directories named is a usage error, exit 2"
  '(2 "" "usage: check-imports.sps DIR\n")
  (check (string-append dir "legal") (string-append dir "chezscheme")))

(test-end "check-imports")

(exit (suite-exit-status runner))
