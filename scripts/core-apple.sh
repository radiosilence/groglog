#!/bin/sh
# Builds groglog-core for iOS and wraps it in a Swift package at core/out/GrogLogCore: the static library as an
# xcframework, and the generated Swift bindings as the package's one source file. project.yml depends on that package,
# which keeps the generated code out of the app's own Swift settings. Run before `xcodegen generate`, which resolves
# the package path.
set -eu
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"

PACKAGE=core/out/GrogLogCore
GENERATED=core/out/generated
rm -rf "$PACKAGE" "$GENERATED"
mkdir -p "$PACKAGE/Sources/GrogLogCore" "$GENERATED/headers"

rustup target add aarch64-apple-ios aarch64-apple-ios-sim >/dev/null
cargo build --release -p groglog-core --target aarch64-apple-ios --target aarch64-apple-ios-sim

# The bindings come from the metadata embedded in a built library, so either target serves.
cargo run -q -p uniffi-bindgen -- generate --library target/aarch64-apple-ios-sim/release/libgroglog_core.a \
  --language swift --out-dir "$GENERATED"
cp "$GENERATED/groglog_core.swift" "$PACKAGE/Sources/GrogLogCore/"
cp "$GENERATED/groglog_coreFFI.h" "$GENERATED/headers/"
cp "$GENERATED/groglog_coreFFI.modulemap" "$GENERATED/headers/module.modulemap"

xcodebuild -create-xcframework \
  -library target/aarch64-apple-ios/release/libgroglog_core.a -headers "$GENERATED/headers" \
  -library target/aarch64-apple-ios-sim/release/libgroglog_core.a -headers "$GENERATED/headers" \
  -output "$PACKAGE/groglog_coreFFI.xcframework"

cat > "$PACKAGE/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrogLogCore",
    platforms: [.iOS(.v17)],
    products: [.library(name: "GrogLogCore", targets: ["GrogLogCore"])],
    targets: [
        .binaryTarget(name: "groglog_coreFFI", path: "groglog_coreFFI.xcframework"),
        .target(name: "GrogLogCore", dependencies: ["groglog_coreFFI"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
SWIFT
