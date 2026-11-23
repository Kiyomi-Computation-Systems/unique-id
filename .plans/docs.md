# The docs: guides, a generated API reference, and the site

The owner asked on 2026-11-23 for a set of doc files like threading's `docs/`, written in
a clear, pragmatic, ELI5 style, on how the library works and how to use it, and for an
API reference. They chose:

- **The reference is generated from the source's signature comments**, with a check in
  `make test` that it is not stale, over a hand-written one.
- **The HTML site comes in this same piece of work**: threading's `site/` generator, its
  checks, and a Pages workflow.

This file is the contract every builder and writer works to. Read
[global-constraints.md](global-constraints.md) and AGENTS.md first.

## Files and owners

One owner per file. Nobody else touches it. Agents do not commit or push.

| Owner | Files |
|:--|:--|
| Me, before any builder | `Makefile` (all new targets, below), `Akku.manifest`, `.akkuignore`, the comments of `src/unique-id/generator.sls` and `src/unique-id/system.sls` (below), an empty `docs/` |
| Reference builder | `tools/unique-id-reference.sls`, `tools/reference.sps`, `tools/reference-head.md`, `tools/test-unique-id-reference.sps`, `tools/fixtures/reference/**`, and `docs/reference.md`, which only `make reference` writes |
| Site builder | `site/*.sls`, `site/style.css`, `site/tests/*.sps`, `site/tests/fixtures/**`, `build-site.sps`, `scripts/fetch-akku-lock`, `Akku.lock`, `.github/workflows/pages.yml`, and in `.github/workflows/ci.yml` a new `docs` job and the header comment |
| Writer A | `docs/README.md`, `docs/getting-started.md`, `docs/quickstart.md` |
| Writer B | `docs/ids.md`, `docs/hashing.md`, `docs/errors.md` |
| Writer C | `docs/generators.md`, `docs/system.md` |
| Me, after | AGENTS.md, README.org, CHANGELOG.md, `.plans/global-constraints.md`, `.plans/progress.md` |

## The pages

Nine pages, in this navigation order. `site/pages.sls` lists exactly these, with these
labels, and the site check holds the list against `docs/*.md`.

| File | Label | What a reader gets from it |
|:--|:--|:--|
| `README.md` | Home | what the library is, a taste, the ideas to keep in mind, what is in it, what it is not, where it runs, status, what to read next |
| `getting-started.md` | Getting started | get the checkout, run the tests, run one program on Chez and on Guile, use it from another directory or another R6RS |
| `quickstart.md` | Quickstart | numbered, task-first examples: make an id, text and bytes, compare and sort, hash tables, the keyed hash, read what an id says |
| `ids.md` | Ids | what a UUID is; v4 or v7, and how to choose; text and bytes; version, variant and timestamp; nil and max; ids are opaque records, compared with `uuid=?` |
| `generators.md` | Generators | a generator is a clock plus a random source; why v7 ids increase; the counter and rollover; the 10-second rule; one generator per thread; testing with a fake clock and fake entropy |
| `system.md` | The system library | the real clock and `/dev/urandom`; why each call opens its own port; forks and threads; platforms; costs |
| `hashing.md` | Hash tables | `uuid-hash` for ids you trust; flooding; `make-uuid-hash` and `make-system-uuid-hash` for ids a client sends; keys |
| `errors.md` | Errors | what raises and what answers `#f`; assertion violations, their who and irritant; the generator's errors; how to catch them |
| `reference.md` | API reference | generated: every export, its call shape, signature and contract |

### What each page must get right

These are the facts easiest to get wrong. Check each against `src/` and the suites
before writing it; the suites are the spec.

- **`string->uuid`** answers `#f` for any string that is not the canonical 36-character
  form, in either case, and raises an assertion violation for a non-string. It refuses
  braces, `urn:uuid:`, missing hyphens and surrounding spaces.
- **`uuid->string`** answers lower case, in a fresh string.
- **`uuid-version`** answers `#f` for an id whose variant is not `rfc9562`, so for
  `nil-uuid` and `max-uuid` too. `uuid-v7-timestamp` answers `#f` for anything but a
  version 7 id of that variant.
- **`uuid<?`** is the order of the 16 bytes, which is the order of the lower-case text,
  so v7 ids sort by time.
- **Never compare ids with `equal?`**: Chez answers `#f` for two ids with the same
  bytes, Guile `#t`. Use `uuid=?`; key a hashtable with
  `(make-hashtable uuid-hash uuid=?)`.
- **A generator's v7 ids increase, one generator at a time.** Ids from two generators,
  or from one process and the next, are not ordered against each other. So make one
  generator and keep it; do not make one per id.
- **The 10-second rule.** While the clock is within 10 seconds behind the last v7 id,
  the generator holds to the last id's millisecond and counts on. Further behind, it
  starts over from the clock, and that id is smaller than the last. A full counter
  moves the timestamp one millisecond past the last.
- **A generator is not safe to share between threads.** Give each thread its own.
- **Running out**: at millisecond 2^48 - 1 with the counter full, `generate-v7` raises
  with `error`, while the clock is within 10 seconds of that millisecond. A clock
  further behind resets the generator instead. A call that raises leaves the generator
  as it was.
- **`make-uuid-generator`** takes a clock, `(-> Nat)`, the Unix time in milliseconds,
  and an entropy source, `(Nat -> Bytevector)`. That is how a test gets fixed ids.
- **`system-entropy`** opens `/dev/urandom` unbuffered at every call that reads, and
  closes it before it returns, so a forked child never repeats its parent's bytes.
  `system-clock` reads SRFI-19's `time-utc`.
- **`make-system-uuid-generator` and `make-system-uuid-hash`** answer a new generator
  or hash at every call; the library keeps none.
- **`uuid-hash`** is unkeyed and below 2^23. Anyone who can choose ids can make them
  all collide, so it is for ids you made or trust. **`make-uuid-hash`** takes an 8-byte
  secret key and answers 32-bit hashes (HalfSipHash-2-4). `make-system-uuid-hash` keys
  one from `/dev/urandom`: its hashes differ between processes, so never store them.
- **Errors**: every export checks its arguments. A bad one raises an assertion violation
  whose who is the procedure's name and whose one irritant is that argument. A hash
  made by `make-uuid-hash` raises with who `make-uuid-hash`. A bad clock or entropy
  answer raises an assertion violation naming the `generate-` procedure; a raise from
  the clock or the entropy source itself passes through unchanged. `system-entropy`
  raises with `error` on a short read from `/dev/urandom`, which the kernel does not
  do.
- **Where it runs.** The library is plain R6RS. `(unique-id)` imports `(rnrs)` alone;
  `(unique-id generator)` imports `(rnrs)` and `(unique-id)`. `(unique-id system)` also
  imports `(srfi :19)` and needs `/dev/urandom`: Linux and macOS. CI runs the suites on
  Chez and Guile 3 on Linux, amd64 and arm64; they have also passed by hand on macOS on
  arm64.
- **Using it from a checkout.** On Chez, `(unique-id system)` needs chez-srfi's
  `(srfi :19)` on the library path: `make deps` links it into `build/scheme-libs`, and
  `make run PROGRAM=file.sps` puts both there. Guile has its own SRFI-19. Nothing is
  released on Akku yet.
- **Costs**, measured on Chez 10.4.0, are for a sense of scale only: a system v7 id
  about 1.4 µs, `uuid-hash` 0.06 µs, the keyed hash 0.43 µs.

## How the pages are written

- **ELI5, pragmatic and short.** Say what a thing is for before how it works. Short
  sentences, second person, one idea a paragraph. Threading's `docs/` are the model:
  read them with `git -C ~/src/threading show origin/main:docs/README.md` and the same
  for `getting-started.md`, `quickstart.md` and `reference.md`. Match their voice and
  their shape: an example first, then a sentence on what it shows.
- **Describe the code as it is.** Never cite a plan, slice, ADR, review, mutation run,
  date, or PR or issue number. No history: no "now", no "new" in the sense of recently
  added. "A new generator", meaning a fresh one, is fine.
- **Plain words for the RFC.** Name RFC 9562 where a reader may want it, never as an
  authority for a claim the page can just state.
- **One `#` heading per page**, then `##` sections. Headings are plain text: no links
  in them. Keep them unique within a page.
- **Links** between pages are relative and go to a whole page,
  `[Generators](generators.md)`, never to another page's section, because the writers
  write at once and cannot see each other's headings. The one exception is the reference's
  three library sections: `reference.md#unique-id`, `reference.md#unique-id-generator`
  and `reference.md#unique-id-system`. Links to a section of the same page are fine,
  the anchor spelled as GitHub spells it. A link out of `docs/` to the repository is
  `../README.org` and the like, and must name a file that exists.
- **No ADRs, no `.plans/`** links: they are not user documentation.
- **Length:** a guide is 60 to 150 lines. The home page about 90, like threading's.
- **The import line.** Each page that has examples shows, once near the top, the import
  its examples need:
  `(import (rnrs) (unique-id) (unique-id generator) (unique-id system))`, or fewer.

### Examples

- **Every example runs.** Run each one on Chez with `make run PROGRAM=file.sps`, and on
  Guile with `guile --r6rs --no-auto-compile -L "$PWD/src" -s file.sps`, before it goes
  on the page. Write the programs under `build/doc-examples/PAGE/`, PAGE being the
  page's name without `.md`, which is scratch.
- **The Guile command for readers** is that one. Guile writes a `WARNING: ...
  overrides core binding` line to stderr for each core name `(rnrs)` replaces. They
  are harmless; getting-started says so once, and no other page mentions them.
- **Deterministic results** are shown as `;; => value`, copied from a run. Build them
  from fixed inputs: `string->uuid` of the RFC's examples, `make-uuid-v7` and
  `make-uuid-v4` with given bytes, a generator over a fake clock and fake entropy.
- **Random results**, from the system library, are shown as `;; => e.g. "…"`, with a
  real output from a run, and the text says they differ every time.
- **Print ids as text.** An id prints differently on each Scheme, `#<id>` on Chez and
  its octets on Guile, and neither is the text: show `(uuid->string id)`.
- **Fixed hashes.** `uuid-hash` and `make-uuid-hash` answer the same numbers on both
  Schemes, so their results may be shown as `;; =>`.
- RFC 9562's example ids: A.6's v7 id is `017F22E2-79B0-7CC3-98C4-DC0C0C07398F`, from
  millisecond 1645557742000; A.3's v4 id is `919108f7-52d1-4320-9bac-f847db4148a8`.

## The reference generator

`docs/reference.md` is written by `make reference` from the comments in `src/`, and
`make test` fails when it is stale. The comments are already the API contract: AGENTS.md
holds every export to a signature on its comment's first line, then what it answers.

### Pieces

- **`(unique-id-reference)`**, `tools/unique-id-reference.sls`: the logic, as
  procedures over text and data, with signature comments like `(unique-id-checks)`'s.
  It may use Chez's own procedures, through `(only (chezscheme) ...)`.
- **`tools/reference.sps SRC-DIR HEAD-FILE`**: writes the whole page to stdout and exits
  0. When an export has no valid signature comment it writes one line per breach to
  stderr, naming the file and the export, writes nothing to stdout, and exits 1. Any
  other number of arguments is a usage error, exit 2.
- **`tools/reference-head.md`**: the page's fixed start, copied verbatim, then the
  generated sections. It holds:
  - `# API reference`, then one sentence: everything the three libraries export, one
    entry each;
  - one sentence for contributors: this page is generated from the signature comments
    in `src/` by `make reference`, so edit those;
  - the import line for all three libraries;
  - **How to read an entry**: the call shape, then the signature; names in capitals in
    the text are the call's arguments, as TEXT is `text`, or the values the text names,
    as CLOCK is a generator's clock; a table of exactly the types the signatures use,
    found by reading them: `Uuid`, `Generator`, `Nat` (an exact nonnegative integer),
    `Boolean`, `String`, `Symbol`, `Bytevector`, `Any`, `#f`, `(U A B)`, `(A B -> C)`,
    `(-> A)` for a procedure of no arguments, and a signature that starts `->` for a
    procedure of no arguments too, as `system-clock : -> Nat`;
  - **Errors**, two sentences: an argument outside its domain raises an assertion
    violation whose who is the procedure's name and whose one irritant is that
    argument; see [Errors](errors.md).
- **`tools/test-unique-id-reference.sps`**: the generator's suite, in the tools lane.
- **`tools/fixtures/reference/`**: small source trees the suite runs the generator on.

### What it reads

- **The libraries**: those `(unique-id-checks)`'s `library-files` answers for
  SRC-DIR, in its order, which is `string<?` on the path: `unique-id.sls` before
  `unique-id/generator.sls` and `unique-id/system.sls`. It passes over an editor's
  litter, such as the lock link Emacs leaves beside a file being edited. So the
  generator's libraries import `(unique-id-checks)`, and `make reference` needs `deps`.
- **The library form**, read as data with Chez's reader: its name and its export list.
  Every export is an identifier; nothing in `src/` renames.
- **Each export's definition**, from the same data: `(define (NAME . FORMALS) ...)` or
  `(define NAME ...)`, the first at the library body's top level.
- **The definition's line**, from the text: the first line that, after leading
  spaces, starts `(define (NAME` or `(define NAME`, followed by a space, a `)` or the
  line's end.
- **Each export's comment**, from the text: the run of lines directly above that line,
  each starting with optional spaces then `;;` but not `;;;`. No blank line may come
  between the run and the definition.
- **The library's header**: the run of `;;;` lines at the top of the file, after
  `#!r6rs`.

### What it writes

For each library, in order:

```
## (unique-id generator)

HEADER PROSE

### `make-uuid-generator`

    (make-uuid-generator clock entropy)
    make-uuid-generator : (-> Nat) (Nat -> Bytevector) -> Generator

ENTRY PROSE
```

with the two code lines in a fenced `text` block, not indented as here.

- **The header prose**: the header split into paragraphs at lines that are exactly
  `;;;`. The first paragraph drops its leading `(NAME): `. A paragraph whose every line
  starts with `;;;` and three spaces is the export table, and is left out. Each kept
  paragraph is its lines' text joined by single spaces.
- **The entries**, in the export list's order.
- **The call shape**: `(NAME FORMAL ...)` for a procedure, `(NAME)` for one of no
  arguments; a rest argument `. REST` shows as `REST ...`. A value has no call shape:
  its block holds the signature alone.
- **The signature**: the comment's first line, without its `;;` and the space after.
  It must read `NAME : TYPE`, NAME being the export and TYPE any non-empty text, not
  parsed. A following line that starts with `;;` and two or more spaces continues it,
  joined by one space.
- **The entry prose**: the comment's first paragraph after the signature, up to a line
  that is exactly `;;` (after any indent), joined by single spaces. Later paragraphs
  are notes for whoever changes the code, and are left out.
- **Breaches**: the library answers them as a list of `(PATH EXPORT RULE)`, PATH
  relative to SRC-DIR, in file order and then export-list order. The program writes
  one line per breach to stderr, `PATH: EXPORT: SENTENCE`, a sentence of the
  builder's choosing per rule, and exits 1. The rules:
  - `no-definition`: no top-level definition, in the data or in the text;
  - `no-comment`: no comment run directly above the definition's line;
  - `signature`: the first line is not `NAME : TYPE` for this export, whether it names
    another export or has no ` : `;
  - `no-prose`: nothing after the signature before the first blank `;;` line or the
    definition.

### Its suite

Tests first: the suite fails every test against a stub `(unique-id-reference)` whose
procedures raise, before the real one is written. The one exception is the program's
usage test, which the program answers before it calls the library. The suite asserts
whole outputs, never substrings. Fixture trees under `tools/fixtures/reference/`, each
one or two tiny libraries:

- **good**: two libraries, one a two-part name in a subdirectory, as `(a)` in `a.sls`
  and `(a b)` in `a/b.sls`, so the order and the name are both held. Between them: a
  procedure, a procedure of no arguments, a value, a rest argument, a two-line
  signature, a first prose paragraph of several lines, a two-paragraph comment, and a
  header whose first paragraph spans several lines, with a table, a table row that
  continues onto a second line, and a paragraph after the table. The suite asserts the
  whole page, byte for byte, against an expected string built with `string-append` in
  the suite.
- **one breach per tree**: no comment; a blank line between comment and define; a
  signature naming another export; a signature with no ` : `; a signature and no prose;
  an export never defined. Each asserts the exact (file export rule) list.
- **order**: exports listed in an order unlike their definitions; the page follows the
  export list.
- **the program**: `tools/reference.sps` on good (exit 0, stdout the page, stderr
  empty), on a breach (exit 1, stdout empty, stderr naming it), and with no arguments
  (exit 2). Run it through `(unique-id-checks)`'s `run-check`.
- **the real thing**: `docs/reference.md` is exactly what `tools/reference.sps src
  tools/reference-head.md` writes. This is what makes a stale page fail `make test`.
  It reads code comments, which AGENTS.md forbids a test to do; this is the one
  intended exception, and AGENTS.md will say so. Editing a comment in `src/` then
  fails `make test` until `make reference` runs.
- **the real thing, not trusting the generator**: the `## ` lines of
  `docs/reference.md` are the three library names of `src/`, read as data, in file
  order, and its `### ` lines are each library's export list, 24 entries in all.

The suite ends with `(exit (suite-exit-status runner))`, like every suite.

## The site

A port of threading's `site/` to unique-id, changed only where this project differs.
Read it with `git -C ~/src/threading show origin/main:PATH`; list it with
`git -C ~/src/threading ls-tree -r --name-only origin/main`. Do not change the local
threading checkout.

- **Copied and adapted**: `site/io.sls`, `links.sls`, `pages.sls`, `render.sls`,
  `serializer.sls`, `slug.sls`, `template.sls`, `transform.sls`, `style.css`;
  `build-site.sps`; `scripts/fetch-akku-lock`; `.github/workflows/pages.yml`.
- **What changes**:
  - the repository URL in `links.sls` and `template.sls`;
  - the description and keywords in `template.sls`: "UUIDs, versions 4 and 7, for R6RS
    Scheme", "uuid uuidv7 rfc9562 scheme r6rs";
  - the wordmark, `unique-id`;
  - `pages.sls`, the nine pages above, in that order, with those labels;
  - the docs directory: `io.sls` and `site-check.sps` both read it from `SITE_DOCS`,
    else `docs`, so the site's own checks run on a fixture tree;
  - comments follow this project's rules (AGENTS.md, "Signatures in comments"):
    - every exported procedure has a signature, the record procedures `render.sls`
      exports from its `define-record-type` among them;
    - internal procedures have one when the name does not make the types plain;
    - the vocabulary is this project's: `(Pair A B)` for threading's `(Pairof ...)`,
      `Void` for `Unspecified`;
    - a file-local type, such as `SXML`, `Registry`, `SiteResult`, `Nav`, `Toc` or
      `Page`, is defined in a comment in the file that uses it;
    - no history.
- **The tests** move from threading's `tests/` to `site/tests/`, because `make
  check-tests` holds `tests/` to plain R6RS and refuses `(chezscheme)`:
  `site/tests/site-unit.sps`, `site-render-unit.sps` and `site-check.sps`, adapted to
  the nine pages and to `(unique-id-testing)`. `site-unit.sps` and
  `site-render-unit.sps` end with `(exit (suite-exit-status runner))`, and `make
  check-suites` reads them; `site-check.sps` is a plain program that exits 1 on its
  first complaint.
- **`site-check.sps`** fails when:
  - `pages.sls` and the `.md` files in the docs directory disagree;
  - a link between pages, or to an anchor, dangles;
  - a `../PATH` link names no file, PATH taken relative to the docs directory.
    Threading's `links.sls` rewrites such links to the repository and never checks
    them.
- **What the site's tests add to threading's**:
  - `site-unit.sps` asserts the whole `pages` list, labels included;
  - `site-render-unit.sps` asserts that `../README.org` renders as
    `https://github.com/Kiyomi-Computation-Systems/unique-id/blob/main/README.org`,
    and that the page's source link points at unique-id's repository;
  - each is watched failing, against a pages list missing a page, a dangling link, a
    `../` link to no file, and the threading URL.
- **`site/tests/fixtures/`** holds a docs tree of the nine pages, each a heading and a
  line, with good links between them, so `site-check.sps` can be run with
  `SITE_DOCS=site/tests/fixtures/docs` before the writers finish. A broken tree beside
  it, for each failure above, is how the check is watched failing.
- **`Akku.lock`** comes from `akku lock`, run through `guix shell akku`, never by
  hand. It pins chez-cmark-gfm 2.0.0, and also a chez-srfi, `0.0.0-akku.291.5219353`,
  that is not the submodule's pin: that entry is expected and unused, since the suites
  take chez-srfi from `vendor/`. `scripts/fetch-akku-lock` reads its entry by name.
- **Running it on this host**: no `libcmark-gfm` is installed system-wide. Use the
  built pair in the chez-cmark-gfm checkout, two absolute paths joined by `:`:
  `CHEZ_CMARK_GFM_LIBS=$HOME/src/chez-cmark-gfm/build/vendor/src/libcmark-gfm.so:$HOME/src/chez-cmark-gfm/build/vendor/extensions/libcmark-gfm-extensions.so`.
  The copies under that checkout's `tests/tmp/` are decoys.
- **CI**: a `docs` job in `ci.yml`, on `ubuntu-24.04`, beside the `linux` matrix. It
  installs Ubuntu's `chezscheme`, `cmark-gfm`, `xz-utils`, `curl`, `make` and `git`,
  naming each as the file's comments require, and runs `make submodules`, `make
  site-deps`, `make check-site CHEZ=chezscheme` and `make site CHEZ=chezscheme`, so a
  broken link or build fails a pull request. It runs Ubuntu's Chez 9.5.8, not the
  10.4.1 the `linux` jobs build: the site is development tooling, and threading's site
  runs on 9.5.8. Pin actions by full SHA, as `ci.yml` and threading's `pages.yml` do.
  The file's header comment, which says it has one job, says what each job is for.
- **Pages**: `pages.yml` as threading's: on a `v*` tag, and by hand; it gates on `make
  check-site`, then builds and deploys. GitHub Pages must be switched on in the
  repository's settings, with GitHub Actions as its source: that is the owner's to do.

## The tooling I add first

- **Makefile**:
  - `reference: deps`, which writes `docs/reference.md` through `tools/reference.sps`
    on the tools lane's path, by way of a temporary file so that a failure leaves the
    old page;
  - `site-deps`, `site` and `check-site`, as threading's. `check-site` runs
    `site/tests/site-unit.sps` on `.:tests:build/scheme-libs`, then
    `site/tests/site-render-unit.sps` on the cmark path plus those, then
    `site/tests/site-check.sps` on `.` and the cmark path, in that order;
  - `check-suites` also reads `site/tests/site-unit.sps` and
    `site/tests/site-render-unit.sps` once they exist;
  - `.PHONY` and `help` for the four new targets; `make check-help` holds them.
- **`Akku.manifest`**: `(depends/dev ("chez-cmark-gfm" "^2.0.0"))`, and its comment,
  which says it names no dev dependency, rewritten.
- **`.akkuignore`**: `build-site.sps`, `docs` and `site`, so the package installs
  `src/` alone.
- **Comments in `src/`**: "An `error' when" becomes "An `error` when", which Markdown
  would otherwise mangle; the generator's and the system library's header taglines
  start with a capital, since the reference shows them as sentences.

## How it is checked

- **The generator**: its suite, watched failing against the stub first. `make test`
  fails on a stale `docs/reference.md`: I prove it by editing a signature comment
  without regenerating.
- **The site**: `make check-site` passes on the real docs; the site's own tests are
  watched failing too, against a pages list missing a page and a dangling link.
- **The examples**: each writer runs every example on Chez and Guile. The review runs
  them again.
- **The review**: a read-only adversarial review on Opus of everything built, against
  the code: every claim in the pages, every example rerun, the generator and its
  suite, the site port.

## What I record after

- **AGENTS.md**: the docs and the site in the layout; `make reference` after any
  change to a comment in `src/`; the reference suite as the one test that reads
  comments; `make site` and `make check-site`.
- **The global constraints and an ADR**: the generated reference, the site, and the
  `docs` CI job's Chez 9.5.8, an exception to "CI builds Chez 10.4.1".

## Out of this piece

- **A check that runs the docs' examples.** Writers and the review run them by hand.
  It goes in Open.
- **Publishing on Akku**, and a version number: the owner's call.
- **Switching on GitHub Pages**: the owner's.
