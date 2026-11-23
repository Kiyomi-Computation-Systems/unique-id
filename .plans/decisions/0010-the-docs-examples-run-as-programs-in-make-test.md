# ADR-0010: The docs' examples run as programs in `make test`

- **Status:** Accepted. The owner chose on 2026-11-23 that every example in `docs/` be
  checked, in CI, before 0.1.0. The rest was chosen with the work, and the owner
  accepted the whole record on 2026-11-23.
- **Date:** 2026-11-23
- **Scope:** `tools/unique-id-doc-examples.sls`, `tools/doc-examples.sps`, their suite
  and fixtures, the Makefile's `check-docs` and `test`, and how `docs/` writes examples
- **Related:** ADR-0009, whose consequence that nothing runs the guides' examples this
  ends; ADR-0001, whose rule 5 keeps the generator in `tools/`, on Chez alone

## Context

ADR-0009's pages show results as `;; => value`, and every one was run by hand on both
Schemes. Hand runs missed one: the home page's first example printed `#f` on Chez,
which makes a call's arguments in an order of its own. Nothing would catch a change
to the library that left a guide wrong.

## Decision

1. **A page's examples are one program.** Its ` ```scheme ` blocks, in order, are the
   body of one R6RS top-level program: one `import`, first, and each name defined once.
   A block opens with exactly ` ```scheme ` at column 0; other fences are not code.
2. **A result is a `;; =>` after a top-level form**, on the form's line, or starting a
   line with only blank lines between, and going on over lines of `;;` and two or more
   spaces. The form's value, as `write` writes it, must equal the text, each run of
   whitespace outside strings made one space. `;; => e.g. VALUE` is a random result,
   checked for its shape: inside strings, each digit and lower-case hex letter becomes
   `x`, one for one; outside, each run of hex digits becomes one `x`.
3. **The generator refuses a page**, naming the line, when it breaks rule 1, puts a
   result after a definition, has a `;; =>` it does not take as a result, has a scheme
   fence it does not read, mentions `exit`, or defines a name with the check's own
   prefix. A refused page's program is a stub that names the refusals and fails, so
   the lanes report the page.
4. **`make test` runs every page's program on Chez and on Guile**, in the lanes
   `docs-chez` and `docs-guile`, under the suites' timeout and descriptor cap. So CI's
   `linux` jobs run it; `make check-docs` runs it alone.
5. **The generator is tooling**, `(unique-id-doc-examples)` and `tools/doc-examples.sps`
   in `tools/`, on Chez alone. The programs it writes are plain R6RS, with the check's
   own definitions written into each.

## Consequences

- A change to the library that changes an example's answer fails `make test`, as does
  an example that raises or a page that breaks the rules.
- Writers follow the example rules in AGENTS.md. Two pages renamed a generator and a
  hash that they defined twice.
- A random result is checked for its shape alone, and what an example prints with
  `display` is not checked. Nothing checks that the prose is true.
- A form that answers several values passes on Guile, which keeps the first; Chez
  refuses it, so the Chez lane fails the page.
