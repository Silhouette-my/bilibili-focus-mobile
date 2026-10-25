# Bilibili Focus iOS：性能与稳定性基础修复

日期：2026-10-16。本文以本轮开始时的工作区快照为比较基准，不把原有未提交实现计为新增成果。

## 范围与工作区保护

工作目录：`/Users/michaeltan/Desktop/Programming/Bilibili-FOCUS/bilibili-FOCUS-iOS`。

原始基线目录（下文记为 `$B`）：`../performance-foundation-baseline-20261016-194504`。原始 `files/`、`manifest.json`、`status.txt`、`worktree.diff`、`index.diff`、`branch.txt`、`head.txt` 及开发期失败证据保留。初始 HEAD 为 `b5e72d07c1db82c70be8e90a72f8f2472c73a668`，分支为 `codex/ios-kmp-integration`。

续接基线与最终验收证据目录（下文记为 `$E`）：`../performance-foundation-continuation-20261016-212755`。继续修改前再次保存了 97 个相关源码/配置/文档文件及工作区、暂存区差异；没有覆盖原始基线。最终日志、命令 JSON 和 xcresult 存在 `$E`，构建复用 `$B/swift-build`、`$B/DerivedData`、`$B/DeviceRelease` 的现有缓存。续接阶段仅调整真实卡片回归的生命周期同步并更新本文；P0–P5 的归属仍以本轮原始基线 `$B` 为准，不把继续前已落地的代码重复算作新实现。

原有 persistent dynamic feed、视觉锚点、播放器首帧处理、评论图片、播放进度写入屏障、KMP Router 及 Android/KMP 未提交工作均不是本轮新成果。本轮没有重置、清理、切分支、提交、推送或发布；没有更换播放器内核、迁移 Flutter、绕过 KMP framework 或安装大型依赖。对照快照审查本轮增量，不以 `git diff HEAD` 的全部改动代替归属证据。

测试使用合成凭据、可注入请求、受控 continuation 和本地媒体 fixture。Scheme 的 `FOCUS_FIXTURE_TESTS=1` 使 hosted app 不建立正常用户图、不注册历史后台任务；测试图使用非持久 WebKit 存储和内存播放进度。默认原生 API / 图片网络实现拒绝 fixture 模式的实际联网；注入请求仍可测试所有错误路径。未读取或导出真实 Cookie、令牌、浏览历史，未执行真实账号互动、登录或退出操作，未清空模拟器数据。

## P0：阶段诊断

状态：基础实现完成；真实设备分布尚未测量。

涉及 `Sources/FocusCore/BiliDiagnostics.swift`、`BiliAPITransport.swift`，以及会话、动态、我的、视频与滚动模块；Debug 展示位于 `Features/Shared/FocusDiagnosticsView.swift`。

`BiliPerformanceStore` 使用单调时钟和随机关联 UUID，默认环形容量 256（构造上限 4096）。阶段与结果为封闭枚举，只记录耗时、计数及可选位置误差，不接受 URL、搜索词、响应正文、账号标识或凭据作为阶段文本。网络事件另外有 200 条上限，并删除目标的用户信息、查询参数与 fragment。

分别记录 sessionInitialization / cookieSnapshot、dynamicLoad / dynamicFirstPage / dynamicDisplayed、myProfile 和各分区、videoDetail / playbackURL / resumeLookup / mediaPreparation / playerReady / firstFrame，以及 scrollRestore / layoutCompensation。缓存返回、页面数据就绪、实际可见行、播放器 ready 和可显示首帧不是同一个事件。刷新期间保留的旧行不会提前结束新一轮 dynamicDisplayed。

视频阶段由随机任务标记关联；首帧需要当前任务、当前 AVPlayerItem、已挂载展示表面、当前 inline/fullscreen 模式及完成的播放准备共同成立。重复、旧 item、旧任务、未挂载或被另一展示模式覆盖的表面不能记为成功。`firstFrame` 从 `preparePlayback` 开始计时，包含其中的会话/本地写入屏障等待，`videoDetail` 独立记录；它不是仅媒体条目创建的耗时，也不要把并行子阶段耗时直接相加作为点击到首帧。列表预览不触发首帧事件。

### 诊断使用

Debug 构建中打开「设置 → 高级 → 登录与网络诊断」。页面显示最近 60 条阶段事件及关联标记、耗时、结果、计数和锚点误差；下拉或右上角刷新可更新快照。现有登录健康检测为只读、合并且限频，不附加到每个业务请求的串行关键路径。

「导出脱敏摘要」调用系统分享面板，仅由用户主动选择输出；没有新增上传端点或自动外发。「清除本地事件」只清除诊断内存缓冲，不清除业务数据。进程终止后诊断缓冲消失。非 Debug 构建不显示这个入口。

## P1：共享会话与账号隔离

状态：共享初始化、版本隔离、错误分类与原生消费者恢复已实现；真实会话生命周期待真机验证。

涉及 `CookieSnapshotProvider.swift`、`LoginHealth.swift`、`BiliAPITransport.swift`、`FocusBrowserViewModel.swift`、`FocusWebView.swift`、`FocusAppGraph.swift`、`FocusAppViewModel.swift`。

普通页面和视频复用同一个 `WebViewCookieSnapshotProvider` 与 `CookieSessionCoordinator`。并发首次消费者共享初始化 flight；取消一个消费者不会取消其他消费者的读取。保留有界的首次恢复预算，不再让多个 provider 各自重复等待。会话区分 restoring、unconfirmed、anonymous、authenticated、expired；临时读取失败不被当成有效认证或确认退出。

WebKit 是 Cookie 权威来源。监听 WKHTTPCookieStore 变化，失效快照并以版本屏障拒绝旧读取、旧账号请求及退出后的迟到响应；已被服务端拒绝的同一凭据不会被再次读取假装恢复。保留域、路径、Secure、过期和 host-only 语义，不按名称粗暴合并，不扩大域，不关闭 TLS 验证。原生 URLSession 不维护第二套独立 Cookie jar；带认证请求不接受重定向带来的身份跨域传播。

真实身份变化撤销旧账号的动态、我的、历史、收藏页和视频访问。账号重置通知的责任不会因随后的普通 Cookie 事件超车而丢失。确认凭据未变但快照版本改变时，只重新启动被屏障打断的首屏/分区/媒体准备；不清空已展示内容，不打断已开始的同账号播放，避免请求取消后永久停留在 loading。

网络、风控、缺失 CSRF 与真实 -101/401 分开处理。单分区网络失败不会显示成整个账号掉登录。真实过期走正常网页重新认证流程。

边界：没有实现未经验证的自动续期，也没有把原生响应 Set-Cookie 自动写回 WebKit。这样避免旧响应、重定向及不完整域属性覆盖新账号；需要续期时重新认证。当前没有证据表明必须接管某个原生响应的凭据轮换，后续若加入写回，必须另行验证来源、host-only、路径、删除/过期和版本契约。

## P2：动态返回与布局稳定

状态：恢复/补偿分离、稳定 ID 展开状态、观察范围优化已实现；真实卡片专项及完整 93 项 Simulator 回归均已通过。

涉及 `Features/Dynamic/FocusDynamicFeature.swift`、`Features/Shared/FocusAppViewModel.swift`、`Tests/BilibiliFocusTests/FocusDynamicScrollRestorationTests.swift`、`PerformanceDynamicTests.swift`。

保留 persistentDynamicFeedLayer、LazyVStack、视觉锚点及原有晚到高度补偿。完整恢复仅由真正激活/恢复版本变化触发；后续 geometry、contentSize、inset 事件合并成局部补偿，不再重新开始整套恢复。每轮最多 24 次实际 offset 校正，窗口为 8 秒，原有短期 materialization 重试最多 30 次；不存在无限寻找消失卡片或无限延长校正窗口。筛选和第一页数据版本变化清除旧锚点；找不到锚点时有限降级为合法范围内的 offset。

用户 pan 开始、拖动或减速时优先取消冲突恢复与锚点。隐藏列表不继续分页、预取和校正。长文本/多图展开状态移到 feed model，按稳定 ID 与内容签名维护，上限 512，并在替换数据、退出或切号时清理。不使用未经宽度或字体校验的永久行高缓存。

原生播放器向顶层只转发去重后的必要状态；进度、弹幕、字幕留在播放器观察子树。标题、返回、底栏和播放相关状态仍更新。

新增真实生产卡片的验证使用 32 行长文本、6 张图、保留展开、行重新创建、分页边界与连续四次返回，并在卡片实际 UIKit 表面上测量 window 坐标，而不是仅断言 scrollOffset 数值或读取可能滞后的 SwiftUI GeometryPreference。布局阶段以实际渲染状态同步：先确认隐藏状态已送达生产 coordinator，替换行并变更前序高度/分页后重新激活，再同时等待新的行 epoch、真实高度和屏幕位置到位。不能要求暂停恢复中的 LazyVStack 提前物化替换行。四次返回的 epoch、展开状态、高度和 2 pt 位置断言全部保留，不靠增加固定 sleep 或放宽精度通过。还验证同轮几何事件合并、完整恢复次数和手势竞争。

## P3：首屏、刷新与我的分区

状态：基础实现完成。

涉及 `FocusDynamicFeature.swift`、`Sources/FocusCore/DynamicFeedService.swift`、`AsyncExpiringCache.swift`、`Features/My/FocusMyFeature.swift`。

动态只等待第一页即可发布 loaded。后续页由可见列表尾部或显式继续加载触发；过滤后暂时没有可见卡片时仍有继续入口，一次操作只加载一页，不无界扫描。合并重复 ID，拒绝重复 cursor，尊重 has_more=0/false，即使服务端仍回传末尾 cursor 也停止。generation、会话版本和独立 append ID 阻止旧追加任务污染刷新、筛选或新的追加状态。

刷新使用独立 isRefreshing 与局部错误，保留同账号旧卡片；追加失败显示尾部重试。缓存的强制刷新不先删除回退数据；显式刷新消费者可以收到原始错误，其他需要 stale-if-error 的消费者仍可使用原缓存。取消/认证失败不回退为旧认证内容；失效和插入会屏蔽迟到 flight。缓存按会话/账号作用域分隔，有容量上限，未引入磁盘元数据数据库。

「我的」基本资料先显示，关注统计、历史、收藏夹列表、稍后再看独立并发发布。分区失败状态和重试与整页分离，失败不伪装为空列表。收藏夹元数据不等待预览；预览最多 6 个文件夹、并发最多 2。所有分区和预览都检查同一会话版本；回到已加载页面不无条件全量刷新。

## P4：视频关键路径

状态：基础实现完成；真实 CDN 起播和真实历史待设备验证。

涉及 `FocusNativeVideo.swift`、`FocusVideoDetailService.swift`、`FocusVideoSubtitleService.swift`、`FocusNativeVideoViews.swift`、`FocusAppGraph.swift`、`FocusAppViewModel.swift`。

CID 确定后，播放地址一到便开始创建媒体条目并等待 ready，与续播查询重叠；正式播放前才汇合。保留本地写入屏障、有效近期本地进度优先、多 P 选择、显式 p/CID、旧任务取消和首次 seek。多 P 需要历史确定目标 CID 的情况不会错误地把未选定的 P 当成最终流。开始播放后不接受迟到历史跳进度。

服务端历史默认等待预算为 2 秒，使用独立 continuation race；不会因结构化并发隐式等待不合作子任务而形成伪超时。计时器和请求均可注入。超时后降级，迟到结果无权替换当前播放器。

`FocusPlayerInfoRepository` 在同一个会话 provider 下共享 resume/subtitle 请求，key 包含 session version、aid、cid，最多 32 项、TTL 2 秒；不是仅复用签名器。保留 WBI 签名和错误处理；一个消费者取消不影响仍需要该 flight 的消费者。

保留 progressive 优先，但只对确实无可用兼容流的结果做一次 DASH 回退；网络、取消和风控不机械走第二遍。没有依据一次失败永久全局禁用某流，没有降低清晰度，也没有长期缓存签名播放 URL。

动态可传已有封面；搜索结果/搜索预览可传已有标题和封面。动态正文可能不是视频标题，因此不冒充标题。路由预览仅临时展示，切视频即清除，完整详情到达后替换。没有改造搜索交互，也没有将已有评论/互动独立加载计为新增。

## P5：图片尺寸与预取调度

状态：在原设施上完成优化。

涉及 `FocusSharedUI.swift` 与 `PerformanceImageTests.swift`。

保留原有 NSCache、URLCache、后台解码、URL/Referer 回退和进行中请求合并。按显示尺寸及屏幕倍率选用稳定像素档位：128 / 256 / 384 / 512 / 768 / 1024 / 1536 / 2048 / 3072 / 4096，减少细小布局变化制造的新键。头像、卡片、封面按各自几何尺寸解码；gallery 与长图保持独立高质量路径，没有统一套用缩略图规格。

预取按去重后的 URL 限总量 24、并发 2；可见消费者不经过预取许可队列，因此不是仅设置一个无效优先级。离开页面取消预取消费者，但仍有可见消费者的共享任务继续；最后一个消费者离开才取消底层请求。离线、超时、TLS 和取消立即终止无意义组合重试；只有明确允许的响应类别执行有限回退。隐藏动态的预取撤销也减少了与视频准备争用。

## 验证与证据

环境：Xcode 26.3 / Swift 6.2.4；自动查询并使用现有 iPhone 16 Pro、iOS Simulator 18.6，UUID `7AC09A76-6490-46E1-A1EB-291698558EB8`。没有要求用户填写 UUID，也没有 erase/reset 模拟器。KMP 通过现有 `Scripts/build_kmp_for_xcode.sh`、Java/Gradle 配置与缓存参与应用构建。

| 验证 | 实际状态 | 证据 |
| --- | --- | --- |
| Swift Core Debug | 126 tests / 22 suites，通过 | `$E/core-debug.log` |
| Swift Core Release | 126 tests / 22 suites，通过 | `$E/core-release.log` |
| FocusVerifier | 8 组检查，通过 | `$E/verifier.log` |
| Runtime mirror | 通过 | `$E/runtime-mirror.log` |
| API contracts mirror | 48 个端点，通过 | `$E/api-contract.log` |
| git diff --check | 通过，文档更新后再检查 | `$E/diff-check.log`、`$E/final-review.json` |
| iOS Simulator 完整回归 | 93/93，通过；0 失败、0 跳过 | `$E/SimulatorFull.xcresult`、`$E/simulator-full-summary.json` |
| 实际卡片测量专项 | 1/1，通过；同一测试也包含在上述 93 项中 | `$E/CardRegression.xcresult`、`$E/card-regression-summary.json` |
| iOS Simulator 独立应用 build | Debug 构建通过 | `$E/simulator-build.log`、`$E/xcode-checks.json` |
| unsigned iOS Release | 最终复验通过；未签名、未安装真机 | `$E/device-release.log`、`$E/xcode-checks.json`；产物在 `$B/DeviceRelease` |
| 在线 smoke opt-in 边界 | 未启用时正确 SKIP；不算真实接口通过 | `$E/online-smoke-opt-out.log` |

上述测试与构建均在最后一次相关 Swift 源码/测试修改之后执行。`core-checks.json`、`xcode-checks.json` 保存准确命令、退出码和结果；完整测试的数量来自 xcresult，而不是根据构建 exit 0 推断。所有执行任务均已结束，没有将运行中的任务作为验收结果。

执行命令如下（`B`、`E` 为上述目录；模拟器 UUID 来自本次自动发现结果）。最终 Core 与 Xcode 联合验收进程显式设置 `FOCUS_FIXTURE_TESTS=1`、`FOCUS_ONLINE_SMOKE=0`，并移除继承的 `FOCUS_BILIBILI_COOKIE`，没有输出其值。此前卡片专项的 hosted app 由 scheme 的 TestAction 设置 fixture 标志，同样不启动真实账号图。

```sh
B=../performance-foundation-baseline-20261016-194504
E=../performance-foundation-continuation-20261016-212755
export FOCUS_FIXTURE_TESTS=1 FOCUS_ONLINE_SMOKE=0
unset FOCUS_BILIBILI_COOKIE

FOCUS_INCLUDE_TESTS=1 swift test --disable-sandbox --scratch-path "$B/swift-build"
FOCUS_INCLUDE_TESTS=1 swift test -c release --disable-sandbox --scratch-path "$B/swift-build"
swift run --scratch-path "$B/swift-build" FocusVerifier
./Scripts/sync_focus_runtime.sh --check
node Scripts/sync_bilibili_api_contracts.mjs --check
node Scripts/run_online_smoke.mjs
git diff --check

xcodebuild -quiet -project BilibiliFocus.xcodeproj -scheme BilibiliFocus test \
  -destination 'platform=iOS Simulator,id=7AC09A76-6490-46E1-A1EB-291698558EB8,arch=arm64' \
  -derivedDataPath "$B/DerivedData" -resultBundlePath "$E/SimulatorFull.xcresult" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

xcodebuild -quiet -project BilibiliFocus.xcodeproj -scheme BilibiliFocus build \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=7AC09A76-6490-46E1-A1EB-291698558EB8,arch=arm64' \
  -derivedDataPath "$B/DerivedData" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

xcodebuild -quiet -project BilibiliFocus.xcodeproj -scheme BilibiliFocus build \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$B/DeviceRelease" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

真实卡片专项使用同一 scheme、设备和 DerivedData，加上
`-only-testing:BilibiliFocusTests/PerformanceDynamicTests/testActualLongTextMultiImageCardKeepsScreenPositionAcrossRepeatedRemountAndPagination`；准确参数保存于 `$E/card-regression-command.json`。随后运行的完整 93 项没有使用 only-testing 或 skip-testing。

独立 scratch / DerivedData 仅隔离构建产物，没有绕过依赖或改变业务实现。新 iOS 测试文件已加入 pbxproj 的 file reference、group 和 Sources build phase；Core 测试由 Package.swift 的既有 conditional test target 编译。没有删除原测试函数、跳过失败测试或放宽原有锚点精度要求。

开发期失败的 xcresult 与日志均保留。新增真实卡片测试暴露了测试 harness 中空 preference 覆盖测量、raw/normalized offset 混用、SwiftUI 几何值滞后及渲染阶段未同步的问题。续接时最后一项失败明确定位为：尚未重新激活恢复，就要求 LazyVStack 的替换行达到新 epoch；调整为激活后同时验证新行、高度和位置，而不是删除断言、延长等待时间或只测 offset。专项与完整测试现均通过。按需创建语义参考 [Apple：Creating performant scrollable stacks](https://developer.apple.com/documentation/swiftui/creating-performant-scrollable-stacks/)。现有首帧测试增加真实挂载窗口，仍保留原断言；「我的」测试改为逐分区失败断言，符合本轮的独立分区语义，而不是把错误吞成空列表。

覆盖包括并发初始化/乱序/真实过期分类、缓存失效和 stale 策略、第一页独立发布、刷新/追加错误、账号/筛选/旧请求隔离、预览并发上限、慢历史时媒体提前创建、真实非阻塞超时、分 P/本地写入/续播、player-info 去重、流回退、首帧归属、原动态手势/晚到布局回归、评论图片、长图、共享图片取消及 KMP Router。最终数量已核实为 Core Debug/Release 各 126 项、Simulator 完整 93 项，详见上表。

原始工作区到最终实现的增量位于 `$E/original-to-final.diff`，保护性检查位于 `$E/preservation-review.json` / `$E/final-review.json`。检查分支、HEAD、暂存区未改变、原始文件未丢失、原有测试函数未移除、Android/KMP 原工作未被本轮改写。续接相对第二份基线的改动仅为 `PerformanceDynamicTests.swift` 与本文；不覆盖或清理无关工作区内容。

## 真机验收矩阵与未验证边界

以下均未作为已通过项目，也未生成性能提升百分比或线上 P50/P95。

| 场景 | 测量或行为要求 |
| --- | --- |
| 冷启动 / 热启动动态与我的 | 分别采集会话恢复、第一页、实际显示；保留相同账号和内容条件，多次样本再计算 P50/P95 |
| 冷 / 热视频起播 | 区分详情、地址、历史、media-ready、真实首帧；覆盖命中本地历史、服务端历史超时、单 P/多 P/显式 CID，不用封面代替首帧 |
| 长文本、多图与展开后返回 | 同一稳定 ID 卡片在屏幕中的真实位置；布局稳定后误差目标约 1–2 pt，不仅比 offset |
| 横屏/竖屏/全屏后返回 | 当前表面首帧归属正确，布局补偿有限，页面不无端重置 |
| 连续快速进入/返回、分页边界 | 包括布局未稳定时再次返回；无旧视频接管、无无限恢复、无手势争夺 |
| 用户拖动与晚到图片/字体/宽度变化 | 用户手势立即优先；晚到高度仍可有限补偿，旋转/Dynamic Type 需要实际设备复核 |
| 切网、离线及恢复 | 同账号旧内容保留，分区局部错误与重试明确；不存在无限 URL/Referer 重试 |
| 进后台、恢复、进程重启 | 会话与进度读取正确，后台期间不无意义分页/预取；按平台真实生命周期验证 |
| 真实会话过期、退出、切号 | 旧账号内容访问即时撤销，迟到响应不能恢复；重新登录可恢复正常请求，不能用过期凭据制造成功 |

延期/边界：完整磁盘元数据缓存；未经验证的自动续期与响应 Cookie 写回；跨内容/跨账号的流能力记忆；真实 CDN、真实登录和物理设备的耗时分布。它们没有被假装成已完成；没有新增对外遥测上传。

交付状态：P0–P5 范围内的基础实现、离线/合成数据自动化回归与 Simulator/unsigned Release 构建已完成，没有剩余构建或测试阻塞。上述真机矩阵与明确延期能力仍未验证或未实现，不据此承诺实际起播提升百分比、绝不漂移或永不掉登录。
