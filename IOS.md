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

首页频道和分类、短剧频道、搜索与热搜、作品详情、短剧分集与 AVPlayer、小说章节阅读、书架/历史/收藏，以及本地“我的”页面均由 SwiftUI 绘制；网络数据请求复用 Rust 核心。

## 与 Android 的对齐

Android 端目前仍是布局与交互的对照基准。原生页面已完成部分结构复刻，但还没有逐页、逐状态完成设备截图对比和交互验收，因此当前安装包属于开发预览，不能视为 Android 完整复刻版。仍待补齐或验收的范围包括阅读器工具栏与设置、短剧播放器交互控件、漫画阅读、听书和后台播放、缓存/备份导入及跨设备同步等。液态玻璃特效不属于 iOS 布局对齐要求。

真机签名安装需要用户的 Apple Developer 签名环境；真机安装和页面验收还需连接并解锁设备。

## 上游同步与预览发布

GitHub Actions 工作流每 5 分钟检查 `ch6vip/fqapp` 的 `master`。检测到上游变化后，会合并并推送到此复刻仓库，重建 iOS/macOS 未签名包，并创建 GitHub 预览发布。
