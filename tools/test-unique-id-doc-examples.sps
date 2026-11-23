#!r6rs
;;; make check-docs's generator: (unique-id-doc-examples) on pages written in
;;; this suite, for the program it makes and the faults it refuses, then
;;; tools/doc-examples.sps as a child on the trees under
;;; tools/fixtures/doc-examples/, and each program it writes run as a child
;;; too, for its output and its exit status.
;;;
;;; The assertions name the whole answer: every complaint, in order, with its
;;; line, and every byte of a program's stdout and stderr, so a generator that
;;; checked the wrong line, dropped a continuation or missed a refusal fails
;;; as surely as one that wrote nothing.
(import (rnrs)
        (srfi :64)
        (unique-id-testing)
        (unique-id-checks)
        (unique-id-doc-examples)
        (only (chezscheme) directory-list mkdir sort file-directory? delete-directory))

(define runner (test-runner-simple))
(test-runner-current runner)
(test-begin "unique-id-doc-examples")

(define fixtures "tools/fixtures/doc-examples/")
(define work "build/doc-examples-test/")

;; remove-tree! : String -> Void
;; Deletes the file or directory PATH and everything under it, if it exists.
(define (remove-tree! path)
  (cond ((not (file-exists? path)) (if #f #f))
        ((file-directory? path)
         (for-each (lambda (f) (remove-tree! (string-append path "/" f)))
                   (directory-list path))
         (delete-directory path))
        (else (delete-file path))))

;; No run reads what another left behind.
(remove-tree! "build/doc-examples-test")

;; join : (Listof String) String -> String
;; WORDS with SEP between each two.
(define (join words sep)
  (if (null? words)
      ""
      (fold-left (lambda (acc w) (string-append acc sep w)) (car words) (cdr words))))

;; lines : String ... -> String
;; The strings as the lines of a text, each ended by a newline.
(define (lines . ls)
  (apply string-append (map (lambda (l) (string-append l "\n")) ls)))

;; scheme-page : String ... -> String
;; A page of the given lines in one scheme block: the lines are lines 4 on.
(define (scheme-page . ls)
  (apply lines (append (list "# T" "" "```scheme") ls (list "```"))))

;; answer : String String -> (U (List (U String #f) (Listof String)) (List 'raised String))
;; What page-program answers for the page NAME of TEXT, or what it raised.
(define (answer name text)
  (guard (e (#t (list 'raised (describe e))))
    (page-program name text)))

;; complaints-of : String String -> (U (Listof String) (List 'raised String))
;; The complaints for the page, and the fact that there is no program.
(define (refusal name text)
  (let ((a (answer name text)))
    (if (and (pair? a) (eq? (car a) 'raised))
        a
        (list (car a) (cadr a)))))

;; prelude-text : String
;; The check's own definitions as a program carries them.
(define prelude-text
  (apply string-append (map (lambda (d) (string-append (written d) "\n")) doc-prelude)))

;; program : String String String -> String
;; The program for the page NAME: IMPORT, the check's definitions, BODY, and
;; the finishing call.
(define (program name import body)
  (string-append import "\n" prelude-text body "(%doc-finish " (written name) ")\n"))

;; slurp : String -> String
;; The UTF-8 text of the file at PATH.
(define (slurp path)
  (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                        (make-transcoder (utf-8-codec)))
    (lambda (p)
      (let ((s (get-string-all p)))
        (if (eof-object? s) "" s)))))

;; put-file : String String -> Void
;; Writes TEXT to the file at PATH as UTF-8.
(define (put-file path text)
  (call-with-port (open-file-output-port path (file-options no-fail) (buffer-mode block)
                                         (make-transcoder (utf-8-codec)))
    (lambda (p) (put-string p text))))

;; ensure-dir : String -> Void
;; Makes the directory PATH, and the ones above it that are missing.
(define (ensure-dir path)
  (let loop ((parts (let split ((cs (string->list path)) (cur '()) (acc '()))
                      (cond ((null? cs) (reverse (cons (list->string (reverse cur)) acc)))
                            ((char=? (car cs) #\/) (split (cdr cs) '() (cons (list->string (reverse cur)) acc)))
                            (else (split (cdr cs) (cons (car cs) cur) acc)))))
             (so-far #f))
    (unless (null? parts)
      (let ((p (if so-far (string-append so-far "/" (car parts)) (car parts))))
        (unless (or (string=? (car parts) "") (file-exists? p)) (mkdir p))
        (loop (cdr parts) p)))))

;; generate : String -> (List Integer String String)
;; Runs the generator on the fixture tree NAME into a work directory of its own,
;; answering its status, stdout and stderr.
(define (generate name)
  (ensure-dir (string-append work name))
  (guard (e (#t (list 'raised (describe e))))
    (run-check "tools/doc-examples.sps"
               (list (string-append fixtures name) (string-append work name)))))

;; run-page : String String -> (List Integer String String)
;; Runs the program the generator wrote for PAGE under the work directory NAME.
(define (run-page name page)
  (guard (e (#t (list 'raised (describe e))))
    (run-check (string-append work name "/" page ".sps") '())))

;; listing : String -> (Listof String)
;; The names in the work directory NAME, in order.
(define (listing name)
  (sort string<? (directory-list (string-append work name))))

;; ---- the text rules, on strings -------------------------------------------------

(test-equal "normalize-text: runs of whitespace become one space, ends go"
  (list "a b c" "" "" "a" "a b" "a b")
  (map normalize-text
       (list "  a   b\t\nc  " "" " \n\t " "a" "a\r\nb" "a b")))

(test-equal "normalize-text: whitespace inside a string literal stays, an escaped quote and #\\\" do not end or open one"
  (list "\"a   b\" c" "\"a \\\" \t b\" c" "#\\\" a \"x  y\"" "#\\space \"p  q\"")
  (map normalize-text
       (list "\"a   b\"   c" "\"a \\\" \t b\"  c" "#\\\"   a   \"x  y\"" "#\\space  \"p  q\"")))

(test-equal "shape-text: outside a string each maximal run of 0-9, a-f and A-F becomes one x, inside one each 0-9 and a-f becomes x"
  (list "\"xxxx-xx\"" "\"xxxx-xx\"" "#x" "xyz x.x x" "(x x x)" "xxx"
        "\"xxxxxxxx\"" "\"DEADBEEF\"" "x \"xx-zz\" x" "\"x\\\"xx\"" "#\\\" x \"xx\"")
  (map shape-text
       (list "\"01a2-77\"" "\"ffff-12\"" "#f" "xyz 0.5 12ab" "(1 2 3)" "xAx"
             "\"deadbeef\"" "\"DEADBEEF\"" "12 \"ab-zz\" 3f" "\"a\\\"bc\""
             "#\\\" 9 \"ab\"")))

(test-equal "shape-text: a string and #f, or a string and a longer list, differ in shape"
  (list #t #f #f)
  (list (string=? (shape-text "\"01a2-77\"") (shape-text "\"ffff-12\""))
        (string=? (shape-text "\"01a2-77\"") (shape-text "#f"))
        (string=? (shape-text "(1 2)") (shape-text "(1 2 3)"))))

;; ---- the program ---------------------------------------------------------------

(test-equal "a page's program: the import, the check's definitions, each checked form wrapped, the rest as written"
  (list (program "t.md" "(import (rnrs) (unique-id))"
                 (string-append
                  "(define x 1)\n"
                  "(%doc-check \"t.md\" 13 #f \"2\" (lambda () (+ x 1)))\n"
                  "(%doc-check \"t.md\" 18 #t \"(1 2)\" (lambda () (list x\n      2)))\n"))
        '())
  (answer "t.md"
          (lines "# T"
                 ""
                 "```text"
                 "(+ 9 9)"
                 ";; => 0"
                 "```"
                 ""
                 "```scheme"
                 "#!r6rs"
                 "(import (unique-id))"
                 "(define x 1)"
                 ""
                 "(+ x 1)   ;; => 2"
                 ";; A word after the marker: a comment, not a result."
                 "(list x"
                 "      2)"
                 ""
                 ";; => e.g. (1"
                 ";;     2)"
                 ";; a comment after"
                 "```")))

(test-equal "a page's program: the blocks are one program, in order, and a page with no import imports (rnrs)"
  (list (program "t.md" "(import (rnrs))"
                 (string-append
                  "(define a 1)\n"
                  "(%doc-check \"t.md\" 11 #f \"1\" (lambda () a))\n"
                  "(%doc-check \"t.md\" 16 #f \"2\" (lambda () (+ a 1)))\n"))
        '())
  (answer "t.md"
          (lines "# T" "" "```scheme" "(define a 1)" "" "```" ""
                 ";; => never code, outside a block"
                 "```scheme" ;; line 9
                 "a"
                 ";; => 1"
                 "```" "" "```scheme"
                 "(+ a 1)" ;; line 15 is the form; the result is below
                 ";; => 2"
                 "```")))

(test-equal "a page's program: (rnrs) is added to an import without it, first"
  (list (program "t.md" "(import (rnrs) (unique-id) (srfi :19))" "") '())
  (answer "t.md" (scheme-page "(import (unique-id) (srfi :19))")))

(test-equal "a page's program: an import with (rnrs) in it is kept as it is"
  (list (program "t.md" "(import (unique-id) (rnrs))" "") '())
  (answer "t.md" (scheme-page "(import (unique-id) (rnrs))")))

(test-equal "a page's program: a #!r6rs line is dropped, and the lines after it keep their numbers"
  (list (program "t.md" "(import (rnrs))"
                 "(%doc-check \"t.md\" 6 #f \"2\" (lambda () (+ 1 1)))\n")
        '())
  (answer "t.md" (scheme-page "#!r6rs" "(+ 1 1)" ";; => 2")))

(test-equal "a page with no scheme block makes no program: sh, text and bare fences are not code"
  (list (list #f '()) (list #f '()) (list #f '()) (list #f '()))
  (list (answer "t.md" (lines "# T" "prose"))
        (answer "t.md" (lines "```sh" "(define a 1)" ";; => 2" "```"))
        (answer "t.md" (lines "```text" "(import (nope))" "```" "```" "(define a 1)" "```"))
        (answer "t.md" "")))

;; ---- what the generator refuses ----------------------------------------------

(test-equal "refused: a result after define, define-record-type and define-syntax, at the result's line"
  (list (list #f (list "t.md:5: `;; =>` follows a definition"))
        (list #f (list "t.md:5: `;; =>` follows a definition"))
        (list #f (list "t.md:5: `;; =>` follows a definition")))
  (list (refusal "t.md" (scheme-page "(define a 1)" ";; => 1"))
        (refusal "t.md" (scheme-page "(define-record-type p (fields x))" ";; => 1"))
        (refusal "t.md" (scheme-page "(define-syntax m (syntax-rules () ((_) 1)))" ";; => 1"))))

(test-equal "refused: a result after an import"
  (list #f (list "t.md:5: `;; =>` follows an import"))
  (refusal "t.md" (scheme-page "(import (rnrs))" ";; => 1")))

(test-equal "refused: a result with no form before it in its block, or none directly before it"
  (list (list #f (list "t.md:4: `;; =>` follows no form directly"))
        (list #f (list "t.md:5: `;; =>` follows no form directly"))
        (list #f (list "t.md:8: `;; =>` follows no form directly"))
        (list #f (list "t.md:6: `;; =>` follows no form directly")))
  (list (refusal "t.md" (scheme-page ";; => 1"))
        (refusal "t.md" (scheme-page ";; a comment" ";; => 1"))
        (refusal "t.md" (lines "# T" "" "```scheme" "(+ 1 1)" "```" "" "```scheme" ";; => 2" "```"))
        (refusal "t.md" (scheme-page "(+ 1 1)" ";; a comment" ";; => 2"))))

(test-equal "refused: an import that is not the first form of the page's first block"
  (list (list #f (list "t.md:5: import is allowed only as the first form of the page's first scheme block"))
        (list #f (list "t.md:9: import is allowed only as the first form of the page's first scheme block"))
        (list #f (list "t.md:5: import is allowed only as the first form of the page's first scheme block")))
  (list (refusal "t.md" (scheme-page "(+ 1 1)" "(import (rnrs))"))
        (refusal "t.md" (lines "# T" "" "```scheme" "(import (rnrs))" "```" "" "```scheme"
                               "(+ 1 1)" "(import (unique-id))" "```"))
        (refusal "t.md" (scheme-page "(import (rnrs))" "(import (rnrs))"))))

(test-equal "refused: a name defined twice, naming both lines, in a block, across blocks, and as record or values names"
  (list (list #f (list "t.md:5: a is defined twice, first at t.md:4"))
        (list #f (list "t.md:10: a is defined twice, first at t.md:4"))
        (list #f (list "t.md:5: p-x is defined twice, first at t.md:4"))
        (list #f (list "t.md:5: b is defined twice, first at t.md:4")))
  (list (refusal "t.md" (scheme-page "(define a 1)" "(define (a) 2)"))
        (refusal "t.md" (lines "# T" "" "```scheme" "(define a 1)" "```" "" "```scheme"
                               "(define b 1)" "" "(define a 2)" "```"))
        (refusal "t.md" (scheme-page "(define-record-type p (fields x))" "(define p-x 1)"))
        (refusal "t.md" (scheme-page "(define-values (b c) (values 1 2))" "(define b 3)"))))

(test-equal "refused: a record type's own name, constructor and predicate, and its mutator, are names too"
  (list (list #f (list "t.md:5: make-p is defined twice, first at t.md:4"))
        (list #f (list "t.md:5: p? is defined twice, first at t.md:4"))
        (list #f (list "t.md:5: p is defined twice, first at t.md:4"))
        (list #f (list "t.md:5: p-y-set! is defined twice, first at t.md:4"))
        (list #f (list "t.md:5: q is defined twice, first at t.md:4")))
  (list (refusal "t.md" (scheme-page "(define-record-type p (fields x))" "(define make-p 1)"))
        (refusal "t.md" (scheme-page "(define-record-type p (fields x))" "(define (p? x) 1)"))
        (refusal "t.md" (scheme-page "(define-record-type p (fields x))" "(define p 1)"))
        (refusal "t.md" (scheme-page "(define-record-type p (fields (mutable y)))" "(define p-y-set! 1)"))
        (refusal "t.md" (scheme-page "(define-record-type (q mk-q is-q) (fields x))" "(define q 1)"))))

(test-equal "refused: a block that does not read as data, at the datum that fails"
  (list (list #f (list "t.md:5: does not read as data"))
        (list #f (list "t.md:5: does not read as data")))
  (list (refusal "t.md" (scheme-page "(define a 1)" "(define b (+ 1 2)" "(define c 3)"))
        (refusal "t.md" (scheme-page "(define a 1)" ")"))))

(test-equal "refused: a definition whose name starts with the check's prefix"
  (list #f (list "t.md:4: %doc-count starts with %doc-, which the check's own definitions use"))
  (refusal "t.md" (scheme-page "(define %doc-count 1)")))

(test-equal "refused: every fault of a page, in line order, whichever block it is in"
  (list #f (list "t.md:5: `;; =>` follows a definition"
                 "t.md:6: a is defined twice, first at t.md:4"
                 "t.md:10: import is allowed only as the first form of the page's first scheme block"))
  (refusal "t.md" (lines "# T" "" "```scheme" "(define a 1)" ";; => 1" "(define a 2)" "```" ""
                         "```scheme" "(import (rnrs))" "```")))

;; not-taken : Nat -> String
;; The complaint for a `;; =>` look-alike on line N of page t.md.
(define (not-taken n)
  (string-append "t.md:" (number->string n)
                 ": `;; =>` is not taken as a result: it must start a line, or follow a form on its line, directly after a top-level form"))

(test-equal "refused: a result that is indented, or inside a form, is named at its line"
  (list (list #f (list (not-taken 6)))
        (list #f (list (not-taken 5))))
  (list (refusal "t.md" (scheme-page "(let ((x 1))" "  (+ x 1))" "  ;; => 99"))
        (refusal "t.md" (scheme-page "(list 1" ";; => (1 99)" "      2)"))))

(test-equal "refused: a marker with no space, one `;`, three `;`, or a block comment before it is named at its line"
  (list (list #f (list (not-taken 5)))
        (list #f (list (not-taken 5)))
        (list #f (list (not-taken 5)))
        (list #f (list (not-taken 4)))
        (list #f (list (not-taken 4))))
  (list (refusal "t.md" (scheme-page "(+ 1 1)" ";;=> 99"))
        (refusal "t.md" (scheme-page "(+ 1 1)" "; => 99"))
        (refusal "t.md" (scheme-page "(+ 1 1)" ";;; => 99"))
        (refusal "t.md" (scheme-page "(+ 1 1) #| c |# ;; => 99"))
        (refusal "t.md" (scheme-page "(+ 1 1) ; => 99"))))

(test-equal "refused: every look-alike of a page is named, and a result taken, with its continuation, is not"
  (list #f (list (not-taken 6) (not-taken 10)))
  (refusal "t.md" (scheme-page "(+ 1 1)" ";; => 2" "  ;; => 3" "(+ 2 2)" ";; => 4" ";;   more" ";;;=> 5")))

(test-equal "the look-alike rule leaves alone a result right after its form, on its line or below, and a continuation, even one that holds a look-alike"
  (list #t '())
  (let ((a (answer "t.md" (scheme-page "(+ 1 1) ;; => 2" "(+ 2 2)" "" ";; => e.g. (4" ";;     4" ";;  ;=> 4)"))))
    (list (and (pair? a) (string? (car a))) (if (pair? a) (cadr a) a))))

(test-equal "refused: a scheme fence that is indented, a tilde fence, or has more than three backticks, is named at its line"
  (list (list #f (list "t.md:3: scheme fence is not exactly ```scheme at column 0, so it is not read"))
        (list #f (list "t.md:3: scheme fence is not exactly ```scheme at column 0, so it is not read"))
        (list #f (list "t.md:3: scheme fence is not exactly ```scheme at column 0, so it is not read"))
        (list #f (list "t.md:3: scheme fence is not exactly ```scheme at column 0, so it is not read"))
        (list #f (list "t.md:3: scheme fence is not exactly ```scheme at column 0, so it is not read"))
        (list #f (list "t.md:3: scheme fence is not exactly ```scheme at column 0, so it is not read")))
  (list (refusal "t.md" (lines "# T" "" "  ```scheme" "  (+ 1 1)" "  ;; => 99" "  ```"))
        (refusal "t.md" (lines "# T" "" "~~~scheme" "(+ 1 1)" ";; => 99" "~~~"))
        (refusal "t.md" (lines "# T" "" "````scheme" "(+ 1 1)" "````"))
        (refusal "t.md" (lines "# T" "" "```scheme " "(+ 1 1)" "```"))
        (refusal "t.md" (lines "# T" "" "   ~~~~ scheme" "(+ 1 1)" "~~~~"))
        (refusal "t.md" (lines "# T" "" "```schemer" "(+ 1 1)" "```"))))

(test-equal "a fence that is not scheme, or is exactly ```scheme, is not refused"
  (list (list #f '()) (list #f '()) (list #f '()) #t)
  (list (answer "t.md" (lines "# T" "" "  ```sh" "  ls" "  ```" "~~~text" "x" "~~~"))
        (answer "t.md" (lines "# T" "" "```schematic" "x" "```"))
        (answer "t.md" (lines "# T" "" "``scheme" "x" "``"))
        (let ((a (answer "t.md" (lines "# T" "" "```scheme" "(+ 1 1)" "```"))))
          (and (string? (car a)) (null? (cadr a))))))

(test-equal "refused: a form that mentions exit, at the form's line, as a call, a name or inside a list"
  (list (list #f (list "t.md:5: exit ends the program before its results are checked"))
        (list #f (list "t.md:4: exit ends the program before its results are checked"))
        (list #f (list "t.md:4: exit ends the program before its results are checked"
                       "t.md:5: exit ends the program before its results are checked"))
        (list #f (list "t.md:4: exit ends the program before its results are checked"))
        (list #f (list "t.md:4: exit ends the program before its results are checked")))
  (list (refusal "t.md" (scheme-page "(+ 1 1)" "(exit 0)"))
        (refusal "t.md" (scheme-page "(define (stop) (exit 1))"))
        (refusal "t.md" (scheme-page "(import (only (rnrs) exit))" "(list 'a (vector 1 exit))"))
        (refusal "t.md" (scheme-page "(let ((x 1)) (if x (+ 1 (begin (exit) 2)) 3))"))
        (refusal "t.md" (scheme-page "'#(1 exit)"))))

(test-equal "a page that only has exit in a string or a longer name is not refused"
  #t
  (let ((a (answer "t.md" (scheme-page "(string-append \"exit\" \"exits\")" ";; => \"exitexits\"" "(list 'exit-code 'emergency)"))))
    (and (string? (car a)) (null? (cadr a)))))

;; ---- the programs run ---------------------------------------------------------

(test-equal "run: a page whose results all match writes its count and exits 0"
  (list (list 0 "" "") (list 0 "match.md: 4 checked\n" "") (list "match.sps"))
  (let* ((g (generate "match")) (r (run-page "match" "match")) (l (listing "match"))) (list g r l)))

(test-equal "run: a wrong result is named by its page and line, with what was expected and got, and exits 1"
  (list (list 0 "" "") (list 1 "" "mismatch.md:8: expected 4, got 3\n"))
  (let* ((g (generate "mismatch")) (r (run-page "mismatch" "mismatch"))) (list g r)))

(test-equal "run: a result continued over lines matches when the joined text does"
  (list (list 0 "" "") (list 0 "continued-ok.md: 1 checked\n" ""))
  (let* ((g (generate "continued-ok")) (r (run-page "continued-ok" "continued-ok"))) (list g r)))

(test-equal "run: a continued result that differs is named at its first line"
  (list (list 0 "" "")
        (list 1 "" "continued-bad.md:6: expected (1 2 3 5), got (1 2 3 4)\n"))
  (let* ((g (generate "continued-bad")) (r (run-page "continued-bad" "continued-bad"))) (list g r)))

(test-equal "run: e.g. results of the same shape match"
  (list (list 0 "" "") (list 0 "eg-ok.md: 2 checked\n" ""))
  (let* ((g (generate "eg-ok")) (r (run-page "eg-ok" "eg-ok"))) (list g r)))

(test-equal "run: e.g. results of another shape are named, and each one is reported"
  (list (list 0 "" "")
        (list 1 ""
              (string-append "eg-bad.md:8: expected e.g. 12, got \"ab\"\n"
                             "eg-bad.md:10: expected e.g. (1 2 3), got (1 2)\n")))
  (let* ((g (generate "eg-bad")) (r (run-page "eg-bad" "eg-bad"))) (list g r)))

(test-equal "run: a raise in a checked form is named at its line, and the forms after it are still checked"
  (list (list 0 "" "")
        (list 1 ""
              (string-append "raise.md:7: raised: boom: it broke 1 \"two\"\n"
                             "raise.md:9: raised: plain\n"
                             "raise.md:11: expected 3, got 2\n")))
  (let* ((g (generate "raise")) (r (run-page "raise" "raise"))) (list g r)))

(test-equal "run: a raise in a checked form fails the program even when every other result is right"
  (list (list 0 "" "") (list 1 "" "raise-only.md:6: raised: car: ~s is not a pair ()\n"))
  (let* ((g (generate "raise-only")) (r (run-page "raise-only" "raise-only"))) (list g r)))

(test-equal "run: a raise in an unchecked form ends the program with a non-zero status, before its count"
  (list (list 0 "" "") #t "" "Exception occurred with non-condition value stop\n")
  (let* ((g (generate "unchecked-raise"))
         (r (run-page "unchecked-raise" "unchecked-raise")))
    (list g (and (pair? r) (not (eqv? (car r) 0))) (if (pair? r) (cadr r) r)
          (if (pair? r) (caddr r) r))))

(test-equal "run: the generator writes every page it can, removes stale programs, and names each refusal"
  (list (list 1 ""
              (string-append "refused.md:6: `;; =>` follows a definition\n"
                             "refused.md:7: a is defined twice, first at refused.md:5\n"))
        (list "good.sps" "keep.txt" "refused.sps")
        (list 0 "good.md: 1 checked\n" "")
        (list 1 ""
              (string-append "refused.md:6: `;; =>` follows a definition\n"
                             "refused.md:7: a is defined twice, first at refused.md:5\n")))
  (begin
    (ensure-dir (string-append work "tree"))
    (put-file (string-append work "tree/stale.sps") "(this is not a program\n")
    (put-file (string-append work "tree/keep.txt") "kept\n")
    (let* ((g (generate "tree"))
           (l (listing "tree"))
           (good (run-page "tree" "good"))
           (refused (run-page "tree" "refused")))
      (list g l good refused))))

(test-equal "run: a refused page's program names its refusals on stderr and exits 1, so a lane fails it"
  (list (list 1 ""
              (string-append "exit-page.md:6: exit ends the program before its results are checked\n"
                             "exit-page.md:9: `;; =>` is not taken as a result: it must start a line, or follow a form on its line, directly after a top-level form\n"))
        (list 1 ""
              (string-append "exit-page.md:6: exit ends the program before its results are checked\n"
                             "exit-page.md:9: `;; =>` is not taken as a result: it must start a line, or follow a form on its line, directly after a top-level form\n"))
        (list "exit-page.sps"))
  (let* ((g (generate "exit-page"))
         (r (run-page "exit-page" "exit-page"))
         (l (listing "exit-page")))
    (list g r l)))

(test-equal "run: whitespace inside a string, hex case inside a string and a string's length are held, and each failure is reported"
  (list (list 0 "" "")
        (list 1 ""
              (string-append "eg-string.md:6: expected \"a b\", got \"a   b\"\n"
                             "eg-string.md:8: expected e.g. \"deadbeef\", got \"DEADBEEF\"\n"
                             "eg-string.md:10: expected e.g. \"012345678\", got \"abcdef01\"\n"
                             "eg-string.md:12: expected e.g. \"a\", got \"A\"\n")))
  (let* ((g (generate "eg-string")) (r (run-page "eg-string" "eg-string"))) (list g r)))

(test-equal "run: the generator takes exactly two arguments"
  (list 2 "" "usage: doc-examples.sps DOCS-DIR OUT-DIR\n")
  (guard (e (#t (list 'raised (describe e))))
    (run-check "tools/doc-examples.sps" '("one"))))

(test-end "unique-id-doc-examples")

(exit (suite-exit-status runner))
