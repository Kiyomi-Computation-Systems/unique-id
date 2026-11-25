# Contributing to unique-id

Thanks for helping. A **small fix**, such as a typo, a doc fix, or a bug with a
test that shows it, needs only the checks below. **Bigger work**, such as a new
export, a new dependency, a change to how a generator orders its ids, or another
UUID version, starts as an issue, so the design is agreed before the code is
written. [RFC 9562](https://www.rfc-editor.org/rfc/rfc9562) is the judge of
what an id is and how its bits are laid out, so changing that is a design
decision, not a fix.

## Setup

You need Linux or macOS, on x86-64 or arm64, with Chez Scheme (as `scheme` or
`chez`), Guile 3 (as `guile` or `guile-3.0`), GNU make and GNU `timeout`
(`brew install coreutils` on macOS). The Build and test section of
[README.org](README.org) gives the versions CI runs.

```sh
git clone https://github.com/Kiyomi-Computation-Systems/unique-id.git
cd unique-id
make submodules
make test
```

`make submodules` clones chez-srfi at its pin into `vendor/`. On Chez, the
suites take SRFI-64 from it, and `(unique-id system)` takes SRFI-19; Guile has
its own. `make help` lists every target.

`make test-chez`, `make test-guile` and `make test-tools` each run one lane.
`make run PROGRAM=try.sps` runs a program on Chez with the library on its path,
and `make dev` and `make dev-guile` start a REPL.

## The checks

CI runs these on every pull request, on Linux: `make test` and
`make check-pins` on amd64 and on arm64, and `make check-site` once. Keep them
green:

- `make test`: the audits, then the tooling's suites on Chez, the library's
  suites on Chez and on Guile, and every example in `docs/` on both. It fails
  if any of them fails or hangs.
- `make check-pins`: chez-srfi's gitlink and its checkout are both at the pin.
- `make check-site`: the docs site's generator passes its tests, and every page,
  link and anchor in `docs/` resolves. It needs `libcmark-gfm`
  (`apt install cmark-gfm`, `brew install cmark-gfm`), and fetches
  chez-cmark-gfm once.

## When you change…

- **A comment above an export in `src/`:** run `make reference`, and commit the
  `docs/reference.md` it writes. `make test` fails while that page is out of
  date. The signature and the paragraph after it are the API reference, so
  write them for a user. Notes for whoever changes the code go in a later
  paragraph, after a line that is `;;` alone.
- **An example in `docs/`:** `make test` runs each page's examples as one
  program on Chez and on Guile, and compares each `;; =>` result with what
  `write` writes; `make check-docs` runs just that. So a page's `scheme` code
  blocks hold one `import`, first, define each name once, and never mention
  `exit`. A random result is written `;; => e.g. VALUE`, and only its shape is
  checked. AGENTS.md has the rules in full.
- **A page in `docs/`:** it is for people using the library, so keep it short
  and plain. A new page goes in `docs/` and in `site/pages.sls`, the nav's
  order. A link goes to a page, a heading on the same page, or a library's
  section of the reference; `make check-site` fails on one that dangles.
- **The chez-srfi pin:** move the submodule, `SRFI_PIN` in the Makefile and
  `Akku.manifest`'s range for chez-srfi together, on a commit of their own.
  `make check-pins` fails until the gitlink and the checkout are both at
  `SRFI_PIN`.
- **The Makefile:** give each new target a `## ` description on its target
  line, and add it to `.PHONY`, which stays on one line. `make check-help`
  fails until both are done.
- **A new directory outside `src/`:** the Akku package is the libraries under
  `src/`. `.akkuignore` keeps every other directory out of it, by name at any
  depth, so name the new one there too.

## Code

- The library is three plain R6RS libraries under `src/`. Each file's first
  line is `#!r6rs`, and it imports only `(rnrs ...)` (but not `(rnrs eval)`),
  the other `(unique-id ...)` libraries and, in `(unique-id system)` alone,
  `(srfi :19)`. `make check-imports` holds it.
- Nothing in `src/` or `tests/` may depend on Chez or on Guile: no procedure
  and no reader syntax of either. AGENTS.md lists the places the two differ,
  such as `equal?` on records and `number->string` in radix 16.
- **Functional core, imperative shell.** `(unique-id)` reads no clock and no
  randomness: whatever varies is an argument. `(unique-id generator)` keeps
  state, and `(unique-id system)` reads the clock and `/dev/urandom`.
- Each export has a comment directly above it: its type, Typed Racket style,
  then what it answers. `;; string->uuid : String -> (U Uuid #f)`. AGENTS.md
  has the type names.
- The library runs on Linux and macOS, on x86-64 and arm64. CI runs Linux only,
  so say in the pull request where else you tested.
- Comments and docs say what the code does and why, in the present tense.
  They don't cite issues, pull requests, plans or dates; that history belongs
  in commits and CHANGELOG.md.

## Tests

- Write the test first, and watch it fail before you make it pass. A test
  that passes whether the code is right or wrong is worse than none.
- A change in behavior comes with a test that fails without it.
- An id's test vectors come from RFC 9562's own text, with the section in the
  test's name, and the keyed hash's from the SipHash reference implementation.
  Never take one from memory, or from a run of this library: a value read off
  the code under test keeps passing after the code is wrong.
- A property test draws its inputs from a seeded generator written in the
  suite, so a failure reproduces. Name the seed and the number of cases in the
  test.
- Hold a generator's clock and entropy with scripted stand-ins: a clock that
  answers a list of times, and an entropy source that answers given bytes.
  Assert what was asked for as well as what came back.
- Compare ids with `uuid=?`, or compare their `uuid->string`. Never use
  `equal?` or `test-equal`, which Chez and Guile answer differently for
  records.
- Neither Scheme fixes the order in which a call's arguments are evaluated,
  and a `let`'s inits are arguments too. Use `let*` when one must run before
  another.
- A library suite is `tests/test-<name>.sps`, plain R6RS, written with SRFI-64,
  and runs on both Schemes. It ends with `(exit (suite-exit-status runner))`,
  which `make check-suites` checks. chez-srfi's SRFI-64 and Guile's treat a
  raise differently, and Guile's changed between releases; AGENTS.md says how
  to write a test that holds on all of them.
- A suite that needs Chez's own procedures, to fork a process, say, goes under
  `tools/`, on Chez alone.
- Test what the code does, never what a comment says.

## Pull requests

- Commit messages and PR titles follow
  [Conventional Commits](https://www.conventionalcommits.org): `feat:`,
  `fix:`, `docs:`, `test:`, `refactor:`, `chore:`.
- Name a branch for its work, in a word or two: `generator`, `release-0.1.0`.
- Pull requests are squash-merged, so the PR title becomes the commit's.
- A change users can see gets an entry under `## [Unreleased]` in
  [CHANGELOG.md](CHANGELOG.md).

## How the project is developed

Feature work starts as a plan in `.plans/`, and each lasting decision gets a
numbered record in `.plans/decisions/`. `.plans/progress.md` is the ledger:
where the project stands, and what each merged change did.
`.plans/global-constraints.md` gathers the records' hard rules, and
[AGENTS.md](AGENTS.md) holds the project's rules in full. Following them is
encouraged for features, not demanded of small fixes. Release archives leave
out `.plans/` and AGENTS.md; read them in the repository.

## Security

Don't open a public issue for a suspected vulnerability.
[SECURITY.md](SECURITY.md) says how to report it privately.
