# Bilibili Focus (Mobile)

一款极简、无广告、以原生体验为核心的 **Bilibili 第三方移动端客户端**，同时支持 **iOS (SwiftUI)** 与 **Android (Jetpack Compose)**。

本项目采用 **原生界面与服务为主 + 净化版 WebView 兜底** 的混合架构：将「关注动态、搜索、视频播放、Opus 图文/专栏、个人中心、UP 主空间」等高频链路全面原生化，并对仍需回退网页的场景注入去干扰与拦截规则。

---

## ✨ 核心特性

* **关注动态与图文 / 专栏原生浏览**
  * **动态流与筛选**：支持全部、视频等分类筛选；前台停留自动检查新动态并在顶部静默刷新，深读过程中保持当前列表与阅读位置，详情返回时精准恢复滚动锚点。
  * **转发与引用动态**：原生展示转发动态卡片及嵌套引用内容，支持直接跳转到被引用视频或图文。
  * **Opus 图文与专栏**：原生解析并渲染富文本混排（表情、艾特、话题、链接卡片）、多图/长图画廊，以及完整专栏正文。
* **原生视频播放体验**
  * **双端原生内核**：iOS 使用 `AVPlayer`，Android 使用 `Media3 / ExoPlayer`。
  * **画质、分 P 与恢复**：支持自动与手动清晰度切换、分 P 与合集选集、断流有界恢复，以及本地优先结合服务端的账号隔离断点续播。
  * **弹幕与字幕**：支持高刷增量排版弹幕、开关与显示范围/字号等参数调节；支持多语言 BCC 字幕发现、选择与样式偏好。
  * **交互与布局**：全区域可点按拖动进度条（Android 全屏支持画面横滑定位）、长按三倍速与常用倍速记忆、可选自动下一 P、睡眠定时；Android 平板及宽屏设备支持播放器与侧栏双列独立滚动布局。
  * **画中画与后台播放**：播放中退回桌面自动进入系统画中画（PiP），锁屏或退至后台时继续音频播放，并提供锁屏、控制中心与媒体通知控制。
* **完整互动、评论与个人中心**
  * **互动与评论**：支持点赞、投币、收藏三连，评论与楼中楼分页展开、评论图片浏览、长按复制评论文本（含表情占位文本）、评论点赞以及发送/回复/删除本人评论。
  * **搜索**：原生搜索入口与综合/视频/番剧/直播/UP 主分类分页浏览。
  * **个人中心与内容管理**：聚合个人资料、继续观看、观看历史（支持关键词搜索、单条删除与清空）、收藏夹管理（新建、重命名、删除收藏夹及内容移动/复制/移除）、关注列表及 UP 主空间/合集浏览。
* **纯净外观与统一登录态**
  * WebView、原生 API 请求与原生播放器共享一套登录 Cookie，各模块严格按账号会话版本隔离。
  * 支持跟随系统的浅色/深色主题切换、自定义强调色、动态 UP 主屏蔽/过滤与网页区去广告导流注入。

---

## 🚀 下载与安装

在 GitHub Releases 页面提供已构建的安装包供直接体验（当前线上已发布版本为 **1.0.1**，主干源码持续演进中）：

👉 **[前往 Releases 页面下载](https://github.com/Silhouette-my/bilibili-focus-mobile/releases)**

* **iOS（免签侧载）**：下载 `BilibiliFocus-unsigned.ipa`，使用 **AltStore、SideStore、TrollStore** 或其他侧载工具签名后安装。
* **Android**：下载 `focus-android-debug.apk`，在系统允许“安装未知来源应用”后直接安装（或通过 `adb install` 安装）。

---

## 🗂️ 仓库结构

```text
├── App/BilibiliFocus           # iOS SwiftUI 客户端源码与资源
│   ├── BilibiliFocusApp.swift  # 应用入口与屏幕方向控制
│   ├── Features/
│   │   ├── Dynamic/            # 关注动态流与滚动锚点恢复
│   │   ├── Search/             # 原生搜索入口与分类分页
│   │   ├── My/                 # 个人中心、历史、收藏、关注、空间、专栏/Opus
│   │   ├── Player/             # 原生播放器、控件、弹幕与字幕视图
│   │   ├── WebBridge/          # WKWebView 兜底容器与页面增强桥接
│   │   └── Shared/             # 依赖图、路由状态、通用 UI、设置与后台调度
│   ├── Assets.xcassets         # 应用图标与矢量资源
│   └── Info.plist
├── Sources/FocusCore           # Swift 核心层（API/WBI、缓存分页、续播与共享 Resources/）
├── focus-core                  # KMP 跨平台核心层（模型、路由、API 服务、缓存分页与脚本构建）
├── focus-android               # Android Jetpack Compose 客户端
│   └── src/main/kotlin/.../    # 界面、ViewModel、Media3 播放服务、图片管线与 WorkManager
├── Tests                       # Swift 核心测试（FocusCoreTests）与应用层测试（BilibiliFocusTests）
├── Scripts                     # KMP Xcode 联动脚本、免签 IPA 打包脚本与清理脚本
└── docs                        # 架构与本地开发文档
```

---

## 💻 本地构建与测试

### 环境要求

* **iOS**：Xcode 16+（Swift 6）
* **Android / KMP**：JDK 17–24（推荐 **JDK 21** / Android Studio 内置 JBR；Gradle 8.12 暂不支持 JDK 25+）

### 快速构建

```bash
# iOS 命令行生成免签 IPA（输出至 build/dist/BilibiliFocus-unsigned.ipa）
# 或直接用 Xcode 打开 BilibiliFocus.xcodeproj，配置 Personal Team 后运行
./Scripts/build_unsigned_ipa.sh

# Android Debug APK
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
./gradlew :focus-android:assembleDebug
```

### 运行单元测试

```bash
# Swift 核心层测试
swift test --disable-sandbox

# KMP 与 Android 单元测试
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
./gradlew :focus-core:testDebugUnitTest :focus-android:testDebugUnitTest
```

更多项目架构细节、Xcode 模拟器测试命令及构建缓存清理方式见：

* [文档索引](docs/README.md)
* [架构说明](docs/architecture.md)
* [开发与构建指南](docs/development.md)
* [CHANGELOG](CHANGELOG.md)

---

## 📝 说明与免责声明

* **自用侧载定位**：本项目默认按个人学习与自用侧载方式设计，不以 App Store 或主流应用商店上架审核为目标。
* **上游接口依赖**：客户端的数据解析与网页净化规则依赖 Bilibili 现有接口与页面结构，如官方接口或 DOM 调整，需要同步更新对应适配逻辑。
* **构建产物忽略**：`build/`、`*.ipa`、`*.apk` 及各平台编译缓存不纳入 Git 追踪。
