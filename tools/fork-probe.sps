#!r6rs
;;; fork-probe.sps: forks, and shows what the parent and the child each draw
;;; from one system generator, from system-entropy and from a new system hash
;;; afterwards.
;;;
;;; No plain R6RS suite can fork, so tools/test-system-fork.sps runs this
;;; Chez program as a child and judges what it writes. Usage:
;;;
;;;   scheme --libdirs LIBDIRS --program tools/fork-probe.sps CHILD-FILE
;;;
;;; CHILD-FILE is where the child leaves its four values. The parent writes
;;; eight lines to stdout, in this order, and exits 0:
;;;
;;;   parent-entropy HEX    child-entropy HEX
;;;   parent-v4 ID          child-v4 ID
;;;   parent-v7 ID          child-v7 ID
;;;   parent-hash N         child-hash N
;;;
;;; N is nil-uuid hashed by a make-system-uuid-hash made after the fork.
;;;
;;; Exit 2: bad usage, a failed fork or waitpid, or a child that did not
;;; exit 0. Exit 3: no "fork" to be found. Both say why on stderr.
(import (rnrs)
        (only (chezscheme) command-line-arguments foreign-alloc foreign-entry?
              foreign-free foreign-procedure foreign-ref load-shared-object)
        (unique-id)
        (unique-id generator)
        (unique-id system))

;; fail : String Nat -> Void
;; Writes MESSAGE and a newline to stderr and exits with status CODE.
(define (fail message code)
  (let ((err (current-error-port)))
    (display message err)
    (newline err)
    (flush-output-port err)
    (exit code)))

;; Chez 10 finds no "fork" until libc is loaded. foreign-procedure looks the
;; entry up where it is evaluated, so this comes first.
(for-each (lambda (name)
            (unless (foreign-entry? "fork")
              (guard (e (#t #f)) (load-shared-object name))))
          '("libc.so.6" "libc.so" "libc.dylib"))

(unless (foreign-entry? "fork")
  (fail "fork-probe: no fork entry found in libc" 3))

;; fork : -> Integer
;; The child's pid in the parent, 0 in the child, a negative number on failure.
(define fork (foreign-procedure "fork" () int))

;; waitpid : Integer Nat Integer -> Integer
;; Waits for process PID, storing its status as an int at the address STATUS;
;; answers the pid it reaped, or a negative number on failure.
(define waitpid (foreign-procedure "waitpid" (int uptr int) int))

;; _exit : Integer -> Void
;; Ends the process with status CODE, running no exit handlers.
(define _exit (foreign-procedure "_exit" (int) void))

;; hex : Bytevector -> String
;; BYTES as lower-case hex.
(define (hex bytes)
  (apply string-append
         (map (lambda (b)
                (string-append (if (< b 16) "0" "") (string-downcase (number->string b 16))))
              (bytevector->u8-list bytes))))

;; draw : Generator -> (List String String String String)
;; 16 bytes of system entropy as hex, a v4 id and a v7 id from G, then
;; nil-uuid hashed under a new system hash, as decimal.
(define (draw g)
  (let* ((e (hex (system-entropy 16)))
         (v4 (uuid->string (generate-v4 g)))
         (v7 (uuid->string (generate-v7 g)))
         (h (number->string ((make-system-uuid-hash) nil-uuid))))
    (list e v4 v7 h)))

;; read-values : String -> (List String String String String)
;; The four lines of the child's file.
(define (read-values path)
  (call-with-port (open-file-input-port path (file-options) (buffer-mode block)
                                        (make-transcoder (utf-8-codec)))
    (lambda (p)
      (let* ((a (get-line p))
             (b (get-line p))
             (c (get-line p))
             (d (get-line p)))
        (list a b c d)))))

(define child-file
  (let ((args (command-line-arguments)))
    (unless (= (length args) 1) (fail "usage: fork-probe.sps CHILD-FILE" 2))
    (car args)))

;; A long-running server's state: entropy read, a generator made and used
;; before the fork.
(system-entropy 16)
(define g (make-system-uuid-generator))
(generate-v7 g)

;; Whatever is buffered would be written by both processes.
(flush-output-port (current-output-port))
(flush-output-port (current-error-port))

(define pid (fork))
(cond
  ((< pid 0) (fail "fork failed" 2))
  ((= pid 0)
   ;; The child writes its values and leaves without running exit handlers.
   (let ((mine (draw g)))
     (call-with-port (open-file-output-port child-file (file-options no-fail)
                                            (buffer-mode block)
                                            (make-transcoder (utf-8-codec)))
       (lambda (p)
         (for-each (lambda (s) (display s p) (newline p)) mine)))
     (_exit 0)))
  (else
   (let* ((mine (draw g))
          (status-cell (foreign-alloc 4))
          (reaped (waitpid pid status-cell 0))
          (status (foreign-ref 'int status-cell 0)))
     (foreign-free status-cell)
     (unless (= reaped pid)
       (fail (string-append "waitpid answered " (number->string reaped)
                            ", not the child " (number->string pid))
             2))
     (unless (= status 0)
       (fail (string-append "the child did not exit 0: wait status "
                            (number->string status))
             2))
     (let ((theirs (read-values child-file)))
       (let loop ((labels '("entropy" "v4" "v7" "hash")) (a mine) (b theirs))
         (unless (null? labels)
           (display (string-append "parent-" (car labels) " " (car a) "\n"))
           (display (string-append "child-" (car labels) " " (car b) "\n"))
           (loop (cdr labels) (cdr a) (cdr b))))
       (flush-output-port (current-output-port))
       (exit 0)))))
