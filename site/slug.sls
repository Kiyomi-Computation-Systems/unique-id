#!r6rs
;; PURE. Imports no library that loads a shared object.
(library (site slug)
  (export slugify heading-text make-slugger)
  (import (rnrs))

  ;; SXML is a Sexp: a string, or a list of a tag symbol, an optional
  ;; (^ (NAME VALUE) ...) attribute list and the child SXML.

  ;; slugify : String -> String
  ;; The GitHub-style heading anchor of STR: lower case, with word
  ;; characters, hyphens and spaces kept, then each space turned to a hyphen.
  (define (slugify str)
    (list->string
     (map (lambda (c) (if (char=? c #\space) #\- c))
          (filter kept? (string->list (string-downcase str))))))

  ;; kept? : Char -> Boolean
  ;; Whether a heading anchor keeps C. Chez's char-numeric? includes circled
  ;; digits, which GitHub drops, so the general category decides.
  (define (kept? c)
    (or (char-alphabetic? c)
        (and (memq (char-general-category c) '(Mn Mc Me Nd Pc)) #t)
        (char=? c #\space)
        (char=? c #\-)))

  ;; heading-text : SXML -> String
  ;; The text descendants of NODE joined, skipping attribute nodes and tags.
  (define (heading-text node)
    (call-with-string-output-port
     (lambda (p)
       (let walk ((n node))
         (cond
           ((string? n) (put-string p n))
           ((pair? n)
            (cond ((eq? (car n) '^) #f)
                  ((symbol? (car n)) (for-each walk (cdr n)))
                  (else (for-each walk n))))
           (else #f))))))

  ;; make-slugger : -> (String -> String)
  ;; A procedure that answers each heading's anchor, numbering the duplicates
  ;; as GitHub does: -1, -2 and so on. It remembers every anchor it gave.
  (define (make-slugger)
    (let ((seen '()))
      (lambda (str)
        (let ((base (slugify str)))
          (let loop ((s base))
            (if (assoc s seen)
                (let ((n (+ 1 (cdr (assoc base seen)))))
                  (set! seen (cons (cons base n) seen))
                  (loop (string-append base "-" (number->string n))))
                (begin (set! seen (cons (cons s 0) seen)) s))))))))
