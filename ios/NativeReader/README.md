# 小满阅读（原生 iOS / macOS）

`XiaomanReading.xcodeproj` 由 XcodeGen 配置生成，提供共用 SwiftUI 界面的 iOS 与 macOS App target。iOS 版在 iOS 17 及以上运行，macOS 版在 macOS 14 及以上运行。

## 本地构建

需要 macOS、Xcode 命令行工具、Rust Apple targets 和 XcodeGen。首次配置 Rust target 后：

```bash
./scripts/build_rust_native.sh
xcodegen generate --spec ios/NativeReader/project.yml --project ios/NativeReader
xcodebuild -project ios/NativeReader/XiaomanReading.xcodeproj \
  -scheme XiaomanReading-iOS -configuration Debug \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
```

macOS scheme 为 `XiaomanReading-macOS`。仅在 iPhone 与 iPad 真机验收通过后，才手动运行 `scripts/package_native_unsigned.sh` 生成未签名安装包。

## 当前实现

原生端已接入 fqapp Rust 内容核心，包含首页频道、搜索与热搜、分类和榜单、小说详情与书评、章节阅读、书架/历史/收藏管理、正文替换、小说离线缓存、备份与合并导入、漫画阅读、短剧播放、听书播放及系统媒体控制。书架可导入 TXT 与 EPUB 本地小说，并将章节正文和已声明的 PNG/JPEG/GIF/WebP 封面保存在应用私有目录。

## 移植与验收状态

原生端仍在按 Android 主工程逐项对照。当前只在模拟器阶段；在小说、短剧、漫剧、漫画、听书、阅读器设置、账号、导入导出、离线、播放手势与多窗口布局等功能完成逐页和交互验收前，不开始 iPhone/iPad 真机验收。其余未对齐能力仍待移植。液态玻璃效果不属于布局对齐要求。

`.github/workflows/upstream-sync-native.yml` 每 5 分钟检查并同步 `ch6vip/fqapp` 的 `master`。工作流不会自动发布安装包；只有在 iPhone 与 iPad 真机验收通过后，由维护者手动触发并勾选通过项，才会打包和创建 GitHub 预发布。

原项目使用 GPL-3.0，发行时需遵守仓库 LICENSE。
