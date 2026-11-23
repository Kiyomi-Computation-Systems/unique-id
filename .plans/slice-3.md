# Slice 3: the system, `(unique-id system)`, and the keyed hash

This is the contract the libraries and their suites are built to. RFC 9562's rules come
from its text, fetched from rfc-editor.org on 2026-11-22, and each cites its section.
HalfSipHash's rules and vectors come from the SipHash reference repository,
https://github.com/veorq/SipHash, at commit `32d067603b93b47828700880649198e0bfbbcffa`:
its `halfsiphash.c` and `vectors.h`. A read-only review of this contract, on Opus, came
before any building; its findings are folded in. ADR-0007 and ADR-0008 record the
decisions.

## Files

| File | What it holds | Who |
|---|---|---|
| `src/unique-id.sls` | the core, `(unique-id)`, which gains one export, `make-uuid-hash` | library builder |
| `src/unique-id/system.sls` | the library `(unique-id system)`, importing `(rnrs)`, `(srfi :19)`, `(unique-id)` and `(unique-id generator)` | library builder |
| `tests/test-unique-id-keyed-hash.sps` | suite `unique-id-keyed-hash`: `make-uuid-hash`, by the reference's vectors and by properties | keyed-hash suite builder |
| `tests/test-unique-id-system.sps` | suite `unique-id-system`: the system's clock, entropy, generator and hash | system suite builder |
| `tools/unique-id-checks.sls`, `tools/test-check-tests.sps`, `tools/fixtures/suite-trees/legal/` and `.../imports/`, `Makefile` | `make check-tests` lets `tests/` import `(srfi :19)`; the lanes cap file descriptors at 64 | tools builder |
| `tools/test-system-fork.sps`, `tools/fork-probe.sps` | suite `system-fork`, Chez alone: a forked child never repeats its parent's entropy | fork builder |
| `.plans/`, `AGENTS.md`, `README.org`, `CHANGELOG.md`, `Akku.manifest` | the records and docs | me, not a builder |

## Measured before this contract

On the host, Chez 10.4.0 with chez-srfi at the pin, and Guile 3.0.11, in the lanes' modes:

- **A buffered `/dev/urandom` port repeats itself across a fork.** A port opened with the
  default buffer mode, read once, then read for 16 bytes by the parent and by a forked
  child, gave both the same 16 bytes, on Guile through `primitive-fork` and on Chez
  through `(foreign-procedure "fork" () int)`. With a port opened unbuffered at each
  read they differed. RFC 9562 §6.9: "Take care to ensure the CSPRNG state is properly
  reseeded upon state changes, such as process forks".
- **`(buffer-mode none)` is honoured by both Schemes**: under `strace`, each
  `get-bytevector-n` of 16 bytes is one `read` of 16 bytes. A buffered port reads 8192
  bytes on Chez and 4096 on Guile at its first read.
- **`get-bytevector-n` blocks until it has the count, or the end of file**, on Chez and
  both Guiles, as R6RS requires: a FIFO written in two chunks gave all 6 bytes asked.
- **What a call costs**, 16 bytes, per call:

  | | Chez | Guile, uncompiled |
  |---|---|---|
  | open unbuffered, read, close | 1.6 µs | 6.0 µs |
  | open buffered, read, close | 17.7 µs | 15.2 µs |
  | one shared unbuffered port | 0.33 µs | 0.49 µs |

- **SRFI-19's `time-utc`** answers an exact second and an exact nanosecond on both. Chez's
  nanosecond has full resolution; Guile's is a multiple of 1000. `time-monotonic` and
  `time-tai` both run 37 s ahead of `time-utc`, on Chez and both Guiles.
- **`(only (srfi :19) current-time time-utc time-second time-nanosecond)` imports cleanly
  beside `(rnrs)`**, in a library and in a program, on Chez and both Guiles.
- **R6RS hashtables take any exact nonnegative integer as a hash** on both: 2^32 − 1,
  2^62 and 2^100 all worked.
- **Empty bytevectors are all one object**: `(eq? (make-bytevector 0) (make-bytevector
  0))` is `#t` on Chez and both Guiles. R6RS leaves `eqv?` on empty objects unspecified.
- **A port that is never closed** fails 5000 calls on all three Schemes under `ulimit -n
  64`, and passes on Guile under higher limits, since Guile closes collected ports. Every
  existing suite passes under `ulimit -n 64` on both lanes.

## The keyed hash, in `(unique-id)`

```
make-uuid-hash
```

| Signature | Answers |
|---|---|
| `make-uuid-hash : Bytevector -> (Uuid -> Nat)` | A procedure HASH such that `(HASH ID)` is HalfSipHash-2-4 of ID's 16 octets under KEY, 8 bytes: from 0 to 2^32 − 1. |

**The rules.**

1. **KEY is checked when `make-uuid-hash` is called**: a bytevector of exactly 8 bytes,
   else an assertion violation with who `make-uuid-hash` and KEY the one irritant.
2. **KEY is read then**, into its two 32-bit words, so changing KEY later changes no
   hash.
3. **HASH checks its argument**: an id, else an assertion violation with who
   `make-uuid-hash` and the argument the one irritant, and message "not an id". HASH has
   no name of its own, so it raises under its maker's. ADR-0005 gives a who to exported
   procedures, and this one leads the reader to the docs.
4. **`(HASH ID)` is what the reference computes** as
   `halfsiphash(in, 16, k, out, 4)`, IN the id's 16 octets from octet 0 and K the 8
   bytes of KEY, with its 4 output bytes read little-endian. That is, from the
   reference's `halfsiphash.c`, for a 16-byte input and a 4-byte output:
   - k0 is KEY's bytes 0–3 read little-endian, and k1 its bytes 4–7.
   - v0 = k0, v1 = k1, v2 = k0 xor #x6C796765, v3 = k1 xor #x74656462.
   - For each of the four words m, octets 4i to 4i+3 read little-endian, i from 0 to 3:
     v3 xor= m, two SIPROUNDs, v0 xor= m.
   - b = 16 << 24, #x10000000, since the input's length is 16 and no bytes are left
     over: v3 xor= b, two SIPROUNDs, v0 xor= b.
   - v2 xor= #xFF, four SIPROUNDs.
   - The answer is v1 xor v3.
   - A SIPROUND, all additions modulo 2^32 and ROTL a 32-bit rotation left:
     v0 += v1; v1 = ROTL(v1, 5); v1 xor= v0; v0 = ROTL(v0, 16);
     v2 += v3; v3 = ROTL(v3, 8); v3 xor= v2;
     v0 += v3; v3 = ROTL(v3, 7); v3 xor= v0;
     v2 += v1; v1 = ROTL(v1, 13); v1 xor= v2; v2 = ROTL(v2, 16).
5. **Arithmetic is generic**, never `fx`: a 32-bit word passes R6RS's promised fixnum
   range. Keep every intermediate value below 2^33: mask each sum with #xFFFFFFFF, and
   rotate x left by b as the low 32 − b bits shifted left by b, or'd with x shifted right
   by 32 − b. The largest value is then a sum before its mask, at most 2^33 − 2: a
   fixnum on 64-bit Chez and Guile, and still right on a Scheme whose fixnums are
   narrower.
6. **Procedures made from equal keys answer alike.**

`uuid-hash` stays as it is: the fast hash for ids a program made itself.

**Vectors.** Ids are given as the hex of their 16 octets.

- **From the reference's own `vectors.h`**, `vectors_hsip32[16]`, the entry for a 16-byte
  input: KEY `0001020304050607`, the id `000102030405060708090a0b0c0d0e0f`. Its bytes are
  `d9 b5 ac 84`, so the answer is #x84ACB5D9.
- **Computed by the reference's own `halfsiphash.c`**, at the commit above, compiled with
  gcc and called as `halfsiphash(in, 16, k, out, 4)`. The driver reproduces the
  `vectors.h` entry above first. The review rebuilt the driver and reproduced every one.

  | KEY | Id | Answer |
  |---|---|---|
  | `0001020304050607` | `00000000000000000000000000000000` | #x805566E3 |
  | `0001020304050607` | `ffffffffffffffffffffffffffffffff` | #xB1F9F81A |
  | `ffffffffffffffff` | `ffffffffffffffffffffffffffffffff` | #x8E3AA694 |
  | `0000000000000000` | `00000000000000000000000000000000` | #xE29C7B3E |
  | `0001020304050607` | `017f22e279b07cc398c4dc0c0c07398f` (A.6) | #xCB9E911D |
  | `0001020304050607` | `919108f752d143209bacf847db4148a8` (A.3) | #xE601E061 |
  | `fcc318c4dc0c0c07` | `017f22e279b07cc398c4dc0c0c07398f` (A.6) | #xB181D3F3 |
  | `0100000000000000` | `00000000000000000000000000000000` | #x041D64AF |
  | `0000000001000000` | `00000000000000000000000000000000` | #xC9F60692 |
  | `0001020304050607` | `00000000000000000000000000000080` | #xCC5B07CE |
  | `0001020304050607` | `80000000000000000000000000000000` | #x54198BA2 |

  The last four tell k0 from k1, and the first octet from the last.

**The suite, `unique-id-keyed-hash`.** It imports `(rnrs)`, `(srfi :64)`, `(unique-id)`
and `(unique-id-testing)`. Each test of a vector names its source: `vectors.h` or the
reference's `halfsiphash.c`.

- **Every vector above, exactly**, each under its own key.
- **The key is read at the call**: KEY `0001020304050607`, then every byte of KEY set to
  0 after `make-uuid-hash` returns and before the first hash, so a key read at the
  first hash is refused too. The zero id still answers #x805566E3, not #xE29C7B3E, the
  zero key's.
- **Two procedures from equal keys**, made by two calls from two bytevectors, answer
  alike for every vector's id, each under that vector's own key.
- **The range**: over 1000 ids from a seeded generator, every answer is an exact integer
  from 0 to 2^32 − 1, at least one is at least 2^31, and at least 999 are distinct.
- **One bit**: flipping any one of the A.6 id's 128 bits changes its answer under the
  `vectors.h` key.
- **Keys**: 16 keys from a seeded generator give 16 distinct answers for the A.6 id.
- **Flooding**: 1024 ids that share one `uuid-hash` take at least 1000 answers under the
  `vectors.h` key. The ids are built at run time, one test, its whole construction in
  that test's actual expression:
  - `uuid-hash` is linear under xor, and the hash of `nil-uuid` is 0.
  - For i from 0 to 9, start from the id whose octet i is 1 and every other 0, take its
    `uuid-hash` s, and set octets 13, 14 and 15 to s >> 16, (s >> 8) & 255 and s & 255.
    Each of the ten has `uuid-hash` 0, and they are linearly independent, since octets 0
    to 9 hold one 1 each.
  - The 1024 ids are the A.6 id xor every subset of the ten.
  - The test asserts, before counting, that the 1024 are distinct by `uuid->string`,
    that each has `uuid-hash` 0 for its ten, and that the 1024 share one `uuid-hash`.
    Its expected value is the tagged outcome of all of it, so a stub fails it.
  - **This one test leans on `uuid-hash` being linear**, against ADR-0005's "the hash
    may change in any release without breaking a suite". If `uuid-hash` changes, this
    test changes with it. A comment in the suite says so.
- **A hashtable**: `(make-hashtable (make-uuid-hash KEY) uuid=?)` finds each of 1000
  seeded ids by a fresh copy of it.
- **Errors**, each with who and irritant asserted, the irritant by `eqv?`:
  - `make-uuid-hash` given a string, a vector, the symbol `key`, 7 bytes, 9 bytes and
    0 bytes;
  - HASH given a 16-byte bytevector, a string, and `#f`.

## `(unique-id system)`

```
system-clock system-entropy
make-system-uuid-generator make-system-uuid-hash
```

| Signature | Answers |
|---|---|
| `system-clock : -> Nat` | The Unix time in milliseconds, from SRFI-19's `time-utc`: its second times 1000, plus its nanosecond div 1000000. |
| `system-entropy : Nat -> Bytevector` | N fresh bytes from `/dev/urandom`. |
| `make-system-uuid-generator : -> Generator` | A new generator over `system-clock` and `system-entropy`. |
| `make-system-uuid-hash : -> (Uuid -> Nat)` | `make-uuid-hash` of a new 8-byte key from `system-entropy`. |

**The imports.** `(rnrs)`, `(only (srfi :19) current-time time-utc time-second
time-nanosecond)`, `(unique-id)` and `(unique-id generator)`. ADR-0002 names those four
SRFI-19 names, which both Schemes have.

**`system-clock`.**
- It calls `(current-time time-utc)` once, naming `time-utc`, and answers
  `(+ (* (time-second t) 1000) (div (time-nanosecond t) 1000000))`.
- Never `time-monotonic` or `time-tai`: each runs 37 s ahead of `time-utc` on both
  Schemes. The generator's CLOCK is the Unix time, leap seconds excluded (§5.7).

**`system-entropy`.**
1. It checks N: an exact integer, 0 or more. Else an assertion violation with who
   `system-entropy` and N the one irritant, and the file is not opened. Test `integer?`
   before `exact?`.
2. When N is 0 it answers an empty bytevector, and does not open the file: that saves an
   open and a close.
3. Else, on every call, it opens `/dev/urandom` with
   `(open-file-input-port "/dev/urandom" (file-options) (buffer-mode none))`, reads N
   bytes with one `get-bytevector-n`, and closes the port, whether the read returns or
   raises: `dynamic-wind`'s after thunk closes it. `call-with-port` would not: it
   closes only when its procedure returns. A raise from opening or reading passes
   through unchanged.
4. When the read answers anything but a bytevector of N bytes, the end of file or a
   short read, it raises with `error`: who `system-entropy`, and the answer the one
   irritant.
5. It answers the bytevector it read, which no one else holds.

**Why a port per call.** No port outlives a call, so nothing buffered can be read twice
by a forked child (§6.9), and no two threads share a port. It costs about 1.6 µs a call
on Chez. A buffered port costs ten times that, since it reads 8192 bytes to answer 16.

**`make-system-uuid-generator`.** Each call answers a new generator,
`(make-uuid-generator system-clock system-entropy)`. The library holds no generator of
its own: a generator belongs to its caller, and one shared among threads would break
that.

**`make-system-uuid-hash`.** Each call answers `(make-uuid-hash (system-entropy 8))`, a
procedure under a new key. Its HASH raises as `make-uuid-hash`'s does, with who
`make-uuid-hash`: a name its caller never called, which the docs say.

**The suite, `unique-id-system`.** It imports `(rnrs)`, `(srfi :64)`, `(only (srfi :19)
current-time time-utc time-second time-nanosecond)`, `(unique-id)`, `(unique-id
generator)`, `(unique-id system)` and `(unique-id-testing)`. Random bytes are never
compared with fixed values. A wrong library fails each property below with certainty;
a right one fails a probabilistic property with the chance given, or none.

- **`system-clock`**:
  - An exact integer, from 1795305600000 (2026-11-22T00:00Z) to below 2^48.
  - Bracketed: the suite reads `time-utc` into milliseconds, with the same formula, just
    before and just after one call, and asserts before ≤ the answer ≤ after. Repeated 100
    times. That refuses a clock in seconds or microseconds, `time-monotonic` and
    `time-tai`, and a nanosecond divided wrongly. It can fail a right library only if
    the wall clock steps back between the reads, as a time daemon's step would.
- **`system-entropy`**:
  - For N of 0, 1, 8, 10, 16 and 100000, a bytevector of N bytes.
  - 64 answers of 16 bytes are pairwise distinct: a right library fails with chance
    about 2^-117.
  - 65536 bytes from one call hold every byte value from 0 to 255: about 2^-362.
  - 65536 bytes from 4096 calls of 16 hold every byte value too: the same.
  - 5000 calls in a row each answer 16 bytes. Under the lanes' cap of 64 file
    descriptors, that refuses a port left open, on all three Schemes.
  - Errors, who and irritant asserted: −1, 1/2, 1.0, `#f` and the symbol `n`.
- **`make-system-uuid-generator`**:
  - Answers a generator, by `uuid-generator?`; two calls answer two that are not `eq?`.
  - 5000 v7 ids from one generator increase strictly under `uuid<?`, each version 7 of
    variant `rfc9562`, each read back by `string->uuid` from its `uuid->string`,
    and each `uuid-v7-timestamp` at least `time-utc`'s milliseconds before the run and
    at most 10001 above them after it.
  - 1000 v4 ids are version 4, pairwise distinct by `uuid->string`: about 2^-103.
  - Two generators' first v7 ids differ: at most 2^-73.
- **`make-system-uuid-hash`**:
  - Each answer for 1000 seeded ids is an exact integer from 0 to 2^32 − 1.
  - Two procedures from two calls differ on at least one of 8 fixed ids: the A.6 id,
    the A.3 id, `nil-uuid`, `max-uuid`, and four more from a seeded generator. A right
    library fails with chance about 2^-64, that of two equal keys; more ids cannot
    lower it.
  - A hashtable keyed by it finds 1000 seeded ids by fresh copies.
  - Its HASH, given a 16-byte bytevector, raises with who `make-uuid-hash` and that
    bytevector as the irritant.

## The fork suite, `system-fork`, on Chez alone

No plain R6RS suite can fork, so this one lives under `tools/`, with the audits' suites,
and runs on Chez alone (ADR-0001 rule 5, amended by ADR-0008).

- **`tools/fork-probe.sps`** is a Chez program, importing `(chezscheme)`, `(unique-id)`,
  `(unique-id generator)` and `(unique-id system)`. It forks through
  `(foreign-procedure "fork" () int)`, and waits with `waitpid`. Chez 10.4.0 finds
  no `fork` entry until libc is loaded, so it loads `libc.so.6` first: the review's
  claim that it resolves without `load-shared-object` was wrong, and the builder
  found it.
  - Before the fork it calls `(system-entropy 16)` once, and makes one system generator
    and one v7 id from it, as a long-running server would have.
  - After the fork, parent and child each take `(system-entropy 16)`, a v4 id and a v7
    id from that generator. The child hands its three to the parent, through a file
    whose path the suite gives it or a pipe, and exits.
  - The parent writes the six, as hex, in an order the suite reads.
- **`tools/test-system-fork.sps`** runs the probe as a child program, on `$CHEZ`, with
  `--libdirs src:build/scheme-libs`, unless the environment's `FORK_LIBDIRS` names
  others, so a mutation run can put its copy first. The tools lane's own path still
  leaves `src/` out. It asserts:
  - the probe exits 0 and writes six well-formed values;
  - parent and child entropy differ, their v4 ids differ, and their v7 ids differ.
- **It must fail against a mutant whose `system-entropy` reads one buffered port opened
  when the library loads**, run through `FORK_LIBDIRS`. That is the fork-unsafe design.
- **It always runs, in the tools lane.** Where `fork` cannot be found, the probe says so
  and exits 3, and the suite fails: it has run on Linux alone, and macOS is unverified.

## The tools: `tests/` may import `(srfi :19)`, and the lanes cap descriptors

- **`make check-tests` lets a file under `tests/` import `(srfi :19)`**, through any
  wrapper, as it does `(srfi :64)`. `import-reference` strips `only`, so one clause
  matching `(srfi :19)` does it. Both lanes have it: chez-srfi's on Chez, Guile's own on
  Guile.
- **`make check-imports` is unchanged**: under `src/`, `(unique-id system)` alone may
  import `(srfi :19)`.
- Every place that states the rule changes with it:
  - `tools/unique-id-checks.sls`: `tests-policy`'s comment and code, and
    `suite-tree-complaints`' rule list;
  - the complaint's text: "a file under tests/ imports only (rnrs ...), (srfi :64),
    (srfi :19), (unique-id ...) and the libraries under tests/";
  - `tools/test-check-tests.sps`: `not-allowed`, the names of the `legal` and `imports`
    tests, the `imports` test's expected complaints, which drop `(srfi :19)`, and the
    `legal` fixture, which imports `(srfi :19)` wrapped, its comment included. `(srfi
    :1)` is still refused.
  - the Makefile's `check-tests` comment and its `##` help line.
- **The lanes run each suite under `ulimit -n 64`**, from a Makefile variable,
  `FD_LIMIT`, chained with `&&` before `exec`, so a shell that refuses the cap runs
  nothing. Each lane's command, the tools lane's included, is then held to it. The
  Makefile's comment says why: a suite that leaks ports fails within 64 calls on every
  Scheme, where Guile's collector would hide it under a higher limit.

## Stubs, and what each suite must fail

- **The keyed-hash suite** fails every test against a copy of the real core whose
  `make-uuid-hash` raises the symbol `stub`, and whose HASH, were one made, would too.
- **The system suite** fails every test against a `(unique-id system)` whose four
  exports each raise the symbol `stub`.
- **The fork suite** fails against the buffered-port mutant above.

A stub raises something no test expects: a stub that raised an assertion violation with
the right who and argument would pass the error tests. Each stub lives under `build/`,
its directory first on both Schemes' library paths: Chez's first libdir and Guile's first
`-L` win. Each is run on Chez, Guile 3.0.11 and Guile 3.0.9, under `ulimit -n 64`, and
the failures counted.

## What the system library promises, and what it does not

- **The clock is the system's wall clock.** It can step back, and the generator handles
  that as ADR-0006 says.
- **Entropy is the kernel's**, read afresh at every call, so a forked child never repeats
  its parent's bytes. A generator's own state, the last millisecond and counter, is
  copied by a fork. When both processes' next v7 ids fall in that millisecond, or the
  clock is behind it, they share their first 64 bits and differ in their 62 random
  bits. At a new tick each draws its own seed.
- **No call shares state with another**: two threads, each with its own generator or
  hash, need no lock. One generator shared between threads still needs one.
- **`/dev/urandom` must exist**: Linux and macOS. On a system without it, the first
  call that reads it raises the Scheme's own i/o error.

## Expected survivors

Mutants no test can kill, each for the reason given:

- **A short read from `/dev/urandom`**, rule 4 of `system-entropy`: the kernel never
  answers short, and no test can make it.
- **The count of 0**, rule 2: `get-bytevector-n` answers an empty bytevector for 0 too,
  so dropping the case is an equivalent mutant.
- **The file not opened for a bad N**, rule 1: nothing observes an open that fails no
  read.
- **Closing in straight-line code**, not `dynamic-wind`, rule 3: no test can make the
  read raise.
- **One unbuffered port, opened once and kept**: fork-safe, since nothing is buffered,
  and no test sees it.
- **A port per call, buffered**: fork-safe and right, about ten times slower; no test
  sees it.
- **`(current-time)` with no argument**, which defaults to `time-utc`: equivalent.
- **KEY copied, and read at each hash** rather than at the call: equivalent.

Found by the mutation run and the slice review, after building:

- **A condition's message.** Messages are for people: as in the core and the
  generator, the suites assert who and irritant (ADR-0005), never the message, so a
  changed message survives.
- **`fx` arithmetic in the hash, and rotations whose values pass 2^33**, against rule
  5: right wherever fixnums are wider than 34 bits, as on every Scheme here.
- **`bytevector-u32-native-ref`** for the key and message words: right on a
  little-endian host, and amd64 and arm64 both are.
- **`system-clock` reading `current-time` twice**: caught only when a second's
  boundary falls between the reads.
- **A key from 4 random bytes and 4 zero bytes**: the fork suite's two hashes still
  differ, but for a chance of 2^-32. No test can see where a key came from.
- **Two equivalent mutants**: `rotl`'s `bitwise-ior` as `bitwise-xor`, since the two
  halves share no bits, and two independent SIPROUND steps swapped.

## Out of this slice

- **A check that the Guile lane searches `src/` before `tests/`**, which the slice 2
  reflection proposed. It goes in Open.
- **Thread safety** of one generator: a generator belongs to its caller.
- **Stable storage** of the last timestamp (§6.3).
