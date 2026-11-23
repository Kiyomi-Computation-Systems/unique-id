#!r6rs
;; NOT pure: (cmark gfm) loads the native cmark-gfm parser.
(library (site render)
  (export render-site site-result? site-result-pages
          site-result-registry site-result-leaked)
  (import (rnrs) (cmark gfm) (site transform) (site links)
          (site template) (site pages))

  ;; SXML is a Sexp: a string, or a list of a tag symbol, an optional
  ;; (^ (NAME VALUE) ...) attribute list and the child SXML.
  ;; Page is (Pair String String): a Markdown file's name and its label.
  ;; Nav is (Listof Page). Registry is (Listof (Pair String (Listof String))):
  ;; each page's file name and the anchors of its headings.
  ;; Toc is (Listof (List Integer String String)): for each heading, its
  ;; level, its text and its anchor.
  ;; SiteResult is the record below.

  ;; A SiteResult carries whole page trees, each page's generated heading ids,
  ;; and internal links whose target page or anchor was absent.
  (define-record-type site-result
    (fields pages registry leaked))

  ;; site-result? : Any -> Boolean
  ;; Whether X is a SiteResult.

  ;; site-result-pages : SiteResult -> (Listof (Pair String SXML))
  ;; The rendered pages, each as its source file name and its document, in
  ;; the order of the inputs.

  ;; site-result-registry : SiteResult -> Registry
  ;; Each page's file name and the anchors of its headings.

  ;; site-result-leaked : SiteResult -> (Listof (Pair String String))
  ;; The internal links that name no page or anchor, each as the page it is
  ;; on and its target, in document order.

  ;; label-for : String -> String
  ;; The label of the page NAME, else NAME.
  (define (label-for name)
    (cond ((assoc name pages) => cdr) (else name)))

  ;; rail-toc : Toc -> Toc
  ;; The second-level entries of TOC.
  (define (rail-toc toc) (filter (lambda (entry) (= (car entry) 2)) toc))

  ;; nav : Nav
  ;; The wordmark reaches Home; the sidebar lists the remaining pages.
  (define nav (filter (lambda (entry) (not (string=? (car entry) "README.md"))) pages))

  ;; neighbors : String -> (Values (U Page #f) (U Page #f))
  ;; The pages before and after the page NAME in the sidebar, each #f at an
  ;; end or when NAME is not in it.
  (define (neighbors name)
    (let loop ((ps nav) (prev #f))
      (cond ((null? ps) (values #f #f))
            ((string=? (caar ps) name)
             (values prev (if (null? (cdr ps)) #f (cadr ps))))
            (else (loop (cdr ps) (car ps))))))

  ;; render-site : (Listof (Pair String String)) String -> SiteResult
  ;; The site for INPUTS, each a page's file name and its Markdown, with ../
  ;; links pointing at the repository at REF. Parses and slugs every input
  ;; first, then resolves all intra-site links against the complete registry
  ;; before applying the document template.
  (define (render-site inputs ref)
    (let* ((parsed
            (map (lambda (in)
                   (let-values (((body toc)
                                 (transform-body (markdown->sxml (cdr in)
                                                                  (default-cmark-options)))))
                     (list (car in) body toc (map caddr toc))))
                 inputs))
           (registry (map (lambda (pg) (cons (car pg) (cadddr pg))) parsed)))
      (let loop ((remaining parsed) (out '()) (leaked '()))
        (if (null? remaining)
            (make-site-result (reverse out) registry (reverse leaked))
            (let* ((pg (car remaining)) (name (car pg))
                   (body (cadr pg)) (toc (caddr pg)))
              (let-values (((body* dangling) (rewrite-links body registry name ref))
                           ((prev next) (neighbors name)))
                (loop (cdr remaining)
                      (cons (cons name
                                  (page->document nav name (label-for name)
                                                  body* (rail-toc toc) prev next))
                            out)
                      (append (reverse dangling) leaked)))))))))
