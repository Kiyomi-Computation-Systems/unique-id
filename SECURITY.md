# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| The latest release (see [CHANGELOG.md](CHANGELOG.md)) | ✅ |
| Earlier releases | ❌ |

## Reporting a vulnerability

Please report suspected vulnerabilities privately via GitHub:
**Security → Report a vulnerability** on this repository. Do not open a
public issue.

You can expect an acknowledgement within 7 days.

Programs use these ids as keys, and check the ids that others send them, so
these reports are especially welcome:

- ids less random than they should be: a v4 id, or the random bits of a v7
  id, that can be guessed, or that repeats across calls, generators or a
  fork;
- a generator that answers the same id twice;
- text or bytes that `string->uuid` or `bytevector->uuid` accepts and should
  refuse, or reads as a different id;
- a way to change an id once it is made, or to make one that `uuid?` accepts
  without going through the library;
- a way to find ids that share a `make-uuid-hash` hash without knowing its
  key, or to learn the key from the hashes.

By design, a v7 id shows the millisecond it was made, and `uuid-hash` has no
key, so anyone can make ids that share one. Neither is a vulnerability.

Please include your platform, your Scheme and its version, and the procedure
you called with the input that shows it, or a small program.
