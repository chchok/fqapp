# 小满阅读（原生 iOS / macOS）

`XiaomanReading.xcodeproj` 由 XcodeGen 配置生成，提供 iOS 与 macOS 两个 SwiftUI App target。运行 `xcodegen generate --spec ios/NativeReader/project.yml --project ios/NativeReader` 后，可在 Xcode 打开工程；命令行可用 `xcodebuild` 构建两个平台。

当前包含书架、书城搜索、阅读器和“我的”界面骨架。书目和正文仍是演示数据，尚未接入 fqapp 的真实书源、Rust 核心、收藏与进度存储、章节缓存或下载。原项目已有 Flutter Runner 与此原生工程并行，尚未替换 Flutter 启动入口。

当前仓库配置 `upstream` 指向 `ch6vip/fqapp`。执行 `scripts/sync_upstream_native.sh` 会合并上游 master，重编 iOS/macOS Rust 核心，并重建两个平台的 Release（未签名）；工作区需干净。该脚本不会自动推送到 GitHub。

原仓库使用 GPL-3.0；发行时需按 LICENSE 履行义务。
