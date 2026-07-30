# Bilibili Focus 升级路线图

本文记录 4–12 周架构改造的实际落地范围，以及 12 周后的建议演进顺序。路线以“先稳定协议和播放，再扩展功能”为原则；时间是单人持续维护时的粗略区间，不是发布承诺。

## 4–12 周：已完成

### 第 4–6 周：API 契约与网络边界

- 建立 48 个 facts-only API 端点目录，Swift 与 KMP 使用同一份提交内快照。
- 增加镜像一致性脚本、Gradle 门禁与 CI 检查。
- 以同级 `bilibili-api` 仓库和固定 commit `87110fe2db7af77425057e163f064700087a3c35` 作为开发期校验 oracle。
- iOS 与 KMP 分别收敛到单一 WBI signer，支持 30 分钟密钥缓存、并发请求合并、RFC 3986 编码和 `403/-403` 刷新重试。
- 主要 aid、cid、mid、cursor、时间戳和计数字段迁移为 64 位整数。
- GET 对网络异常、408、425、429 与 5xx 做有界退避重试；写请求不自动重试。
- 网络诊断只保留 method、去 query/fragment 的目标、状态码、耗时和响应大小，不记录 Cookie、签名、关键词或正文。
- Android Cookie 快照按实际 Bilibili origin 重建并保留同名不同作用域条目，避免跨子域登录态丢失，同时拒绝欺骗后缀。

### 第 6–8 周：数据流、缓存与分页

- 增加带 TTL、stale-if-error、LRU 和并发请求合并的内存缓存。
- 增加 generation-guarded cursor pager，统一 refresh/append、去重、旧请求丢弃、重复 cursor 终止和追加错误状态。
- Android 动态流与历史记录迁移到统一 pager；动态首屏使用短 TTL 缓存。
- iOS 动态流使用按登录态隔离的短 TTL 缓存，离线刷新可短暂回退到陈旧数据。
- 评论接口迁移到 `pagination_str` 与 opaque `next_offset`，不再假设 cursor 是页码或可解析数字。
- Android 建立 application-scoped `FocusAppGraph`，统一持有 Cookie、HTTP、WBI 与 feature services；移除未使用的 Koin 依赖。

### 第 8–10 周：可靠播放状态

- 续播元数据统一改为 WBI `/x/player/wbi/v2`，并从端点目录取址。
- iOS 与 Android 都保存有界本地播放位置，重新进入同一视频时优先使用近期本地进度，服务端进度作为回退。
- 接近开头不跳转，接近结尾从头播放；分 P 续播按 cid 恢复。
- 历史上报改为 durable outbox：先持久化、按 aid/cid 合并、成功后按 revision 删除，失败或进程退出后重试。
- 本地进度和 outbox 按账号 scope 隔离；发送前用同一份 Cookie 快照再次核对账号，切号不会把旧账号历史写入新账号。
- Android 播放状态由 application-scoped store 共享；iOS 使用 actor 与 UserDefaults 持久层。

### 第 10–12 周：稍后再看与质量门禁

- iOS 与 Android 完成稍后再看列表、添加、移除、删除已看和清空的 service contract。
- “我的”页面增加预览；完整列表支持续播进度、乐观删除、失败回滚和清空确认。
- 新增 WBI、64 位字段、opaque cursor、缓存、分页、重试、脱敏诊断、播放恢复、outbox 与稍后再看的单元测试。
- Swift Package、Xcode、KMP、Android unit test、Lint、Debug assemble 和两份运行时/契约镜像进入 CI。

## 12–16 周近期升级：工程基础已完成

- iOS 建立独立 `FocusAppGraph`，并按 Dynamic、Search、My、Player、WebBridge、Shared 拆分应用层；Android 视频页按播放器、控件、弹幕、详情和评论拆分。
- iOS 使用单一、仅认证 pending 才提交的 `BGProcessingTask`；Android 使用带网络约束、指数退避和有限重试的 `WorkManager`。两端共同唤醒已有 durable history outbox，前后台不维护第二套提交逻辑。
- 匿名播放只持久化本地进度；永久失败按 revision 精确丢弃并继续后项，网络失败保留重试，登录失效或切号不会跨账号提交。
- iOS 增加共享本地写入屏障，退出后立即重新进入同一视频时，续播读取一定发生在退出进度写入之后。
- iOS 原生播放器完成字幕轨道发现、BCC 字幕加载、语言选择、开关与语言偏好持久化；切换分 P 时会按新 cid 重新加载字幕。
- iOS 评论完成 opaque cursor 楼中楼分页、展开与去重，并支持账号绑定的评论点赞/取消点赞、乐观更新和失败回滚。
- 两端增加一致的登录健康状态，区分未登录、会话过期、缺少 CSRF、WBI/风控、网络不可用、健康和未知。
- 增加二次脱敏的诊断快照；Debug 设置页可以查看并导出摘要，Release 不编译诊断入口、旧调试开关或 WebView 日志桥。
- 增加显式 opt-in、只读的在线 API smoke；CI 只验证默认跳过路径，不保存账号 Cookie。
- iOS 通用构建、Simulator 测试、Swift/KMP/Android 单元测试、Android Lint 与 Debug APK 继续作为固定门禁。

尚未由自动化替代的部分是真机与真实账号验收：系统何时实际唤醒后台任务由 iOS/Android 调度器决定；强杀、后台 30 分钟、Cookie 过期、切网和多设备冲突仍需在发布候选版本上执行矩阵测试。

## `bilibili-api` 的使用边界

同级仓库用于开发期核对 URL 与 HTTP method，不是移动端运行时依赖。当前目录仅保存可独立维护的接口事实，没有复制其完整 JSON catalog、实现或文档。这样既能尽量利用上游变化线索，也避免把 GPL-3.0-or-later 代码直接合入当前仓库。

校验方式：

```bash
./Scripts/sync_bilibili_api_contracts.mjs --check
./Scripts/sync_bilibili_api_contracts.mjs --validate-source ../bilibili-api
```

当上游变化时，应先人工确认语义、认证、CSRF 与 WBI 要求，再更新本仓库 facts-only 子集及测试；不要直接覆盖式同步整个 catalog。

## 下一阶段：建议路线

### 下一步：真机线上稳定性验收

目标：使用已经完成的后台队列、登录健康、诊断和 smoke 基础设施，证明真实登录态与弱网下的可靠性。

- 建立真机矩阵：强杀进程、后台 30 分钟、切网、飞行模式、Cookie 过期、分 P、接近片尾和多设备进度冲突。
- 使用本地真实 Cookie 运行 opt-in smoke，并记录上游接口变更时的固定状态，不上传响应或凭据。
- 观察 iOS/Android 实际后台调度延迟、重试次数和队列年龄，依据真机数据再收紧策略。
- 验证 Debug 诊断导出在登录过期、风控和弱网场景中仍不含 Cookie、query、正文或关键词。

验收标准：进程强杀后可续播；离线期间上报不丢；恢复网络后不重复写操作；切换账号不读取或提交另一账号的播放状态；诊断信息不含 Cookie、query、正文和用户关键词。

### 下一步：KMP iOS 渐进接入（尚未完成）

当前 iOS 生产路径仍由 Swift `FocusCore` 提供。KMP iOS framework 已有编译与链接门禁，但其产物和 Xcode 原生 framework 目前都叫 `FocusCore`，不能直接共存。

- 先将 KMP iOS framework 改名为 `FocusKMP`，保持静态链接；原生 Swift `FocusCore` 的模块名和现有调用保持不变。
- 在 App target 的 Compile Sources 之前运行 Gradle Xcode framework 任务，只把 `FocusKMP.framework` 加入链接阶段，不加入 Embed Frameworks。
- 首个生产切片只迁移同步、无网络的主页 `FocusRouter.redirectTarget`；由单独 Swift adapter 同时导入 `FocusCore` 与 `FocusKMP`，映射设置和路由结果，并用双实现 fixture 做一致性测试。
- Router 稳定后再迁移网络服务。迁移前必须先补齐 Kotlin 异常到 Swift `Error` 的安全边界、Cookie provider adapter、静态 framework 资源装载和 KMP DTO 到 Swift `Sendable` 领域模型的映射。
- 每个 feature 独立切换和回归；SwiftUI 不直接持有 Kotlin DTO，未迁移的功能继续使用 Swift `FocusCore`。不要把现有 KMP 编译门禁描述为已经完成 iOS 运行时接入。

验收标准：Simulator 与真机架构均能链接两个不同模块；首个 Router 切片与 Swift 结果完全一致；App 不出现重复 framework、重复符号或静态 framework 误嵌入；网络迁移前任何 Kotlin 业务异常都不会在 Swift 侧触发 fatal。

### 16–20 周：视频与评论能力

- 接入相关视频并做有限预取。
- 在已完成 iOS 原生字幕的基础上，评估 Android 对等能力，并继续完善字幕样式和无障碍选项。
- 在已完成 iOS 评论楼中楼与点赞的基础上，补齐评论发送与删除，并评估 Android 对等能力；所有写操作复用 CSRF、失败恢复和幂等策略。
- 在视频页加入“稍后再看”切换，并与列表状态同步。
- 完善收藏夹 CRUD、移动/复制视频和收藏状态即时刷新。

验收标准：所有列表使用统一分页状态；写操作失败可恢复；任何 ID 均不降级为 32 位；接口地址均来自契约目录。

### 20–28 周：离线只读与性能

- 将 feed、history、watch later、favorite 元数据从内存缓存升级为账号隔离的持久缓存。
- 评估 SQLDelight 作为 KMP 数据层；iOS 在迁移完成前保持 repository protocol，避免 UI 直接依赖具体数据库。
- 增加封面磁盘预算、LRU 清理、列表预取上限和低数据模式。
- 支持最近观看、稍后再看与收藏的离线只读；恢复网络后按 generation 刷新。
- 建立启动、首屏、滚动和播放器首帧基准，防止功能增长带来持续回退。

验收标准：无网可打开最近数据；不同账号缓存不串线；存储和图片都有明确容量上限；关键性能指标进入自动化基线。

### 28 周以后：跨平台收敛

- 逐步把 API DTO、错误模型、分页、缓存策略和 use case 收敛到 KMP；SwiftUI 与 Compose UI 保持原生。
- 为 Swift/KMP 生成类型安全端点访问层，减少字符串 key，同时保留提交内可审查快照。
- 拆分当前较大的 iOS view-model 文件，按 Feed、Search、Player、My、WebBridge feature 分包。
- 将 WebView 注入能力降为兼容层，新功能优先走 typed native service。
- 评估多账号、账号级数据清理和可导入/导出的本地设置。

验收标准：同一接口只有一份领域语义和 fixture；平台差异集中在 Cookie、媒体栈、持久层与 UI adapter；新增 feature 不需要修改全局巨型文件。

## 每次升级的固定门禁

```bash
./Scripts/sync_focus_runtime.sh --check
./Scripts/sync_bilibili_api_contracts.mjs --check
FOCUS_INCLUDE_TESTS=1 swift test --disable-sandbox
FOCUS_INCLUDE_TESTS=1 swift test -c release --disable-sandbox
./gradlew :focus-core:testDebugUnitTest :focus-android:testDebugUnitTest \
  :focus-core:compileKotlinIosSimulatorArm64 \
  :focus-core:linkDebugFrameworkIosSimulatorArm64 \
  :focus-android:lintDebug :focus-android:assembleDebug \
  :focus-android:compileReleaseKotlin --no-daemon
git diff --check
```

涉及 API、播放或 Cookie 的改动，还应完成真机登录与弱网验证；单元测试不能替代线上接口和系统生命周期测试。
