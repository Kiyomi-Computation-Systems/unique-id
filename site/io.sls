#!r6rs
;; NOT pure: this library owns the generator's filesystem access.
(library (site io)
  (export read-site-inputs write-site)
  (import (rnrs) (only (chezscheme) getenv) (site pages) (site render)
          (site serializer))

  ;; slurp : String -> String
  ;; The whole text of the file at PATH.
  (define (slurp path)
    (call-with-input-file path
      (lambda (p)
        (let loop ((cs '()) (c (get-char p)))
          (if (eof-object? c)
              (list->string (reverse cs))
              (loop (cons c cs) (get-char p)))))))

  ;; docs-dir : -> String
  ;; The directory the pages are read from: the SITE_DOCS environment
  ;; variable, else docs.
  (define (docs-dir) (or (getenv "SITE_DOCS") "docs"))

  ;; source-path : String -> String
  ;; The path of the page file NAME in the docs directory.
  (define (source-path name) (string-append (docs-dir) "/" name))

  ;; read-site-inputs : -> (Listof (Pair String String))
  ;; Each source in (site pages)'s declared order, as its name and its text.
  (define (read-site-inputs)
    (map (lambda (entry)
           (let ((name (car entry))) (cons name (slurp (source-path name)))))
         pages))

  ;; write-site : SiteResult String -> Void
  ;; Writes each fully rendered page of RESULT into the directory OUT-DIR in
  ;; UTF-8, replacing a previous output.
  (define (write-site result out-dir)
    (for-each
     (lambda (pg)
       (let ((p (open-file-output-port
                 (string-append out-dir "/" (page-file-name (car pg)))
                 (file-options no-fail))))
         (put-bytevector p
                         (string->utf8
                          (string-append "<!doctype html>\n" (sxml->html (cdr pg)))))
         (close-port p)))
     (site-result-pages result))))
