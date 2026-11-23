# ADR-0009: The API reference is generated from the signature comments, and `docs/` renders into a site

- **Status:** Proposed. The owner chose decisions 2 and 3 on 2026-11-23, the reference
  generated from the source over a hand-written one, and the site in the same piece of
  work. The rest was chosen with the work, not asked of the owner.
- **Date:** 2026-11-23
- **Scope:** `docs/`, the reference generator under `tools/`, `site/`, the Makefile's
  `reference`, `site-deps`, `site` and `check-site`, `.github/workflows/ci.yml`'s `docs`
  job, `.github/workflows/pages.yml`, `Akku.manifest`, `Akku.lock` and `.akkuignore`
- **Related:** ADR-0001, whose suites the reference suite joins in the tools lane;
  ADR-0003, whose CI rule decision 4 makes an exception to; `.plans/docs.md`, the
  contract

## Context

The library is heading for a release, and has only README.org for a user. The sibling
project threading has a `docs/` of four Markdown pages, a hand-written API reference,
and a static site rendered from them through chez-cmark-gfm, deployed to GitHub Pages
on release tags.

AGENTS.md already holds every export in `src/` to a comment directly above its
definition: a Typed Racket style signature, then what it answers in a sentence or two.
Those comments are the API's contract, and the suites test what they say.

## Decision

1. **`docs/` holds nine user pages**: Home, Getting started, Quickstart, five guides
   (Ids, Generators, The system library, Hash tables, Errors), and the API reference.
   They are short and plain, an example first, and describe the code as it is: no plans,
   decision records, reviews or dates. Every example was run on Chez and Guile.
2. **`docs/reference.md` is generated** by `make reference` from `src/`. Each export
   gets its call shape, read from its definition as data; its signature, the comment's
   first line; and the comment's first paragraph. Later paragraphs are notes for whoever
   changes the code, and are left out. Each library's section opens with its header
   comment, less its export table. An export without a signature, or a signature with no
   prose, fails the generator.
3. **`make test` fails while the page is stale.** A suite in the tools lane compares
   `docs/reference.md` with what the generator writes. It is the one test that reads
   code comments, which AGENTS.md otherwise forbids: changing a comment in `src/` then
   needs `make reference` before `make test` passes.
4. **`docs/` renders into an HTML site**, a port of threading's `site/`. chez-cmark-gfm
   2.0.0 is a development dependency, pinned in `Akku.lock` and fetched by
   `scripts/fetch-akku-lock`. `make check-site` tests the generator, then holds the
   page list against `docs/`, and fails on a dangling link, anchor, or `../` link to no
   file.
5. **CI checks the site on every pull request**, in a `docs` job beside the `linux`
   matrix. It runs Ubuntu's own Chez 9.5.8 and `cmark-gfm`, not the Chez 10.4.1 the
   `linux` jobs build and assert: the site is development tooling, not the library, and
   threading's site runs on 9.5.8.
6. **Pages deploys the site** on a `v*` tag, or by hand, gated on `make check-site`.
   GitHub Pages builds from GitHub Actions, and its `github-pages` environment deploys
   from `main` and from `v*` tags alone, as threading's does. The site is
   https://kiyomi-computation-systems.github.io/unique-id/.
7. **The package installs `src/` alone**: `.akkuignore` leaves out `docs/`, `site/` and
   `build-site.sps`, as it does the tests and the tooling.

## Consequences

- The reference cannot drift from the code's contract, and the comments' first
  paragraphs are now user-facing text: they must read well to a user, not only to a
  maintainer.
- A comment-only change to `src/` touches two files, the source and the page.
- The site needs `libcmark-gfm` and one network fetch; `make test` needs neither.
- Nothing runs the guides' examples automatically. The writers and the review ran them
  by hand; a change to the library's behaviour can leave a guide wrong.
