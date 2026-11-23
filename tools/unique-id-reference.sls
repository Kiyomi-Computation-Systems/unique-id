#!r6rs
;;; (unique-id-reference): the logic of make reference, which writes
;;; docs/reference.md from the signature comments in src/.
;;;
;;; reference-breaches finds the exports whose comment breaks a rule;
;;; reference-page writes the page when there are none. Both read the files
;;; (unique-id-checks)'s library-files names: the library form as data, for
;;; its name, its exports and each export's definition, and the text, for the
;;; definition's line, the comment directly above it and the file's header.
;;;
;;; A Breach is (list PATH EXPORT RULE): the file relative to the source
;;; directory, the export, and one of these rules:
;;;
;;;   no-definition  no top-level definition, in the data or in the text
;;;   no-comment     no comment directly above the definition's line
;;;   signature      the comment's first line is not `NAME : TYPE`
;;;   no-prose       nothing after the signature before a blank `;;` line
;;;
;;; Tooling, not a suite library: it lives in tools/, which only the tools
;;; lane puts on its library path. Its suite is tools/test-unique-id-reference.sps
;;; and its program tools/reference.sps.
(library (unique-id-reference)
  (export reference-breaches reference-page breach-line file-text)
  (import (rnrs)
          (unique-id-checks))

  ;; --- text ----------------------------------------------------------------

  ;; file-text : String -> String
  ;; The UTF-8 text of the file at PATH.
  (define (file-text path)
    (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                          (make-transcoder (utf-8-codec)))
      (lambda (port)
        (let ((s (get-string-all port)))
          (if (eof-object? s) "" s)))))

  ;; split-lines : String -> (Listof String)
  ;; TEXT's lines, without their newlines; a last newline ends a line and
  ;; starts none.
  (define (split-lines text)
    (let loop ((chars (string->list text)) (line '()) (acc '()))
      (cond ((null? chars)
             (reverse (if (null? line) acc (cons (list->string (reverse line)) acc))))
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

  ;; drop : String Nat -> String
  ;; S without its first N characters.
  (define (drop s n)
    (substring s n (string-length s)))

  ;; trim : String -> String
  ;; S without leading and trailing spaces.
  (define (trim s)
    (let loop-end ((end (string-length s)))
      (if (and (> end 0) (char=? (string-ref s (- end 1)) #\space))
          (loop-end (- end 1))
          (let loop-start ((start 0))
            (if (and (< start end) (char=? (string-ref s start) #\space))
                (loop-start (+ start 1))
                (substring s start end))))))

  ;; take-while : (A -> Boolean) (Listof A) -> (Listof A)
  ;; The longest prefix of ITEMS whose members all satisfy KEEP?.
  (define (take-while keep? items)
    (if (and (pair? items) (keep? (car items)))
        (cons (car items) (take-while keep? (cdr items)))
        '()))

  ;; drop-while : (A -> Boolean) (Listof A) -> (Listof A)
  ;; ITEMS without the prefix take-while keeps.
  (define (drop-while keep? items)
    (if (and (pair? items) (keep? (car items)))
        (drop-while keep? (cdr items))
        items))

  ;; sym : Symbol -> String
  (define (sym s) (symbol->string s))

  ;; library-name-text : (Listof Symbol) -> String
  ;; A library name as it is written: (unique-id generator).
  (define (library-name-text name)
    (string-append "(" (join (map sym name) " ") ")"))

  ;; --- the library form ----------------------------------------------------

  ;; A Library is (list NAME EXPORTS BODY): the name as a list of symbols, the
  ;; export list and the forms after the import clause.

  ;; read-library : String -> Library
  ;; The first datum of TEXT, which must be (library NAME (export E ...)
  ;; (import ...) FORM ...), taken apart. Else an assertion violation.
  (define (read-library text)
    (let ((form (read (open-string-input-port text))))
      (unless (and (list? form) (>= (length form) 4)
                   (eq? (car form) 'library)
                   (list? (cadr form))
                   (list? (caddr form)) (pair? (caddr form))
                   (eq? (car (caddr form)) 'export)
                   (for-all symbol? (cdr (caddr form))))
        (assertion-violation 'read-library
          "not (library NAME (export NAME ...) (import ...) ...)" form))
      (list (cadr form) (cdr (caddr form)) (cdddr (cdr form)))))

  ;; definition-of : Symbol (Listof Sexp) -> (U (Listof Any) #f)
  ;; How the top-level form of BODY that defines NAME defines it: (list
  ;; 'procedure FORMALS), the formals a list, an improper list or a symbol, or
  ;; (list 'value); #f when no form defines it.
  (define (definition-of name body)
    (cond ((null? body) #f)
          ((and (pair? (car body)) (eq? (caar body) 'define)
                (pair? (cdar body)))
           (let ((target (cadar body)))
             (cond ((and (pair? target) (eq? (car target) name))
                    (list 'procedure (cdr target)))
                   ((eq? target name) (list 'value))
                   (else (definition-of name (cdr body))))))
          (else (definition-of name (cdr body)))))

  ;; call-shape : Symbol Any -> String
  ;; (NAME FORMAL ...) for a procedure's formals; a rest argument shows as
  ;; REST ..., and no arguments as (NAME).
  (define (call-shape name formals)
    (let loop ((rest formals) (words '()))
      (cond ((null? rest)
             (string-append "(" (join (cons (sym name) (reverse words)) " ") ")"))
            ((symbol? rest) (loop '() (cons (string-append (sym rest) " ...") words)))
            (else (loop (cdr rest) (cons (sym (car rest)) words))))))

  ;; --- the text around a definition ----------------------------------------

  ;; definition-line : Symbol (Listof String) -> (U Nat #f)
  ;; The index of the first line that, after leading spaces, starts
  ;; `(define (NAME` or `(define NAME` and then has a space, a `)` or its end.
  (define (definition-line name lines)
    (let ((forms (list (string-append "(define (" (sym name))
                       (string-append "(define " (sym name)))))
      (let loop ((i 0) (rest lines))
        (cond ((null? rest) #f)
              ((defines? forms (trim-left (car rest))) i)
              (else (loop (+ i 1) (cdr rest)))))))

  ;; defines? : (Listof String) String -> Boolean
  (define (defines? forms line)
    (exists (lambda (form)
              (and (prefix? form line)
                   (or (= (string-length line) (string-length form))
                       (memv (string-ref line (string-length form)) '(#\space #\))))))
            forms))

  ;; trim-left : String -> String
  (define (trim-left s)
    (let loop ((i 0))
      (if (and (< i (string-length s)) (char=? (string-ref s i) #\space))
          (loop (+ i 1))
          (drop s i))))

  ;; comment-rest : String -> (U String #f)
  ;; What follows the `;;` of a comment line, which starts with optional
  ;; spaces then `;;` but not `;;;`; #f for any other line.
  (define (comment-rest line)
    (let ((s (trim-left line)))
      (and (prefix? ";;" s)
           (not (prefix? ";;;" s))
           (drop s 2))))

  ;; comment-above : Nat (Listof String) -> (Listof String)
  ;; The run of comment lines directly above line INDEX, top first, each as
  ;; comment-rest answers it. Empty when the line above is no comment.
  (define (comment-above index lines)
    (let loop ((i (- index 1)) (acc '()))
      (let ((rest (and (>= i 0) (comment-rest (list-ref lines i)))))
        (if rest (loop (- i 1) (cons rest acc)) acc))))

  ;; analyze-comment : Symbol (Listof String) -> (U Symbol (List String String))
  ;; The rule a comment (the answer of comment-above) breaks, signature or
  ;; no-prose; else (list SIGNATURE PROSE), the signature as one line and the
  ;; prose of the first paragraph after it as one line.
  (define (analyze-comment name run)
    (let* ((first (car run))
           (line (if (prefix? " " first) (drop first 1) first))
           (head (string-append (sym name) " : ")))
      (if (not (and (prefix? head line)
                    (positive? (string-length (trim (drop line (string-length head)))))))
          'signature
          (let* ((more (drop-while continuation? (cdr run)))
                 (continued (take-while continuation? (cdr run)))
                 (prose-lines (take-while (lambda (l) (not (string=? (trim-right l) "")))
                                          more)))
            (if (null? prose-lines)
                'no-prose
                (list (join (cons (trim-right line) (map trim continued)) " ")
                      (join (map trim prose-lines) " ")))))))

  ;; continuation? : String -> Boolean
  ;; Whether a comment line (as comment-rest answers it) goes on a signature:
  ;; it starts with two or more spaces and holds more.
  (define (continuation? rest)
    (and (prefix? "  " rest) (positive? (string-length (trim rest)))))

  ;; trim-right : String -> String
  (define (trim-right s)
    (let loop ((end (string-length s)))
      (if (and (> end 0) (char=? (string-ref s (- end 1)) #\space))
          (loop (- end 1))
          (substring s 0 end))))

  ;; --- breaches and entries ------------------------------------------------

  ;; An Entry is (list CALL-SHAPE-OR-#f SIGNATURE PROSE).

  ;; analyze-export : Symbol (Listof Sexp) (Listof String) -> (U Symbol Entry)
  ;; The rule NAME's comment breaks, or its entry.
  (define (analyze-export name body lines)
    (let* ((data (definition-of name body))
           (index (definition-line name lines)))
      (if (not (and data index))
          'no-definition
          (let ((run (comment-above index lines)))
            (if (null? run)
                'no-comment
                (let ((found (analyze-comment name run)))
                  (if (symbol? found)
                      found
                      (cons (if (eq? (car data) 'procedure)
                                (call-shape name (cadr data))
                                #f)
                            found))))))))

  ;; library-source : String String -> (List String Library (Listof String))
  ;; The file PATH of SRC-DIR: PATH, its library form and its lines.
  (define (library-source src-dir path)
    (let ((text (file-text (string-append src-dir "/" path))))
      (list path (read-library text) (split-lines text))))

  ;; reference-breaches : String -> (Listof (List String Symbol Symbol))
  ;; Every export under SRC-DIR whose comment breaks a rule, as (PATH EXPORT
  ;; RULE): PATH relative to SRC-DIR, files in library-files' order and each
  ;; file's exports in its export list's order.
  (define (reference-breaches src-dir)
    (apply append
           (map (lambda (path)
                  (let* ((source (library-source src-dir path))
                         (library (cadr source)))
                    (filter values
                            (map (lambda (name)
                                   (let ((found (analyze-export name (caddr library)
                                                                (caddr source))))
                                     (and (symbol? found) (list path name found))))
                                 (cadr library)))))
                (library-files src-dir))))

  ;; breach-line : (List String Symbol Symbol) -> String
  ;; A breach as one line for a person: PATH: EXPORT: a sentence.
  (define (breach-line breach)
    (let ((path (car breach)) (name (sym (cadr breach))) (rule (caddr breach)))
      (string-append
       path ": " name ": "
       (case rule
         ((no-definition) "no top-level definition of it is found")
         ((no-comment) "its definition has no comment directly above it")
         ((signature)
          (string-append "the first line of its comment is not `" name " : TYPE`"))
         ((no-prose) "its comment says nothing after the signature")
         (else (assertion-violation 'breach-line "unknown rule" rule))))))

  ;; --- the header ----------------------------------------------------------

  ;; header-paragraphs : (Listof Symbol) (Listof String) -> (Listof String)
  ;; The paragraphs of the run of `;;;` lines at the top of a file, after its
  ;; `#!` line: split at lines that are exactly `;;;`, each line's text joined
  ;; by single spaces. The first drops its leading `(NAME): `, and a paragraph
  ;; whose every line starts `;;;` and three spaces, the export table, is left
  ;; out.
  (define (header-paragraphs name lines)
    (let* ((below (if (and (pair? lines) (prefix? "#!" (car lines))) (cdr lines) lines))
           (run (take-while (lambda (l) (prefix? ";;;" l)) below))
           (paragraphs (split-paragraphs run))
           (lead (string-append (library-name-text name) ": ")))
      (let loop ((ps paragraphs) (first? #t) (acc '()))
        (if (null? ps)
            (reverse acc)
            (let* ((p (car ps))
                   (text (join (map (lambda (l) (trim (drop l 3))) p) " "))
                   (text (if (and first? (prefix? lead text)) (drop text (string-length lead)) text)))
              (loop (cdr ps) #f
                    (if (for-all (lambda (l) (prefix? ";;;   " l)) p)
                        acc
                        (cons text acc))))))))

  ;; split-paragraphs : (Listof String) -> (Listof (Listof String))
  ;; LINES cut at each line that is exactly `;;;`, empty paragraphs dropped.
  (define (split-paragraphs lines)
    (let loop ((rest lines) (current '()) (acc '()))
      (define (flush) (if (null? current) acc (cons (reverse current) acc)))
      (cond ((null? rest) (reverse (flush)))
            ((string=? (car rest) ";;;") (loop (cdr rest) '() (flush)))
            (else (loop (cdr rest) (cons (car rest) current) acc)))))

  ;; --- the page ------------------------------------------------------------

  ;; entry-block : Symbol Entry -> String
  ;; The section of one export.
  (define (entry-block name entry)
    (string-append
     "### `" (sym name) "`\n\n```text\n"
     (if (car entry) (string-append (car entry) "\n") "")
     (cadr entry) "\n```\n\n"
     (caddr entry)))

  ;; reference-page : String String -> String
  ;; The whole page for the libraries under SRC-DIR: HEAD, its trailing
  ;; newlines made one, then for each library in library-files' order its
  ;; heading, its header's paragraphs and an entry for each export, in the
  ;; export list's order, blocks apart by a blank line. An assertion violation
  ;; when reference-breaches finds any.
  (define (reference-page src-dir head)
    (let ((breaches (reference-breaches src-dir)))
      (unless (null? breaches)
        (assertion-violation 'reference-page
          "an export has no valid signature comment" breaches)))
    (let ((blocks
           (cons (trim-newlines head)
                 (apply append
                        (map (lambda (path)
                               (let* ((source (library-source src-dir path))
                                      (library (cadr source)))
                                 (append
                                  (list (string-append "## " (library-name-text (car library))))
                                  (header-paragraphs (car library) (caddr source))
                                  (map (lambda (name)
                                         (entry-block name (analyze-export name (caddr library)
                                                                           (caddr source))))
                                       (cadr library)))))
                             (library-files src-dir))))))
      (string-append (join blocks "\n\n") "\n")))

  ;; trim-newlines : String -> String
  ;; S without trailing newlines.
  (define (trim-newlines s)
    (let loop ((end (string-length s)))
      (if (and (> end 0) (char=? (string-ref s (- end 1)) #\newline))
          (loop (- end 1))
          (substring s 0 end))))
  )
