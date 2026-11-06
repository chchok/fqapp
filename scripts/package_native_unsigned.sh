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

当前预览包括原生首页推荐与六类频道、分类浏览、短剧入口、搜索、作品卡片与基础详情、小说目录和章节阅读、本地书架及阅读进度。内容通过仓库内同一 Rust 核心请求。

尚未移植完成：短剧/漫剧播放与剧集详情、漫画阅读、听书播放与后台控制、分类和排行榜、完整书架/收藏管理、评论互动、离线下载与多设备同步。此预览不代表 Android 功能已全部覆盖。
NOTES
