# Progress ledger

Where unique-id stands. Read it with [global-constraints.md](global-constraints.md)
before starting slice work. When a slice merges, update **Now** and add a close-out under
**Close-outs**, newest first.

## Now

- **Slice 3, the system, `(unique-id system)`, and the keyed hash, is merged**,
  squashed from [PR #4](https://github.com/Kiyomi-Computation-Systems/unique-id/pull/4)
  on 2026-11-23; its close-out is below. The brief's three slices are all merged.
- **The design** is the brief, [uuid.md](uuid.md). The owner answered its open questions
  on 2026-11-22; its **Answers** section records them, and ADR-0001 to ADR-0004 the
  decisions they led to; later answers are recorded there too.
- **0.1.0 is the first release**: the signed tag `v0.1.0`, on the squash commit of
  [PR #8](https://github.com/Kiyomi-Computation-Systems/unique-id/pull/8), with a GitHub
  release, on 2026-11-23. Its close-out is below. The work toward it, each with a
  close-out below:
  - a sweep of the code comments, squashed from
    [PR #5](https://github.com/Kiyomi-Computation-Systems/unique-id/pull/5);
  - the docs, the generated API reference and the docs site, squashed from
    [PR #6](https://github.com/Kiyomi-Computation-Systems/unique-id/pull/6). The site
    is https://kiyomi-computation-systems.github.io/unique-id/, and a `v*` tag deploys
    it.
- **The contributor docs are merged**: CONTRIBUTING.md, SECURITY.md and GitHub's
  templates, squashed from
  [PR #9](https://github.com/Kiyomi-Computation-Systems/unique-id/pull/9) on 2026-11-25;
  its close-out is below. Private vulnerability reporting is on.
- **Next:** publishing on Akku is the owner's call, and `akku publish` signs with the
  owner's key. The items under **Open** are the known work.

## Slices

1. **The core, `(unique-id)`**: the record; text in and out; bytes in and out; version,
   variant and v7 timestamp; `uuid=?`, `uuid<?` and `uuid-hash`; the nil and max ids;
   `make-uuid-v4` and `make-uuid-v7`. RFC 9562's Appendix A vectors, copied from the
   RFC's text; round trips; every malformed text refused; a property test of the version
   and variant bits.
2. **The generator, `(unique-id generator)`**: `make-uuid-generator`, `generate-v4`,
   `generate-v7`, with RFC 9562 §6.2 Method 1's counter. A scripted clock that repeats,
   steps back and overflows the counter gives strictly increasing ids; one more than 10 seconds behind resets it.
3. **The system, `(unique-id system)`**: the clock through SRFI-19, bytes from
   `/dev/urandom`, and a generator made of them, whose ids parse back and differ.
   `Akku.manifest` names chez-srfi; `akku` reads it.
   - **A keyed hash**, for tables keyed by ids a client sends, which `uuid-hash` leaves
     open to flooding (ADR-0005). It has two parts:
     - In the core, `make-uuid-hash : Bytevector -> (Uuid -> Nat)`, which takes the key
       as an argument.
     - In `(unique-id system)`, one keyed from `/dev/urandom`.

     HalfSipHash-2-4 is the candidate, checked against the SipHash reference's own
     vectors. Measured on a prototype, it is about 7× `uuid-hash`'s cost on Chez,
     0.47 µs a hash, and 2× on compiled Guile. Its arithmetic stays below 2^33, so
     AGENTS.md's below-2^23 rule for hashing needs amending with it. `uuid-hash` stays.

## Open

- **On CI, no lane catches a test that expects `#f` from a raise**: chez-srfi and Guile
  3.0.9 both pass it. AGENTS.md forbids such tests. Only the host's Guile 3.0.11 catches
  one (ADR-0003).
- **No check holds `system-entropy`'s unbuffered port.** A buffered port, closed at
  every call, passes every suite on both Schemes and the fork suite. It costs speed
  alone: a buffered port reads thousands of bytes to answer 16.
- **macOS has run on arm64 alone.** On 2026-11-23, `make test` on slice 3's branch
  passed every lane, the fork suite among them, on macOS 26.7.1 on arm64. It ran with
  Apple's GNU make 3.81, Homebrew's Chez 10.4.1, found as `chez`, and Guile 3.0.11.
  Nothing has run on an Intel Mac.
- **`check-help`'s reading of the contributor docs has not run on macOS's awk**, only on
  mawk, gawk and busybox awk. The next `make test` on the Mac runs it.
- **Akku.** The package is not published. Akku 1.1.0 installed it into a clean project
  on 2026-11-23, and a program using all three libraries ran on Chez and on Guile;
  `akku publish` signs with the owner's key.

## Close-outs

### The contributor docs: PR #9, 2026-11-25

- **The owner's ask:** a CONTRIBUTING.md "and similar". The owner then had GitHub's
  private vulnerability reporting turned on, which SECURITY.md points to. It was off
  here, though on for chez-http-server.
- **What merged:**
  - CONTRIBUTING.md, SECURITY.md, a pull-request template, and bug and feature issue
    templates. They are the set chez-http-server, uriparse, chez-websocket, chez-libuv,
    chez-sodium and chez-cmark-gfm carry, written for unique-id. SECURITY.md names the
    reports most wanted: guessable or repeated ids, a generator that answers one id
    twice, readers that accept what they should refuse, forged or changed ids, and
    attacks on the keyed hash.
  - README.org links CONTRIBUTING.md and SECURITY.md; CHANGELOG.md has an
    `[Unreleased]` entry; AGENTS.md says these files restate its rules and change with
    them.
  - `make check-help` also fails when CONTRIBUTING.md, the PR template or the bug
    report quotes a `make` target that is not in `.PHONY`, or quotes none. Unlike
    chez-http-server's and uriparse's, it also reads fenced lines, and code spans
    wrapped over two lines.
- **How it was built:** by me, with no agents.
- **Verified:**
  - `make test` and `make check-site` on Chez 10.4.0 and Guile 3.0.11. CI on amd64,
    arm64 and the `docs` job.
  - Before the change, `check-help` passed with a made-up target quoted. After it, 11
    mutants on a scratch copy each failed or passed as meant, under mawk, gawk 5.3.0
    and busybox awk. `nawk` on this host is mawk.
- **Caught checking the drafts against the repository:**
  - The keyed hash's vectors come from the SipHash reference, not RFC 9562.
  - A docs link may go to a heading on the same page only.
  - A docs page never mentions `exit`, which is stricter than never calling it.
  - `make check-site` runs on one image, not on both architectures.
- **Also learned:** an `.akkuignore` line is a name, not a path. Akku's scanner skips
  every file and directory of that name at any depth. It always skips dot files,
  names ending in `~`, `Akku.lock` and `Akku.manifest`.

### Release 0.1.0: PR #8, 2026-11-23

- **The owner's choices:**
  - Version 0.1.0, as a git tag only. Akku comes later.
  - Four things before the tag: a review of the whole library; the docs' examples run
    in CI; the Akku install tried on both Schemes, with install steps; and the
    ledger's small test gaps.
  - After the review, each the recommended option: document the rollover reset
    rather than change it; `bytevector->uuid` keeps raising for a wrong length; the
    export names and the variant `rfc9562` stay.
  - ADR-0010, accepted. The tag signed with the releases key, and a GitHub release.
- **What merged:**
  - **`make check-docs`, in `make test`** (ADR-0010): each page of `docs/` is one
    program, run on Chez and on Guile, with every `;; =>` result compared. The
    generator refuses a page it cannot check fully, and a refused page's program
    fails. Its suite has 40 tests.
  - **`make check-lane-order`, in `make test`**: both lanes find `src/` before `tests/`,
    and the stand-in it plants is found at all.
  - **`run-check`'s two tests**: it runs `$CHEZ`, and its child's stdin is `/dev/null`,
    held by pointing the suite's own descriptor 0 at a file through libc.
  - **Docs:** the reset that millions of ids a second cause; `uuid-hash`'s numbers may
    change; printing ids; install steps for the tag; the 0.1.0 changelog entry.
  - **Records:** ADR-0010, an amendment to ADR-0009, AGENTS.md, the global constraints,
    and the plan, [release-0.1.0.md](release-0.1.0.md).
- **How it was built:**
  - A read-only review of the whole library, on Opus.
  - Two Sonnet builders on disjoint files: `check-docs`, and the `run-check` tests. I
    wrote the lane-order check and tried the Akku install.
  - A read-only adversarial review on Opus, then a Sonnet fixer for `check-docs`; I
    made the docs and records fixes.
- **Verified:**
  - `make test` in a fresh copy with no `build/`, on Chez 10.4.0 and Guile 3.0.11, and
    its Guile and docs lanes on Guile 3.0.9. `make check-site` all green.
  - CI on amd64 and arm64, on Chez 10.4.1 and Guile 3.0.9: the docs lanes ran 9 pages
    each, and the lane-order check passed.
  - Akku 1.1.0 installed the package into a clean project: the three libraries and the
    LICENSE, nothing else. A program using all three ran on Chez and on Guile, with
    `system-clock` within 0.2 s of the real time on each.
  - Each new test was watched failing against a break in a copy of what it covers, and
    both reviews' counterexample pages are caught.
- **The whole-library review** found the libraries sound against RFC 9562, and
  `make-uuid-hash` equal to a HalfSipHash written from the paper, on all 64 of the
  reference's vectors and 3000 random keys and ids. It found:
  - **A promise the docs broke.** They called a falling clock the one reset. But each
    counter rollover moves the next id a millisecond ahead, so ids asked for faster
    than milliseconds hold them run ahead of the clock, and reset once 10 s ahead.
    ADR-0006 records it; the user docs did not. Reproduced: a stuck clock with
    constant entropy goes back at id 20,492,051, after 1.2 s on Chez.
  - `uuid-hash`'s numbers shown as fixed, though ADR-0005 lets them change.
  - `generate-v7`'s comment: its reason for keeping CLOCK out of G was wrong. Only
    ENTROPY is called after G's state is read.
  - Three API questions, which the owner settled as above.
- **The final review** found, each reproduced and fixed:
  - **The new suite failed from a clean `build/`**, so CI's first run would have: a
    `let` ran a program before the init that writes it, Chez making the second init
    first.
  - `;; =>` lines neither checked nor refused: indented, inside a form, `;;=>`, after a
    block comment, and in fences the check did not read.
  - `e.g.` shapes loose enough to pass Chez's upper-case hex, whitespace collapsed
    inside strings, and a page that could exit before its failures counted.
  - The docs' rates overstated by about 1.5×, taken from the least seed alone.
  - The Guile install command without `--r6rs`, and the docs home page silent on the
    release.
- **Caught in hand-backs:**
  - The `check-docs` suite had no `test-begin`, so it printed no summary, though its
    tests counted.
  - The `run-check` stand-in printed its arguments with `echo`; it uses `printf`.
  - My own rename of a page's repeated `g` also caught the `g` in "e.g." and a word of
    prose. `check-docs` then refused the page for a third repeat. Fixed by hand.
- **Also learned:**
  - **Reset rates**, simulated with random seeds: no reset in 60 s at 2.5 million ids a
    second; a reset after 33 s at 4 million, and 9.8 s at 6.2 million. A millisecond
    holds 2049 to 4096 ids, about 3072 on average.
  - `make-system-uuid-generator` makes about 670,000 ids a second on Chez and 80,000
    on Guile here: far below a reset.
  - **Akku:** it installs a `unique-id/main.sls` link to `(unique-id)`. Akku's
    chez-srfi has no SRFI-19 for Guile, so Guile uses its own. `akku publish` reads
    the tag `v` plus the version, signs with gpg, and uploads.
  - Guile with auto-compilation warns of a program's `hash`, which shadows its own; the
    docs' renamed `test-hash` and `random-hash` avoid it.

### The docs: PR #6, 2026-11-23

- **The owner's request:** a `docs/` like threading's, of clear, pragmatic, ELI5 pages
  on how the library works and how to use it, and an API reference, built by
  subagents in parallel as threading's was.
- **What merged:**
  - **The pages:** `docs/`, nine of them: Home, Getting started, Quickstart, five
    guides (Ids, Generators, The system library, Hash tables, Errors), and the API
    reference. The contract they were written to is [docs.md](docs.md).
  - **The reference generator:** `(unique-id-reference)` and `tools/reference.sps`,
    which `make reference` runs. Its suite, 27 tests in the tools lane, also fails
    `make test` while `docs/reference.md` is stale. Ten fixture trees.
  - **The site:** a port of threading's `site/`, `build-site.sps`,
    `scripts/fetch-akku-lock` and `Akku.lock`, which pins chez-cmark-gfm 2.0.0. `make
    site-deps`, `make site` and `make check-site`; the site's suites: unit (14 tests),
    render (11) and the broken-tree fixtures (7), and `site-check` over the real
    `docs/`.
  - **CI and Pages:** a `docs` job in `ci.yml`, on Ubuntu's Chez 9.5.8 and
    `cmark-gfm`, and `pages.yml`, threading's, which deploys on a `v*` tag or by hand.
  - **Records:** ADR-0009. Also AGENTS.md, the global constraints, README.org,
    CHANGELOG.md, `Akku.manifest`'s dev dependency and `.akkuignore`. In `src/`, two
    comments only: two library headers now open with a capital, and one quote is
    Markdown's, as each renders on the reference page.
- **The owner's choices:**
  - The reference generated from the source, over a hand-written one.
  - The docs and the site in one piece of work.
  - GitHub Pages turned on. It builds from Actions, and its `github-pages` environment
    deploys from `main` and from `v*` tags alone, as threading's does.
  - ADR-0009, accepted on 2026-11-23 after the merge.
- **Chosen with the work, and accepted with ADR-0009:**
  - The reference takes each export's call shape, its signature and the comment's
    first paragraph. Later paragraphs, after a line that is `;;` alone, are notes for
    whoever changes the code. Each library's header comment opens its section, less
    the export table.
  - The staleness suite is the one test that reads code comments.
  - Links go to a page, a heading on the same page, or one of the reference's three
    library sections.
  - The `docs` job runs Chez 9.5.8, not the 10.4.1 the `linux` jobs build.
  - The package installs `src/` alone: `.akkuignore` leaves out `docs/`, `site/` and
    `build-site.sps`.
- **How it was built:**
  - A contract, [docs.md](docs.md), and a read-only review of it on Opus before any
    building.
  - Then five Sonnet agents, on disjoint files: the reference generator, the site port,
    and three writers, each with its own pages.
  - A read-only adversarial review on Opus, and four Sonnet fixers.
- **Verified:**
  - `make test` on Chez 10.4.0 and Guile 3.0.11: every lane passes.
  - `make check-site` passes on the real `docs/`, and each broken tree fails it as
    expected. `make site` writes nine pages.
  - The code blocks were extracted from the final pages and run: all 72 `;; =>`
    results match on both Schemes.
  - Changing a comment in `src/` fails the reference staleness test alone.
  - **Mutants of the reference generator:** four, A to D, fail 3, 5, 2 and 2 tests.
  - CI on amd64 and arm64, and the `docs` job, with Chez 9.5.8.
- **The contract review**, before building, found 16 problems. Among them:
  - a wrong path to the `libcmark-gfm` library;
  - no fixture tree for `SITE_DOCS`, and gaps in the planned suites;
  - writers left to guess at the reference's anchors, now limited to three;
  - editor litter in `src/`, which the generator now skips through `library-files`;
  - `../` links that nothing checked;
  - the packages CI's `docs` job needs, and no `make site` in it.

  All of these were fixed before any builder started.
- **The final review** found 18 problems, each reproduced and fixed. Among them:
  - **The README's first example printed `#f` on Chez.** `(uuid<? (generate-v7 gen)
    (generate-v7 gen))` makes its second argument first. The examples now name each
    id with `define`.
  - claims that v7 ids "always increase", which the clock reset breaks;
  - a claim about the system library's cost, now a table of measured costs;
  - a claim in errors.md about input from outside;
  - a reference-style `../` link that `site-check` missed;
  - the broken fixture trees, which no suite ran;
  - reference generator mutants that passed every test;
  - the page template's meta tags, which nothing asserted;
  - repetition, rewrapping and a stray `###` heading.
- **Caught in hand-backs:** a fixer reported the reference suite as flaky. It was
  run without `CHEZ` and `TOOL_LIBDIRS`, which fails exactly ten tests; through `make`
  it passed three times in a row.
- **Also learned:**
  - Chez evaluates a call's arguments right to left in a program, so two calls that
    each make an id, in one call's arguments, make them in reverse.
  - **Costs on Chez 10.4.0:** `generate-v7` on the system generator 1.47 µs,
    `system-entropy` 1.37 µs, `make-uuid-v7` 0.027 µs.
  - **Akku:** `akku lock` also pins chez-srfi `0.0.0-akku.291.5219353`, which the site
    does not use.
  - This host has no system `libcmark-gfm`; `CHEZ_CMARK_GFM_LIBS` names the libraries
    built in `~/src/chez-cmark-gfm`.
  - Turning Pages on makes the `github-pages` environment with a `main` branch rule
    alone: a `v*` tag's deploy needs its own rule.
  - A hand-run workflow needs its file on `main`, so the site cannot deploy before the
    merge.

### The comment sweep: PR #5, 2026-11-23

- **The owner's request:** sweep every code comment, in the tests and the source, of
  milestones and ADRs, unless a design reason needs the link, and focus them on what
  a developer needs.
- **What merged:**
  - **Nothing cited an ADR, a slice, a plan or a date.** AGENTS.md's comment rule had
    held, so no ADR link needed keeping either.
  - **Process talk, reworded:**
    - the fork suite's "Expected survivor" paragraph and its "mutation run" wording;
    - "stub" in the system suite;
    - the sibling projects in the Makefile's pin comment;
    - "a reviewed change" in `build-chez.sh`.
  - **Clearer:** the system library's header now gives its port rule, then the
    reasons. The monotonic suite's header is now a list. Ragged and over-long prose
    is rewrapped. `(unique-id-checks)` now names all three of its programs.
  - **AGENTS.md:** the comment rule now names mutation runs, and says comments are for
    a developer using or changing the code.
- **How it was done:** by hand, with no subagents: about a dozen edits, fewer than
  briefing agents would have taken.
- **Verified:** `make test` on Chez 10.4.0 and Guile 3.0.11, and CI on amd64 and arm64.
- **Caught in my own edit:** I first wrote that the system suite's `attempt` keeps a
  raise from ending the suite. On chez-srfi and Guile 3.0.9, a raise in a test's
  actual expression becomes `#f` instead. The comment now says only that a raise
  inside it fails the test.

### Slice 3, the system and the keyed hash: PR #4, 2026-11-23

- **What merged:**
  - **The library:**
    - `make-uuid-hash`, in `src/unique-id.sls`;
    - `src/unique-id/system.sls`, `(unique-id system)`, which exports `system-clock`,
      `system-entropy`, `make-system-uuid-generator` and `make-system-uuid-hash`.

    Both were built to the contract in [slice-3.md](slice-3.md).
  - **The suites:**
    - keyed hash, 28 tests: 12 HalfSipHash vectors, one from the SipHash reference's
      `vectors.h` and 11 computed by its C code;
    - system, 23 tests;
    - the fork suite, `tools/test-system-fork.sps`, 9 tests, on Chez, which runs
      `tools/fork-probe.sps` as a child program.
  - **Tooling:** `make check-tests` allows `(srfi :19)` in `tests/`, and every lane
    runs each suite under `ulimit -n 64`.
  - **Records:** ADR-0007 and ADR-0008, with amendments to ADR-0001 and ADR-0005.
    Also `Akku.manifest`'s chez-srfi dependency, README.org, CHANGELOG.md, AGENTS.md
    and the global constraints.
- **The owner's choices:**
  - The keyed hash in slice 3, with `uuid-hash` kept.
  - ADR-0007 and ADR-0008, accepted on 2026-11-23 after the build. The decisions in
    them were made with the slice.
- **Chosen with the slice, and accepted with those records:**
  - **The keyed hash:**
    - HalfSipHash-2-4 of the 16 octets, the 32-bit output read little-endian;
    - generic arithmetic, below 2^33;
    - its procedure raises under `make-uuid-hash`'s name.
  - **The system library:**
    - `time-utc` for the clock;
    - a fresh unbuffered `/dev/urandom` port at every call that reads, closed by
      `dynamic-wind`;
    - makers that answer a new generator or hash at each call, so the library holds
      none of its own.
  - **Tests and packaging:**
    - `(srfi :19)` in `tests/`;
    - the fork suite in `tools/`, on Chez;
    - the 64-descriptor cap on every lane;
    - chez-srfi from `0.0.0-akku.181.7879b52` up.
- **How it was built:**
  - A read-only review of the contract, on Opus, came before any building.
  - Then five Sonnet builders worked in parallel, on disjoint files: the library, the
    keyed-hash suite, the system suite, the tools rule and cap, and the fork suite.
    The suites were built against stubs that raise `'stub`.
  - A Sonnet mutation run and a read-only adversarial review on Opus followed, and two
    Sonnet fixers.
- **Verified:**
  - `make test` on Chez 10.4.0 and Guile 3.0.11, and the Guile lane on Guile 3.0.9.
  - CI on amd64 and arm64, with Chez 10.4.1 and Guile 3.0.9.
  - **macOS, its first run.** `make test` passed every lane, the fork suite among them,
    on macOS 26.7.1 on arm64, with Apple's make 3.81, Homebrew's Chez 10.4.1 and
    Guile 3.0.11.
  - **Mutants:** 116 of the library were run on all three Schemes.
    - 100 are killed on every Scheme. One more, a shared buffered port, is killed on
      Chez alone, by the fork suite.
    - The other 15 survive, each listed in the contract with its reason.
  - **Stubs:** the keyed-hash and system suites each fail every test against them, on
    all three Schemes.
  - **Akku:** Akku 1.1.0 installs the package, and a consumer program runs on Chez.
- **The contract review**, before building, found:
  - **A test that fails on correct code:** empty bytevectors are one object on all
    three Schemes, so "a fresh empty bytevector" could not be tested.
  - **Stale records:** AGENTS.md and the global constraints still stated the old rules.
  - **Leaks hidden on Guile:** the 5000-call leak test was blind there, since Guile
    closes the ports its collector finds. Hence the descriptor cap.
  - **A design unsafe across a fork:** a shared buffered port passed every planned
    test. Hence the fork suite.
  - **Gaps in the contract:** survivors it did not list, the flooding test's reliance on
    `uuid-hash`, and the order the builders depended on.

  All of these were fixed before any builder started. The review's one wrong claim was
  that Chez finds `fork` without loading libc. The fork builder found it does not, and
  that was confirmed.
- **The slice review** found four wrong libraries that passed every suite, each one
  reproduced:
  - entropy read one byte short into a zeroed bytevector, so its last byte is always 0;
  - entropy that stops at 65536 bytes, leaving the rest 0;
  - a hash key from a counter, the same in every process;
  - a generator over a clock 9 s fast.

  New tests kill all four. The review also found about a dozen slips:
  - argument order in `let`;
  - in the fork suite: the label order, the child's status and a stale output file;
  - unguarded top-level calls;
  - comments citing the contract;
  - "every call opens" for "every call that reads";
  - false claims in the ADRs, README.org and the manifest.
- **Caught in hand-backs:**
  - The key-read test must zero KEY before the first hash, or a copied key passes it.
    The keyed-hash builder found this.
  - The mutation run reported changed messages as gaps. Messages are not asserted,
    under ADR-0005, and are now listed as survivors.
- **Traps recorded in AGENTS.md:** the mutant recipe's descriptor cap, and why it is
  needed: Guile closes the ports its collector finds, so under a higher limit a leak
  hides.
- **Also learned:**
  - **Fork and buffering:**
    - A buffered `/dev/urandom` port gives a forked child its parent's bytes, on both
      Schemes; an unbuffered one does not. This settles slice 2's open note.
    - `(buffer-mode none)` reads once per `get-bytevector-n`. A buffered port reads
      8192 bytes on Chez, 4096 on Guile.
  - **Costs on Chez 10.4.0:**
    - opening an unbuffered port per call costs 1.3 to 1.6 µs, a buffered one 17.7 µs;
    - the keyed hash 0.43 µs, `uuid-hash` 0.063 µs;
    - a system v7 id 1.36 µs.
  - **Akku 1.1.0:**
    - the range `^0.0.0-akku.181.7879b52` locks at `0.0.0-akku.291.5219353`;
    - `akku install` installs only the libraries under `src/`.
  - **Tools:**
    - Running the SipHash reference's own `test.c` was refused by the permission
      classifier. A driver that reproduced the `vectors.h` entry did the job.
    - Apple's make 3.81 runs the Makefile.

### Slice 2, the generator: PR #3, 2026-11-22

- **What merged:**
  - **The library:** `src/unique-id/generator.sls`, `(unique-id generator)`. It exports
    `make-uuid-generator`, `uuid-generator?`, `generate-v4` and `generate-v7`, built to
    the contract in [slice-2.md](slice-2.md).
  - **The suites:**
    - generator, 93 tests: exact calls and answers from A.6 and A.3, bad answers,
      rollover, reset and running out;
    - monotonic, 10 seeded runs of scripted clocks.
  - **Records:** ADR-0006. Also the brief's later answers, README.org, CHANGELOG.md, an
    AGENTS.md trap, the global constraints, and the Makefile's Guile `-L` order.
- **The owner's choices:**
  - The keyed hash goes in slice 3.
  - A clock more than 10 seconds behind the last id resets the generator, chosen over
    counting on and over refusing.
  - The reset was kept after it was shown to depart from §6.2's SHOULD, as LiosK's
    uuidv7 does.
- **Chosen with the slice:**
  - Method 1, seeded from 11 random bits.
  - One entropy call per id.
  - A bad clock or entropy answer raises an assertion violation, and running out
    raises with `error`.
  - A raise leaves the generator unchanged.
  - Order holds within one generator only.
- **How it was built:**
  - A read-only review of the contract, on Opus, came before any building, which the
    slice 1 reflection asked for.
  - Then three Sonnet builders worked in parallel, from one contract: the library and
    the two suites. A mutation run on Sonnet and an adversarial review on Opus followed,
    and two Sonnet fixers.
  - The reset was its own round: tests first, the library after, mutants, and a focused
    Opus review.
- **Verified:**
  - `make test` on Chez 10.4.0 and Guile 3.0.11, and the Guile lane on Guile 3.0.9.
  - CI on amd64 and arm64, with Chez 10.4.1 and Guile 3.0.9.
  - All 46 mutants of the generator are killed on all three Schemes, each by a counted
    test failure, as were the 13 mutants the reviews built, each when it was made.
- **The contract review**, before building, found:
  - which calls happen on a path that raises was unspecified;
  - the rollover vector could not tell LAST-MS + 1 from NOW + 1, which answers
    decreasing ids;
  - the four table vectors shared their last 8 bytes;
  - nothing tested the 2^48 edge.

  All of these were fixed before any builder started.
- **The slice review** found no fault in the library's behaviour. It found five
  untested paths, each with a surviving mutant, and doc and signature slips:
  - a full counter, then the clock moving on;
  - a bad entropy answer at a new tick after a first id;
  - the generator's opacity;
  - a bad NOW on an exhausted generator;
  - v4 answers indistinguishable from strings.
- **The reset review** found:
  - two wrong libraries passing both suites: state changed by a raise on the reset
    path, and the edge unpinned on the rollover path;
  - the departure from §6.2's SHOULD, which the recommendation to the owner had missed;
  - about a dozen untrue claims, among them "always increase", "breaks once", "10
    seconds ahead" (it is 10.001) and the rate that resets without a clock fault.
- **Caught in hand-backs:**
  - **Guile's `-L` order.** Guile searches `-L` directories in the order given, so the
    scaffold's Guile lane searched `tests/` before `src/`, though its comment said the
    opposite. A shadow library planted in `tests/` replaced the core for all 150 of
    its tests. `make check-tests` had always refused such a file. The Makefile now puts
    `src/` first.
  - A builder's stub runs on Guile had loaded the real library through that order. It
    was told, and reran them.
- **Traps recorded in AGENTS.md:** Guile's `-L` order. To test a stand-in library, put
  its directory first on both Schemes.
- **Also learned:**
  - SRFI-19's `time-monotonic` runs 37 s ahead of `time-utc` on both Schemes.
  - A clock held exactly 10 s behind cannot stay held past a rollover: the rollover
    puts it 10.001 s behind.
  - A stray `git stash` and `git stash pop` in one command did no harm, but is no
    way to work.

### Slice 1, the core: PR #2, 2026-11-22

- **What merged:**
  - **The library:** `src/unique-id.sls`, `(unique-id)`, with 15 exports, built to the
    contract in [slice-1.md](slice-1.md).
  - **The suites:** text (49 tests), core (150) and order (33). RFC 9562's vectors are
    copied from its text, and the property tests are seeded.
  - **Records:** ADR-0005, and an amendment to ADR-0004. Also README.org, CHANGELOG.md,
    and new traps in AGENTS.md.
- **The owner's choices:**
  - `uuid-version : Uuid -> (U Nat #f)`, #f outside variant `rfc9562`, where the brief
    had `Uuid -> Nat`.
  - `string->uuid` raises for a non-string.
  - A keyed hash comes in slice 3, and `uuid-hash` stays.
- **Chosen with the slice:**
  - Every export checks its own arguments: who is its name, the one irritant is the bad
    argument, checked first to last.
  - Variants are symbols.
  - The hash rotates and xors within 23 bits.
  - The record is generative.
- **How it was built:**
  - Four Sonnet agents in parallel, from one contract: the library and the three
    suites. Each suite had to fail every test against a stub that only raises.
  - Then a Sonnet mutation run and a read-only adversarial review on Opus.
  - Two Sonnet agents fixed what they found.
- **Verified:**
  - `make test` on Chez 10.4.0 and Guile 3.0.11, and the Guile lane on Guile 3.0.9.
  - CI on amd64 and arm64, with Chez 10.4.1 and Guile 3.0.9.
  - All 76 mutants of the library are killed on all three Schemes, each by a counted
    test failure.
- **Caught in hand-backs:**
  - The library's record had a fixed `nongenerative` uid. Any program could define the
    type again, make 3-byte ids, and change `nil-uuid`'s own octets, on both Schemes.
    The record is now generative.
  - A builder claimed `record?` needs `(rnrs records inspection)`. It does not:
    `(rnrs)` has it on both Schemes.
  - A suite dropped its `string-set!` freshness test, reading `(rnrs mutable-strings)`
    as forbidden. It is allowed, and the test is back. It kills a caching
    `uuid->string`.
- **The review:** 9 findings, each reproduced.
  - **Test gaps.** Untested were the characters next to the hex ranges (`/`, `@`, `` ` ``),
    the variant boundaries (the mutation run's 3 survivors), and exact non-integers
    such as `1/2`. All are now tested, and each kills mutants made for it.
  - **`uuid-version` answered 7 for ids that are not v7.** It is now #f outside the
    RFC's variant.
  - **`uuid-hash` is unkeyed and linear under xor**, so ids that share a hash cost
    nothing. README.org warns, and slice 3 adds a keyed hash.
  - **Guile's `struct-ref` reaches an id's octets.** ADR-0004 now says "within R6RS".
  - **The rest:** comment and signature slips, and an ADR claim about Guile's who.
- **Traps recorded in AGENTS.md:**
  - `string-set!` and `string-fill!` are in `(rnrs mutable-strings)`, and `quotient`,
    `remainder` and `modulo` in `(rnrs r5rs)`: none is in `(rnrs)`.
  - `number->string` in radix 16 is upper case on Chez and lower case on Guile.
  - A fixed `nongenerative` uid opens a record type to any program.
- **Also learned:**
  - On Guile, a record accessor's raise carries no who condition at all.
  - The Guile lane runs uncompiled, so its timings are not Guile's speed: `uuid-hash`
    took 7 µs there and 2 µs compiled.

### The scaffold: PR #1, 2026-11-22

- **What merged:**
  - **Build and pin:** the Makefile, with `help`, `check-help`, `submodules`,
    `check-pins`, `check-chez`, `check-guile`, `deps`, `dev`, `dev-guile`, `run`, `test`,
    `test-chez`, `test-guile`, `test-tools`, `check-suites`, `check-imports`,
    `check-tests` and `clean`. `scripts/require-chez`, `scripts/require-guile`,
    `scripts/guile-prelude.scm`, and `scripts/ci/build-chez.sh` from threading.
    chez-srfi pinned at `7879b52`.
  - **Test harness:** `(unique-id-testing)`, plain R6RS, for both lanes;
    `(unique-id-checks)`, Chez's, for the audits. Three audit programs, one library-lane
    suite, four audit suites and their fixtures.
  - **CI and docs:** CI, AGENTS.md with its rule for signatures in comments, README.org,
    CHANGELOG.md, Akku.manifest.
  - **Plans:** ADR-0001 to ADR-0004, the global constraints, and the owner's answers in
    the brief.
- **The owner's choices:** the name `unique-id`; an id is a record, and `uuid-hash` is
  exported; the suites run on Chez and on Guile; the package goes to Akku later.
- **Chosen with the scaffold:** three libraries, `(srfi :19)` in `(unique-id system)`
  alone; the audits in `tools/` on Chez alone; Ubuntu's Guile in CI.
- **Verified:**
  - `make test` passes on Chez 10.4.0 and Guile 3.0.11 locally, and the Guile lane on a
    Guile 3.0.9 from the Guix store.
  - CI's first run built Chez 10.4.1 on both images (`ta6le` and `tarm64le`), ran
    Ubuntu's Guile 3.0.9, and passed every lane on each.
  - 27 mutants of the harness and the audits are all killed.
- **The review:** a read-only adversarial review, on Opus, found 10 defects, each
  reproduced and fixed before merge.
  - `tests/` was unaudited: a `.guile.sls` beside the testing library let a failing
    suite pass on Guile. `make check-tests` now holds `tests/`.
  - The Guile lane read `GUILE_LOAD_PATH`, `GUILE_LOAD_COMPILED_PATH` and the user's
    compiled cache, and Guile 3.0.9 wrote log files into the tree. The lane now runs
    with `GUILE_ENV`, from `build/guile`.
  - The rest were false claims: the SRFI-64 rules stated for one Guile, a fixnum bound
    a bit too wide, an `equal?` hashtable claim, the prelude's reach, three comments,
    the brief's rendering, and minor breaches of the signature rule.
  - Its fix for the prelude, keeping `warn`, brings back the core warnings on both
    Guiles; the comments were corrected instead.
- **Traps recorded in AGENTS.md:**
  - chez-srfi and Guile 3.0.9 turn a raise in the actual expression into `#f`; Guile
    3.0.11 counts it a failure.
  - `equal?` on records: `#f` on Chez, `#t` on Guile. Tests never compare ids with it.
  - A suite's top level on Guile sees Guile's own names, such as `string-map`.
  - Guile prefers `STEM.guile.sls` to `STEM.sls`.
- **Also learned:**
  - `bytevector`, `bytevector-append` and `read-bytevector` are R7RS, not R6RS.
  - Ubuntu 24.04's `guile-3.0` is 3.0.9, in universe, built for arm64 too.
  - Guile reads compiled files from its cache even with `--no-auto-compile`.
