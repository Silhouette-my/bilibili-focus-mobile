# Bilibili Focus (Mobile)

一款专为移动端打造的 **Bilibili 极简、清爽型第三方容器客户端**。

本项目是作者因不满官方客户端的臃肿和广告而开发的自用高效刷 B 站神器。它采用 **原生（Native）+ 网页（WebView）混合架构**，核心目标是将 B 站的「动态、搜索、视频、个人中心」全面原生化，提供丝滑、无广告、纯净的观看体验。

目前仓库已同时支持 **iOS (SwiftUI)** 和 **Android (Jetpack Compose)** 两条主线。

---

## 🌟 核心特性与亮点

* **广告与干扰全面净化**：WebView 区域内置自动化去干扰、导流拦截和布局修复机制，还你一个纯净的浏览界面。
* **丝滑的原生体验**：
    * **核心页面原生化**：关注动态流、搜索入口及结果页、个人中心、历史记录、关注列表、收藏夹/合集页、UP主空间等均采用原生组件渲染。
    * **原生视频播放**：iOS 采用底层 `AVPlayer`，Android 采用 `Media3/ExoPlayer`，支持分 P 播放、弹幕、评论查看、点赞/投币/收藏三连互动，以及播放进度自动上报。iOS 还支持原生字幕轨道发现、语言选择与开关偏好，并已支持评论楼中楼分页和评论点赞。
    * **PiP 与后台播放**：播放中返回桌面会自动进入系统画中画；PiP 不可用或锁屏时继续后台音频，并提供通知、锁屏及控制中心媒体控制。


* **统一登录态**：WebView、原生 API 请求和原生播放器共享一套登录 Cookie，无需反复登录。
* **个性化定制**：完美支持跟随系统的浅色/深色主题切换、自定义强调色、动态内容过滤以及弹幕开关。
* **完全掌控**：不以应用商店上架为目的，100% 独立构建，无隐私追踪。

---

## 🚀 下载与安装 (Direct Download)

为了方便无法在本地配置开发环境的读者，本项目在 Release 页面直接提供编译好的成品包：

当前版本：**1.0.1**

👉 **[前往 Releases 页面下载 1.0.1](https://github.com/Silhouette-my/bilibili-focus-mobile/releases/tag/1.0.1)**

### 1.0.1 更新内容

* iOS 与 Android 支持播放中自动进入 PiP，并在 PiP 不可用时继续后台音频。
* 增加锁屏、控制中心和 Android 媒体通知的播放控制及媒体信息。
* 补齐来电、音频焦点、耳机拔出和媒体服务重置处理。
* 修复 iOS `MPMediaItemArtwork` 跨执行队列崩溃，以及 Android 平板 PiP 画面缩放异常。

### 📱 iOS 安装指引

* **分发格式**：Unsigned (免签) `BilibiliFocus-unsigned.ipa`
* **安装方式**：由于该包不包含企业或 App Store 签名，下载后你需要使用 **AltStore、SideStore、TrollStore** 或其他签名/侧载工具，签名后方可安装至手机。

### 🤖 Android 安装指引

* **分发格式**：Debug `focus-android-debug.apk`
* **安装方式**：下载后直接传输到手机上，在系统设置中允许“安装未知来源应用”即可直接安装运行（或通过 `adb install` 调试安装）。

---

## 🛠️ 仓库架构

项目采用模块化设计，尽可能在 iOS 和 Android 之间复用逻辑：

```text
├── App/BilibiliFocus
│   ├── Features          # iOS Dynamic/Search/My/Player/WebBridge/Shared features
│   └── …                 # SwiftUI 入口、WebView 与平台适配
├── Sources/FocusCore     # Swift API/WBI、缓存分页、诊断、续播与 durable outbox
├── focus-core            # KMP 模型、路由、API、缓存分页与跨平台服务
├── focus-android
│   ├── playback          # Media3 service、播放状态、outbox 与 WorkManager
│   └── ui/video          # 拆分后的播放器、控件、弹幕、详情与评论 UI
├── Scripts               # 构建、运行时/契约同步与 opt-in 在线 smoke
├── Tests                 # Swift Core 与 iOS 应用层测试
└── docs                  # 升级路线、在线 smoke 与维护说明
```

iOS 生产代码当前仍使用 Swift `FocusCore`。KMP 的 iOS framework 已进入编译/链接
门禁，但尚未接入 App 运行路径；计划先将其 framework 改名为 `FocusKMP`，通过
Router adapter 完成首个共存切片，再逐项迁移网络服务。具体边界见升级路线图。

---

## 💻 本地源码运行与编译

如果你希望自己修改代码并编译，可以参考以下指南：

### iOS 运行

1. 使用 Xcode 打开 `BilibiliFocus.xcodeproj`。
2. 选择 `BilibiliFocus` scheme。
3. 在 `Signing & Capabilities` 中配置你自己的个人开发 Team（Personal Team）。
4. 连接真机或选择模拟器，点击 **Run** 即可。

*命令行源码构建：*

```bash
./Scripts/build_unsigned_ipa.sh

```

### Android 运行

> ⚠️ **注意**：请务必使用 **JDK 21**（推荐使用 Android Studio 自带的 JBR）。当前 Gradle/Kotlin 工具链暂不支持 JDK 25 初始化构建。

*macOS 环境下使用 Android Studio 内置 JDK 编译：*

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
./gradlew :focus-android:assembleDebug

```

---

## 🧪 自动化测试

项目包含完善的测试集，确保 B 站接口或网页结构变动时能快速定位问题。

* **iOS 核心测试**：`FOCUS_INCLUDE_TESTS=1 swift test --disable-sandbox`
* **iOS Release 边界测试**：`FOCUS_INCLUDE_TESTS=1 swift test -c release --disable-sandbox`
* **Web 注入规则验证**：`swift run FocusVerifier`
* **Android 单元测试**：`./gradlew :focus-android:testDebugUnitTest :focus-core:testDebugUnitTest`
* **KMP iOS 编译/链接门禁**：`./gradlew :focus-core:compileKotlinIosSimulatorArm64 :focus-core:linkDebugFrameworkIosSimulatorArm64`
* **跨平台运行时一致性**：`./Scripts/sync_focus_runtime.sh --check`
* **Bilibili API 契约一致性**：`./Scripts/sync_bilibili_api_contracts.mjs --check`
* **在线 API smoke（默认跳过）**：`node ./Scripts/run_online_smoke.mjs`

GitHub Actions 会在 Pull Request 和 `main` 分支更新时运行上述检查，并额外执行
Xcode 单元测试、Android Lint 与 Debug APK 构建。

### Web 注入运行时同步

`Sources/FocusCore/Resources/focus-runtime.js` 是 Web 注入运行时的唯一编辑源；
`focus-core/src/commonMain/resources/focus-runtime.js` 是供 Kotlin Multiplatform
打包的提交内镜像。修改运行时后执行：

```bash
./Scripts/sync_focus_runtime.sh --sync
./Scripts/sync_focus_runtime.sh --check
```

Gradle 的测试与 assemble 任务也依赖同一份一致性门禁，未同步时会直接失败。

### API 契约与升级路线

Swift 与 KMP 共享一份 independently maintained、facts-only 的 Bilibili API
端点子集。开发时可以用同级 `bilibili-api` 仓库校验当前 48 个端点：

```bash
./Scripts/sync_bilibili_api_contracts.mjs --validate-source ../bilibili-api
```

完整的 4–12 周改造成果、许可边界和后续功能顺序见
[升级路线图](docs/UPGRADE_ROADMAP.md)。
真实账号的只读在线检查使用显式 opt-in，详见
[在线 Smoke 说明](docs/ONLINE_SMOKE.md)。

---

## 📝 说明与免责声明

* **非商业/不考虑上架**：本项目默认按自用侧载方案设计，不以 App Store 或主流 Android 应用商店的审核兼容为目标。
* **维护依赖度高**：部分页面与数据接口依赖 Bilibili 当前的网页结构和 API，一旦上游发生重大改动，需要及时维护并更新相关规则。
* **忽略文件说明**：`Build/` 目录、`*.ipa`、`*.apk` 以及各平台的构建缓存默认不会进入 Git 追踪，发布用成品请关注 Releases 页面。
* `localonly/` 目录下的内容仅供本地调试，不属于远端主线的分发物资。
