# Slice 2: the generator, `(unique-id generator)`

This is the contract the library and its suites are built to. Every rule here comes
from RFC 9562's text, fetched from rfc-editor.org on 2026-11-22, and each cites its
section. A read-only review of this contract, on Opus, came before any building; its
findings are folded in.

## Files

| File | What it holds |
|---|---|
| `src/unique-id/generator.sls` | the library `(unique-id generator)`, importing `(rnrs)` and `(unique-id)` |
| `tests/test-unique-id-generator.sps` | suite `unique-id-generator`: what a generator asks of its clock and entropy, what it answers, and its errors, by fixed vectors |
| `tests/test-unique-id-monotonic.sps` | suite `unique-id-monotonic`: seeded runs of scripted clocks, whose v7 ids increase but at a reset |

## Exports

```
make-uuid-generator uuid-generator?
generate-v4 generate-v7
```

| Signature | Answers |
|---|---|
| `make-uuid-generator : (-> Nat) (Nat -> Bytevector) -> Generator` | A fresh generator over CLOCK and ENTROPY. It calls neither. CLOCK answers the Unix time in milliseconds: time since 1970-01-01 UTC, leap seconds excluded (§5.7), such as SRFI-19's `time-utc`. ENTROPY, given N, answers N random bytes. |
| `uuid-generator? : Any -> Boolean` | #t for a generator, #f for anything else. |
| `generate-v4 : Generator -> Uuid` | `make-uuid-v4` of the 16 bytes that `(ENTROPY 16)` answers (§5.4). It never calls CLOCK, and leaves the v7 state alone. |
| `generate-v7 : Generator -> Uuid` | A v7 id greater, under `uuid<?`, than the last v7 id this generator answered, unless the clock has fallen more than 10 seconds behind that id's millisecond; then the id takes the clock's time, and is less (see **v7**). |

## v7

**Method 1 (RFC 9562 §6.2).** The 12 bits of `rand_a` are a counter, right after the
timestamp. A generator keeps the last v7 id's timestamp and counter, LAST-MS and
LAST-COUNTER. A new generator has neither.

**The steps.** Each `generate-v7` takes these steps in order, and stops at the first
that raises. LAST-MS and LAST-COUNTER change only in step 7.

1. **Its argument.** It checks its argument is a generator; else an assertion violation,
   and neither CLOCK nor ENTROPY is called.
2. **The clock.** It calls `(CLOCK)` once, and NOW is its answer. A raise from CLOCK
   passes through unchanged.
3. **NOW.** It checks NOW on every call, used or not: an exact integer, 0 ≤ NOW < 2^48.
   Else it raises an assertion violation with who `generate-v7` and NOW the one
   irritant, and ENTROPY is not called. Test `integer?` before `exact?`: `exact?` raises
   on a non-number.
4. **The case.** It picks one of four, in this order:
   - **New tick**: there is no LAST-MS, or NOW > LAST-MS. MS is NOW, and N is 10.
   - **Reset**: NOW < LAST-MS − 10000, so the clock has fallen more than 10 seconds
     behind. MS is NOW, and N is 10, as in a new tick. This id is less than the last.
   - **Same tick, or the clock stepped back by up to 10 seconds**: LAST-MS − 10000 ≤
     NOW ≤ LAST-MS, and LAST-COUNTER < 4095. MS is LAST-MS, COUNTER is LAST-COUNTER + 1,
     and N is 8.
   - **Rollover**: LAST-MS − 10000 ≤ NOW ≤ LAST-MS, and LAST-COUNTER = 4095. MS is
     LAST-MS + 1, never NOW + 1, and N is 10. If LAST-MS is 2^48 − 1, it raises here,
     with `error`: who `generate-v7`, LAST-MS the one irritant. ENTROPY is not called.
5. **The entropy.** It calls `(ENTROPY N)` once. A raise from ENTROPY passes through
   unchanged. The answer must be a bytevector of N bytes; else an assertion violation
   with who `generate-v7` and the answer the one irritant.
6. **The bytes.** When N is 10, COUNTER is the big-endian value of bytes 0–1 AND #x7FF,
   0 to 2047, and the 8 bytes are bytes 2–9. When N is 8, the 8 bytes are the answer.
7. **The id.** It is `(make-uuid-v7 MS COUNTER the-8-bytes)`. LAST-MS becomes MS,
   LAST-COUNTER becomes COUNTER, and the id is answered.

**Why it works.**
- The seed's top bit is clear, which guards against rollover (§6.2, "Fixed Bit-Length
  Dedicated Counter Seeding").
- A rollover runs the timestamp ahead (§6.2, "Counter Rollover Handling": "increment the
  timestamp ahead of the actual time and reinitialize the counter").
- While the clock stays within 10 seconds of the last id's time, a step back is ignored (§6.2, "Monotonic Error
  Checking": "reuse the previous timestamp and increment the previous counter method").
  That covers time daemons' corrections and leap seconds.
- A clock more than 10 seconds behind was badly wrong, so the generator starts over
  from it rather than carry a bad time forward. This departs from §6.2's SHOULD ("ensure that the next UUID generated is greater than
  the previous, or they should at least report an appropriate error"), as LiosK's
  `generate()` does. The owner chose it over refusing. The 10 seconds is the rollback allowance LiosK's uuidv7, for
  JavaScript, and its Rust port, uuid7, use by default.
- Running out raises rather than repeat an id (§6.1, "Error Handling": "MUST NOT
  knowingly return duplicate values due to a counter rollover").

So, but at a reset, (MS, COUNTER) grows strictly from each v7 id to the next. MS fills
the 48 bits ahead of the version and COUNTER the 12 after it, so the ids grow strictly
under `uuid<?`, whatever the random bits. A reset draws a fresh seed and 62 fresh random
bits, so its ids stay distinct from earlier ones at the same milliseconds, by chance.

**Arithmetic.** NOW, MS and LAST-MS reach 2^48, past the fixnum range R6RS promises:
use generic arithmetic on them, never `fx` operations.

## generate-v4

1. It checks its argument is a generator; else an assertion violation, and ENTROPY is
   not called.
2. It calls `(ENTROPY 16)` once. A raise from ENTROPY passes through unchanged. The
   answer must be a bytevector of 16 bytes; else an assertion violation with who
   `generate-v4` and the answer the one irritant.
3. The id is `(make-uuid-v4 the-16-bytes)`.

## Errors

- **`make-uuid-generator`** raises an assertion violation unless CLOCK and ENTROPY are
  procedures. Its who is `make-uuid-generator`, and its one irritant is the first bad
  argument.
- **`generate-v4` and `generate-v7`** raise as their steps say. Every assertion
  violation carries the procedure's own name as who and one irritant, compared with
  `eqv?`, as in `(unique-id)`.
- **Running out of timestamp** raises with `error`, not an assertion violation: it is
  no caller's mistake.
- **A call that raises leaves the generator as it was.**

## The record

- **An opaque, sealed, generative R6RS record** holding CLOCK, ENTROPY, LAST-MS and
  LAST-COUNTER. Its type, constructor and accessors are not exported.
- **ENTROPY's answer is the caller's.** The generator does not change it, and changing
  it after the call changes no id.

## What a generator promises, and what it does not

- **Its order holds among one generator's ids**, not across generators, processes or
  restarts. A new generator starts afresh. Ids made after a restart can sort below
  earlier ones if the clock went back in between. §6.3 allows keeping the last
  timestamp in stable storage; this library does not.
- **A clock that jumps ahead and then comes back by up to 10 seconds pins the
  generator at the jumped-to time.** Its ids carry that time until the clock catches
  up, at most 10 seconds and 1 millisecond. Further back, the generator resets, and its ids sort below
  those made while the clock was ahead.
- **A generator that runs ahead of its clock by rollovers alone** resets too, once it
  is more than 10 seconds ahead. That takes 20 to 30 million ids beyond the clock's pace: over 4 million a second for 10 seconds at the luckiest seeds, about 6 million at typical ones.
- **The generator runs out only while the clock holds within 10 seconds of 2^48 − 1.**
  A clock that comes back from there resets the generator.
- **CLOCK and ENTROPY return once per call and do not use the generator they belong
  to.** If they do, ids are neither ordered nor distinct.

## Vectors: the generator suite

Each table runs one generator from new. ENTROPY's answers are hex. A vector names the
RFC 9562 text its values come from.

**Basic, from A.6's timestamp #x017F22E279B0 and its `rand_b` bytes, with A.3's random
bytes for calls 2 and 3:**

| Call | CLOCK | ENTROPY asked, answers | Id |
|---|---|---|---|
| 1 | #x017F22E279B0 | 10: `FCC318C4DC0C0C07398F` | `017f22e2-79b0-74c3-98c4-dc0c0c07398f` |
| 2 | #x017F22E279B0 | 8: `5BACF847DB4148A8` | `017f22e2-79b0-74c4-9bac-f847db4148a8` |
| 3 | #x017F22E279AF, stepped back | 8: `919108F752D13320` | `017f22e2-79b0-74c5-9191-08f752d13320` |
| 4 | #x017F22E279B1 | 10: `0123D8C4DC0C0C07398F` | `017f22e2-79b1-7123-98c4-dc0c0c07398f` |

In call 1, #xFCC3 AND #x7FF is #x4C3. In call 4, `D8` gives octet 8 `98`.

**Rollover on a clock that stepped back:**
- CLOCK answers #x017F22E279B0 for calls 1 to 2049, and #x017F22E279AF for call 2050.
- ENTROPY answers `07FF18C4DC0C0C07398F` for call 1, `18C4DC0C0C07398F` for calls 2 to
  2049, and `FCC318C4DC0C0C07398F` for call 2050.
- Asked: 10, then 8 2048 times, then 10.
- Call 1 gives `017f22e2-79b0-77ff-98c4-dc0c0c07398f`.
- Calls 2 to 2049 give counters #x800 to #xFFF. Call 2049 is
  `017f22e2-79b0-7fff-98c4-dc0c0c07398f`.
- Call 2050 is `017f22e2-79b1-74c3-98c4-dc0c0c07398f`: LAST-MS + 1, its seed masked.

**Running out.** Every 10-byte answer is `07FF18C4DC0C0C07398F`, every 8-byte answer
`18C4DC0C0C07398F`.
- **CLOCK fixed at #xFFFFFFFFFFFE:**
  - Call 2050 rolls over to `ffffffff-ffff-77ff-98c4-dc0c0c07398f`.
  - Calls 2051 to 4098 give counters #x800 to #xFFF.
  - Call 4099 raises with `error`, who `generate-v7`, irritant 281474976710655, and asks
    ENTROPY nothing.
  - A further call raises the same.
- **CLOCK fixed at #xFFFFFFFFFFFF:** call 2050 raises the same, asking nothing.

**v4, from A.3:**
- `(ENTROPY 16)` answers A.3's raw random bytes, `919108F752D133205BACF847DB4148A8`.
- The id is `919108f7-52d1-4320-9bac-f847db4148a8`, and CLOCK is never called.
- **Interleaved:** v7 at a new tick, then v4, then v7 at the same CLOCK asks 10, 16 and
  8, and the last counter is the first plus 1.

**Reset, from A.6's timestamp, 1645557742000:**

| Call | CLOCK | ENTROPY asked, answers | Id |
|---|---|---|---|
| 1 | 1645557742000 | 10: `FCC318C4DC0C0C07398F` | `017f22e2-79b0-74c3-98c4-dc0c0c07398f` |
| 2 | 1645557732000, exactly 10 s behind | 8: `5BACF847DB4148A8` | `017f22e2-79b0-74c4-9bac-f847db4148a8` |
| 3 | 1645557731999, 10.001 s behind | 10: `0123D8C4DC0C0C07398F` | `017f22e2-529f-7123-98c4-dc0c0c07398f` |
| 4 | 1645557731999 | 8: `919108F752D13320` | `017f22e2-529f-7124-9191-08f752d13320` |

Call 3 resets: its MS is NOW, and call 4 counts on from it.

**Recovery from the top:**
- CLOCK answers #xFFFFFFFFFFFF for call 1, and 1645557742000 for call 2. ENTROPY
  answers `FCC318C4DC0C0C07398F` both times.
- Call 2 resets, asking 10: `017f22e2-79b0-74c3-98c4-dc0c0c07398f`.
- An exhausted generator, its counter full at #xFFFFFFFFFFFF, resets the same way when
  CLOCK answers 1645557742000, rather than raise.

**Bad answers.** Each must raise as the steps say, with what was asked asserted. Then the
next good call must continue from the state before.
- **CLOCK accepted:** 0 and 2^48 − 1.
- **CLOCK refused:**
  - 2^48, −1, 1/2, an inexact `1645557742000.`, and the symbol `tick`;
  - −1 after a first id, which must not be read as a stepped-back clock.
- **ENTROPY refused:**
  - a non-bytevector;
  - one byte short and one byte long;
  - 8 bytes when 10 were asked, and 10 when 8 were.
  - For `generate-v4`: 15 and 17 bytes.
- **Raises from CLOCK and ENTROPY pass through:** a stand-in that raises a symbol is met
  by that symbol, and nothing else is called.

## The monotonic suite

**Its stand-ins.** ENTROPY draws from the suite's seeded generator, answering the
length asked. CLOCK is scripted.

**What it asserts.** Each run asserts, for every id:
- when NOW is more than 10000 below the last id's timestamp, its timestamp is NOW;
  else it is greater than the last id under `uuid<?`;
- its `uuid-v7-timestamp` is at least NOW;
- its timestamp equals NOW whenever NOW exceeds every earlier timestamp;
- it is version 7 with variant `rfc9562`.

**The runs.** Each names its seed and its count. They include:
- a held clock, for at least 5000 ids, so it rolls over;
- a clock that steps back 1000 ms and holds, so it rolls over while held back;
- a clock that steps back exactly 10000 ms and holds, which never resets;
- a clock that steps back 10001 ms, which resets once, then increases from there;
- a clock that jumps forward;
- a random walk that repeats, steps back and jumps;
- a rollover at 2^48 − 2;
- two generators over one clock, each increasing on its own.

## Out of this slice

- **For slice 3:** the system's clock and entropy, a ready-made generator, and the keyed
  hash. Slice 3 should note:
  - SRFI-19's `time-monotonic` runs 37 s ahead of `time-utc` on both Schemes, measured.
  - A buffered `/dev/urandom` port is shared across a fork (§6.9 asks to reseed on a
    fork); it was reported, not yet measured.
  - A shared ready-made generator meets "a generator belongs to its caller".
- **Thread safety:** a generator belongs to its caller.
- **Stable storage** of the last timestamp (§6.3).
