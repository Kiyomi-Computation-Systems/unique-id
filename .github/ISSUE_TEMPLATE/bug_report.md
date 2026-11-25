---
name: Bug report
about: Something broke, or an id came out wrong
labels: bug
---

<!-- A suspected vulnerability? Don't file it here: SECURITY.md says how to
report it privately. -->

**Environment**

- OS and architecture (e.g. macOS 15 arm64, Ubuntu 24.04 x86_64):
- Scheme and its version (`scheme --version`, `guile --version`):
- unique-id version or commit:

**What happened**

**What you expected**

Which part of RFC 9562 says so, if you know (a section, say)?

**How to reproduce it**

Ideally a small program. A generator takes its clock and its random bytes as
arguments, so a fixed clock and fixed bytes make one that fails every time.
On Chez, `make run PROGRAM=repro.sps` runs it from a checkout.

**Does it happen on both Chez and Guile?**

**Does `make test` pass on your machine?**
