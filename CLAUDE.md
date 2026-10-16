# GrogLog

## Changelog

`CHANGELOG.md` is assembled from fragments by `just changelog` and is never edited by hand, not even to fix a typo:
change the fragment and run the recipe again. Every change adds one fragment under `changelog.d/unreleased/<section>/`,
named `<yyyymmdd>-<slug>.md` and holding one `- **Lead.** Detail.` entry. The sections and the format are in
`changelog.d/README.md`.

Releases are cut with `just release patch|minor|major`, which turns the unreleased fragments into the version and opens
the release PR. Tags and the GitHub release are left to the maintainer.
