#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree has changes; commit or stash them before syncing." >&2
  exit 2
fi
if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream https://github.com/ch6vip/fqapp.git
fi

git fetch upstream master
git merge --no-edit upstream/master
"$ROOT/scripts/build_rust_native.sh"
xcodegen generate --spec ios/NativeReader/project.yml --project ios/NativeReader
xcodebuild -project ios/NativeReader/XiaomanReading.xcodeproj -scheme XiaomanReading-iOS -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ios/NativeReader/XiaomanReading.xcodeproj -scheme XiaomanReading-macOS -configuration Release -sdk macosx CODE_SIGNING_ALLOWED=NO ARCHS="arm64 x86_64" build
