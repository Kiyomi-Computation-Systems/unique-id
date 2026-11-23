#!r6rs
;;; Runs site/tests/site-check.sps on each fixture docs tree, as a child
;;; process, and holds its whole outcome: the good tree passes with its one
;;; line, and each broken tree fails with its one complaint. A check deleted
;;; from site-check.sps makes one of these fail. It needs CHEZ and
;;; SITE_LIBDIRS in the environment, which the Makefile exports, and
;;; chez-cmark-gfm for the child.
(import (rnrs) (srfi :64) (unique-id-testing)
        (only (chezscheme) getenv system get-process-id mkdir))

(define fixtures "site/tests/fixtures/")
(define capture-dir "build/site-check-fixtures")

;; required-env : String -> String
;; The value of the environment variable NAME, else an assertion violation.
(define (required-env name)
  (let ((value (getenv name)))
    (unless (and value (positive? (string-length value)))
      (assertion-violation 'site-check-fixtures
        (string-append name " is not set: run the suite through make check-site")
        name))
    value))

;; shell-quote : String -> String
;; WORD single-quoted for a POSIX shell.
(define (shell-quote word)
  (string-append
   "'"
   (apply string-append
          (map (lambda (c) (if (char=? c #\') "'\\''" (string c)))
               (string->list word)))
   "'"))

;; slurp : String -> String
;; The whole text of the UTF-8 file at PATH, "" when it is empty.
(define (slurp path)
  (call-with-port
   (open-file-input-port path (file-options) (buffer-mode block)
                         (make-transcoder (utf-8-codec)))
   (lambda (port)
     (let ((text (get-string-all port)))
       (if (eof-object? text) "" text)))))

;; make-directory : String -> Void
;; Makes the directory PATH unless it exists.
(define (make-directory path)
  (unless (file-exists? path) (mkdir path)))

;; run-site-check : String -> (List Integer String String)
;; Runs site/tests/site-check.sps with SITE_DOCS the fixture tree TREE and
;; SITE_REF main, as `$CHEZ --libdirs $SITE_LIBDIRS --program`, with stdin
;; from /dev/null. The answer is the exit status, then what it wrote to
;; stdout and to stderr. The streams go through files under
;; build/site-check-fixtures/, named for this process and removed once read.
(define (run-site-check tree)
  (make-directory "build")
  (make-directory capture-dir)
  (let* ((stem (string-append capture-dir "/" (number->string (get-process-id))))
         (out (string-append stem ".out"))
         (err (string-append stem ".err"))
         (command
          (string-append
           "SITE_DOCS=" (shell-quote (string-append fixtures tree))
           " SITE_REF=main "
           (shell-quote (required-env "CHEZ"))
           " --libdirs " (shell-quote (required-env "SITE_LIBDIRS"))
           " --program site/tests/site-check.sps </dev/null >" (shell-quote out)
           " 2>" (shell-quote err)))
         (status (system command))
         (stdout (slurp out))
         (stderr (slurp err)))
    (for-each delete-file (list out err))
    (list status stdout stderr)))

(define blob "https://github.com/Kiyomi-Computation-Systems/unique-id/blob/main/")

;; failure : String -> (List Integer String String)
;; What a failing run is expected to answer: exit 1, nothing on stdout, and
;; the one line LINE on stderr.
(define (failure line) (list 1 "" (string-append line "\n")))

(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "site-check-fixtures")

(test-equal "the good tree passes with its one line"
  (list 0
        "check-site: page registry, anchors, Markdown links, ../ links, and output count -- all green\n"
        "")
  (run-site-check "docs"))
(test-equal "a page missing from disk fails"
  (failure (string-append
            "check-site: pages and " fixtures "broken-missing-page disagree; "
            "in pages.sls but not on disk=(errors.md) on disk but not in pages.sls=()"))
  (run-site-check "broken-missing-page"))
(test-equal "a page on disk that pages.sls lacks fails"
  (failure (string-append
            "check-site: pages and " fixtures "broken-extra-page disagree; "
            "in pages.sls but not on disk=() on disk but not in pages.sls=(notes.md)"))
  (run-site-check "broken-extra-page"))
(test-equal "a link to a missing page fails"
  (failure "check-site: unresolved documentation links: ((README.md . nope.md))")
  (run-site-check "broken-dangling-page"))
(test-equal "a link to a missing anchor fails"
  (failure "check-site: unresolved documentation links: ((README.md . reference.md#no-such-heading))")
  (run-site-check "broken-dangling-anchor"))
(test-equal "an inline ../ link to a missing file fails"
  (failure (string-append
            "check-site: README.md links to " blob "MISSING.org, which names no "
            "file relative to " fixtures "broken-up-link/.."))
  (run-site-check "broken-up-link"))
(test-equal "a reference-style ../ link to a missing file fails"
  (failure (string-append
            "check-site: ids.md links to " blob "NOPE.org, which names no "
            "file relative to " fixtures "broken-up-link-reference/.."))
  (run-site-check "broken-up-link-reference"))

(test-end "site-check-fixtures")

(exit (suite-exit-status runner))
