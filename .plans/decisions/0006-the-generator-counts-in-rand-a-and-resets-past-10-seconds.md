# ADR-0006: The generator counts in rand_a, and resets when the clock falls 10 seconds behind

- **Status:** Accepted. Decisions 1 to 3 are the brief's own rules. The owner chose
  decision 2's 10-second reset on 2026-11-22, over counting on whatever the step and over
  refusing. Decisions 4 to 6 were chosen with the slice, not asked of the owner.
- **Date:** 2026-11-22
- **Scope:** `(unique-id generator)`
- **Related:** the brief's "Shell: a generator"; `.plans/slice-2.md`, the contract;
  ADR-0005, whose error conventions this extends to the generator's stand-ins

## Context

Techo's clients make v7 ids offline and sort by them, so one client's ids must increase
even when its clock repeats a millisecond or steps back, and when many are asked for at
once.
RFC 9562 §6.2 offers three ways to count within a millisecond:

- **Method 1:** a counter in `rand_a`;
- **Method 2:** a random counter in `rand_b`;
- **Method 3:** more clock precision.

§6.1 and §6.2 leave the generator to decide what to do on a step back and on rollover.
They require that a rollover is handled so ids still sort, and that the generator never
knowingly answers a duplicate. §6.2's "Monotonic Error Checking" adds a SHOULD: "correct
the problem to ensure that the next UUID generated is greater than the previous, or they
should at least report an appropriate error".

How far back should a clock be followed? Time daemons rarely step a clock back:
chrony adjusts it gradually by default, and common configurations step it only at boot,
for an error over 1 second (`makestep 1 3`)
([chrony.conf(5)](https://man.archlinux.org/man/chrony.conf.5),
[chrony FAQ](https://third-party-mirror.googlesource.com/chrony/+/refs/heads/main/chrony/doc/faq.adoc)).
A leap second costs one. A larger step back means the clock
was badly wrong. LiosK's uuidv7, for JavaScript, and its Rust port, uuid7, keep counting
within a 10-second rollback allowance by default. Beyond it they reset to the clock, or
refuse
([V7Generator](https://liosk.github.io/uuidv7/classes/V7Generator.html),
[uuidv7 README](https://cdn.jsdelivr.net/npm/uuidv7@1.2.1/README.md),
[uuid7's generator](https://docs.rs/crate/uuid7/1.8.0/source/src/generator.rs)).

The generator's clock and entropy are its caller's procedures, so they can answer
anything. A read-only review of the contract, before it was built, found its first draft
silent on which calls happen when one of them answers badly, and on what raises then.

## Decision

1. **Method 1.** The 12 bits after the version are a counter. Each new millisecond seeds
   it from 11 random bits, its top bit clear as a rollover guard. Each id within the
   millisecond adds one. `rand_b`'s 62 bits are fresh for every id.
2. **While the clock stays within 10 seconds of the last id's time, the generator keeps
   that time and counts on** (§6.2, "Monotonic Error Checking"). **Further behind, it
   resets**: the id is a new tick at the clock's time, less than the last id. Ids made
   while the clock was wrong keep their bad times, but later ids carry the right one.
   - **This departs from §6.2's SHOULD**: the next id is neither greater nor an error.
     LiosK's `generate()` does the same.
   - The owner chose it so that offline clients keep working, and declined refusing,
     the RFC's fallback, on 2026-11-22.
3. **A counter that rolls over moves the timestamp on one millisecond** past the last,
   which may run ahead of the clock, never to the clock's answer plus one, and reseeds
   (§6.2, "Counter Rollover Handling").
4. **One entropy call per id**:
   - 10 bytes when the counter is seeded, on a new tick or a rollover;
   - 8 bytes within a tick;
   - 16 bytes for v4.

   The clock is called first, and once.
5. **Errors.**
   - A clock or entropy answer outside its domain raises an assertion violation that
     names the `generate-` procedure, with the answer as its one irritant. A raise from
     either passes through unchanged.
   - Running out of timestamp, at 2^48 − 1, raises with `error`: no caller made a
     mistake.
   - A call that raises leaves the generator as it was.
6. **Order holds within one generator.** No state is kept across generators or restarts
   (§6.3's stable storage is not offered). Each reset, decision 2, breaks it. CLOCK
   and ENTROPY must not call their own generator: its state is read before they
   answer.

## Consequences

- **Suites can pin every call.** Each step's calls and answers are fixed, so a scripted
  clock and entropy source give exact ids, requests and raises.
- **A client whose clock jumps ahead and comes back by more than 10 seconds resets.**
  Its new ids carry the right time, and sort below those made while it was ahead.
  - Within 10 seconds, its ids run up to 10 seconds and 1 millisecond ahead: a rollover from 10 seconds ahead.
  - A server that refuses ids from the future should allow 10.001 seconds plus its clients' clock skew.
- **A generator runs out only while its clock holds within 10 seconds of 2^48 − 1.** One
  bad answer of 2^48 − 1 no longer stops it for good.
- **A reset can come without a clock fault**, if rollovers alone run the generator more
  than 10 seconds ahead. It takes 20 to 30 million ids beyond the clock's pace: over 4 million a second for 10
  seconds at the luckiest seeds, about 6 million at typical ones, or 2.1 million a second
  for about 400 seconds, measured with a constant entropy source.
- **After a reset, distinctness rests on chance.** The reset id differs from earlier ids
  at its millisecond by 73 random bits, and later ids by 62 where counters overlap.
- **One far-off clock answer**, 0 for instance, gives one id with that time, and the
  next good answer is a new tick. A server should expect such ids.
- **Ids made within one millisecond can be linked**: their counters run by one, and
  their difference is how many ids came between. Ids from different milliseconds cannot
  be linked this way, since each millisecond reseeds.
- **`(unique-id system)` must give a Unix clock**, leap seconds excluded. SRFI-19's
  `time-monotonic` runs 37 s ahead of `time-utc` on both Schemes.
