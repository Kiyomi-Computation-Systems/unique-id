#!r6rs
;;; make test-tools: a forked child never repeats its parent's entropy.
;;;
;;; Runs tools/fork-probe.sps as a child Chez program: it makes a system
;;; generator, forks, and has the parent and the child each draw 16 bytes
;;; from system-entropy, a v4 id and a v7 id, then makes a system hash and
;;; hashes nil-uuid. The suite asserts the probe exits 0 and writes eight
;;; well-formed lines in the order it documents, and that the parent's and
;;; the child's entropy, v4 ids, v7 ids and hashes all differ. A (unique-id
;;; system) that reads one buffered /dev/urandom port, opened when it loads,
;;; fails the first three; a hash key that is the same in every process (a
;;; counter, say) fails the last.
;;;
;;; Expected survivor: a hash key of 4 random bytes and 4 zero bytes still
;;; differs between processes, and this suite cannot tell it from a full key.
;;;
;;; No plain R6RS suite can fork, which is why it lives under tools/, on
;;; Chez alone. The Chez to run comes from the environment's CHEZ, which
;;; make exports; without it the suite fails. The probe's libraries come from
;;; FORK_LIBDIRS, else src:build/scheme-libs, so a mutation run can put a
;;; copy of (unique-id system) first:
;;;
;;;   FORK_LIBDIRS=build/mutant:src:build/scheme-libs make test-tools
(import (rnrs)
        (srfi :64)
        (unique-id-testing)
        (unique-id-checks)
        (only (chezscheme) get-process-id getenv system mkdir))

(define runner (test-runner-simple))
(test-runner-current runner)

(define probe "tools/fork-probe.sps")

;; The probe's files, named for this process, so that runs side by side,
;; as in a mutation run, never share one.
(define stem (string-append "build/fork-probe-" (number->string (get-process-id))))
(define out (string-append stem ".out"))
(define err (string-append stem ".err"))
(define child-file (string-append stem ".child"))

;; chez : (U String #f)
;; The Chez to run the probe on: $CHEZ, or #f when it is unset or empty. Not
;; falling back to scheme: on some systems another Scheme owns that name.
(define chez
  (let ((v (getenv "CHEZ")))
    (and v (positive? (string-length v)) v)))

;; libdirs : String
(define libdirs (or (getenv "FORK_LIBDIRS") "src:build/scheme-libs"))

;; quote-word : String -> String
(define (quote-word word)
  (string-append
   "'"
   (apply string-append
          (map (lambda (c) (if (char=? c #\') "'\\''" (string c)))
               (string->list word)))
   "'"))

;; slurp : String -> String
(define (slurp path)
  (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                        (make-transcoder (utf-8-codec)))
    (lambda (p)
      (let ((s (get-string-all p)))
        (if (eof-object? s) "" s)))))

;; split-lines : String -> (Listof String)
(define (split-lines s)
  (let loop ((chars (string->list s)) (cur '()) (acc '()))
    (cond ((null? chars)
           (reverse (if (null? cur) acc (cons (list->string (reverse cur)) acc))))
          ((char=? (car chars) #\newline)
           (loop (cdr chars) '() (cons (list->string (reverse cur)) acc)))
          (else (loop (cdr chars) (cons (car chars) cur) acc)))))

;; remove-files : -> Void
;; Deletes the probe's three files, so an old one is never read.
(define (remove-files)
  (for-each (lambda (f) (if (file-exists? f) (delete-file f))) (list out err child-file)))

;; run-probe : -> (List Integer String String)
;; The probe's exit status, stdout and stderr; never raises on a bad exit.
(define (run-probe)
  (unless chez
    (error 'run-probe "CHEZ is not set: run the suite through make test-tools"))
  (unless (file-exists? "build") (mkdir "build"))
  (remove-files)
  (let* ((words (list chez "--libdirs" libdirs "--program" probe child-file))
         (command (string-append
                   (apply string-append
                          (map (lambda (w) (string-append (quote-word w) " ")) words))
                   "</dev/null >" (quote-word out) " 2>" (quote-word err)))
         (status (system command))
         (o (slurp out))
         (e (slurp err)))
    (remove-files)
    (list status o e)))

;; hex? : String Nat -> Boolean
;; STR is exactly N lower-case hex digits.
(define (hex? str n)
  (and (= (string-length str) n)
       (for-all (lambda (c) (or (char<=? #\0 c #\9) (char<=? #\a c #\f)))
                (string->list str))))

;; id? : String -> Boolean
;; STR is 36 characters of lower-case hex with hyphens at 8, 13, 18, 23.
(define (id? str)
  (and (= (string-length str) 36)
       (let loop ((i 0))
         (or (= i 36)
             (let ((c (string-ref str i)))
               (and (if (memv i '(8 13 18 23))
                        (char=? c #\-)
                        (or (char<=? #\0 c #\9) (char<=? #\a c #\f)))
                    (loop (+ i 1))))))))

(define result (guard (e (#t (list 'raised (describe e)))) (run-probe)))
(define probe-ok (and (pair? result) (not (eq? (car result) 'raised))))
(define status (if probe-ok (car result) result))
(define stdout (if probe-ok (cadr result) ""))
(define stderr (if probe-ok (caddr result) ""))

;; field : String -> (U String #f)
;; The value on the stdout line labelled LABEL, or #f when no line has it.
(define (field label)
  (let loop ((lines (split-lines stdout)))
    (cond ((null? lines) #f)
          ((let ((l (car lines)) (n (+ 1 (string-length label))))
             (and (> (string-length l) n)
                  (string=? (substring l 0 n) (string-append label " "))
                  (substring l n (string-length l)))))
          (else (loop (cdr lines))))))

(define labels
  '("parent-entropy" "child-entropy" "parent-v4" "child-v4" "parent-v7" "child-v7"
    "parent-hash" "child-hash"))

;; line-label : String -> String
;; The text of LINE before its first space, or all of it.
(define (line-label line)
  (let loop ((i 0))
    (cond ((= i (string-length line)) line)
          ((char=? (string-ref line i) #\space) (substring line 0 i))
          (else (loop (+ i 1))))))

;; hash-value : String -> (U Nat #f)
;; The exact integer the field LABEL holds, below 2^32, else #f.
(define (hash-value label)
  (let* ((v (field label))
         (n (and v (> (string-length v) 0)
                 (for-all (lambda (c) (char<=? #\0 c #\9)) (string->list v))
                 (string->number v))))
    (and n (exact? n) (integer? n) (< n 4294967296) n)))

(test-begin "system-fork")

(test-equal "the probe exits 0 and writes nothing to stderr" (list 0 "") (list status stderr))

(test-equal "the probe writes eight lines, labelled in exactly this order"
  labels
  (map line-label (split-lines stdout)))

(test-equal "both entropy values are 32 hex digits"
  '(#t #t)
  (map (lambda (l) (let ((v (field l))) (and v (hex? v 32) #t)))
       '("parent-entropy" "child-entropy")))

(test-equal "all four ids are 36-character ids"
  '(#t #t #t #t)
  (map (lambda (l) (let ((v (field l))) (and v (id? v) #t)))
       '("parent-v4" "child-v4" "parent-v7" "child-v7")))

;; differ? : String String -> Boolean
;; Both fields are present and unequal.
(define (differ? a b)
  (let ((x (field a)) (y (field b)))
    (and x y (not (string=? x y)))))

(test-equal "parent and child entropy differ" #t (differ? "parent-entropy" "child-entropy"))
(test-equal "parent and child v4 ids differ" #t (differ? "parent-v4" "child-v4"))
(test-equal "parent and child v7 ids differ" #t (differ? "parent-v7" "child-v7"))

(test-equal "both hashes are exact integers below 2^32"
  '(#t #t)
  (map (lambda (l) (and (hash-value l) #t)) '("parent-hash" "child-hash")))

(test-equal "parent and child hashes of nil-uuid differ"
  #t
  (let ((a (hash-value "parent-hash")) (b (hash-value "child-hash")))
    (and a b (not (= a b)))))

(test-end "system-fork")

(exit (suite-exit-status runner))
