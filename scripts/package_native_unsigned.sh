#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/dist/unsigned"

"$ROOT/scripts/build_rust_native.sh"
xcodegen generate --spec "$ROOT/ios/NativeReader/project.yml" --project "$ROOT/ios/NativeReader"
xcodebuild -project "$ROOT/ios/NativeReader/XiaomanReading.xcodeproj" -scheme XiaomanReading-iOS -configuration Release -sdk iphoneos -derivedDataPath "$ROOT/build/native-ios" CODE_SIGNING_ALLOWED=NO build
xcodebuild -project "$ROOT/ios/NativeReader/XiaomanReading.xcodeproj" -scheme XiaomanReading-macOS -configuration Release -sdk macosx -derivedDataPath "$ROOT/build/native-macos" CODE_SIGNING_ALLOWED=NO ARCHS='arm64 x86_64' build

mkdir -p "$OUT/ios/Payload" "$OUT/macos"
ditto "$ROOT/build/native-ios/Build/Products/Release-iphoneos/XiaomanReading-iOS.app" "$OUT/ios/Payload/XiaomanReading.app"
(cd "$OUT/ios" && ditto -c -k --norsrc --keepParent Payload XiaomanReading-iOS-unsigned.ipa)
ditto "$ROOT/build/native-macos/Build/Products/Release/XiaomanReading-macOS.app" "$OUT/macos/XiaomanReading.app"
(cd "$OUT/macos" && ditto -c -k --norsrc --keepParent XiaomanReading.app XiaomanReading-macOS-unsigned.zip)
cat > "$OUT/README.md" <<'NOTES'
# 小满阅读原生版（未签名构建）

- `ios/XiaomanReading-iOS-unsigned.ipa`：iOS 真机 Release 包；未签名，需要用开发者证书重签后安装。
- `macos/XiaomanReading-macOS-unsigned.zip`：Intel 与 Apple Silicon 通用 macOS Release App；未签名，正式分发需签名和公证。

书城搜索连接 fqapp 的 Rust 核心。书架本地保存。详情目录、章节正文、进度、离线下载尚未完成，当前版仍是早期预览。
NOTES
