# GrogLog

## Changelog

Never edit `CHANGELOG.md` by hand; it is generated. Every change adds one fragment under
`changelog.d/unreleased/<section>/`, named `<yyyymmdd>-<slug>.md` and holding one `- **Lead.** Detail.` entry, then runs
`just changelog` to regenerate the file. The sections and the format are in `changelog.d/README.md`.

Releases are cut with `just release patch|minor|major`, which turns the unreleased fragments into the version and opens
the release PR. Tags and the GitHub release are left to the maintainer.
