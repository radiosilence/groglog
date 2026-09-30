#!/bin/sh
# Runs the test suite on whichever iPhone simulator the machine has. Runner images and laptops carry different
# simulators, and a named one would break when the runner image is updated.
set -eu
cd "$(dirname "$0")/.."
xcodegen generate --quiet
SIM=$(xcrun simctl list devices available | grep -E '^\s+iPhone' | tail -1 | grep -oE '[0-9A-F-]{36}')
# xcodebuild passes TEST_RUNNER_-prefixed variables to the tests without the prefix, so the tests can detect CI.
[ -n "${CI:-}" ] && export TEST_RUNNER_CI=1
xcodebuild -scheme GrogLog -destination "id=$SIM" test -quiet
