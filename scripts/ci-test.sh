#!/bin/sh
# Runs the test suite on whichever iPhone simulator the machine has. Runner images carry different ones from a laptop,
# and naming one here would break the day the image moves on.
set -eu
cd "$(dirname "$0")/.."
xcodegen generate --quiet
SIM=$(xcrun simctl list devices available | grep -E '^\s+iPhone' | tail -1 | grep -oE '[0-9A-F-]{36}')
# xcodebuild hands TEST_RUNNER_-prefixed variables to the tests without the prefix, so they know they're on CI.
[ -n "${CI:-}" ] && export TEST_RUNNER_CI=1
xcodebuild -scheme GrogLog -destination "id=$SIM" test -quiet
