#!r6rs
;; PURE. Imports no library that loads a shared object.
(library (site template)
  (export page->document)
  (import (rnrs) (only (site pages) page-file-name))

  ;; SXML is a Sexp: a string, or a list of a tag symbol, an optional
  ;; (^ (NAME VALUE) ...) attribute list and the child SXML.
  ;; Page is (Pair String String): a Markdown file's name and its label.
  ;; Nav is (Listof Page).
  ;; Toc is (Listof (List Integer String String)): for each heading, its
  ;; level, its text and its anchor.

  ;; nav-item : String -> (Page -> SXML)
  ;; A procedure that answers the sidebar link for a page, marked as the
  ;; current one when its file is CURRENT.
  (define (nav-item current)
    (lambda (entry)
      (let ((file (car entry)) (label (cdr entry)))
        (if (string=? file current)
            `(a (^ (href ,(page-file-name file)) (class "on") (aria-current "page")) ,label)
            `(a (^ (href ,(page-file-name file))) ,label)))))

  ;; toc-item : (List Integer String String) -> SXML
  ;; The rail link for one heading of a Toc.
  (define (toc-item entry)
    `(a (^ (href ,(string-append "#" (caddr entry)))) ,(cadr entry)))

  ;; pagenav : (U Page #f) (U Page #f) -> (Listof SXML)
  ;; The previous and next footer, or nothing when PREV and NEXT are both #f.
  (define (pagenav prev next)
    (if (or prev next)
        (list
         `(div (^ (class "pagenav"))
               ,(if prev
                    `(a (^ (href ,(page-file-name (car prev))))
                        (span (^ (class "lbl")) "Previous")
                        ,(string-append "\x2190; " (cdr prev)))
                    '(span))
               ,(if next
                    `(a (^ (href ,(page-file-name (car next))) (class "next"))
                        (span (^ (class "lbl")) "Next")
                        ,(string-append (cdr next) " \x2192;"))
                    '(span))))
        '()))

  ;; This text must not contain <, >, or &: site/serializer writes it as a
  ;; normal text node in script, where browsers do not decode HTML entities.
  (define theme-script
    (string-append
     "(function(){var r=document.documentElement,b=document.getElementById('theme'),"
     "l=document.getElementById('theme-label');"
     "function g(){try{return localStorage.getItem('theme');}catch(e){return null;}}"
     "function p(x){try{localStorage.setItem('theme',x);}catch(e){}}"
     "function m(){var s=g();return s?s:(matchMedia('(prefers-color-scheme:dark)').matches?'dark':'light');}"
     "function a(x){r.setAttribute('data-mode',x);p(x);l.textContent=x==='dark'?'Light mode':'Dark mode';}"
     "a(m());b.addEventListener('click',function(){a(r.getAttribute('data-mode')==='dark'?'light':'dark');});})();"))

  ;; page->document : Nav String String SXML Toc (U Page #f) (U Page #f) -> SXML
  ;; The complete document for the page whose file is CURRENT, titled TITLE,
  ;; with navigation, BODY's content, an optional previous/next footer and a
  ;; rail of the headings in TOC.
  (define (page->document nav current title body toc prev next)
    `(*TOP*
      (html
       (head
        (meta (^ (charset "utf-8")))
        (meta (^ (name "viewport") (content "width=device-width, initial-scale=1")))
        (meta (^ (name "description") (content "UUIDs, versions 4 and 7, for R6RS Scheme")))
        (meta (^ (name "keywords") (content "uuid uuidv7 rfc9562 scheme r6rs")))
        (title ,title)
        (link (^ (rel "stylesheet") (href "style.css"))))
       (body
        (div (^ (class "topbar"))
             (a (^ (class "source-link")
                   (href "https://github.com/Kiyomi-Computation-Systems/unique-id"))
                "Source code")
             (button (^ (id "theme") (class "toggle") (aria-label "Toggle theme"))
                     (span (^ (class "knob") (aria-hidden "true")))
                     (span (^ (id "theme-label")) "Dark mode")))
        (div (^ (class "layout"))
             (aside (^ (class "side"))
                    (a (^ (class "mark") (href "index.html")) "unique-id")
                    (nav ,@(map (nav-item current) nav)))
             (main (^ (class "main"))
                   (div (^ (class "col")) ,@(cdr body) ,@(pagenav prev next)))
             (aside (^ (class "toc"))
                    (div (^ (class "lbl")) "On this page")
                    ,@(map toc-item toc)))
        (script ,theme-script))))))
