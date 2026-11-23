# Getting started

Use `unique-id` from a checkout. It is three plain R6RS libraries. The
commands below use Chez Scheme because the repository's own `make` targets do;
Guile 3 runs the same libraries and the same tests.

## Get the checkout

```sh
git clone https://github.com/Kiyomi-Computation-Systems/unique-id.git
cd unique-id
```

That is the latest code. For the 0.1.0 release, add `--branch v0.1.0` to
`git clone`. Use git rather than a downloaded archive: `make submodules`, below,
needs it.

You need Chez Scheme (as `scheme` or `chez`), Guile 3 (as `guile` or
`guile-3.0`), GNU make and GNU `timeout`. The Makefile finds the Schemes. On
macOS, `brew install coreutils` gives you `gtimeout`.

```sh
make submodules
make test
```

`make submodules` clones chez-srfi, which the tests and `(unique-id system)`
use on Chez. Guile has its own. `make test` checks the code and runs every
suite on both Schemes. `make help` lists every target.

## Make an id

Save this as `try.sps` in the checkout:

```scheme
#!r6rs
(import (rnrs) (unique-id) (unique-id generator) (unique-id system))

(define gen (make-system-uuid-generator))
(display (uuid->string (generate-v7 gen)))
(newline)
```

Run it:

```sh
make run PROGRAM=try.sps
```

It first prints a `check-chez: Chez Scheme Version ...` line and the `scheme
--libdirs ... --program ...` command it runs, then an id such as
`01a20830-6807-74fc-9c85-3f03c11b49fa`. The id is different every time.
`make run` gives Chez the `src/` directory and chez-srfi, which
`(unique-id system)` needs. `make dev` starts a Chez REPL with the same paths.

## Use Guile

From the checkout:

```sh
guile --r6rs --no-auto-compile -L "$PWD/src" -s try.sps
```

`--r6rs` selects Guile's R6RS mode, and `-L` puts `src/` on its path. Guile
prints a `WARNING: ... overrides core binding` line to stderr for each core
name `(rnrs)` replaces. They are harmless.

## Use it from another directory

On Chez, give `--libdirs` this checkout's `src/` directory. A program that
imports `(unique-id system)` also needs chez-srfi, which `make deps` links into
`build/scheme-libs`. Separate the directories with a colon:

```sh
scheme --libdirs /path/to/unique-id/src:/path/to/unique-id/build/scheme-libs \
  --program /path/to/your-program.sps
```

Use `chez` if that is your Chez's name. A program that imports only
`(unique-id)` and `(unique-id generator)` needs `src/` alone.

On Guile, `src/` is enough, since Guile has SRFI-19. Keep `--r6rs`:

```sh
guile --r6rs -L /path/to/unique-id/src /path/to/your-program.sps
```

## Use another R6RS implementation

Find its library-path option and point it at `src/`. The files are
`src/unique-id.sls`, `src/unique-id/generator.sls` and
`src/unique-id/system.sls`. `(unique-id)` imports `(rnrs)` alone;
`(unique-id generator)` imports `(rnrs)` and `(unique-id)`.
`(unique-id system)` needs `(srfi :19)` and `/dev/urandom` too. The tests run on
Chez and Guile only, so run a small program of your own before you depend on
another Scheme.

Next, [make a few ids](quickstart.md).
