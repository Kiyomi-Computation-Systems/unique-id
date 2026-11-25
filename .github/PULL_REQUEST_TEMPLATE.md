## What

<!-- One or two sentences: what changes, and why. Link the issue if there is one. -->

## Tested on

<!-- CI runs `make test` on Linux, amd64 and arm64, with Chez 10.4.1 and Guile 3.0.9. Say where else you ran it: macOS, or another Chez or Guile. -->

## Checklist

- [ ] `make test` passes locally, on Chez and on Guile
- [ ] A behavior change comes with a test I watched fail without it
- [ ] Test vectors come from RFC 9562's text, with the section in the test's name, or from the SipHash reference, never from a run of this library
- [ ] The title is a Conventional Commit (`feat:`, `fix:`, `docs:`, …)
- [ ] `docs/reference.md` is regenerated, if a comment in `src/` changed (`make reference`)
- [ ] `README.org` and `docs/` match, if what users see changed (`make check-site`)
- [ ] `CHANGELOG.md` has an entry under `[Unreleased]`, if users can see the change
- [ ] A moved chez-srfi pin is on a commit of its own, with `SRFI_PIN` and `Akku.manifest` (`make check-pins`)
