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

- `ios/XiaomanReading-iOS-unsigned.ipa`：iOS 真机 Release 包，未签名；需重签后才能安装。
- `macos/XiaomanReading-macOS-unsigned.zip`：Intel 与 Apple Silicon 通用 macOS Release App，未签名。

当前原生预览含首页频道与分类浏览、搜索/热搜、短剧频道、作品详情、短剧剧集目录和 AVPlayer 播放、小说详情与章节阅读、书架/历史/收藏及“我的”页面。内容请求复用仓库 Rust 核心。

本包仍是开发预览。与 Android 的逐页布局和交互尚未完成完整对照验收；播放器的弹幕、评论、清晰度、离线下载等控件，漫画阅读、听书后台播放、备份导入及跨设备同步等功能仍未完成。不能据此宣称功能或 UI 已与 Android 完全一致。
NOTES
shasum -a 256 \
  "$OUT/ios/XiaomanReading-iOS-unsigned.ipa" \
  "$OUT/macos/XiaomanReading-macOS-unsigned.zip" \
  | sed "s#$ROOT/##" > "$OUT/SHA256SUMS.txt"
