#!r6rs
;;; Gate the documentation sources before a Pages artifact is published. The
;;; docs directory is SITE_DOCS, else docs. It exits 1 on its first complaint.
(import (rnrs) (only (chezscheme) directory-list getenv)
        (site io) (site pages) (site links) (site render) (site serializer))

;; die : Any ... -> Void
;; Writes PARTS and a newline to the error port, and exits 1.
(define (die . parts)
  (for-each (lambda (part) (display part (current-error-port))) parts)
  (newline (current-error-port))
  (exit 1))

;; ends-with? : String String -> Boolean
;; Whether TEXT ends with SUFFIX.
(define (ends-with? suffix text)
  (let ((suffix-length (string-length suffix)) (text-length (string-length text)))
    (and (>= text-length suffix-length)
         (string=? suffix (substring text (- text-length suffix-length) text-length)))))

;; starts-with? : String String -> Boolean
;; Whether TEXT starts with PREFIX.
(define (starts-with? prefix text)
  (and (>= (string-length text) (string-length prefix))
       (string=? prefix (substring text 0 (string-length prefix)))))

;; string-search : String String Nat -> (U Nat #f)
;; The first index at or after START where NEEDLE occurs in TEXT, else #f.
(define (string-search text needle start)
  (let ((text-length (string-length text)) (needle-length (string-length needle)))
    (let loop ((at start))
      (cond ((> (+ at needle-length) text-length) #f)
            ((string=? needle (substring text at (+ at needle-length))) at)
            (else (loop (+ at 1)))))))

;; list-minus : (Listof Any) (Listof Any) -> (Listof Any)
;; The items of LEFT that RIGHT lacks.
(define (list-minus left right)
  (filter (lambda (item) (not (member item right))) left))

;; markdown-file? : String -> Boolean
;; Whether NAME is a Markdown file's name.
(define (markdown-file? name)
  (and (ends-with? ".md" name) (> (string-length name) 3)))

(define docs-dir (or (getenv "SITE_DOCS") "docs"))

;; site/pages.sls declares the complete source set and navigation order.
(define nav-docs (list-sort string<? (map car pages)))
(define disk-docs (list-sort string<? (filter markdown-file? (directory-list docs-dir))))
(define missing (list-minus nav-docs disk-docs))
(define extra (list-minus disk-docs nav-docs))
(unless (and (null? missing) (null? extra))
  (die "check-site: pages and " docs-dir " disagree; in pages.sls but not on disk="
       missing " on disk but not in pages.sls=" extra))

(define ref (or (getenv "SITE_REF") "main"))
(define inputs (read-site-inputs))
(define result (render-site inputs ref))
(unless (null? (site-result-leaked result))
  (die "check-site: unresolved documentation links: " (site-result-leaked result)))

;; link-path : String -> String
;; VALUE without its #anchor.
(define (link-path value)
  (let ((anchor (string-search value "#" 0)))
    (if anchor (substring value 0 anchor) value)))

;; attr-values : String String -> (Listof String)
;; The value of each attribute written MARKER, such as href=", found in markup
;; only. A literal source snippet is escaped as &lt;, so it cannot introduce a
;; false tag here.
(define (attr-values html marker)
  (let ((html-length (string-length html)) (marker-length (string-length marker)))
    (let loop ((at 0) (out '()) (in-tag #f))
      (cond ((> (+ at marker-length) html-length) (reverse out))
            ((char=? (string-ref html at) #\<) (loop (+ at 1) out #t))
            ((char=? (string-ref html at) #\>) (loop (+ at 1) out #f))
            ((and in-tag (string=? marker (substring html at (+ at marker-length))))
             (let* ((start (+ at marker-length))
                    (end (or (string-search html "\"" start) html-length)))
               (loop (+ end 1) (cons (substring html start end) out) #t)))
            (else (loop (+ at 1) out in-tag))))))

;; links : String -> (Listof String)
;; Every href and src value in HTML.
(define (links html)
  (append (attr-values html "href=\"") (attr-values html "src=\"")))

;; relative-markdown-link? : String -> Boolean
;; Whether VALUE is a relative link to a Markdown file.
(define (relative-markdown-link? value)
  (and (not (starts-with? "http" value))
       (or (ends-with? ".md" value)
           (string-search value ".md#" 0))))

;; A link the site pointed at the repository must name a file that exists:
;; every href that starts with the repository's blob URL at REF is that file's
;; path relative to the docs directory's parent. The rendered links are
;; checked, so a link written in either Markdown form is seen.
(define blob-prefix (string-append repo-blob ref "/"))
(for-each
 (lambda (page)
   (for-each
    (lambda (value)
      (when (starts-with? blob-prefix value)
        (let ((path (link-path (substring value (string-length blob-prefix)
                                          (string-length value)))))
          (unless (file-exists? (string-append docs-dir "/../" path))
            (die "check-site: " (car page) " links to " value
                 ", which names no file relative to " docs-dir "/..")))))
    (links (sxml->html (cdr page)))))
 (site-result-pages result))

;; Every internal Markdown link must be rewritten, and every remaining
;; relative resource must name something `make site` writes.
(define written (cons "style.css" (map (lambda (page) (page-file-name (car page))) pages)))
(for-each
 (lambda (page)
   (let ((html (sxml->html (cdr page))))
     (let ((markdown-leaks (filter relative-markdown-link? (links html)))
           (unwritten
            (filter (lambda (value)
                      (let ((path (link-path value)))
                        (and (not (starts-with? "http" value))
                             (not (string=? path ""))
                             (not (member path written)))))
                    (links html))))
       (unless (null? markdown-leaks)
         (die "check-site: a Markdown link leaked into " (car page) ": " markdown-leaks))
       (unless (null? unwritten)
         (die "check-site: a link names no generated file in " (car page) ": " unwritten)))))
 (site-result-pages result))

;; The generated file set follows the registry exactly.
(unless (= (length pages) (length (site-result-pages result)))
  (die "check-site: rendered page count differs from pages registry"))

(display "check-site: page registry, anchors, Markdown links, ../ links, and output count -- all green\n")
(exit 0)
