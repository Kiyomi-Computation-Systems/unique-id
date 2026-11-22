#!r6rs
;;; (unique-id-checks): the rules make check-suites, make check-imports and
;;; make check-tests hold, as procedures that answer complaints.
;;;
;;; A Complaint is (list PATH RULE DETAIL): the file it is about, a symbol
;;; naming the rule it breaks, and a sentence for a person. The programs
;;; tools/check-suites.sps and tools/check-imports.sps print the details and
;;; set the exit status; the suites assert the paths and the rules.
;;;
;;; It also holds what the audits' suites share: written, describe and
;;; run-check.
;;;
;;; Tooling, not a suite library: it lives in tools/, which only the tools
;;; lane puts on its library path, and it uses Chez's own procedures. Its
;;; suites are tools/test-check-suites.sps, tools/test-check-imports.sps,
;;; tools/test-check-tests.sps and tools/test-unique-id-checks.sps.
(library (unique-id-checks)
  (export suite-complaints import-complaints library-files suite-tree-complaints suite-tree-files
          written describe run-check)
  (import (rnrs)
          (unique-id-testing)
          (only (chezscheme) directory-list display-condition file-directory? file-regular?
                get-process-id getenv mkdir sort system))

  ;; written : Any -> String
  ;; DATUM as `write` writes it.
  (define (written datum)
    (call-with-string-output-port (lambda (p) (write datum p))))

  ;; describe : Any -> String
  ;; A condition as Chez displays it, anything else as `write` writes it.
  ;; Evidence for a test's expected value, never raising itself.
  (define (describe obj)
    (guard (e (#t "<the raised object could not be printed>"))
      (call-with-string-output-port
       (lambda (p)
         (if (condition? obj) (display-condition obj p) (write obj p))))))

  ;; --- run-check -----------------------------------------------------------

  ;; run-check : String (Listof String) -> (List Integer String String)
  ;; Runs PROGRAM with ARGS as `$CHEZ --libdirs $TOOL_LIBDIRS --program`,
  ;; from the current directory, with stdin from /dev/null. The answer is the
  ;; exit status, then all it wrote to stdout and to stderr, as UTF-8. A
  ;; non-zero exit is an answer, not a raise, so a test compares the whole
  ;; list with what it expects.
  ;;
  ;; CHEZ and TOOL_LIBDIRS come from the environment, which the Makefile
  ;; exports; it raises when either is missing. Each word reaches the shell
  ;; single-quoted, so it arrives as one argument, unchanged. The two streams
  ;; go through files under build/run-check/, named for this process and a
  ;; count, and removed once read.
  (define (run-check program args)
    (let ((chez (required-env "CHEZ"))
          (libdirs (required-env "TOOL_LIBDIRS")))
      (let* ((stem (next-capture-stem))
             (out (string-append stem ".out"))
             (err (string-append stem ".err"))
             (words (append (list chez "--libdirs" libdirs "--program" program) args))
             (command (string-append (join (map shell-quote words) " ")
                                     " </dev/null >" (shell-quote out)
                                     " 2>" (shell-quote err)))
             (status (system command))
             (stdout (slurp out))
             (stderr (slurp err)))
        (for-each delete-file (list out err))
        (list status stdout stderr))))

  (define (required-env name)
    (let ((value (getenv name)))
      (unless (and value (positive? (string-length value)))
        (assertion-violation 'run-check
          (string-append name " is not set: run the suites through make test")
          name))
      value))

  (define capture-dir "build/run-check")

  ;; The count makes each name this process asks for its own; the process id
  ;; keeps two suites at once apart.
  (define next-capture-stem
    (let ((count 0))
      (lambda ()
        (unless (file-exists? "build") (mkdir "build"))
        (unless (file-exists? capture-dir) (mkdir capture-dir))
        (set! count (+ count 1))
        (string-append capture-dir "/" (number->string (get-process-id))
                       "-" (number->string count)))))

  (define (shell-quote word)
    (string-append
     "'"
     (apply string-append
            (map (lambda (c) (if (char=? c #\') "'\\''" (string c)))
                 (string->list word)))
     "'"))

  (define (join words sep)
    (if (null? words)
        ""
        (fold-left (lambda (acc w) (string-append acc sep w)) (car words) (cdr words))))

  (define (slurp path)
    (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                          (make-transcoder (utf-8-codec)))
      get-string-all-or-empty))

  (define (get-string-all-or-empty port)
    (let ((s (get-string-all port)))
      (if (eof-object? s) "" s)))

  ;; --- check-suites --------------------------------------------------------

  ;; suite-complaints : String -> (Listof Complaint)
  ;; What is wrong with the suite at PATH, read as data with Chez's reader:
  ;;
  ;;   no-datum    it holds no datum at all
  ;;   last-datum  its last datum is not exactly suite-exit-form
  ;;   early-exit  a datum before the last holds an exit form other than
  ;;               (exit 1), however deeply nested: it would end the suite
  ;;               before its verdict
  ;;   unreadable  the reader raised
  ;;
  ;; The last datum's complaint comes first, then each early exit in order.
  ;; Reading data, not text, is the point: an exit form in a comment or a
  ;; string is no datum. Data is all it sees, so a quoted '(exit 0) is an
  ;; early exit too: build such a list another way.
  (define (suite-complaints path)
    (let ((found (read-file-data path))
          (form (written suite-exit-form)))
      (case (car found)
        ((data)
         (let ((data (cadr found)))
           (if (null? data)
               (list (list path 'no-datum
                           (string-append "it holds no datum, so it cannot end with " form)))
               (append
                (let ((last (car (reverse data))))
                  (if (equal? last suite-exit-form)
                      '()
                      (list (list path 'last-datum
                                  (string-append "its last datum is " (written last)
                                                 ", not " form)))))
                (map (lambda (exit-form)
                       (list path 'early-exit
                             (string-append (written exit-form)
                                            " before the last datum would end the suite"
                                            " before its verdict; only (exit 1) may exit early")))
                     (apply append (map early-exits (all-but-last data))))))))
        (else
         (list (list path 'unreadable
                     (string-append "it cannot be read as data: " (cadr found))))))))

  ;; early-exits : Any -> (Listof (Pair Symbol Any))
  ;; Every list in DATUM, DATUM itself and each list nested in it, in a list
  ;; or a vector, whose car is the symbol exit and which is not exactly
  ;; (exit 1), in the order they appear. It visits a list's elements, never
  ;; its tails: in '(quit exit) the tail (exit) is no exit form. It visits a
  ;; vector's elements because quasiquote runs code inside one: `#(,(exit 0)).
  (define (early-exits datum)
    (cond
      ((pair? datum)
       (append (if (and (eq? (car datum) 'exit) (not (equal? datum '(exit 1))))
                   (list datum)
                   '())
               (let walk ((rest datum))
                 (cond ((pair? rest) (append (early-exits (car rest)) (walk (cdr rest))))
                       ((vector? rest) (early-exits rest))
                       (else '())))))
      ((vector? datum) (apply append (map early-exits (vector->list datum))))
      (else '())))

  (define (all-but-last xs)
    (reverse (cdr (reverse xs))))

  ;; --- check-imports -------------------------------------------------------

  ;; import-complaints : String -> (Listof Complaint)
  ;; What keeps the tree at ROOT from being plain R6RS libraries that import
  ;; only (rnrs ...) and (unique-id ...), and (srfi :19) in (unique-id
  ;; system) alone. Each complaint's path is relative to
  ;; ROOT; "." is ROOT itself. The rules, for each file in path order:
  ;;
  ;;   not-regular   a link or anything else that is not a regular file or a
  ;;                 directory
  ;;   file-name     not named STEM.sls with no other dot: Chez prefers
  ;;                 STEM.chezscheme.sls and STEM.ss to STEM.sls, and Guile
  ;;                 STEM.guile.sls, so any of them would shadow the portable
  ;;                 file, and anything else is no library
  ;;   unreadable    not UTF-8, or the reader raised
  ;;   header        its first line is not exactly #!r6rs
  ;;   hash-bang     #! appears after the first line: #!chezscheme there
  ;;                 would switch the reader to Chez's syntax
  ;;   library-form  it is not exactly one (library NAME (export ...)
  ;;                 (import ...) ...) form
  ;;   name          NAME is not the one its path gives, or carries a version
  ;;   import        an import names a library outside (rnrs ...) and
  ;;                 (unique-id ...), however it is wrapped, but for one
  ;;                 that extra-imports allows the importing library; names
  ;;                 (rnrs eval), whose environment reaches any library at
  ;;                 run time; names a (unique-id ...) library no file under
  ;;                 ROOT holds, which would load from elsewhere on the path;
  ;;                 or cannot be read
  ;;
  ;; and then, for ROOT itself, not-a-directory, or no-library when no file
  ;; is named as a library. Litter an OS or an editor leaves is passed over
  ;; (litter?).
  (define (import-complaints root)
    (if (not (directory? root))
        (list (list "." 'not-a-directory (string-append root " is not a directory")))
        (let* ((entries (walk root ""))
               (names (map (lambda (e) (path->library-name (car e)))
                           (library-entries entries)))
               (complaints
                (apply append
                       (map (lambda (entry)
                              (let ((rel (car entry)) (kind (cdr entry)))
                                (cond
                                  ((not (eq? kind 'file))
                                   (list (list rel 'not-regular
                                               "it is neither a regular file nor a directory")))
                                  ((not (library-file-name? rel))
                                   (list (list rel 'file-name
                                               "a file under src/ is named STEM.sls, with no other dot")))
                                  (else (library-complaints root rel (src-policy names))))))
                            entries))))
          (if (null? (library-entries entries))
              (append complaints
                      (list (list "." 'no-library "it holds no file named as a library")))
              complaints))))

  ;; library-files : String -> (Listof String)
  ;; The paths, relative to ROOT, of the files under it named as libraries.
  (define (library-files root)
    (if (directory? root)
        (map car (library-entries (walk root "")))
        '()))

  (define (library-entries entries)
    (filter (lambda (e) (and (eq? (cdr e) 'file) (library-file-name? (car e))))
            entries))

  ;; A link to a directory is no directory here: links are not followed.
  (define (directory? path)
    (file-directory? path #f))

  ;; walk : String String -> (Listof (Pair String (U 'file 'other)))
  ;; Every entry under ROOT/REL that is neither a directory nor litter, with
  ;; its path relative to ROOT, sorted by that path: unique-id.sls comes
  ;; before unique-id/private.sls. Links are not followed: a link is 'other.
  (define (walk root rel)
    (sort (lambda (a b) (string<? (car a) (car b)))
          (walk-unsorted root rel)))

  (define (walk-unsorted root rel)
    (let ((dir (if (string=? rel "") root (string-append root "/" rel))))
      (apply append
             (map (lambda (name)
                    (let ((child-rel (if (string=? rel "") name (string-append rel "/" name)))
                          (full (string-append dir "/" name)))
                      (cond
                        ((file-directory? full #f) (walk-unsorted root child-rel))
                        ((litter? name) '())
                        ((file-regular? full #f) (list (cons child-rel 'file)))
                        (else (list (cons child-rel 'other))))))
                  (directory-list dir)))))

  ;; litter? : String -> Boolean
  ;; A file name an OS or an editor leaves beside the sources: a dot file,
  ;; such as .DS_Store or Emacs's .#NAME lock link; an #autosave#; a backup~.
  ;; Passing over a dot file is safe though Chez can load one, under an
  ;; escaped name such as (unique-id \x2E;hidden): the import rule takes the
  ;; (unique-id ...) names a library may import from the files it counts, and
  ;; it never counts litter. Directories are walked whatever their names.
  (define (litter? name)
    (let ((n (string-length name)))
      (and (> n 0)
           (or (char=? (string-ref name 0) #\.)
               (char=? (string-ref name 0) #\#)
               (char=? (string-ref name (- n 1)) #\~)))))

  ;; file-name-with? : String String -> Boolean
  ;; Whether REL's last component is STEM followed by EXT, four characters
  ;; long, with no dot in STEM.
  (define (file-name-with? rel ext)
    (let* ((base (last-component rel))
           (n (string-length base)))
      (and (> n 4)
           (string=? (substring base (- n 4) n) ext)
           (not (memv #\. (string->list (substring base 0 (- n 4))))))))

  (define (library-file-name? rel) (file-name-with? rel ".sls"))

  (define (program-file-name? rel) (file-name-with? rel ".sps"))

  (define (last-component rel)
    (let loop ((i (- (string-length rel) 1)))
      (cond ((< i 0) rel)
            ((char=? (string-ref rel i) #\/) (substring rel (+ i 1) (string-length rel)))
            (else (loop (- i 1))))))

  ;; split : String Char -> (Listof String)
  (define (split s c)
    (let loop ((i 0) (start 0) (parts '()))
      (cond ((= i (string-length s))
             (reverse (cons (substring s start i) parts)))
            ((char=? (string-ref s i) c)
             (loop (+ i 1) (+ i 1) (cons (substring s start i) parts)))
            (else (loop (+ i 1) start parts)))))

  ;; The library name REL's path gives: "unique-id/private.sls" is
  ;; (unique-id private).
  (define (path->library-name rel)
    (let* ((parts (split rel #\/))
           (base (car (reverse parts)))
           (stem (substring base 0 (- (string-length base) 4))))
      (map string->symbol (append (all-but-last parts) (list stem)))))

  ;; A Policy is a procedure of a file's path and a library reference, other
  ;; than (rnrs ...), that answers the complaints importing it earns:
  ;; (String Library-Name -> (Listof Complaint)).

  ;; source-complaints : String String (String (Listof Any) -> (Listof Complaint))
  ;;                     -> (Listof Complaint)
  ;; The reading, header and #! rules for the file at ROOT/REL, then what
  ;; FORMS complains of in the data it holds, when it can be read.
  (define (source-complaints root rel forms)
    (let ((text (read-file-text (string-append root "/" rel))))
      (if (not (string? text))
          (list (list rel 'unreadable (string-append "it cannot be read as UTF-8: " (cadr text))))
          (let* ((newline-at (string-index text #\newline))
                 (first-line (if newline-at (substring text 0 newline-at) text))
                 (rest (if newline-at
                           (substring text (+ newline-at 1) (string-length text))
                           "")))
            (append
             (if (string=? first-line "#!r6rs")
                 '()
                 (list (list rel 'header
                             (string-append "its first line is " (written first-line)
                                            ", not \"#!r6rs\""))))
             (if (string-contains? rest "#!")
                 (list (list rel 'hash-bang
                             "#! appears after the first line; only the #!r6rs header may use it"))
                 '())
             (let ((found (read-string-data text)))
               (if (eq? (car found) 'unreadable)
                   (list (list rel 'unreadable
                               (string-append "it cannot be read as data: " (cadr found))))
                   (forms rel (cadr found)))))))))

  ;; library-complaints : String String Policy -> (Listof Complaint)
  (define (library-complaints root rel policy)
    (source-complaints root rel
                       (lambda (rel data) (library-form-complaints rel data policy))))

  ;; program-complaints : String String Policy -> (Listof Complaint)
  (define (program-complaints root rel policy)
    (source-complaints root rel
                       (lambda (rel data) (program-form-complaints rel data policy))))

  (define (library-form-complaints rel data policy)
    (let ((form (and (= (length data) 1) (car data))))
      (if (not (library-form? form))
          (list (list rel 'library-form
                      (string-append "it holds " (number->string (length data))
                                     " data; a .sls file holds one"
                                     " (library NAME (export ...) (import ...) ...) form")))
          (append (name-complaints rel (cadr form))
                  (apply append (map (lambda (spec) (import-spec-complaints rel spec policy))
                                     (cdr (cadddr form))))))))

  ;; A program's first datum is its import form; what follows is its body.
  (define (program-form-complaints rel data policy)
    (let ((form (and (pair? data) (car data))))
      (if (not (and (list? form) (pair? form) (eq? (car form) 'import)))
          (list (list rel 'program-form
                      "its first datum is not (import ...); a suite is an R6RS top-level program"))
          (apply append (map (lambda (spec) (import-spec-complaints rel spec policy))
                             (cdr form))))))

  (define (library-form? form)
    (and (list? form)
         (>= (length form) 4)
         (eq? (car form) 'library)
         (list? (caddr form)) (pair? (caddr form)) (eq? (car (caddr form)) 'export)
         (list? (cadddr form)) (pair? (cadddr form)) (eq? (car (cadddr form)) 'import)))

  (define (name-complaints rel name)
    (let ((expected (path->library-name rel)))
      (cond
        ((not (and (list? name) (pair? name)))
         (list (list rel 'name (string-append "its name " (written name) " is not a list"))))
        ((not (for-all symbol? name))
         (list (list rel 'name (string-append "its name " (written name)
                                              " carries a version; name it "
                                              (written expected)))))
        ((not (equal? name expected))
         (list (list rel 'name (string-append "it declares " (written name)
                                              ", but its path makes it " (written expected)))))
        (else '()))))

  ;; extra-imports : (Listof (Pair Library-Name (Listof Library-Name)))
  ;; Each library under src/ that may import more than (rnrs ...) and
  ;; (unique-id ...), by the name its path gives, and the libraries it may
  ;; import besides. (unique-id system) reads the clock, which (rnrs) cannot.
  (define extra-imports
    '(((unique-id system) (srfi :19))))

  ;; allowed-elsewhere : Library-Name -> (U Library-Name #f)
  ;; The library extra-imports lets import REF, or #f when none may.
  (define (allowed-elsewhere ref)
    (let loop ((entries extra-imports))
      (cond ((null? entries) #f)
            ((member ref (cdar entries)) (caar entries))
            (else (loop (cdr entries))))))

  (define not-allowed
    (string-append "; a library under src/ imports only (rnrs ...) and (unique-id ...),"
                   " and (unique-id system) (srfi :19) too"))

  ;; import-spec-complaints : String Any Policy -> (Listof Complaint)
  ;; What importing SPEC earns the file at REL: a complaint when SPEC cannot
  ;; be read or names (rnrs eval), nothing for the rest of (rnrs ...), and
  ;; POLICY's answer for anything else.
  (define (import-spec-complaints rel spec policy)
    (let ((ref (import-reference spec)))
      (cond
        ((not ref)
         (list (list rel 'import (string-append "it cannot read the import spec " (written spec)))))
        ((and (eq? (car ref) 'rnrs) (pair? (cdr ref)) (eq? (cadr ref) 'eval))
         (list (list rel 'import
                     (string-append "it imports " (written ref)
                                    ", whose environment reaches any library at run time"))))
        ((eq? (car ref) 'rnrs) '())
        (else (policy rel ref)))))

  ;; missing-library : String Library-Name -> (Listof Complaint)
  (define (missing-library rel ref)
    (list (list rel 'import
                (string-append "it imports " (written ref) ", which no file under src/ holds"))))

  ;; src-policy : (Listof Library-Name) -> Policy
  ;; A library under src/ may import the (unique-id ...) libraries in NAMES,
  ;; the names the files under src/ give by their paths, and what
  ;; extra-imports allows it.
  (define (src-policy names)
    (lambda (rel ref)
      (let ((extra (cond ((assoc (path->library-name rel) extra-imports) => cdr)
                         (else '()))))
        (cond
          ((eq? (car ref) 'unique-id)
           (if (member ref names) '() (missing-library rel ref)))
          ((member ref extra) '())
          ((allowed-elsewhere ref)
           => (lambda (owner)
                (list (list rel 'import
                            (string-append "it imports " (written ref) ", which only "
                                           (written owner) " may import")))))
          (else
           (list (list rel 'import
                       (string-append "it imports " (written ref) not-allowed))))))))

  ;; tests-policy : (Listof Library-Name) (Listof Library-Name) -> Policy
  ;; A file under tests/ may import (srfi :64), the (unique-id ...) libraries
  ;; in SRC-NAMES, and the libraries in TEST-NAMES, those under tests/.
  (define (tests-policy src-names test-names)
    (lambda (rel ref)
      (cond
        ((equal? ref '(srfi :64)) '())
        ((eq? (car ref) 'unique-id)
         (if (member ref src-names) '() (missing-library rel ref)))
        ((member ref test-names) '())
        (else
         (list (list rel 'import
                     (string-append "it imports " (written ref)
                                    "; a file under tests/ imports only (rnrs ...), (srfi :64),"
                                    " (unique-id ...) and the libraries under tests/")))))))

  ;; --- check-tests ---------------------------------------------------------

  ;; suite-tree-complaints : String String -> (Listof Complaint)
  ;; What keeps the tree at TESTS from being plain R6RS that both lanes load
  ;; alike, given the library tree at SRC. Each complaint's path is relative
  ;; to TESTS; "." is TESTS itself. The rules, for each file in path order:
  ;;
  ;;   not-regular   a link or anything else that is not a regular file or a
  ;;                 directory
  ;;   file-name     not named STEM.sls or STEM.sps with no other dot: Guile
  ;;                 loads STEM.guile.sls before STEM.sls, and Chez
  ;;                 STEM.chezscheme.sls and STEM.ss, so the two lanes would
  ;;                 load different files
  ;;   shadow        a .sls named (unique-id ...) by its path: such a library
  ;;                 belongs under src/
  ;;
  ;; then, for a .sls, import-complaints' rules for a library, and for a
  ;; .sps, unreadable, header and hash-bang as for a library, and:
  ;;
  ;;   program-form  its first datum is not (import ...)
  ;;   import        an import names (rnrs eval), or a library other than
  ;;                 (rnrs ...), (srfi :64), the (unique-id ...) libraries
  ;;                 under SRC and the libraries under TESTS, however it is
  ;;                 wrapped; or cannot be read
  ;;
  ;; and, for TESTS itself, not-a-directory. Litter is passed over, as by
  ;; import-complaints. SRC need not exist: then no (unique-id ...) library
  ;; may be imported.
  (define (suite-tree-complaints tests src)
    (if (not (directory? tests))
        (list (list "." 'not-a-directory (string-append tests " is not a directory")))
        (let* ((entries (walk tests ""))
               (policy (tests-policy (map path->library-name (library-files src))
                                     (map (lambda (e) (path->library-name (car e)))
                                          (library-entries entries)))))
          (apply append
                 (map (lambda (entry)
                        (let ((rel (car entry)) (kind (cdr entry)))
                          (cond
                            ((not (eq? kind 'file))
                             (list (list rel 'not-regular
                                         "it is neither a regular file nor a directory")))
                            ((library-file-name? rel)
                             (append
                              (if (eq? (car (path->library-name rel)) 'unique-id)
                                  (list (list rel 'shadow
                                              (string-append "its path names it "
                                                             (written (path->library-name rel))
                                                             "; a (unique-id ...) library belongs under src/")))
                                  '())
                              (library-complaints tests rel policy)))
                            ((program-file-name? rel)
                             (program-complaints tests rel policy))
                            (else
                             (list (list rel 'file-name
                                         "a file under tests/ is named STEM.sls or STEM.sps, with no other dot"))))))
                      entries)))))

  ;; suite-tree-files : String -> (Listof String)
  ;; The paths, relative to ROOT, of the files under it named as libraries or
  ;; programs.
  (define (suite-tree-files root)
    (if (directory? root)
        (map car (filter (lambda (e)
                           (and (eq? (cdr e) 'file)
                                (or (library-file-name? (car e)) (program-file-name? (car e)))))
                         (walk root "")))
        '()))

  ;; import-reference : Any -> (U (Listof Any) #f)
  ;; The library reference an import spec names, through for, library, only,
  ;; except, prefix and rename however deeply, or #f when SPEC has no such
  ;; shape. A reference is a list whose first element is a symbol.
  (define (import-reference spec)
    (define (reference r)
      (and (list? r) (pair? r) (symbol? (car r)) r))
    (define (from-set s)
      (and (list? s) (pair? s)
           (case (car s)
             ((library) (and (= (length s) 2) (reference (cadr s))))
             ((only except prefix rename) (and (>= (length s) 2) (from-set (cadr s))))
             (else (reference s)))))
    (if (and (list? spec) (pair? spec) (eq? (car spec) 'for))
        (and (>= (length spec) 2) (from-set (cadr spec)))
        (from-set spec)))

  ;; --- reading -------------------------------------------------------------

  (define (strict-utf-8)
    (make-transcoder (utf-8-codec) (eol-style none) (error-handling-mode raise)))

  ;; read-file-text : String -> (U String (List 'unreadable String))
  (define (read-file-text path)
    (guard (e (#t (list 'unreadable (describe e))))
      (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                            (strict-utf-8))
        (lambda (port)
          (let ((s (get-string-all port)))
            (if (eof-object? s) "" s))))))

  ;; read-file-data : String -> (U (List 'data (Listof Any)) (List 'unreadable String))
  (define (read-file-data path)
    (let ((text (read-file-text path)))
      (if (string? text)
          (read-string-data text)
          text)))

  (define (read-string-data text)
    (guard (e (#t (list 'unreadable (describe e))))
      (let ((port (open-string-input-port text)))
        (let loop ((found '()))
          (let ((datum (read port)))
            (if (eof-object? datum)
                (list 'data (reverse found))
                (loop (cons datum found))))))))

  (define (string-index s c)
    (let loop ((i 0))
      (cond ((= i (string-length s)) #f)
            ((char=? (string-ref s i) c) i)
            (else (loop (+ i 1))))))

  (define (string-contains? s needle)
    (let ((n (string-length s)) (m (string-length needle)))
      (let loop ((i 0))
        (cond ((> (+ i m) n) #f)
              ((string=? (substring s i (+ i m)) needle) #t)
              (else (loop (+ i 1))))))))
