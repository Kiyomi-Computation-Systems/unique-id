#!r6rs
;;; (unique-id): UUIDs, versions 4 and 7, as RFC 9562 defines them.
;;;
;;;   uuid?                                  is it an id
;;;   bytevector->uuid  uuid->bytevector     16 octets in and out
;;;   string->uuid  uuid->string             the canonical 36-character text
;;;   uuid-version  uuid-variant             what the bits say
;;;   uuid-v7-timestamp                      a version 7 id's milliseconds
;;;   uuid=?  uuid<?  uuid-hash              equality, order and hashing
;;;   make-uuid-hash                         a keyed hash, HalfSipHash-2-4
;;;   nil-uuid  max-uuid                     all 0 bits, all 1 bits
;;;   make-uuid-v4  make-uuid-v7             ids from the bits the caller gives
;;;
;;; An id is an opaque, sealed record of 16 octets. The library reads no clock
;;; and no entropy: every bit it does not fix is an argument. Octets are
;;; numbered 0 to 15 and bits 0 to 127, most significant first.
;;; Plain R6RS, importing (rnrs) alone.
(library (unique-id)
  (export uuid?
          bytevector->uuid uuid->bytevector
          string->uuid uuid->string
          uuid-version uuid-variant uuid-v7-timestamp
          uuid=? uuid<? uuid-hash make-uuid-hash
          nil-uuid max-uuid
          make-uuid-v4 make-uuid-v7)
  (import (rnrs))

  ;; An id: its 16 octets, which never leave the library uncopied. The record
  ;; is sealed and opaque, and its type, constructor and accessor are not
  ;; exported. It is generative: given a nongenerative uid, any program could
  ;; define the same type again, and with it make ids of any length and reach
  ;; into an id's octets. That holds within R6RS: Guile's own struct-ref, in a
  ;; program that imports (guile), still reaches them.
  (define-record-type (id make-id id?)
    (fields (immutable octets id-octets))
    (sealed #t)
    (opaque #t))

  ;; check-uuid : Symbol Any -> Void
  ;; Returns when X is an id, else an assertion violation naming WHO, with X
  ;; as its one irritant.
  (define (check-uuid who x)
    (unless (id? x)
      (assertion-violation who "not an id" x)))

  ;; check-bytes : Symbol Any Nat -> Void
  ;; Returns when X is a bytevector of LEN bytes, else an assertion violation
  ;; naming WHO, with X as its one irritant.
  (define (check-bytes who x len)
    (unless (and (bytevector? x) (= (bytevector-length x) len))
      (assertion-violation who "not a bytevector of the right length" x)))

  ;; check-nat : Symbol Any Nat -> Void
  ;; Returns when X is an exact integer from 0 to below BOUND, else an
  ;; assertion violation naming WHO, with X as its one irritant.
  (define (check-nat who x bound)
    (unless (and (integer? x) (exact? x) (<= 0 x) (< x bound))
      (assertion-violation who "not an exact integer in range" x)))

  ;; uuid? : Any -> Boolean
  ;; #t for an id, #f for anything else, a 16-byte bytevector included.
  (define (uuid? x) (id? x))

  ;; bytevector->uuid : Bytevector -> Uuid
  ;; The id whose octets are BYTES, 16 bytes. The id keeps its own copy:
  ;; changing BYTES later does not change it. Else an assertion violation.
  (define (bytevector->uuid bytes)
    (check-bytes 'bytevector->uuid bytes 16)
    (make-id (bytevector-copy bytes)))

  ;; uuid->bytevector : Uuid -> Bytevector
  ;; The id's 16 octets, octet 0 first, in a fresh bytevector. Else an
  ;; assertion violation.
  (define (uuid->bytevector id)
    (check-uuid 'uuid->bytevector id)
    (bytevector-copy (id-octets id)))

  ;; hex-value : Char -> (U Nat #f)
  ;; The value of C when it is an ASCII hex digit, 0-9, a-f or A-F, else #f.
  ;; It goes by code point: char-numeric? and string->number accept more
  ;; (other scripts' digits, signs, prefixes).
  (define (hex-value c)
    (let ((n (char->integer c)))
      (cond ((and (>= n 48) (<= n 57)) (- n 48))
            ((and (>= n 97) (<= n 102)) (- n 87))
            ((and (>= n 65) (<= n 70)) (- n 55))
            (else #f))))

  ;; string->uuid : String -> (U Uuid #f)
  ;; The id TEXT spells in the canonical 36-character form, in either case,
  ;; or #f when TEXT is any other string. An assertion violation when TEXT is
  ;; not a string.
  (define (string->uuid text)
    (unless (string? text)
      (assertion-violation 'string->uuid "not a string" text))
    (and (= (string-length text) 36)
         (let ((out (make-bytevector 16 0)))
           (let loop ((i 0) (k 0))
             (cond
               ((= i 36) (make-id out))
               ((memv i '(8 13 18 23))
                (and (char=? (string-ref text i) #\-)
                     (loop (+ i 1) k)))
               (else
                (let ((hi (hex-value (string-ref text i)))
                      (lo (hex-value (string-ref text (+ i 1)))))
                  (and hi lo
                       (begin
                         (bytevector-u8-set! out k (+ (* 16 hi) lo))
                         (loop (+ i 2) (+ k 1)))))))))))

  ;; hex-digits : String
  ;; The 16 lower-case hex digits, by value.
  (define hex-digits "0123456789abcdef")

  ;; uuid->string : Uuid -> String
  ;; The canonical form in lower case, in a fresh string. Else an assertion
  ;; violation.
  (define (uuid->string id)
    (check-uuid 'uuid->string id)
    (let ((octets (id-octets id)))
      (let loop ((k 15) (acc '()))
        (if (< k 0)
            (list->string acc)
            (let* ((b (bytevector-u8-ref octets k))
                   (acc (cons (string-ref hex-digits (div b 16))
                              (cons (string-ref hex-digits (mod b 16)) acc))))
              (loop (- k 1)
                    (if (memv k '(4 6 8 10)) (cons #\- acc) acc)))))))

  ;; uuid-version : Uuid -> (U Nat #f)
  ;; For an id of variant `rfc9562`, bits 48-51, the high 4 bits of octet 6:
  ;; 0 to 15. #f for an id of any other variant, the nil and max ids among
  ;; them: RFC 9562 defines versions for its own variant alone. Else an
  ;; assertion violation.
  (define (uuid-version id)
    (check-uuid 'uuid-version id)
    (and (eq? (uuid-variant id) 'rfc9562)
         (div (bytevector-u8-ref (id-octets id) 6) 16)))

  ;; uuid-variant : Uuid -> Symbol
  ;; From octet 8's high bits: `ncs` for 0xxx, `rfc9562` for 10xx,
  ;; `microsoft` for 110x, `future` for 111x. Else an assertion violation.
  (define (uuid-variant id)
    (check-uuid 'uuid-variant id)
    (let ((b (bytevector-u8-ref (id-octets id) 8)))
      (cond ((< b #x80) 'ncs)
            ((< b #xC0) 'rfc9562)
            ((< b #xE0) 'microsoft)
            (else 'future))))

  ;; uuid-v7-timestamp : Uuid -> (U Nat #f)
  ;; For an id of version 7 and variant `rfc9562`, octets 0-5 as a big-endian
  ;; unsigned integer: milliseconds since 1970-01-01 UTC. #f for any other
  ;; id. Else an assertion violation.
  (define (uuid-v7-timestamp id)
    (check-uuid 'uuid-v7-timestamp id)
    (and (eqv? (uuid-version id) 7)
         (bytevector-uint-ref (id-octets id) 0 (endianness big) 6)))

  ;; uuid=? : Uuid Uuid -> Boolean
  ;; #t when A and B have the same 16 octets. Else an assertion violation.
  (define (uuid=? a b)
    (check-uuid 'uuid=? a)
    (check-uuid 'uuid=? b)
    (bytevector=? (id-octets a) (id-octets b)))

  ;; uuid<? : Uuid Uuid -> Boolean
  ;; #t when A's octets come before B's, compared as unsigned bytes from
  ;; octet 0. This is the ids' order as 128-bit unsigned integers, and their
  ;; lower-case text's order under string<?. Else an assertion violation.
  (define (uuid<? a b)
    (check-uuid 'uuid<? a)
    (check-uuid 'uuid<? b)
    (let ((x (id-octets a))
          (y (id-octets b)))
      (let loop ((k 0))
        (and (< k 16)
             (let ((p (bytevector-u8-ref x k))
                   (q (bytevector-u8-ref y k)))
               (cond ((< p q) #t)
                     ((> p q) #f)
                     (else (loop (+ k 1)))))))))

  ;; uuid-hash : Uuid -> Nat
  ;; A nonnegative fixnum below 2^23, from the octets alone, for
  ;; (make-hashtable uuid-hash uuid=?). Ids that differ in one octet hash
  ;; apart. Else an assertion violation.
  ;;
  ;; R6RS promises a fixnum width of only 24 bits, sign included, so a
  ;; nonnegative fixnum is below 2^23 everywhere. The state h stays below
  ;; 2^23: each octet rotates h left by 8 within 23 bits, then xors in the
  ;; octet. Both steps are bijections of h, so a change in one octet changes
  ;; every state after it.
  (define (uuid-hash id)
    (check-uuid 'uuid-hash id)
    (let ((octets (id-octets id)))
      (let loop ((k 0) (h 0))
        (if (= k 16)
            h
            (loop (+ k 1)
                  (fxxor (fxior (fxarithmetic-shift-left (fxand h #x7FFF) 8)
                                (fxarithmetic-shift-right h 15))
                         (bytevector-u8-ref octets k)))))))

  ;; make-uuid-hash : Bytevector -> (Uuid -> Nat)
  ;; A procedure HASH such that (HASH ID) is HalfSipHash-2-4 of ID's 16
  ;; octets under KEY, 8 bytes: a number from 0 to 2^32 - 1. KEY is read at
  ;; this call, so changing it later changes no hash, and procedures made from
  ;; equal keys answer alike. Use it where an attacker may choose the ids, with
  ;; a secret KEY. HASH, given anything but an id, raises an assertion
  ;; violation whose who is make-uuid-hash. Else an assertion violation for a
  ;; KEY that is not 8 bytes.
  ;;
  ;; Arithmetic is generic, never fx: a 32-bit word is past the fixnum width
  ;; R6RS promises. Every intermediate value stays below 2^33: each sum is
  ;; masked to 32 bits, and a rotation left by b is the low 32 - b bits shifted
  ;; left by b, or'd with the word shifted right by 32 - b.
  (define (make-uuid-hash key)
    (check-bytes 'make-uuid-hash key 8)
    (let ((k0 (bytevector-u32-ref key 0 (endianness little)))
          (k1 (bytevector-u32-ref key 4 (endianness little))))
      (lambda (id)
        (unless (id? id)
          (assertion-violation 'make-uuid-hash "not an id" id))
        (halfsiphash-16 k0 k1 (id-octets id)))))

  ;; halfsiphash-16 : Nat Nat Bytevector -> Nat
  ;; HalfSipHash-2-4 with a 4-byte output of the 16 bytes IN, under the key
  ;; words K0 and K1, each below 2^32.
  (define (halfsiphash-16 k0 k1 in)
    (define mask #xFFFFFFFF)
    (define v (vector k0 k1 (bitwise-xor k0 #x6C796765)
                      (bitwise-xor k1 #x74656462)))
    (define (add a b) (bitwise-and (+ a b) mask))
    (define (rotl x b)
      (bitwise-ior
       (bitwise-arithmetic-shift-left
        (bitwise-and x (- (expt 2 (- 32 b)) 1)) b)
       (bitwise-arithmetic-shift-right x (- 32 b))))
    (define (sipround!)
      (let* ((v0 (vector-ref v 0)) (v1 (vector-ref v 1))
             (v2 (vector-ref v 2)) (v3 (vector-ref v 3))
             (v0 (add v0 v1))
             (v1 (bitwise-xor (rotl v1 5) v0))
             (v0 (rotl v0 16))
             (v2 (add v2 v3))
             (v3 (bitwise-xor (rotl v3 8) v2))
             (v0 (add v0 v3))
             (v3 (bitwise-xor (rotl v3 7) v0))
             (v2 (add v2 v1))
             (v1 (bitwise-xor (rotl v1 13) v2))
             (v2 (rotl v2 16)))
        (vector-set! v 0 v0) (vector-set! v 1 v1)
        (vector-set! v 2 v2) (vector-set! v 3 v3)))
    (define (absorb! m)
      (vector-set! v 3 (bitwise-xor (vector-ref v 3) m))
      (sipround!)
      (sipround!)
      (vector-set! v 0 (bitwise-xor (vector-ref v 0) m)))
    (do ((i 0 (+ i 1))) ((= i 4))
      (absorb! (bytevector-u32-ref in (* 4 i) (endianness little))))
    (absorb! #x10000000)
    (vector-set! v 2 (bitwise-xor (vector-ref v 2) #xFF))
    (sipround!) (sipround!) (sipround!) (sipround!)
    (bitwise-xor (vector-ref v 1) (vector-ref v 3)))

  ;; nil-uuid : Uuid
  ;; The id whose 128 bits are all 0.
  (define nil-uuid (make-id (make-bytevector 16 0)))

  ;; max-uuid : Uuid
  ;; The id whose 128 bits are all 1.
  (define max-uuid (make-id (make-bytevector 16 255)))

  ;; make-uuid-v4 : Bytevector -> Uuid
  ;; BYTES, 16 bytes, with the high 4 bits of octet 6 set to 0100 and the
  ;; high 2 bits of octet 8 set to 10. The other 122 bits are BYTES' own.
  ;; BYTES is not changed. Else an assertion violation.
  (define (make-uuid-v4 bytes)
    (check-bytes 'make-uuid-v4 bytes 16)
    (let ((out (bytevector-copy bytes)))
      (bytevector-u8-set! out 6 (+ #x40 (mod (bytevector-u8-ref out 6) 16)))
      (bytevector-u8-set! out 8 (+ #x80 (mod (bytevector-u8-ref out 8) 64)))
      (make-id out)))

  ;; make-uuid-v7 : Nat Nat Bytevector -> Uuid
  ;; MS (below 2^48) big-endian in octets 0-5. Then 0111 in the high 4 bits
  ;; of octet 6, and COUNTER (below 2^12) in the 12 bits after it, octet 6's
  ;; low 4 bits and octet 7. Then BYTES, 8 bytes, in octets 8-15, with octet
  ;; 8's high 2 bits set to 10. BYTES is not changed. Else an assertion
  ;; violation, the first argument that fails being the one raised.
  (define (make-uuid-v7 ms counter bytes)
    (check-nat 'make-uuid-v7 ms (expt 2 48))
    (check-nat 'make-uuid-v7 counter 4096)
    (check-bytes 'make-uuid-v7 bytes 8)
    (let ((out (make-bytevector 16 0)))
      (bytevector-uint-set! out 0 ms (endianness big) 6)
      (bytevector-u8-set! out 6 (+ #x70 (div counter 256)))
      (bytevector-u8-set! out 7 (mod counter 256))
      (bytevector-copy! bytes 0 out 8 8)
      (bytevector-u8-set! out 8 (+ #x80 (mod (bytevector-u8-ref out 8) 64)))
      (make-id out))))
