#!r6rs
;;; (unique-id system): the system's clock and entropy, and what is made of
;;; them.
;;;
;;;   system-clock                  the Unix time in milliseconds
;;;   system-entropy                fresh random bytes from /dev/urandom
;;;   make-system-uuid-generator    a generator over the two
;;;   make-system-uuid-hash         a keyed hash under a fresh random key
;;;
;;; Every call of system-entropy that reads opens its own unbuffered
;;; /dev/urandom port, and closes it before it returns. A forked child reads again whatever its
;;; parent's port had buffered, and a buffered port reads thousands of bytes
;;; to answer 16; a port that outlived the call could be shared by two
;;; threads. The clock reads SRFI-19's time-utc, which is the Unix time:
;;; time-monotonic and time-tai run 37 seconds ahead of it.
;;; Needs /dev/urandom: Linux and macOS. Plain R6RS, importing (rnrs),
;;; SRFI-19 and the two libraries of this package.
(library (unique-id system)
  (export system-clock system-entropy
          make-system-uuid-generator make-system-uuid-hash)
  (import (rnrs)
          (only (srfi :19) current-time time-utc time-second time-nanosecond)
          (unique-id)
          (unique-id generator))

  ;; system-clock : -> Nat
  ;; The Unix time in milliseconds: the second of SRFI-19's time-utc times
  ;; 1000, plus its nanosecond div 1000000.
  (define (system-clock)
    (let ((t (current-time time-utc)))
      (+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))))

  ;; system-entropy : Nat -> Bytevector
  ;; A fresh bytevector of N random bytes from /dev/urandom, which no one else
  ;; holds. N not an exact nonnegative integer is an assertion violation. When
  ;; the read answers anything but N bytes, an error whose irritant is that
  ;; answer.
  (define (system-entropy n)
    (unless (and (integer? n) (exact? n) (>= n 0))
      (assertion-violation 'system-entropy "not an exact nonnegative integer"
                           n))
    (if (= n 0)
        (make-bytevector 0)
        (let ((port #f))
          ;; dynamic-wind's after thunk closes the port whether the read
          ;; returns or raises.
          (let ((bytes (dynamic-wind
                        (lambda () #f)
                        (lambda ()
                          (set! port (open-file-input-port
                                      "/dev/urandom" (file-options)
                                      (buffer-mode none)))
                          (get-bytevector-n port n))
                        (lambda () (when port (close-port port))))))
            (if (and (bytevector? bytes) (= (bytevector-length bytes) n))
                bytes
                (error 'system-entropy "short read from /dev/urandom"
                       bytes))))))

  ;; make-system-uuid-generator : -> Generator
  ;; A new generator over system-clock and system-entropy.
  (define (make-system-uuid-generator)
    (make-uuid-generator system-clock system-entropy))

  ;; make-system-uuid-hash : -> (Uuid -> Nat)
  ;; make-uuid-hash under a new 8-byte key from system-entropy. Its procedure
  ;; raises as make-uuid-hash's does, with who make-uuid-hash.
  (define (make-system-uuid-hash)
    (make-uuid-hash (system-entropy 8))))
