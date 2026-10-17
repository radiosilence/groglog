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
STAMP=core/out/.built

# A release build with LTO is slow, and a fresh package makes Xcode resolve it again, so nothing is rebuilt while the
# sources are older than the last build.
if [ -f "$STAMP" ] && [ -d "$PACKAGE" ] && [ -z "$(find core/src core/Cargo.toml core/uniffi.toml Cargo.toml Cargo.lock \
  rust-toolchain.toml tools scripts/core-apple.sh -type f -newer "$STAMP" -not -path '*/target/*' | head -1)" ]; then
  exit 0
fi

rm -f "$STAMP"
rm -rf "$PACKAGE" "$GENERATED"
mkdir -p "$PACKAGE/Sources/GrogLogCore" "$GENERATED/headers"

# Apple silicon only: there is no x86_64 simulator slice. The targets come from rust-toolchain.toml.
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

touch "$STAMP"
