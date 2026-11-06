# 小满阅读原生 Apple 版

仓库包含独立的 SwiftUI iOS 与 macOS App，共用 Rust 内容核心。iOS 部署目标为 iOS 17，macOS 部署目标为 macOS 14。

## 本地构建

需要 macOS、Xcode 命令行工具、Rust Apple targets 和 XcodeGen。首次配置 Rust target 后：

```bash
./scripts/build_rust_native.sh
xcodegen generate --spec ios/NativeReader/project.yml --project ios/NativeReader
xcodebuild -project ios/NativeReader/XiaomanReading.xcodeproj \\
  -scheme XiaomanReading-iOS -configuration Debug \\
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
```

macOS App 使用 scheme `XiaomanReading-macOS`。生成 iOS 与通用 macOS 未签名 Release 安装包：

```bash
./scripts/package_native_unsigned.sh
```

输出位于 `dist/unsigned/`。IPA 未签名，不能直接安装；需要使用有效 Apple Developer 签名重新签署后才能装到真机。此仓库没有保存开发者证书或签名凭据。macOS ZIP 同样未签名。

## 当前原生页面

首页频道、分类与榜单、搜索、作品详情与书评、章节目录和小说阅读器、短剧/漫剧频道、漫画分话阅读、听书、书架及个人设置均由原生 SwiftUI 呈现；内容请求复用仓库 Rust 核心。
已接入书评、漫画分话阅读、听书章节与系统媒体控制、小说缓存、书架备份/恢复/合并、正文替换和 TXT/EPUB 本地导入。TXT 支持常见 UTF 编码与 GB18030，并按章节标题拆分；EPUB 按 spine 顺序抽取 XHTML 章节，并读取已声明的常见栅格封面。

## 与 Android 的对齐

Android 端仍是布局与交互的对照基准。原生页面还没有完成逐页、逐状态的模拟器对比和交互验收，不能视为 Android 完整复刻版。需要继续盘点并补齐全部 Android 功能与视觉状态；之后才进入 iPhone 和 iPad 真机验收。液态玻璃特效不属于 iOS 布局对齐要求。

真机签名安装需要用户的 Apple Developer 签名环境；真机安装和页面验收还需连接并解锁设备。当前按“模拟器移植与验收完成 → iPhone/iPad 真机验收通过 → 发布未签名安装包”的顺序执行。

## 上游同步与预览发布

GitHub Actions 工作流每 5 分钟检查 `ch6vip/fqapp` 的 `master`，检测到上游变化后会合并并推送到复刻仓库。工作流不会自动发布 iOS/macOS 安装包；真机验收通过后，维护者手动触发工作流并确认通过项，才会构建和发布未签名安装包。
