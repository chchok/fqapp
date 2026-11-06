#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/ios/Frameworks"
mkdir -p "$OUT"
cp "$ROOT/assets/config/config.json" "$ROOT/ios/NativeReader/Resources/config.json"
cp "$ROOT/assets/config/filter.json" "$ROOT/ios/NativeReader/Resources/filter.json"
export CARGO_PROFILE_RELEASE_STRIP=debuginfo
export IPHONEOS_DEPLOYMENT_TARGET=17.0
export MACOSX_DEPLOYMENT_TARGET=14.0

build_one() {
  local target="$1" output="$2"
  echo "==> Building Rust core for $target"
  (cd "$ROOT" && cargo rustc --locked --release --manifest-path rust/Cargo.toml --target "$target" --crate-type staticlib)
  local lib="$ROOT/rust/target/$target/release/libfqapi_core.a"
  test -s "$lib"
  cp "$lib" "$OUT/$output"
  echo "    $(du -h "$OUT/$output" | awk '{print $1}') $OUT/$output"
}

build_one aarch64-apple-ios libfqapi_core_ios.a
build_one aarch64-apple-ios-sim libfqapi_core_iphonesimulator_arm64.a
build_one x86_64-apple-ios libfqapi_core_iphonesimulator_x86_64.a
lipo -create "$OUT/libfqapi_core_iphonesimulator_arm64.a" "$OUT/libfqapi_core_iphonesimulator_x86_64.a" -output "$OUT/libfqapi_core_iphonesimulator.a"
build_one aarch64-apple-darwin libfqapi_core_macos_arm64.a
build_one x86_64-apple-darwin libfqapi_core_macos_x86_64.a
lipo -create "$OUT/libfqapi_core_macos_arm64.a" "$OUT/libfqapi_core_macos_x86_64.a" -output "$OUT/libfqapi_core_macos_universal.a"
