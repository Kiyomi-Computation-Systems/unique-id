#!r6rs
;;; (unique-id-doc-examples): the logic of make check-docs, which runs every
;;; example in docs/ as a program on Chez and on Guile and checks each result.
;;;
;;; A page's ```scheme blocks, in order, are the body of one R6RS program.
;;; Other fences are not code. A result is checked when a line that starts
;;; `;; =>` comes right after a top-level form, on the form's own line or
;;; after blank lines only:
;;;
;;;   (+ 1 2)
;;;   ;; => 3
;;;
;;; The text after `;; =>` is the expected value, and goes on over each
;;; following line that starts `;;` and two or more spaces. The form's value,
;;; as `write` writes it, must equal it once each run of whitespace is one
;;; space, outside string literals only. `;; => e.g. EXAMPLE` shows a random
;;; value: it must have EXAMPLE's shape. Outside string literals each maximal
;;; run of the characters 0-9, a-f and A-F counts as one; inside one each such
;;; character counts for itself, so only its hex digits may vary. A literal
;;; starts and ends with an unescaped `"`, and `\#\` with the character after
;;; it is one unit, so `#\"` opens nothing.
;;;
;;; page-program refuses a page, with a complaint per fault, when:
;;;
;;;   a `;; =>` follows a definition or an import
;;;   a `;; =>` follows no form directly
;;;   an import is not the first form of the page's first scheme block
;;;   a name is defined twice, which R6RS refuses in a program's body
;;;   a block does not read as data
;;;   a definition's name starts with %doc-, which the check's own use
;;;   a form mentions `exit`, which would end the program before its checks
;;;   a line in a scheme block holds `;`, spaces and `=>` and is not taken as
;;;     a result: an indented one, one inside a form, `;;=>`, `; =>`,
;;;     `;;; =>`, or one after a block comment
;;;   a line is a scheme fence but not exactly ```scheme at column 0, such as
;;;     one indented under a list item, or `~~~scheme`
;;;
;;; The program imports what the page's import form names, with (rnrs) added
;;; when it is missing, then holds the check's own definitions, written into
;;; it so that it needs nothing but the page's libraries, then the page's
;;; forms. Each checked form is wrapped in a call that compares it, reports
;;; `PAGE.md:LINE: expected TEXT, got TEXT` on stderr when it differs, and
;;; carries on. A form that raises is reported the same way, as `PAGE.md:LINE:
;;; raised: WHO: MESSAGE IRRITANTS`. The program exits 1 at its end if any
;;; check failed, and otherwise writes `PAGE.md: N checked`.
;;;
;;; Tooling, not a suite library: it lives in tools/, which only the tools
;;; lane puts on its library path, and it uses Chez's own procedures. Its
;;; suite is tools/test-unique-id-doc-examples.sps and its program
;;; tools/doc-examples.sps.
(library (unique-id-doc-examples)
  (export page-program write-programs normalize-text shape-text doc-prelude refusal-program)
  (import (rnrs)
          (rnrs eval)
          (only (chezscheme) directory-list mkdir sort))

  ;; --- the check's own definitions -------------------------------------------

  ;; doc-prelude : (Listof Sexp)
  ;; The definitions each program carries, as data. The program runs on
  ;; Guile too, so they use (rnrs) alone. Every name starts with %doc-.
  (define doc-prelude
    '((define %doc-failed 0)
      (define %doc-count 0)
      (define (%doc-space? c) (memv c '(#\space #\tab #\newline #\return)))
      (define (%doc-hex? c) (memv c (string->list "0123456789abcdefABCDEF")))
      (define (%doc-lower-hex? c) (memv c (string->list "0123456789abcdef")))
      ;; Each character of S with its kind: in for one inside a string literal,
      ;; lit for `#\` and the character after it, out for any other, quote for
      ;; a literal's own quotes. A `\` in a literal escapes the next character.
      (define (%doc-classify s)
        (let loop ((cs (string->list s)) (mode 'out) (acc '()))
          (cond
            ((null? cs) (reverse acc))
            ((eq? mode 'esc) (loop (cdr cs) 'str (cons (cons (car cs) 'in) acc)))
            ((eq? mode 'str)
             (cond ((char=? (car cs) #\\) (loop (cdr cs) 'esc (cons (cons (car cs) 'in) acc)))
                   ((char=? (car cs) #\") (loop (cdr cs) 'out (cons (cons (car cs) 'quote) acc)))
                   (else (loop (cdr cs) 'str (cons (cons (car cs) 'in) acc)))))
            ((char=? (car cs) #\") (loop (cdr cs) 'str (cons (cons (car cs) 'quote) acc)))
            ((and (char=? (car cs) #\#) (pair? (cdr cs)) (char=? (cadr cs) #\\)
                  (pair? (cddr cs)))
             (loop (cdddr cs) 'out
                   (cons (cons (caddr cs) 'lit) (cons (cons (cadr cs) 'lit)
                                                      (cons (cons (car cs) 'out) acc)))))
            (else (loop (cdr cs) 'out (cons (cons (car cs) 'out) acc))))))
      (define (%doc-normalize s)
        (let loop ((cs (%doc-classify s)) (out '()) (pending #f))
          (cond ((null? cs) (list->string (reverse out)))
                ((and (eq? (cdar cs) 'out) (%doc-space? (caar cs)))
                 (loop (cdr cs) out (pair? out)))
                (else (loop (cdr cs)
                            (cons (caar cs) (if pending (cons #\space out) out))
                            #f)))))
      (define (%doc-shape s)
        (let loop ((cs (%doc-classify s)) (out '()) (in-run #f))
          (cond ((null? cs) (list->string (reverse out)))
                ((eq? (cdar cs) 'in)
                 (loop (cdr cs) (cons (if (%doc-lower-hex? (caar cs)) #\x (caar cs)) out) #f))
                ((and (eq? (cdar cs) 'out) (%doc-hex? (caar cs)))
                 (loop (cdr cs) (if in-run out (cons #\x out)) #t))
                (else (loop (cdr cs) (cons (caar cs) out) #f)))))
      (define (%doc-written v)
        (call-with-string-output-port (lambda (p) (write v p))))
      (define (%doc-join parts)
        (if (null? parts)
            ""
            (fold-left (lambda (acc s) (string-append acc " " s)) (car parts) (cdr parts))))
      (define (%doc-describe e)
        (if (condition? e)
            (let* ((who (and (who-condition? e) (condition-who e)))
                   (msg (and (message-condition? e) (condition-message e)))
                   (irritants (if (irritants-condition? e) (condition-irritants e) '()))
                   (parts (append (if who (list (string-append (%doc-written who) ":")) '())
                                  (if msg (list (if (string? msg) msg (%doc-written msg))) '())
                                  (map %doc-written irritants))))
              (if (null? parts) "raised" (string-append "raised: " (%doc-join parts))))
            (string-append "raised: " (%doc-written e))))
      (define (%doc-report s)
        (let ((p (current-error-port)))
          (put-string p s)
          (put-char p #\newline)
          (flush-output-port p)))
      (define (%doc-check page line shape? expected thunk)
        (set! %doc-count (+ %doc-count 1))
        (let* ((where (string-append page ":" (number->string line) ": "))
               (got (guard (e (#t (%doc-report (string-append where (%doc-describe e))) #f))
                      (%doc-written (thunk)))))
          (if got
              (let ((want-n (%doc-normalize expected)) (got-n (%doc-normalize got)))
                (unless (if shape?
                            (string=? (%doc-shape want-n) (%doc-shape got-n))
                            (string=? want-n got-n))
                  (%doc-report (string-append where "expected " (if shape? "e.g. " "")
                                              want-n ", got " got-n))
                  (set! %doc-failed (+ %doc-failed 1))))
              (set! %doc-failed (+ %doc-failed 1)))))
      (define (%doc-finish page)
        (if (> %doc-failed 0)
            (exit 1)
            (let ((p (current-output-port)))
              (put-string p (string-append page ": " (number->string %doc-count) " checked\n"))
              (flush-output-port p))))))

  ;; The two procedures of the prelude that a suite can call on strings,
  ;; taken from the very text a program carries.
  (define prelude-procedures
    (eval `(let () ,@doc-prelude (cons %doc-normalize %doc-shape))
          (environment '(rnrs))))

  ;; normalize-text : String -> String
  ;; S with each run of whitespace made one space, and no space at either end.
  (define (normalize-text s) ((car prelude-procedures) s))

  ;; shape-text : String -> String
  ;; S with each maximal run of the characters 0-9, a-f and A-F made one x.
  (define (shape-text s) ((cdr prelude-procedures) s))

  ;; --- text --------------------------------------------------------------------

  ;; split-lines : String -> (Listof String)
  ;; TEXT cut at each newline, so "a\n" is ("a" ""), and "" is ("").
  (define (split-lines text)
    (let loop ((chars (string->list text)) (line '()) (acc '()))
      (cond ((null? chars) (reverse (cons (list->string (reverse line)) acc)))
            ((char=? (car chars) #\newline)
             (loop (cdr chars) '() (cons (list->string (reverse line)) acc)))
            (else (loop (cdr chars) (cons (car chars) line) acc)))))

  ;; join : (Listof String) String -> String
  ;; WORDS with SEP between each two.
  (define (join words sep)
    (if (null? words)
        ""
        (fold-left (lambda (acc w) (string-append acc sep w)) (car words) (cdr words))))

  ;; prefix? : String String -> Boolean
  ;; Whether S starts with PREFIX.
  (define (prefix? prefix s)
    (and (>= (string-length s) (string-length prefix))
         (string=? prefix (substring s 0 (string-length prefix)))))

  ;; suffix? : String String -> Boolean
  ;; Whether S ends with SUFFIX.
  (define (suffix? suffix s)
    (and (>= (string-length s) (string-length suffix))
         (string=? suffix (substring s (- (string-length s) (string-length suffix))
                                     (string-length s)))))

  ;; blank? : String -> Boolean
  ;; Whether S holds nothing but whitespace.
  (define (blank? s)
    (for-all char-whitespace? (string->list s)))

  ;; trim : String -> String
  ;; S without leading and trailing whitespace.
  (define (trim s)
    (let loop-end ((end (string-length s)))
      (if (and (> end 0) (char-whitespace? (string-ref s (- end 1))))
          (loop-end (- end 1))
          (let loop-start ((start 0))
            (if (and (< start end) (char-whitespace? (string-ref s start)))
                (loop-start (+ start 1))
                (substring s start end))))))

  ;; drop : String Nat -> String
  ;; S without its first N characters.
  (define (drop s n) (substring s n (string-length s)))

  ;; file-text : String -> String
  ;; The UTF-8 text of the file at PATH.
  (define (file-text path)
    (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                          (make-transcoder (utf-8-codec)))
      (lambda (port)
        (let ((s (get-string-all port)))
          (if (eof-object? s) "" s)))))

  ;; count-newlines : String Nat -> Nat
  ;; How many newlines TEXT has before offset END.
  (define (count-newlines text end)
    (let loop ((i 0) (n 0))
      (cond ((>= i end) n)
            ((char=? (string-ref text i) #\newline) (loop (+ i 1) (+ n 1)))
            (else (loop (+ i 1) n)))))

  ;; --- blocks ------------------------------------------------------------------

  ;; fence-line? : String -> Boolean
  ;; Whether LINE is a scheme fence of any kind: after any leading spaces, three
  ;; or more backticks or tildes, any spaces, then `scheme`.
  (define (scheme-fence? line)
    (let* ((start (let skip ((i 0))
                    (if (and (< i (string-length line)) (char=? (string-ref line i) #\space))
                        (skip (+ i 1))
                        i)))
           (rest (drop line start)))
      (and (> (string-length rest) 0)
           (memv (string-ref rest 0) '(#\` #\~))
           (let run ((i 0))
             (if (and (< i (string-length rest)) (char=? (string-ref rest i) (string-ref rest 0)))
                 (run (+ i 1))
                 (and (>= i 3)
                      (prefix? "scheme" (trim-left (drop rest i)))))))))

  ;; scheme-blocks : String -> (Pair (Listof (Pair Nat String)) (Listof Nat))
  ;; The ```scheme blocks of the page TEXT, in order, each as the line number
  ;; of its first line and its text, and the lines of each scheme fence that
  ;; is not exactly ```scheme at column 0, which no block starts at. Any other
  ;; fence is skipped to its close. A fence starts a line. A line `#!r6rs` is
  ;; blanked, so lines stay put.
  (define (scheme-blocks text)
    (let loop ((lines (split-lines text)) (n 1) (mode 'out) (first 0) (acc '()) (blocks '())
               (bad '()))
      (define (finish)
        (cons (cons first (join (reverse acc) "\n")) blocks))
      (cond
        ((null? lines)
         (cons (reverse (if (eq? mode 'scheme) (finish) blocks)) (reverse bad)))
        (else
         (let ((line (car lines)))
           (case mode
             ((out)
              (cond ((string=? line "```scheme")
                     (loop (cdr lines) (+ n 1) 'scheme (+ n 1) '() blocks bad))
                    ((scheme-fence? line)
                     (loop (cdr lines) (+ n 1) 'out 0 '() blocks (cons n bad)))
                    ((prefix? "```" line)
                     (loop (cdr lines) (+ n 1) 'other 0 '() blocks bad))
                    (else (loop (cdr lines) (+ n 1) 'out 0 '() blocks bad))))
             ((other)
              (loop (cdr lines) (+ n 1) (if (prefix? "```" line) 'out 'other) 0 '() blocks bad))
             (else
              (if (prefix? "```" line)
                  (loop (cdr lines) (+ n 1) 'out 0 '() (finish) bad)
                  (loop (cdr lines) (+ n 1) 'scheme first
                        (cons (if (string=? (trim line) "#!r6rs") "" line) acc)
                        blocks bad)))))))))

  ;; skip-gap : String Nat -> Nat
  ;; The offset in TEXT of the first character at or after START that is not
  ;; whitespace, a `;` comment or a `#|` block comment: where the next datum
  ;; starts, or the end of TEXT.
  (define (skip-gap text start)
    (let ((len (string-length text)))
      (let loop ((i start) (depth 0))
        (cond
          ((>= i len) len)
          ((> depth 0)
           (cond ((and (< (+ i 1) len) (char=? (string-ref text i) #\|)
                       (char=? (string-ref text (+ i 1)) #\#))
                  (loop (+ i 2) (- depth 1)))
                 ((and (< (+ i 1) len) (char=? (string-ref text i) #\#)
                       (char=? (string-ref text (+ i 1)) #\|))
                  (loop (+ i 2) (+ depth 1)))
                 (else (loop (+ i 1) depth))))
          ((char-whitespace? (string-ref text i)) (loop (+ i 1) 0))
          ((char=? (string-ref text i) #\;)
           (let skip ((j i))
             (if (or (>= j len) (char=? (string-ref text j) #\newline))
                 (loop j 0)
                 (skip (+ j 1)))))
          ((and (< (+ i 1) len) (char=? (string-ref text i) #\#)
                (char=? (string-ref text (+ i 1)) #\|))
           (loop (+ i 2) 1))
          (else i)))))

  ;; A Form is (vector DATUM START-LINE END-LINE START END RESULT): a top-level
  ;; datum, the lines it starts and ends on, its offsets in the block, and its
  ;; checked result, which is #f or (list LINE EG? TEXT).

  ;; result-of : Nat String (Listof String) -> (List Nat Boolean String)
  ;; The result on LINE whose first text, after `;; =>`, is REST, and whose
  ;; continuation lines' text, after `;;`, is MORE: with `e.g.` taken off the
  ;; front, if it starts REST, as the flag.
  (define (result-of line rest more)
    (let* ((all (join (cons (trim rest) (map trim more)) " "))
           (eg? (or (string=? all "e.g.") (prefix? "e.g. " all))))
      (list line eg? (if eg? (trim (drop all 4)) all))))

  ;; gap-results : Nat String Boolean -> (List (U (List Nat Boolean String) #f) (Listof Nat) (Listof Nat))
  ;; What the text GAP between a datum and the next says, GAP-LINE being the
  ;; line it starts on and AFTER-FORM? whether a datum came before it: the
  ;; datum's result, if any, the lines of each `;; =>` that follows no form
  ;; directly, and every line the gap's results and their continuations
  ;; take, orphans included. The gap's first line is the rest of the datum's
  ;; line, where a `;; =>` may follow spaces; on any later line it starts the
  ;; line.
  (define (gap-results gap gap-line after-form?)
    (let loop ((segs (split-lines gap)) (i 0) (result #f) (more '())
               (collecting #f) (directly after-form?) (orphans '()) (taken '()))
      (define (done)
        (list (and result (result-of (car result) (cdr result) (reverse more)))
              (reverse orphans)
              taken))
      (if (null? segs)
          (done)
          (let* ((seg (car segs))
                 (line (+ gap-line i))
                 (lead (trim-left seg))
                 (marker ";; =>"))
            (cond
              ((and (= i 0) after-form? (prefix? marker lead))
               (loop (cdr segs) (+ i 1) (cons line (drop lead 5)) '() #t #f orphans
                     (cons line taken)))
              ((and (or (> i 0) (not after-form?)) (prefix? marker seg))
               (if (and directly (not result))
                   (loop (cdr segs) (+ i 1) (cons line (drop seg 5)) '() #t #f orphans
                         (cons line taken))
                   (loop (cdr segs) (+ i 1) result more #f directly (cons line orphans)
                         (cons line taken))))
              ((and collecting (prefix? ";;  " seg))
               (loop (cdr segs) (+ i 1) result (cons (drop seg 2) more) #t directly orphans
                     (cons line taken)))
              ((blank? seg)
               (loop (cdr segs) (+ i 1) result more #f directly orphans taken))
              ((= i 0)
               (loop (cdr segs) (+ i 1) result more #f directly orphans taken))
              (else
               (loop (cdr segs) (+ i 1) result more #f #f orphans taken)))))))

  ;; trim-left : String -> String
  ;; S without leading whitespace.
  (define (trim-left s)
    (let loop ((start 0))
      (if (and (< start (string-length s)) (char-whitespace? (string-ref s start)))
          (loop (+ start 1))
          (substring s start (string-length s)))))

  ;; with-result : Form (U (List Nat Boolean String) #f) -> Form
  ;; A copy of FORM with RESULT as its result.
  (define (with-result form result)
    (vector (vector-ref form 0) (vector-ref form 1) (vector-ref form 2)
            (vector-ref form 3) (vector-ref form 4) result))

  ;; scan-block : String Nat -> (List (Listof Form) (Listof Nat) (U Nat #f) (Listof Nat))
  ;; The top-level forms of a block that starts on line FIRST, in order, the
  ;; lines of its `;; =>` that follow no form directly, the line of the
  ;; first datum that does not read, if one does not, and the lines of the
  ;; block that its results and their continuations take; the forms before an
  ;; unreadable datum are still answered.
  (define (scan-block text first)
    (define bad (list 'unreadable))
    (define (line-at offset) (+ first (count-newlines text offset)))
    (let ((port (open-string-input-port text)) (len (string-length text)))
      (let loop ((prev-end 0) (prev #f) (forms '()) (orphans '()) (taken '()))
        (let* ((start (skip-gap text prev-end))
               (datum (guard (e (#t bad)) (get-datum port)))
               (gap (gap-results (substring text prev-end start) (line-at prev-end)
                                 (and prev #t)))
               (forms (if prev (cons (with-result prev (car gap)) forms) forms))
               (orphans (append (reverse (cadr gap)) orphans))
               (taken (append (caddr gap) taken)))
          (cond
            ((and (eq? datum bad) (< start len))
             (list (reverse forms) (reverse orphans) (line-at start) taken))
            ((or (eof-object? datum) (eq? datum bad))
             (list (reverse forms) (reverse orphans) #f taken))
            (else
             (let ((end (port-position port)))
               (loop end
                     (vector datum (line-at start) (line-at (max start (- end 1)))
                             start end #f)
                     forms orphans taken))))))))

  ;; holds-marker? : String -> Boolean
  ;; Whether LINE holds a `;`, any more `;`, any spaces, then `=>`: a comment
  ;; that looks like a result.
  (define (holds-marker? line)
    (let ((len (string-length line)))
      (let find ((i 0))
        (and (< i len)
             (or (and (char=? (string-ref line i) #\;)
                      (let skip ((j i))
                        (if (and (< j len) (memv (string-ref line j) '(#\; #\space #\tab)))
                            (skip (+ j 1))
                            (prefix? "=>" (drop line j)))))
                 (find (+ i 1)))))))

  ;; mentions-symbol? : Sexp Symbol -> Boolean
  ;; Whether the symbol SYM appears anywhere in the datum D, in a list or a vector.
  (define (mentions-symbol? d sym)
    (cond ((symbol? d) (eq? d sym))
          ((pair? d) (or (mentions-symbol? (car d) sym) (mentions-symbol? (cdr d) sym)))
          ((vector? d) (exists (lambda (e) (mentions-symbol? e sym)) (vector->list d)))
          (else #f)))

  ;; --- the page ----------------------------------------------------------------

  ;; names-defined : Sexp -> (Listof Symbol)
  ;; The names a top-level definition D binds, or () for any other form.
  (define (names-defined d)
    (define (flatten-formals f)
      (cond ((pair? f) (append (flatten-formals (car f)) (flatten-formals (cdr f))))
            ((symbol? f) (list f))
            (else '())))
    (define (head h)
      (cond ((pair? h) (head (car h))) ((symbol? h) (list h)) (else '())))
    (guard (e (#t '()))
      (case (car d)
        ((define) (head (cadr d)))
        ((define-syntax) (head (cadr d)))
        ((define-values) (flatten-formals (cadr d)))
        ((define-record-type) (record-names d))
        (else '()))))

  ;; record-names : Sexp -> (Listof Symbol)
  ;; The names a define-record-type form D binds: the type, its constructor and
  ;; predicate, which are made from the type's name when it is a bare symbol,
  ;; and each field's accessor and mutator, made from the field's name when
  ;; the clause gives none.
  (define (record-names d)
    (let* ((spec (cadr d))
           (name (if (pair? spec) (car spec) spec))
           (str (symbol->string name))
           (ctor (if (pair? spec) (cadr spec) (string->symbol (string-append "make-" str))))
           (pred (if (pair? spec) (caddr spec) (string->symbol (string-append str "?"))))
           (fields (let find ((clauses (cddr d)))
                     (cond ((null? clauses) '())
                           ((and (pair? (car clauses)) (eq? (caar clauses) 'fields))
                            (cdar clauses))
                           (else (find (cdr clauses)))))))
      (define (field-name f) (symbol->string (if (pair? f) (cadr f) f)))
      (define (derived f suffix) (string->symbol (string-append str "-" (field-name f) suffix)))
      (append
       (filter symbol? (list name ctor pred))
       (apply append
              (map (lambda (f)
                     (cond
                       ((not (pair? f)) (list (derived f "")))
                       ((eq? (car f) 'mutable)
                        (if (null? (cddr f))
                            (list (derived f "") (derived f "-set!"))
                            (cddr f)))
                       (else (if (null? (cddr f)) (list (derived f "")) (cddr f)))))
                   fields)))))

  ;; definition? : Sexp -> Boolean
  ;; Whether D is a definition form.
  (define (definition? d)
    (and (pair? d) (memq (car d) '(define define-syntax define-values define-record-type)) #t))

  ;; import? : Sexp -> Boolean
  ;; Whether D is an import form.
  (define (import? d) (and (pair? d) (eq? (car d) 'import)))

  ;; written : Sexp -> String
  ;; D as `write` writes it.
  (define (written d) (call-with-string-output-port (lambda (p) (write d p))))

  ;; page-program : String String -> (List (U String #f) (Listof String))
  ;; The program for the page NAME, such as "ids.md", whose text is TEXT, and
  ;; the page's complaints, each `NAME:LINE: RULE`, in line order. The program
  ;; is #f when the page has no scheme block or any complaint.
  (define (page-program name text)
    (define prefix "%doc-")
    (define scanned (scheme-blocks text))
    (define blocks (car scanned))
    (define complaints '())     ; (LINE . TEXT), newest first
    (define items '())          ; (list CHECKED? FORM BLOCK-TEXT), newest first
    (define known '())          ; (NAME . LINE) of each name defined so far
    (define import-spec #f)
    (define first-form? #t)
    (define (complain! line msg)
      (set! complaints
            (cons (cons line (string-append name ":" (number->string line) ": " msg))
                  complaints)))
    (define (define-name! n line)
      (let ((s (symbol->string n)))
        (cond ((prefix? prefix s)
               (complain! line (string-append s " starts with " prefix
                                              ", which the check's own definitions use")))
              ((assq n known)
               => (lambda (p)
                    (complain! line (string-append s " is defined twice, first at " name ":"
                                                   (number->string (cdr p))))))
              (else (set! known (cons (cons n line) known))))))
    (for-each (lambda (l)
                (complain! l "scheme fence is not exactly ```scheme at column 0, so it is not read"))
              (cdr scanned))
    (for-each
     (lambda (block)
       (let ((scan (scan-block (cdr block) (car block))))
         (let ((taken (cadddr scan)))
           (let check ((ls (split-lines (cdr block))) (n (car block)))
             (unless (null? ls)
               (when (and (holds-marker? (car ls)) (not (memv n taken)))
                 (complain! n "`;; =>` is not taken as a result: it must start a line, or follow a form on its line, directly after a top-level form"))
               (check (cdr ls) (+ n 1)))))
         (for-each (lambda (l) (complain! l "`;; =>` follows no form directly")) (cadr scan))
         (when (caddr scan) (complain! (caddr scan) "does not read as data"))
         (for-each
          (lambda (f)
            (let ((d (vector-ref f 0)) (line (vector-ref f 1)) (result (vector-ref f 5)))
              (when (mentions-symbol? d 'exit)
                (complain! line "exit ends the program before its results are checked"))
              (cond
                ((import? d)
                 (if first-form?
                     (set! import-spec d)
                     (complain! line "import is allowed only as the first form of the page's first scheme block"))
                 (when result (complain! (car result) "`;; =>` follows an import")))
                ((definition? d)
                 (for-each (lambda (n) (define-name! n line)) (names-defined d))
                 (when result (complain! (car result) "`;; =>` follows a definition"))
                 (set! items (cons (list #f f (cdr block)) items)))
                (else
                 (set! items (cons (list (and result #t) f (cdr block)) items))))
              (set! first-form? #f)))
          (car scan))))
     blocks)
    (let ((texts (map cdr (sort (lambda (a b) (< (car a) (car b))) (reverse complaints)))))
      (list (and (null? texts) (pair? blocks)
                 (program-text name (reverse items) import-spec))
            texts)))

  ;; program-text : String (Listof (List Boolean Form String)) (U Sexp #f) -> String
  ;; The program for the page NAME: its import, the check's definitions, then
  ;; each of ITEMS, which is a form, the text of the block it came from and
  ;; whether its result is checked; a checked form is wrapped.
  (define (program-text name items import-spec)
    (let* ((specs (if import-spec (cdr import-spec) '()))
           (specs (if (member '(rnrs) specs) specs (cons '(rnrs) specs))))
      (string-append
       (written (cons 'import specs)) "\n"
       (apply string-append (map (lambda (d) (string-append (written d) "\n")) doc-prelude))
       (apply string-append
              (map (lambda (item)
                     (let* ((f (cadr item))
                            (form-text (substring (caddr item) (vector-ref f 3) (vector-ref f 4)))
                            (result (vector-ref f 5)))
                       (if (car item)
                           (string-append "(%doc-check " (written name) " "
                                          (number->string (car result)) " "
                                          (if (cadr result) "#t" "#f") " "
                                          (written (caddr result))
                                          " (lambda () " form-text "))\n")
                           (string-append form-text "\n"))))
                   items))
       "(%doc-finish " (written name) ")\n")))

  ;; --- the files -----------------------------------------------------------------

  ;; ensure-dir : String -> Void
  ;; Makes the directory PATH when it does not exist.
  (define (ensure-dir path)
    (unless (file-exists? path) (mkdir path)))

  ;; write-text : String String -> Void
  ;; Writes TEXT to the file at PATH as UTF-8, replacing what was there.
  (define (write-text path text)
    (call-with-port (open-file-output-port path (file-options no-fail) (buffer-mode block)
                                           (make-transcoder (utf-8-codec) (eol-style lf)))
      (lambda (port) (put-string port text))))

  ;; refusal-program : (Listof String) -> String
  ;; The program that stands for a refused page: it writes each of COMPLAINTS,
  ;; a line apiece, to stderr and exits 1, so a lane reports the page as failed.
  (define (refusal-program complaints)
    (string-append
     "(import (rnrs))\n"
     "(let ((p (current-error-port)))\n"
     "  (for-each (lambda (c) (put-string p c) (put-char p #\\newline)) '"
     (written complaints) ")\n"
     "  (flush-output-port p))\n"
     "(exit 1)\n"))

  ;; write-programs : String String -> (Listof String)
  ;; Writes the program of each DOCS-DIR/PAGE.md that has one to
  ;; OUT-DIR/PAGE.sps, after removing every *.sps from OUT-DIR, which it makes
  ;; if it is missing. A page that is refused gets a program that writes its
  ;; complaints to stderr and exits 1. Answers the complaints of every page, in
  ;; page order.
  (define (write-programs docs-dir out-dir)
    (ensure-dir out-dir)
    (for-each (lambda (f)
                (when (suffix? ".sps" f) (delete-file (string-append out-dir "/" f))))
              (directory-list out-dir))
    (let ((pages (sort string<? (filter (lambda (f) (suffix? ".md" f))
                                        (directory-list docs-dir)))))
      (apply append
             (map (lambda (page)
                    (let* ((answer (page-program page (file-text (string-append docs-dir "/" page))))
                           (program (or (car answer)
                                        (and (pair? (cadr answer))
                                             (refusal-program (cadr answer))))))
                      (when program
                        (write-text (string-append out-dir "/"
                                                   (substring page 0 (- (string-length page) 3))
                                                   ".sps")
                                    program))
                      (cadr answer)))
                  pages)))))
