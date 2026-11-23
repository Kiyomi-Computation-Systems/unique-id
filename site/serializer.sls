#!r6rs
;; PURE. Imports no library that loads a shared object.
(library (site serializer)
  (export sxml->html)
  (import (rnrs))

  ;; SXML is a Sexp: a string, or a list of a tag symbol, an optional
  ;; (^ (NAME VALUE) ...) attribute list and the child SXML. (*TOP* NODE ...)
  ;; is a document, and (*COMMENT* TEXT) a comment.

  (define void-tags
    '(area base br col embed hr img input link meta param source track wbr))

  ;; void? : Symbol -> Boolean
  ;; Whether the element TAG has no end tag.
  (define (void? tag) (and (memq tag void-tags) #t))

  ;; escape-text : String -> String
  ;; S with &, < and > written as entities.
  (define (escape-text s)
    (escape s '((#\& . "&amp;") (#\< . "&lt;") (#\> . "&gt;"))))

  ;; escape-attr : String -> String
  ;; S with &, <, > and " written as entities.
  (define (escape-attr s)
    (escape s '((#\& . "&amp;") (#\< . "&lt;") (#\> . "&gt;") (#\" . "&quot;"))))

  ;; escape : String (Listof (Pair Char String)) -> String
  ;; S with each character TABLE has written as the string TABLE gives.
  (define (escape s table)
    (call-with-string-output-port
     (lambda (p)
       (string-for-each
        (lambda (c)
          (cond ((assv c table) => (lambda (kv) (put-string p (cdr kv))))
                (else (put-char p c))))
        s))))

  ;; attrs-node? : Any -> Boolean
  ;; Whether X is a list that starts with an attribute list.
  (define (attrs-node? x) (and (pair? x) (pair? (car x)) (eq? (caar x) '^)))

  ;; render-attrs : SXML Port -> Void
  ;; Writes the attributes of ATTR-NODE, an attribute list, to P.
  (define (render-attrs attr-node p)
    (for-each
     (lambda (a)
       (put-string p " ") (put-string p (symbol->string (car a)))
       (put-string p "=\"") (put-string p (escape-attr (cadr a))) (put-string p "\""))
     (cdr attr-node)))

  ;; sxml->html : SXML -> String
  ;; NODE as HTML, its text and attributes escaped, and void elements with no
  ;; end tag. Raises with `error` when NODE holds anything but a string or a
  ;; list.
  (define (sxml->html node)
    (call-with-string-output-port (lambda (p) (emit node p))))

  ;; emit : SXML Port -> Void
  ;; Writes NODE as HTML to P.
  (define (emit node p)
    (cond
      ((string? node) (put-string p (escape-text node)))
      ((and (pair? node) (eq? (car node) '*TOP*))
       (for-each (lambda (k) (emit k p) (put-string p "\n")) (cdr node)))
      ((and (pair? node) (eq? (car node) '*COMMENT*))
       (put-string p "<!--") (put-string p (cadr node)) (put-string p "-->"))
      ((pair? node)
       (let* ((tag (car node))
              (rest (cdr node))
              (attr (and (pair? rest) (attrs-node? rest) (car rest)))
              (kids (if attr (cdr rest) rest)))
         (put-string p "<") (put-string p (symbol->string tag))
         (when attr (render-attrs attr p))
         (put-string p ">")
         (unless (void? tag)
           (for-each (lambda (k) (emit k p)) kids)
           (put-string p "</") (put-string p (symbol->string tag)) (put-string p ">"))))
      (else (error 'sxml->html "unrenderable node" node)))))
