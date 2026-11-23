# Release 0.1.0

The first release of unique-id. Read it with [global-constraints.md](global-constraints.md)
and AGENTS.md.

## The owner's choices, 2026-11-23

- **Version 0.1.0**, the version `Akku.manifest` already names. CHANGELOG.md says the API
  may change in any release before 1.0.
- **A git tag only.** `v0.1.0`, annotated `Release v0.1.0`, as threading's are. Pushing it
  deploys the docs site. Akku comes later: `akku publish` signs with the owner's key, so the
  owner runs it.
- **Before the tag:**
  1. a read-only review of the whole library, on Opus, and the fixes it calls for;
  2. `make check-docs`: every example in `docs/` runs as a program on Chez and on Guile,
     and each `;; =>` result is compared, in `make test`;
  3. the package installed by Akku into a clean checkout, and a program using it run on
     Chez and on Guile; and install steps in the docs and README.org;
  4. the small test gaps the ledger lists: the lanes' search order, and `run-check`'s
     `$CHEZ` and stdin.

## After the review, 2026-11-23

The whole-library review found the libraries sound against RFC 9562, the keyed hash
correct and every example right on both Schemes. The owner chose, each the recommended
option:

- **Document the rollover reset**, which ADR-0006 already records: a generator asked
  for more ids than its milliseconds hold runs ahead of the clock, and resets once 10
  seconds ahead. The docs had promised a falling clock as the one reset.
- **`bytevector->uuid` keeps raising** for a bytevector that is not 16 long.
- **The names stay**: `generate-v4`, `generate-v7`, `system-clock`, `system-entropy`
  and the variant `rfc9562`.

The docs now also say that `uuid-hash`'s numbers may change in a later release, and to
show an id with `uuid->string`. `generate-v7`'s comment gives the reentrancy reason
that holds: ENTROPY is called after G's state is read.

## After the final review, 2026-11-23

A read-only review on Opus found the docs suite failing from a clean `build/`: it ran
a program before the step that writes it, as a `let`'s inits may run in any order. It
also found `;; =>` lines that were neither checked nor refused, `e.g.` shapes loose
enough to hide Chez's upper-case hex, whitespace collapsed inside strings, a page that
could exit early, and the generator's rates overstated. A Sonnet fixer changed the
check; I changed the docs and records. The rules as built are ADR-0010's, which
supersede the section on `make check-docs` below where the two differ.

## Files and owners

| Files | What | Owner |
|---|---|---|
| `tools/unique-id-doc-examples.sls`, `tools/doc-examples.sps`, `tools/test-unique-id-doc-examples.sps`, `tools/fixtures/doc-examples/**`, the Makefile | `make check-docs` | builder A |
| `tools/test-unique-id-checks.sps`, `tools/fixtures/run-check/**` | `run-check`'s tests | builder B |
| `tools/fixtures/lane-order/**`, the Makefile's `chez_libdirs`, `guile_flags` and `check-lane-order` | the lanes' search order | me, done before the builders |
| `src/`, `docs/`, README.org, CHANGELOG.md, AGENTS.md, `.plans/`, `Akku.manifest`, `.akkuignore`, `ci.yml` | the review's fixes, install steps, records | me, or a fixer I brief |

No builder edits a file it does not own. A fault found in someone else's file is reported,
not fixed.

## `make check-docs` (builder A)

### What it does

- **A page's examples are one program.** Its ` ```scheme ` blocks, in the order they
  appear, are the body of one R6RS top-level program, `build/doc-examples/PAGE.sps`, PAGE
  being the page's name without `.md`. Other fences, ` ```sh `, ` ```text ` and bare
  ` ``` `, are not code. A page with no ` ```scheme ` block makes no program.
- **The program runs on Chez and on Guile**, and fails, exiting 1, if any checked result
  differs or a form raises.
- **A result is checked** when a line that starts `;; =>` comes directly after a
  top-level form, with nothing between them but blank lines. The text after `;; =>` is
  the expected value. It continues on each following line that starts `;;` followed by
  two or more spaces; those lines' text, after the `;;`, joins it with a space. A line
  that starts `;; ` and then a word is a comment, and is ignored.
- **Comparing.** The form's value, as `write` writes it, is compared with the expected
  text, after every run of whitespace in each is made one space and each is trimmed.
- **`;; => e.g. EXAMPLE`** shows a random value. Its check compares shapes: in the
  written value and in EXAMPLE, every maximal run of the characters `0-9`, `a-f` and
  `A-F` becomes `x`, and the two must then be equal. So `"01a2-77"` and `"ffff-12"`
  match, and `"01a2-77"` and `#f` do not.
- **A failure names its place**: `PAGE.md:LINE: expected TEXT, got TEXT`, LINE being the
  `;; =>` line in the `.md` file, on stderr. A raise inside a checked form is reported
  at that line, as `PAGE.md:LINE: raised`, followed by the condition's who, message and
  irritants where it has them. A raise in an unchecked form ends the program with a
  non-zero exit, as any uncaught raise does.

### What the generator refuses

The generator, not the Scheme, refuses a page, naming `PAGE.md:LINE` and the rule, and
exits 1. It still writes every page it can.

- a `;; =>` after a definition (`define`, `define-record-type`, `define-syntax`), or with
  no form before it in its block;
- any `import` form but one, which must be the first form of the page's first
  ` ```scheme ` block;
- a name defined twice in one page: R6RS refuses that in a program's body, and the
  generator names both lines;
- a block that does not read as data, such as an unclosed parenthesis;
- a page that defines a name starting with the prefix the check's own definitions use.

A `#!r6rs` line in a block is dropped. The program's import is the page's import form,
with `(rnrs)` added when it is missing. The check's own definitions come after the
import and before the page's forms; they are written into each program, not imported.

### Interfaces

- `(unique-id-doc-examples)`, under `tools/`, runs on Chez alone and may use `(only
  (chezscheme) ...)`. It holds the parsing, the shape rule, the normalising and the
  program text, as procedures its suite can call on strings.
- `tools/doc-examples.sps DOCS-DIR OUT-DIR` writes one program per page into OUT-DIR,
  which it empties of `*.sps` first, so a deleted page leaves no program behind.
- **`make check-docs`** runs the generator into `build/doc-examples/`, then two lanes
  built with the Makefile's `lane` function: `docs-chez` runs each program as
  `$(CHEZ) --libdirs $(LIBDIRS) --program`, and `docs-guile` as `$(GUILE_ENV) $(GUILE)
  --r6rs --no-auto-compile -L $(abspath src) -l $(abspath scripts/guile-prelude.scm)`.
  The lanes give the timeout and descriptor cap the suites get.
- **`make test`** runs the generator and both docs lanes after its three lanes, in the
  same way: every lane runs, and the run fails if any did. A generator failure counts
  as a failed lane.
- `check-docs` goes in `.PHONY`, and `make help` lists it; `make check-help` holds both.

### Its suite

`tools/test-unique-id-doc-examples.sps`, in the tools lane, ends with the shared exit
form. Fixture pages under `tools/fixtures/doc-examples/` use `(rnrs)` alone, so the
programs made from them run on the tools lane's path. Tests must cover:

- a page whose results all match: its program exits 0, and its output is asserted whole;
- a wrong result: exit 1, and the message names the right `PAGE.md:LINE`, expected and
  got;
- a result continued on two `;;` lines, matching and not matching;
- `e.g.` results: a matching shape, and a non-matching one, such as a string for a
  number;
- a raise in a checked form, reported at its line, with the program going on to check
  the forms after it;
- each refusal above, by its line;
- other fences ignored, a page with no ` ```scheme ` block making no program, a
  `#!r6rs` line dropped, and `(rnrs)` added to an import without it;
- the normalising and the shape rule on their own, on strings.

Each test is watched failing: break the code it covers, see the test fail, and undo.
Report the breaks you made and which tests failed for each.

### Against the real `docs/`

Run `make check-docs` on the real pages and report what it says. Two pages are expected
to be refused, because each defines a name twice: `generators.md` defines `g` twice, and
`hashing.md` defines `hash` twice. Do not edit `docs/`: I rename those. Report anything
else it finds, with the line.

## `run-check`'s tests (builder B)

`run-check`, in `tools/unique-id-checks.sls`, runs a program as `$CHEZ --libdirs
$TOOL_LIBDIRS --program PROGRAM ARGS...`, with stdin from `/dev/null`. Two of its
promises are untested. Add tests to `tools/test-unique-id-checks.sps`:

1. **It runs `$CHEZ`**, not the `scheme` on `PATH`. Point `CHEZ` at a stand-in, an
   executable `#!/bin/sh` script under `tools/fixtures/run-check/`, through Chez's
   `putenv`, and restore it after, even if the test raises. The stand-in writes a fixed
   line and its arguments, one to a line. Assert `run-check`'s whole answer: the status,
   the stdout and the stderr.
2. **Its child's stdin is `/dev/null`.** The test must fail when `run-check` passes on its
   own stdin, however the suite was started: at a terminal, in CI, or under `make` with
   stdin already `/dev/null`. So for the call, make the suite's own descriptor 0 a file
   that holds known bytes, through libc's `open`, `dup` and `dup2` (load libc as
   `tools/fork-probe.sps` does), and put the original back after, even if the test
   raises. The stand-in copies its stdin to stdout. Assert that nothing of the file
   arrives.

Commit the stand-in executable: its mode must be 100755 in git. Do not edit
`tools/unique-id-checks.sls`; if `run-check` is wrong, report it. Watch each test fail on
a copy of the library under `build/` with the promise broken: `scheme` for `$CHEZ`, and
no `</dev/null`. Report the breaks and which tests failed.

## Done by me

- **The lanes' search order.** `make check-lane-order`, run by `make test`, runs a probe
  on each lane's path, built by `chez_libdirs` and `guile_flags`, with a stand-in
  `(unique-id)` where `tests/` is, and fails unless `src/`'s wins. It also fails unless
  each Scheme refuses the probe with the stand-in first. It failed with each lane's order
  swapped, and with the stand-in removed.
- **The Akku check.** In a clean clone, `akku install`, then a program importing all three
  libraries run under `.akku/env` on Chez and on Guile. By hand: it needs the network and
  Akku.
- **Install steps** in `docs/getting-started.md` and README.org: using the libraries from a
  checkout or the tag in your own project, on Chez and on Guile.
- **The review's fixes**, the renames for `check-docs`, AGENTS.md, CHANGELOG.md's
  `## [0.1.0] - DATE`, and the ledger.

## How it is checked

- `make test` and `make check-site` pass on Chez 10.4.0 and Guile 3.0.11, and the Guile
  lanes on Guile 3.0.9; CI passes on amd64, arm64 and the `docs` job.
- A read-only adversarial review on Opus of everything this piece changed.
- The tag is pushed only when the owner says so.
