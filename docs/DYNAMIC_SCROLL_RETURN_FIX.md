# 动态详情返回：滚动位置与可见连续性专项

## 2026-10-25：build 5 自动刷新与阅读位置

动态改为前台可见时定期自动获取，并在顶部、非拖动/减速状态自动应用；深处阅读期间保留原列表和分页，待滚回顶部后自动展示新第一页，不要求用户点击提示。详情覆盖期间和后台停止轮询，返回时只做到期检查，避免每次视频返回都重新请求。

试验的“深处立即 prepend 新卡片”方案在真实 LazyVStack 宿主中出现首帧阅读卡片缺失，结果保留于 `build/PhoneLayout-20261025/IntegratedIOS18.xcresult`。因此采用上述顶部自动发布策略，移除试验中分离 canonical 页与额外阅读后缀的合并层，继续使用原有列表、分页 cursor 和 generation。回归验证深处收到更新后各帧保持原位，以及回顶后自动应用新内容；原详情返回测试和 ±2pt 标准保留。

完整回归还捕获了返回已对齐、详情已揭开之后的非用户 offset 晚到。事件序列最终确认：viewport 高 739.6667pt，目标卡片高 428pt，迟到位置恰为 311.6667pt，即默认 `reader.scrollTo(id)` 为了完整显示整行而执行的底对齐；长于屏幕的图文则被再次顶对齐。它与 UIKit 保存的部分可见阅读位置是两个不同目标。

现在把显式滚动 ID 放在卡片顶部不影响行高的 1pt 标记上，保留 ForEach 的原 card.id 以支持离屏查找；物化请求用保存的 viewport Y 为该点计算 UnitPoint。位置不再依赖卡片高度，也覆盖整屏等高行、长图文与负 Y。`DynamicPointMarker-v2.xcresult` 的 21 项专项通过，四次宽度变化返回无缺失样本，最大误差低于 0.001pt，每次物化 1 次；原物化/校正预算和 0.8 秒截止不变。

直接 KVO 校正会在同周期 offset/frame 共同重基时产生两次反向校正（`DynamicSuccessRebase.xcresult`）；提交前合并虽通过专项，全量仍有迟到位移。这两种补偿及跳过 rootView 更新的尝试均已撤回，完整环境传递和强化后的重基回归保留。

最终 iOS 18.6 完整回归 **168/168 通过**，见 `build/PhoneLayout-20261025/DynamicPointDelivery.xcresult`。iOS 26.3.1 为 **167/168**，唯一记录失败来自系统 Gestures 的 `InvalidTransition`，相同包的快速返回隔离复测四轮通过、无缺失、最大误差低于 0.001pt；整套结果与隔离结果分别保留。安装包及具体边界见 [build 5 交付证据](PERFORMANCE_FOLLOWUP.md#build-5-交付证据)。

## 2026-10-25：build 4 的布局交接修复

本轮继续处理 build 3 之后仍存在的返回跳动，沿用已有卡片、分页、缓存和视觉锚点模型。

- 动态列表使用独立的 `UIHostingController` 边界，由外层 viewport 统一消费安全区；详情覆盖时保留完整尺寸，不只保留宽度。完整 `EnvironmentValues` 继续传入，字体、辅助功能、方向和主题不会被隔断。
- 返回时先在实际详情覆盖下提交目标尺寸与环境，再沿用锚点对齐流程。pending return 中后续布局更新会撤销旧的 ready 状态，不能用上一次布局的确认放行。普通布局未变仍原位返回；原 0.8 秒截止、物化/校正预算及 2pt 测试阈值不扩大。
- 用户展开或收起文字、图片时，先撤销旧返回锚点；新阅读操作不再被旧位置补偿拉回。真正的异步高度变化仍使用原有补偿。
- 原生播放器改用画面内控制，不再给详情额外预留旧 dock 的 74pt；网页控制栏保留。

定位中曾记录“首个可见帧偏 32.67pt、次帧归零”，且同步 `preserved` 之后才发生一次恢复。它暴露的是返回放行早于新布局提交，而非最终 offset 无法找回。快速导航与后续宽度变化进一步要求每次布局更新都使旧确认失效。

另一项诊断确认旧 fixture 的固定 22,000pt 移位会越过列表末端，随后由 UIKit 合法夹取 269pt。fixture 改为距末端至少一屏的内部位置；原用户操作的 +40pt、两帧采样、±2pt 和“旧校正不增加”断言均保留，末端 clamped 专项也保留。ID 物化仅要求最小可见滚动，精确位置由 coordinator 单独负责，避免迟到的顶端对齐再次移动卡片。

证据在 `build/PlayerRefresh-20261025/`。早期把“用户主动展开”当作“网络高度晚到”的诊断断言已撤回；最终测试仍要求用户选择的卡片位置连续、旧补偿不增加，原用户滚动的 raw offset 断言也保留。真实账号长列表、物理设备旋转和网络图片时序尚需真机验证。

### build 4 最终验证

- iOS 18.6 完整 App 回归：**156/156 通过，0 失败、0 跳过**，结果为 `DeliveryIOS18-v21.xcresult`。
- 完整回归 v20 在用户展开用例的准备阶段失败：ID 物化只承诺最小可见，而旧 setup 假定顶端对齐；直接设置一次 offset 后，80 行 LazyVStack 的前缀估算又可能把所需两行移出视口。最终该交互专项使用两张真实生产卡片，按实际坐标摆放，末端保有至少 240pt 滚动余量。只在打开详情前确认两行可见，返回后的首帧、±2pt、展开增高和旧校正不增加断言均保留。深列表、物化、旋转和快速导航仍由其他宿主用例覆盖，默认 80 行 fixture 未改。
- iOS 26.3.1 的 `IOS26ScrollPlayer.xcresult` 中动态回归通过；该轮唯一失败为进度条测试把 UIKit `Float` 值强制与整数精确比较。按实际 slider 值修正测试后，播放器及最新搜索/网页专项在 `DeliveryIOS26-PlayerSearch.xcresult` 中 **19/19** 通过。
- Release iphoneos 无签名构建通过，独立安装包为 `BilibiliFocus-1.0.2-build4-unsigned.ipa`；包内版本、arm64 架构、ZIP 完整性和无测试 bundle 已核对。播放器交互及真机验证边界见 [播放器与性能记录](PERFORMANCE_FOLLOWUP.md)。

## 2026-10-17 后续验证与 1.0.2（build 3）

本节为本次新增工作；下方旧专项记录保留历史失败与成功证据，不重复计入本次成果。基线目录 `$N`：`../scroll-layout-validation-20261017-153718`。开始时保存 97 个相关源码/测试/配置/文档快照和哈希、工作区与暂存区 diff、分支/HEAD，以及 Android/KMP 文件哈希。未发现同仓库活动写入任务。原开发目录、分支、HEAD、暂存区均保留，没有提交、推送、发布、清空原有模拟器或读取真实会话数据。

### 本次用失败测试确认的问题

1. **未展开长文本的二次行高。**原 `FocusExpandableDynamicText` 的 GeometryReader → preference → `@State` 路径，在首次尺寸提案中没有折叠按钮，下一轮才插入。生产卡片的首次高度为 220 pt、挂载后为 240 pt；连续创建三次新行均复现，见 `HypothesisBaseline.xcresult`。这不是修改误差阈值后得出的结论。
2. **没有实际位移仍执行补偿。**正常返回后，尾部分页及重复几何通知使同一卡片保持原位，但执行了 8 次局部补偿。新增测试要求这类路径为 0 次，基线失败。
3. **与框架坐标重算竞争。**受控测试先发 offset 变化、再在同一渲染周期发内容坐标等量变化，实际阅读位置本应不变；旧实现插入了 2 次反向 offset 校正，见 `RebaseBaseline.xcresult`。这证明该通知时序下存在竞争，不代表已经捕获用户真机上的唯一根因。
4. **iOS 26 中窗口归属不等于有效布局。**额外创建隔离的 iOS 26.3.1 / iPhone 17 Pro 模拟器后，发现离屏行的 UIView 仍有 window，但父级宿主 `isHidden=true`，SwiftUI owner 和 preference 均已消失。旧恢复仍把该表面当有效目标。先修正独立测试探针以排除隐藏祖先，生产恢复未改时，真正返回场景继续失败、目标缺失且没有请求物化；`IOS26LifecycleProbe.xcresult` 和 `IOS26ActiveIdentityBaseline.xcresult` 保存证据。另有迟到几何回调会重新登记已消失 owner 的独立失败测试。

### 实现范围

`FocusDynamicFeature.swift` 仅将**动态文本组件**改为 UIKit 支持的同步尺寸计算，卡片、LazyVStack、导航与已有详情覆盖层不重写。正文和六行限制、折叠判断、按钮高度在同一个有效宽度提案中决定。测量与显示采用相同 UIFont/UILabel 配置；文本、字体/Dynamic Type、粗体偏好、展开状态、显示倍率、文字方向变化时使缓存失效，宽度精确参与实例内缓存，最多四项，不缓存全部列表行高。支持 RTL、Unicode、短文本隐藏按钮及辅助功能点击；保留正文打开详情、按钮仅切换展开的区别与减少动态效果偏好。修复后同一失败案例为 **240 → 240 pt**，不需要几何回调写状态再加按钮。

局部补偿先看当前真实锚点误差。没有位移时只观察，不进入补偿；需要处理时合并到一次显示刷新机会，在框架布局完成后再次检查真实误差。若内容坐标和 offset 同步移动而屏幕位置不变，就不额外校正。被详情覆盖的异常返回只由原 returnFrame 流程负责，KVO 不再并行启动第二个写入者。取消、generation、用户拖动优先和原晚到高度能力保留；没有增加 8 秒窗口、24 次校正或 3 次物化预算，也没有加固定 sleep。

有效生产锚点同时要求：真实 onAppear owner 仍注册、当前 live surface/布局版本有效、相同窗口与滚动祖先、到 ScrollView 之间没有隐藏/全透明祖先。检查不越过 ScrollView，因此独立详情覆盖不使底层活跃行失效。已消失 owner 的迟到 geometry 不能重新激活行；onAppear 会使用 marker 保留的最新几何重新注册。没有使用私有类名判断、私有 API、逆向依赖或强行销毁 SwiftUI 缓存视图。

### 测试与证据边界

新增 8 项测试均在现有 Xcode 测试 target 中，包含首轮/重建尺寸、宽度/字体/内容/展开缓存失效、短文本按钮和辅助功能、RTL/复杂 Unicode/大字号、真实宿主未展开多图的物化返回、无位移通知、框架重算竞争与迟到 owner。保留原有首帧、评论图片、续播、KMP Router、全屏、分页、目标删除、手势与快速导航回归。

一次 iOS 18 完整复验暴露旧 eager-stack 测试把尚未更新的全局 SwiftUI preference 当离开前坐标（950 pt 的旧偏移，导致 44 pt 高度变化读成 -906 pt）。只将该基线采样改为独立的真实 UIKit 测试表面；未把测量结果注入生产算法，原数值阈值与行为断言不变。iOS 26 的独立探针同样检查隐藏祖先，防止窗口中缓存的离屏 UIView 被误计为“目标存在”。两种修正均不先等待返回稳定再采样。

首次 iOS 26 完整尝试为 114/123，未视为通过；修正活跃布局归属后为 124/124，随后再跑最终完整与专项。最后验收、采样汇总、打包校验以下方“本次最终结果”小节和 `$N` 中原始日志为准。所有测试使用合成 Cookie、非持久 WebKit store、既有网络隔离和 `FOCUS_ONLINE_SMOKE=0`；临时模拟器只清理本任务新建的确切 UUID。

本次生产改动：`App/BilibiliFocus/Features/Dynamic/FocusDynamicFeature.swift`；新增与增强回归：`Tests/BilibiliFocusTests/PerformanceDynamicTests.swift`、`FocusDynamicScrollRestorationTests.swift`、`FocusDynamicReturnHostTests.swift`；仅 app Debug/Release 的版本配置在 `BilibiliFocus.xcodeproj/project.pbxproj` 从 1.0.1（2）变为 **1.0.2（3）**，便于区分旧包。没有修改其他功能业务逻辑或 Android/KMP 源码。

仍须真机确认：真实网络图片晚到、长时间深列表滚动、全屏旋转/侧滑/惯性、后台恢复、系统键盘/弹窗、VoiceOver 与实际字体外观；采样结果不是物理设备帧率、用户 P50/P95 或“绝不漂移”的保证。异常目标删除、不可达及超时仍按既有明确规则降级，不算定位成功。

## 02:43 旧专项记录（历史证据）

日期：2026-10-17。范围仅限 iOS 动态宿主、详情往返、锚点恢复、诊断与相关测试。

## 工作区与证据基线

项目：`/Users/michaeltan/Desktop/Programming/Bilibili-FOCUS/bilibili-FOCUS-iOS`。

分支：`codex/ios-kmp-integration`。开始时 HEAD：`b5e72d07c1db82c70be8e90a72f8f2472c73a668`。

本轮证据目录（下文 `$E`）：`../scroll-return-fix-20261017-014646`，即仓库旁的独立目录。修改前保存了 143 个相关文件的 `files/` 快照、`manifest.json`、`protected.json`（Android/KMP 源码哈希）、`status.txt`、`worktree.diff`、`index.diff`、`head.txt`、`branch.txt` 和关联进程检查。开始时没有发现同仓库正在运行的写入/构建任务。

本轮增量按这份工作区快照比较，不把此前首帧、评论图片、KMP Router、动态缓存与后台更新、展开状态、图片调度等未提交改动算作本轮新增。旧的 `build/ScrollDriftResearch-20261017-zay/` 只读用于理解调查结果，没有把其源码或 EXPERIMENT-ONLY.diff 覆盖进生产仓库。

没有 reset、clean、切分支、提交、推送、发布、清空模拟器或修改 Android/KMP 业务源码。测试全部使用合成数据、非持久 WebKit store、fixture-only 已加载详情和现有网络隔离。未读取真实 Cookie、令牌、用户历史或执行真实账号写操作。现有 `DynamicFeedSnapshotStore.shared` 在 fixture 模式中使用 nil 文件路径，不访问真实磁盘动态缓存。

## 已确认的根因与失败证据

### 1. 保留 View 不等于隔离布局

原结构在同一个 NavigationStack 内让 `persistentDynamicFeedLayer` 和详情 ZStack 参与同一父布局。opacity 保留了 SwiftUI 身份，却没有隔离详情内容、播放器/底栏与父内容区域的尺寸提案。详情变化以及实际宽度、安全区变化会触发 LazyVStack 的行高估算和物化更新。

本轮没有把“每一次普通视频返回都会改变 viewport”作为已证明事实：新增基线中普通往返的主要失败是无条件重新恢复；宽度/安全区路径则确实出现了目标卡片缺失。普通返回是否稳定必须同时看宿主和卡片，而不是单凭 View 还在内存。

### 2. 普通返回无条件启动完整恢复

原 Coordinator 每次 inactive → active 都清除 applied restoration revision 并调用 startRestoration。即使同一 ScrollView、viewport 和卡片位置完全未变，也进入完整恢复流程。

`HostBaselineMeasured.xcresult` 中四次普通往返分别出现 full-restoration 次数 1→2、2→3、3→4、4→5，新增的“普通返回不启动完整恢复”断言失败。

### 3. 旧 offset、缓存 CGRect 与实际卡片不是同一个事实

LazyVStack 重新估算内容后，旧 offset 仍可能合法，但原卡片已经不在当前物化区域。旧 SwiftUI 几何记录也不能证明该卡片在当前 UIKit 布局中仍存在。只判断 placement.reachedTarget，或者超时根据 hasReachedTarget 宣告成功，会混淆数字合法与阅读位置正确。

同一基线的布局变化测试在约 805 ms 的 49 个可见采样中全部找不到目标卡片；该轨迹的误差应为“不可测/目标缺失”，不能用 0 或上一次 frame 填补。证据：`HostBaselineMeasured-continuity.json` 及对应 xcresult 的 JSON 附件。

### 4. 非用户 offset 变化与返回输入竞争

原 contentOffset KVO 主要处理用户滚动，没有在有界恢复期内处理仅由框架引起的 offset 变化。另一个扩展测试发现：路由已经提交返回，但 SwiftUI 尚未向桥接层交付 isActive 时，真实用户输入会被旧 inactive 标记忽略，随后旧 offset 又覆盖用户位置。

现在分别处理非用户局部补偿与真实输入交接；自发 setContentOffset 不递归触发自身校正。

### 5. 最终位置正确仍可能先露出错误列表

原返回先删除详情层，再让动态恢复。研究候选 C 已经表明最终找回 ID 不足以保证早期连续性。本轮改为在确有必要时保留实际详情层，完成身份解析和稳定对齐后才提交返回，而不是在错误列表已经可见时补救。

### 6. 多个几何回调可以过早耗尽物化预算

交付前的重复专项暴露了另一个真实竞争：`SimulatorDelivery` 的 115 项完整测试通过，但随后 `ScrollDelivery` 在连续导航场景中失败（37/38），约 812 ms 后走了超时降级，98 个采样均缺少目标。没有把前一次通过当作最后结论。

随后新增受控回归：让渲染端在两个显示刷新事件后才消费 ID 请求，同时提前交付一批几何通知。旧实现会在同一渲染机会前消耗完三个请求，`MaterializationBurstBaseline.xcresult` 稳定失败。现在对物化请求实施基于显示刷新事件的调度约束，使上一请求有机会被真实布局处理后才花费下一次预算。仍是最多三次，没有增加重试次数，也没有添加按毫秒 sleep。`MaterializationRenderFix.xcresult` 中该受控案例和连续导航案例均通过；最后整体复验另见下表。

## 布局与生命周期调整

`FocusBrowserView` 仍使用现有 NavigationStack、路由模型、返回按钮、左缘返回区、底部主入口和播放器全屏。没有引入新的独立 Tab 导航栈或重写导航架构。

动态宿主由 GeometryReader 接收当前导航 viewport 的真实尺寸。详情变为该稳定宿主上的 overlay；播放器底部间距仅影响详情层，不再作为动态宿主的尺寸输入。没有写死设备高度、安全区或方向尺寸。

动态不再以 opacity 反复切换渲染状态，而是保留在实际不透明详情层下面；交互和辅助功能仍按当前路由启停。只有根入口真的离开动态时才沿用既有根页面销毁规则。详情层移除不会改变底层动态的尺寸提案。

借鉴的是 PiliPala 的页面保活、Controller 持有滚动对象和独立详情路由原则：普通导航不应依赖重新滚动定位。核对的参考入口为 `lib/pages/dynamics/view.dart` 的 AutomaticKeepAliveClientMixin / controller.scrollController 和 `lib/pages/main/view.dart` 的 PageView。参考：

- https://github.com/guozhigq/pilipala/blob/main/lib/pages/dynamics/view.dart
- https://github.com/guozhigq/pilipala/blob/main/lib/pages/main/view.dart

没有移植 Flutter 实现或复制参考仓库代码。BiliBiliMApp 不作为独立导航/恢复框架使用，也没有引入官方客户端私有对象、逆向依赖或私有 API。

## 普通返回：保留，而不是重新定位

打开详情前由路由同步冻结当前阅读身份与 viewport，早于详情改变 SwiftUI 树。延迟到来的 inactive 回调不能覆盖这份快照；同一渲染事务中的快速打开/返回也不能遗留旧冻结状态。

返回前检查同一 ScrollView 的有效 viewport，以及当前真实卡片相对 viewport 的位置。已经一致时同步完成返回，不调用 scrollTo，不启动完整恢复，也不为了普通返回再次 setContentOffset。

一个例外发生在离开页面时：确有用户滚动减速的情况下，只在当前位置停止剩余惯性，防止详情下面继续滑动。这不是返回时的重新定位。

动态 `.loaded` 内容继续保留。既有 loadIfNeeded 只在 idle 时加载，普通返回不拉取新的第一页、不改变 dataRevision、筛选或文本/图片展开状态。隐藏状态仍停止无意义的分页和预取。

返回后可以保留有界的、事件驱动的布局观察；没有实际误差就不移动列表。真实手势立即取消冲突工作，包括发生在路由提交与 SwiftUI active 回调之间的输入。

## 异常布局：身份解析、精确对齐、再显示

### 当前几何的权威来源

`FocusDynamicFeedVisualAnchor` 由 feed model 持有，快照包含稳定卡片 ID、相对 viewport 顶部距离、数据版本和几何版本。当前可见筛选的 ID 集合用于验证目标是否仍属于当前数据；已有展开状态仍由原模型按稳定 ID 管理。

新增轻量 UIKit live anchor surface，使用当前挂载表面的 `convert(bounds, to: scrollView)`，并检查相同窗口、真实祖先关系、非零尺寸和当前几何版本。只弱引用当前挂载行，不保留全部卡片视图。新旧同 ID 行通过实例序号区分，旧实例的迟到清理/布局不能覆盖替换行。

原 SwiftUI GeometryReader marker 保留为布局变化通知来源，但其旧 CGRect 不再作为生产恢复成功的证据。纯 UIKit 局部测试仍可注入受控 frame，完整宿主测试另用独立的 UIKit 探针测量，不向恢复算法供应测试答案。

### 有界恢复流程

1. 只有实质位置/viewport 变化才启动异常恢复。
2. 确认目标仍属于当前筛选与数据版本。
3. 已物化时读取当前真实 frame，按原相对位置对齐。
4. 尚未物化时通过现有 ScrollViewReader 按稳定 ID 发出请求，等待当前布局的真实 surface，再精确对齐。
5. 相邻两次显示刷新机会中的 viewport、contentSize、目标 frame、offset 和几何版本一致，且位置误差不超过 1 pt，才结束门控并提交动态返回。

资源上限：每轮 ID 物化请求最多 3 次，异常门控内两次请求间必须经过显示刷新/布局处理机会，几何回调突发不能提前耗尽额度；实际 offset 校正最多 24 次；原有晚到布局补偿窗口仍为 8 秒，不增加重试预算；阻止详情退出的等待上限为 0.8 秒。0.8 秒仅是超时上限，不是固定显示延迟，普通返回不等待它。CADisplayLink 与独立截止任务均有取消与清理路径。

目标删除、筛选/刷新换代、不可达的合法边界、超时、用户手势、重复返回和新导航均有有限终止路径。不可达目标落到当前合法位置并报告 clamped；超时或用户主动强制返回不会露出列表后又重启旧恢复。新导航先撤销旧完成回调的 UUID，再取消旧工作；仍可保留根动态的阅读身份供之后真正返回。

筛选、刷新和应用新动态在模型修改时同步撤销恢复作用域，不等待稍后的 SwiftUI onChange。不会让旧任务在新列表上继续滚动。

### 为什么没有先露出错误位置再找回

异常恢复期间，实际详情路由和详情层仍在。门控通过后，才执行原有 pop/清理/激活操作；底部“动态”入口回到已有动态根时也复用同一门控。

没有引入截图长期遮挡、额外黑白屏、永久 loading 或固定 300/500 ms 延时。超时、目标不存在或用户强制返回允许有限降级，并明确不算锚点恢复成功。双击返回不会把用户困在转场中。

这证明的是受控场景下的呈现顺序与连续性，不是对未来所有异步图片、系统动画或真机调度的绝对保证。

## 本地诊断

继续使用 `BiliPerformanceStore` 的有界内存缓冲和既有 Debug「设置 → 高级 → 登录与网络诊断」。不新增上传。

新增/区分的阶段包括：`scrollReturn`、`normalReturnPreserved`、`layoutChanged`、`anchorMaterializationRequested`、`anchorResolved`、`anchorMissing`、`preciseAlignment`、`restorationFallback`、`restorationCancelledByGesture`、`restorationScopeChanged`、`restorationClamped`、`visiblePositionError`。

关联 ID 随机生成；记录阶段、结果、耗时、计数、几何版本计数和位置误差，不记录动态 ID、账号 ID、Cookie、查询参数或正文。`visiblePositionError` 在返回后的有界显示刷新采样中记录最大位置误差与缺失采样数；缺失不填成 0。完整恢复的 success 必须有当前实际目标卡片且对齐，旧数字 offset 合法不再构成 success。

现有 Debug 导出摘要仍为用户主动操作。诊断是本地工程观测，不等价于真机耗时分布、每个像素的光学呈现测量或线上 P50/P95。

## 回归测试与证据

新增 `FocusDynamicReturnHostTests` 共 13 项，直接使用 FocusBrowserView、FocusAppViewModel、默认安全区和导航栏、实际 LazyVStack 与生产卡片。视频和富文本多图详情通过 DEBUG 且 fixture-only 的入口呈现真实 loaded 布局，不用真实 API/CDN，也不把错误页面当作已加载详情的替身。

测试覆盖普通深位置往返、展开图文与分页、顶部/底部安全区、宽度变化、Dynamic Type、实际 fullScreenCover 展示和消失、缺失行有界物化、目标删除、筛选换代、物化不合作超时、恢复期间新导航、立即拖动、重复返回、连续四次变化中返回，六次无渲染间隔的打开/返回，以及几何通知突发与延后物化消费之间的竞争。

原 `FocusDynamicScrollRestorationTests` 增加 3 项：非用户 offset 单独变化、目标不可达的 clamped 终止、受控减速状态下进入详情。其余旧测试未删除、跳过或放宽断言，包括晚到高度补偿、真实卡片展开、首帧、评论图片、续播和 KMP Router。

### 测量方法

完整宿主中的测试卡片探针独立于恢复 surface。可见采样从真实详情覆盖分支离开 UIKit 层级之后的首个显示刷新事件开始，不仅检查路由布尔值，也不先等卡片对齐才开始计时。多数轨迹逐显示刷新机会采样约 1.6 秒；连续快速返回轨迹在约 0.2 秒后立即发起下一轮，专门制造恢复竞争。最终和整个可见区间均要求目标存在、误差不超过 2 pt。

每条轨迹同时导出 `return-metrics-*`：从实际返回请求发出到首次可见、到首次已对齐可见采样的耗时，原目标缺失数、最大误差、完整恢复次数、额外 offset 校正次数、物化请求数和结束状态。因此不仅有返回后的相对采样时间，还保留了转场请求到结果的完整测量边界。

初始测试准备允许等待第一屏实际完成布局，再模拟用户滚动；返回路径没有对应的“先等待稳定再计时”。新增测试不靠固定 sleep 掩盖返回问题。初始 harness 的过早 ScrollViewReader 请求以及长卡片选择问题已修正，开发期失败日志全部保留。

### 对照结果

| 阶段 | 结果 | 证据 |
| --- | --- | --- |
| 只增加观察/完整宿主测试的基线 | 2/2 失败：普通返回完整恢复递增；布局变化有目标缺失 | `$E/HostBaselineMeasured.xcresult` |
| 先做布局隔离与普通返回保留 | 24/25 通过，异常目标缺失仍失败 | `$E/HostLayoutIsolation.xcresult` |
| 增加当前身份几何与显示门控 | 25/25 通过，随后继续扩充边界测试 | `$E/HostIdentityGate.xcresult` |
| 扩展可见连续性回归 | 36/36 通过 | `$E/HostVisibleContinuity.xcresult` |
| 最终完整回归 | 116/116 通过，0 失败、0 跳过 | `$E/FinalFull.xcresult` |
| 最终滚动专项复验 | 39/39 通过，0 失败、0 跳过 | `$E/FinalScroll.xcresult` |
| 调度/连续导航竞争再次独立重放 | 2/2 通过 | `$E/FinalRaceReplay.xcresult` |

最终完整验证导出 18 条成功返回轨迹、1424 个可见采样；目标缺失为 0，最大位置误差小于 2 pt（数值差在浮点误差量级）。最终专项再得到 18 条轨迹、1421 个采样，独立竞争重放得到 2 条轨迹、196 个采样，均未出现目标缺失或超出 2 pt 的误差。证据分别为 `FinalFull-continuity.json`、`FinalScroll-continuity.json`、`FinalRaceReplay-continuity.json`。

普通往返的四条完整回归记录均为：完整恢复 0、ID 物化请求 0、额外 offset 校正 0。请求到首次可见/首次已对齐可见的原始耗时保存在对应 `return-metrics-*` 附件。这些是当前合成场景的实际采样，不是 1424 次独立导航，不是物理设备“零像素误差”，也不用于推算真机 P50/P95。

### 最终验证命令

使用自动发现的现有 iPhone 16 Pro、iOS Simulator 18.6、arm64，UUID `7AC09A76-6490-46E1-A1EB-291698558EB8`。现有 Java/Gradle 配置、缓存与 Build FocusKMP 阶段保持启用，没有绕过 Kotlin framework。

```sh
export FOCUS_INCLUDE_TESTS=1 FOCUS_ONLINE_SMOKE=0
E=../scroll-return-fix-20261017-014646
swift test --disable-sandbox --scratch-path "$E/swift-build"
swift test -c release --disable-sandbox --scratch-path "$E/swift-build"
swift run --scratch-path "$E/swift-build" FocusVerifier
./Scripts/sync_focus_runtime.sh --check
node Scripts/sync_bilibili_api_contracts.mjs --check
node Scripts/run_online_smoke.mjs

auto_device=7AC09A76-6490-46E1-A1EB-291698558EB8 # 本轮由 simctl 自动查询得到
xcodebuild test -project BilibiliFocus.xcodeproj -scheme BilibiliFocus \
  -destination "platform=iOS Simulator,id=$auto_device,arch=arm64" \
  -derivedDataPath "$E/DerivedData" -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

# 专项另加以下三个 -only-testing 参数：
# -only-testing:BilibiliFocusTests/FocusDynamicReturnHostTests
# -only-testing:BilibiliFocusTests/FocusDynamicScrollRestorationTests
# -only-testing:BilibiliFocusTests/PerformanceDynamicTests

xcodebuild build -project BilibiliFocus.xcodeproj -scheme BilibiliFocus \
  -configuration Debug -destination "platform=iOS Simulator,id=$auto_device,arch=arm64" \
  -derivedDataPath "$E/DerivedData" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
xcodebuild build -project BilibiliFocus.xcodeproj -scheme BilibiliFocus \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$E/DeviceRelease" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

git diff --check
```

Scheme 明确设置 `FOCUS_FIXTURE_TESTS=1`、`FOCUS_ONLINE_SMOKE=0`。完整可复现 argv、退出码、日志和每次测试时的源码哈希在 `$E/*-command.json`、`verified-checks.json`、`*.log`、`*-source.json` 中，不只依赖 Xcode 的一行成功标志。

最终一轮在最后一次相关 Swift 源码/测试修改后重新执行：

| 验证 | 最终结果 | 日志/结果 |
| --- | --- | --- |
| Swift Core Debug | 131 tests / 22 suites，通过 | `$E/CoreDebugFinalVerified.log` |
| Swift Core Release | 131 tests / 22 suites，通过 | `$E/CoreReleaseFinalVerified.log` |
| iOS Simulator 完整测试 | 116/116，通过 | `$E/FinalFull.xcresult` |
| 滚动相关专项 | 39/39，通过 | `$E/FinalScroll.xcresult` |
| 几何突发/连续导航重放 | 2/2，通过 | `$E/FinalRaceReplay.xcresult` |
| Simulator Debug 应用 build | 通过 | `$E/SimulatorDebugBuildVerified.log` |
| unsigned iOS Release build | 通过 | `$E/ReleaseVerified.log` |
| FocusVerifier | 8 组检查通过 | `$E/VerifierFinalVerified.log` |
| Runtime / API mirror | 通过，48 个端点同步 | `$E/RuntimeMirrorFinalVerified.log`、`$E/APIContractsFinalVerified.log` |
| 在线 smoke 默认关闭 | 明确 SKIP，没有真实账号请求 | `$E/OnlineOptOutFinalVerified.log` |
| git diff --check | 通过，最终文档更新后再次执行 | `$E/final-diff-check.log` |

全量与专项不是不同的 155 个测试；专项是全量中的子集，额外重放也是相同案例的再次执行。本轮共新增 16 项测试（13 个完整宿主测试、3 个 UIKit 边界测试）。最终没有未回收的构建/测试任务或剩余自动化失败。

已核对外部基线的 143 个原文件：快照无损、原文件未丢失；原有测试函数未删除；Android/KMP 受保护源码哈希未变；分支、HEAD 和暂存区未变。最终测试后没有继续修改 Swift 源码。增量与审查记录在 `$E/implementation-incremental.diff`、`$E/final-review.json`、`$E/verified-source.json`。

## 本轮涉及文件

| 文件 | 本轮增量 |
| --- | --- |
| `App/BilibiliFocus/FocusBrowserView.swift` | 稳定尺寸提案、详情 overlay、保留真实动态层；完整宿主/实际覆盖层观察接缝 |
| `App/BilibiliFocus/Features/Dynamic/FocusDynamicFeature.swift` | 生命周期稳定的锚点、弱引用当前 UIKit surface、按 ID 物化、有界门控/补偿/取消与诊断 |
| `App/BilibiliFocus/Features/Shared/FocusAppViewModel.swift` | 同步冻结、返回门控、重复返回、新导航和账号重置的完成回调隔离 |
| `App/BilibiliFocus/FocusNativeVideo.swift` | 仅 DEBUG、fixture-only 的真实已加载视频详情测试接缝 |
| `App/BilibiliFocus/Features/My/FocusMyFeature.swift` | 仅在其中的 Opus ViewModel 增加 DEBUG 图文 loaded fixture 接缝；未改“我的”业务行为 |
| `Sources/FocusCore/BiliDiagnostics.swift` | 封闭枚举的滚动阶段与明确终止类别 |
| `Tests/BilibiliFocusTests/FocusDynamicReturnHostTests.swift` | 13 项完整宿主测试与独立逐帧采样/返回耗时附件 |
| `Tests/BilibiliFocusTests/FocusDynamicScrollRestorationTests.swift` | 保留原测试，新增 3 项受控 UIKit 边界验证 |
| `BilibiliFocus.xcodeproj/project.pbxproj` | 新测试真实加入 file reference、group 与 test Sources phase |
| `BilibiliFocus.xcodeproj/xcshareddata/xcschemes/BilibiliFocus.xcscheme` | 明确关闭在线 smoke |
| 本文档 | 根因、实现、证据、命令与未验证边界 |

## 真机待验证与剩余风险

自动化已验证所列 fixture 的当前宿主/路由/卡片坐标与连续性。没有真实设备证据，不能声称所有用户的可见漂移已彻底消失，也没有返回性能提升百分比或线上 P50/P95。

| 真机场景 | 验收要求 |
| --- | --- |
| 长文本、多图、不同展开状态、深位置与分页边界 | 相同卡片从首次重新可见起处于正确位置；布局稳定后误差约 1–2 pt，无先错后对 |
| 普通快速打开/返回、连续返回、左缘返回与底部入口 | 同一滚动对象，正常路径零恢复校正，手势不被旧任务夺回 |
| 真实惯性减速、返回立即拖动 | 离开时停止剩余惯性；用户输入立即接管，不能被补偿拉回 |
| 横竖屏、真实全屏旋转、iPad/其他 iPhone、安全区和键盘/系统弹窗 | 实际 viewport 改变后有限对齐；详情和底栏安全区正常，不遮挡内容 |
| 真机 Dynamic Type、图片真实解码/网络晚到、系统字体/布局动画 | 当前 frame 与几何版本正确；不能只看返回 1 秒后的最终位置 |
| 后台/前台、系统暂停或丢帧、低内存 | 截止与取消能结束，目标消失/超时有明确降级，不无限等待 |
| 真实会话退出、切号与动态更新同时发生 | 旧阅读身份/恢复回调无权操作新账号数据 |
| 流畅度与能耗 | 核对返回时主线程耗时、帧率、实际等待与隐藏层绘制成本；当前仅证明普通路径减少无意义恢复，不等价于真机 FPS 结论 |

模拟器覆盖了 fullScreenCover 展示/退出、受控宽度重排和字体变化，不等价于真实设备传感器旋转、系统交互动画、网络图片解码时序、所有键盘/弹窗组合。物化超时、目标消失、不可达和用户强制返回的降级路径会放弃原阅读点，但必须有限结束且不能误报成功；这是公开的边界，不是被隐藏的“无漂移保证”。

该次 02:43 专项没有发布版本或覆盖 `Build/BilibiliFocus-unsigned.ipa`，当时的 IPA 仍是较早产物；其 unsigned Release `.app` 位于 `$E/DeviceRelease/Build/Products/Release-iphoneos/`。本次后续任务另行生成 1.0.2（3）的新版 IPA，结果见下节。

## 本次最终结果：1.0.2（3）

以下均在最后一次相关 Swift 源码/测试修改之后执行；之后只更新本文档。`$N` 为本次外部基线目录，不是上方旧专项的 `$E`。当前没有剩余构建或自动化测试阻塞。真机网络和体验仍按前述矩阵待验收。

| 验证 | 实际结果 | 本次证据 |
| --- | --- | --- |
| Swift Core Debug | 131 tests / 22 suites 通过 | `$N/FinalCoreDebug.log` |
| Swift Core Release | 131 tests / 22 suites 通过 | `$N/FinalCoreRelease.log` |
| iPhone 16 Pro / iOS 18.6 完整回归 | 124/124，0 失败、0 跳过 | `$N/FinalIOS18.xcresult` |
| iPhone 17 Pro / iOS 26.3.1 完整回归 | 124/124，0 失败、0 跳过 | `$N/FinalIOS26.xcresult` |
| iOS 26.3.1 滚动专项再次复验 | 47/47，0 失败、0 跳过 | `$N/RepeatScrollIOS26.xcresult` |
| Simulator Debug 应用 build | 通过 | `$N/SimulatorDebugBuild.log` |
| unsigned iOS Release build + IPA | 通过，现有 KMP framework 构建正常参与 | `$N/UnsignedIPA.log` |
| FocusVerifier | 8 组通过 | `$N/FinalVerifier.log` |
| Runtime / API mirror | 同步，48 端点 | `$N/FinalRuntimeMirror.log`、`FinalAPIContracts.log` |
| 线上测试默认 opt-out | 明确 SKIP，未访问真实账号 | `$N/FinalOnlineOptOut.log` |
| `git diff --check` | 通过，文档更新后再检查 | `$N/FinalDiffCheck.log`、`DeliveryDiffCheck.log` |

首次可见连续性：iOS 18.6 完整运行导出 21 条轨迹、1713 个采样；iOS 26.3.1 为 21 条、1708 个采样；iOS 26 专项复验为 21 条、1709 个采样。三次均没有目标缺失，最大误差小于 2 pt。各次普通往返四条记录均为完整恢复 0、物化请求 0、额外 offset 校正 0。它们是逐帧的合成测试采样，不是数千次独立导航，也不是真机“零漂移”保证。原始轨迹与请求到首次可见耗时在各次 `*-continuity.json` 及 `*-attachments/` 中。

原用户模拟器 UUID `7AC09A76-6490-46E1-A1EB-291698558EB8` 保持原数据，没有 erase/delete。只清理本任务新建的两个 iOS 26 测试模拟器，删除均返回成功；最终清理前该测试设备已由测试流程关闭，额外 shutdown 返回 149，随后精确 UUID delete 返回 0，详见 `$N/simulator-cleanup.json`、`final-simulator-cleanup.json`。

### 实际命令

```sh
export FOCUS_FIXTURE_TESTS=1 FOCUS_ONLINE_SMOKE=0 FOCUS_INCLUDE_TESTS=1
N='../scroll-layout-validation-20261017-153718'
swift test --disable-sandbox --scratch-path "$N/swift-build"
swift test -c release --disable-sandbox --scratch-path "$N/swift-build"
swift run --scratch-path "$N/swift-build" FocusVerifier
./Scripts/sync_focus_runtime.sh --check
node Scripts/sync_bilibili_api_contracts.mjs --check
node Scripts/run_online_smoke.mjs

# validate.py 自动查询可用设备；本次完整参数也保存在各次 *-summary.json。
FOCUS_TEST_SIMULATOR_ID=7AC09A76-6490-46E1-A1EB-291698558EB8 \
  python3 "$N/validate.py" FinalIOS18
# 本次新建后使用、现已删除的独立 iOS 26 设备：806A2E96-A310-4241-A255-1A5D77844356。
# 此 UUID 只用于记录证据，不应在后续复制执行时假定仍存在。

xcodebuild -quiet build -project BilibiliFocus.xcodeproj -scheme BilibiliFocus \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=7AC09A76-6490-46E1-A1EB-291698558EB8,arch=arm64' \
  -derivedDataPath "$N/DerivedData" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
bash Scripts/build_unsigned_ipa.sh
git diff --check
```

iOS 26 的完整测试和专项同样经 validate.py 调用 `xcodebuild test`，使用同一 project/scheme、fixture 环境、`-parallel-testing-enabled NO` 和独立 resultBundlePath；全部原样参数位于 `FinalIOS26-summary.json` 与 `RepeatScrollIOS26-summary.json`。IPA 脚本执行的是 Release / `generic/platform=iOS` / `-sdk iphoneos` 无签名构建，没有删除或绕过 KMP。

### 新版产物与一致性

开发目录标准路径已更新为 `Build/BilibiliFocus-unsigned.ipa`；另保留明确版本名 `Build/BilibiliFocus-1.0.2-build3-unsigned.ipa`。覆盖前的旧包已备份到 `$N/previous-BilibiliFocus-unsigned.ipa`，没有修改原源码历史或 Git 状态。

- App 版本：**1.0.2（3）**；Bundle ID：`com.michaeltan.BilibiliFocus`。
- 大小：**4,983,815 bytes**。
- SHA-256：`45b499dd735f3a19aaa73c3ec0184e997c7704b0738f0289435261267847da77`。
- ZIP 完整性校验通过；包含 `Payload/BilibiliFocus.app/Info.plist` 与主可执行文件；arm64，Mach-O platform 为 iOS 而非 Simulator；不含测试 bundle。
- 打包前后源码及项目版本配置哈希一致，`package-source-manifest.json` 与各次测试源码清单保持对应；导出下载文件的哈希再次核对一致。
- 这是未签名包，未在物理设备签名安装，未发布到 GitHub/App Store。此前的 1.0.1 下载包不包含这些新修复，应使用这一份进行真机验收。

完整工作区审查见 `$N/worktree-review.json`、`incremental.diff` 与交付检查；旧测试未删除，8 项新增测试实际执行，没有无关 Android/KMP 修改或新增敏感/自由文本生产日志。
