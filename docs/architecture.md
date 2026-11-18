# 架构说明

Bilibili Focus 采用 **原生为主、WebView 净化兜底** 的移动端双端架构：核心阅读与播放体验由原生 UI 与服务承担，暂未完全原生化的网页页面通过注入运行时规则去干扰并统一拦截跳转。

## 模块划分

### 1. iOS 应用与 Swift Core

- `App/BilibiliFocus/BilibiliFocusApp.swift`：应用入口与全局设备方向控制。
- `App/BilibiliFocus/Features/`：按业务拆分的功能模块：
  - `Dynamic/`：关注动态流、分类筛选、前台自动刷新与返回滚动锚点恢复（`FocusDynamicFeature.swift`）。
  - `Search/`：多分类原生搜索入口、结果分页与阅读窗口预取（`FocusSearchFeature.swift`）。
  - `My/`：个人中心、观看历史（含搜索与管理）、收藏夹管理、关注列表、UP 主空间/合集、专栏与 Opus 详情（`FocusMyFeature.swift`）。
  - `Player/`：`AVPlayer` 原生播放器、画面内控件、弹幕/字幕叠层、清晰度切换、画中画与后台媒体控制（`FocusNativeVideo.swift`、`FocusNativeVideoViews.swift`、`FocusNativePlaybackControls.swift`）。
  - `WebBridge/`：`WKWebView` 容器、外链/深链导航拦截、深浅色同步及网页端原生增强桥接（`FocusBrowserView.swift`、`FocusBrowserViewModel.swift`、`FocusNativePageAugmentService.swift` 等）。
  - `Shared/`：应用级依赖根 `FocusAppGraph`、顶层路由状态 `FocusAppViewModel`、通用图片加载与画廊/富文本组件 `FocusSharedUI`、设置与持久化、`BGProcessingTask` 后台上报调度、`FocusKMPRouterAdapter` 及 Debug 诊断视图。
- `Sources/FocusCore/`：Swift 领域模型、路由策略、WBI 签名、API 传输与诊断、缓存分页、续播进度与持久化 Outbox，以及跨平台共享资源 `Resources/`。

### 2. Kotlin Multiplatform 共享层（`focus-core`）

- `commonMain`：跨平台模型、路由（`FocusRouter` / `FocusNavigationPolicy`）、WBI 签名（`WbiSigner`）、重试传输（`ResilientHttpClient` / `ObservingHttpClient`）、缓存与分页（`AsyncExpiringCache` / `CursorPager`）、各类 Bilibili 业务 Service 及 Web 注入规则目录（`FocusRuleCatalog` / `FocusScriptBuilder`）。
- `androidMain` / `iosMain`：平台加密摘要（MD5 / SHA-256）、Ktor 网络引擎（OkHttp / Darwin）、设置存储与资源读取实现。
- iOS 侧通过 `Scripts/build_kmp_for_xcode.sh` 编译并静态链接 `FocusKMP.framework`；当前主页重定向已通过 `FocusKMPRouterAdapter` 接入 KMP 并保留一致性回退，其余网络与数据服务在 iOS 侧仍以 Swift `FocusCore` 为主实现。

### 3. Android 应用（`focus-android`）

- `FocusApp.kt` / `FocusAppGraph.kt` / `MainActivity.kt`：Jetpack Compose 导航栈、应用级依赖图（统一共享 `CookieProvider`、HTTP 客户端、WBI 签名器与播放历史 Outbox）及自适应手机/平板窗口布局。
- `playback/`：基于 Media3 的前台播放服务（`FocusPlaybackService`）、系统媒体通知与 PiP 联动、本地断点续播存储、历史 Outbox 与 `WorkManager` 后台补偿上报。
- `images/`：Coil `ImageLoader`、B站 CDN 尺寸桶重写拦截器（`FocusImageCDNInterceptor`）、动态列表滚动预取与同请求合并。
- `ui/` & `ui/video/`：按页面和播放器子组件拆分的 Compose 界面（动态流、搜索、个人中心、历史、收藏夹、UP 主空间/合集、专栏、Opus 详情、播放器控件/手势进度条/弹幕/评论/宽屏侧栏双列布局）。

## 共享资源与关键边界

### 单一事实源的共享资源

`Sources/FocusCore/Resources/` 存放两份由 Swift 与 KMP/Android 直接共用的只读资源，`focus-core/build.gradle.kts` 直接将该目录配置为资源源路径：

- `focus-runtime.js`：WebView 去干扰与布局修复注入运行时脚本。
- `bilibili-api-contracts.json`：独立维护的 Bilibili API 端点目录（URL、HTTP Method、认证、WBI 与 CSRF 要求）。

### 会话隔离、播放与 Outbox

- **统一 Cookie 权威源**：WebView 与原生请求共享登录 Cookie；账号变更或失效时会递增会话版本，阻断旧账号迟到响应与跨账号数据串线。
- **网络与签名**：GET 请求对瞬时网络异常与 `408`/`425`/`429`/`5xx` 做有界退避重试，写请求不自动重试；WBI 接口在遇到 `403`/`-403` 时自动刷新密钥并重试。
- **断流与续播**：两端均保留本地近期播放位置与服务端回退，历史观看上报写入按账号隔离的持久化 Outbox，由前后台调度器在联网鉴权后异步上报，并避免历史删除与旧队列重传互相冲突。
- **图片请求策略**：对已知支持缩略图参数的 BFS CDN 图片按显示档位请求适配尺寸，对签名 URL、表情动图及图库原图保持原址；动态列表支持按可见窗口并发预取并合并相同在途请求。
