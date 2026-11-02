# 双端主力客户端改进（2026-10-29—30）

## 本次约定

- iOS 与 Android 同步推进，保持操作、默认值和设置语义一致，使用各自原生媒体与 UI 能力。
- 删除“稍后再看”的客户端入口、请求、服务和专属模型；不修改 B 站账号中已有的远端列表。
- 保留当前未提交的播放器、弹幕、搜索、WebView 与性能改进。
- 不提交、推送或发布；真实账号写操作与真机/CDN 验收不由离线测试替代。

## 工作范围与 owner

| 范围 | owner | 完成条件 |
| --- | --- | --- |
| iOS 播放器、字幕弹幕偏好、评论互动 | ios_player | 中断有界恢复、可选下一 P、倍速记忆、可调显示、评论操作及定向测试 |
| Android 对等播放体验 | android_player | 同等用户语义，原生 Media3 生命周期与定向测试 |
| 双端个人中心、历史与收藏管理、删除稍后再看 | personal_center | 紧凑身份区、稳定功能入口、继续观看、按需详情、相关请求与测试清理 |
| 双端图片与预取 | image_performance | CDN 目标尺寸、设备状态策略、共享请求取消正确性 |
| 双端搜索、共享契约、集成和验收 | root | 各类别分页与失败重试、契约同步、双端构建/测试、实际界面检查 |

## 产品取舍

- 自动下一 P 默认关闭，不加入无限推荐连播。
- “自动画质”当前为默认选流；本次优先补自动模式的有界弱网降档，不将其称为平滑 ABR。
- 手动画质、暂停意图、分 P、观看位置和常用倍速在恢复时保留；长按临时速度不写入常用偏好。
- 睡眠定时为当前播放会话状态；尚无可靠源的拖动缩略图不展示假预览。
- 不通过降低高刷弹幕、放大缓存、丢弃返回现场或延长观看进度保存间隔换取性能指标。

## 集成状态

本次核心改进及受影响的自动化验证已完成。Android 实际界面验收按用户选择暂缓。

- 双端活跃代码不再包含稍后再看入口、请求或服务；契约测试保留“该端点组不存在”的断言。
- “我的”使用紧凑资料区、历史/收藏/关注三个常驻入口、继续观看及少量收藏夹条目；不再预取六个收藏夹的内容。
- 收藏夹可创建、重命名、删除，内容可移动、复制、移除。重命名保留原有简介、隐私和封面。
- 历史删除与在途上报串行，只退休删除请求前的匹配待提交 revision；保留本地续播、新观看事件和其他账号状态。单条删除目前限普通视频（archive），清空确认覆盖账号全部历史。
- 历史搜索提交关键词后请求服务端，按 `pn` 分页；不解析未知的 `cursor`，以空页或无新 ID 终止。清空关键词恢复普通历史，旧查询与旧账号响应不能覆盖当前结果。收藏与用户空间的数字秒数统一格式化为时长（600 秒显示 `10:00`）。
- 双端已加入评论发送/回复/本人删除、字幕和弹幕显示偏好、常用倍速、可选下一 P、睡眠定时及有界播放恢复。iOS 使用 AirPlay/系统 PiP；Android 使用系统 PiP，未增加视频 Cast。
- 搜索类别分页与追加失败重试已补齐；综合结果与视频排序缓存互不污染。
- 图片按已知 BFS CDN 支持的目标像素桶请求；签名地址、动图表情与图库原图不改写。iOS 预取响应低数据/低电量/热与内存压力，Android 沿用 Coil 的内存管理。

### 当前验证证据

- Swift Core 全量：146 tests / 22 suites 通过，`build/client-maturity-swift-core.log`。
- Android 首轮全量：Core 测试通过；App 75 项中 1 项取消契约失败，已修复并通过后续相关专项。个人中心现在先发布资料、各区独立加载；取消保持未完成区状态，不当作成功空列表，测试据此检查实际分区契约。新增账号管理与 outbox 测试也已通过，见 `build/client-maturity-android-checks.log`、`build/client-maturity-android-final.log`。
- Android 最终历史/个人中心/取消与 KMP 管理/UserService 专项：**20/20**，0 跳过。Debug APK、Lint 和 Release Kotlin 编译均通过，`build/client-maturity-android-history-final.log`；此前 Media3 显式 opt-in 缺失已修复。APK 为开发构建，未发布。
- iOS 新播放器释放路径曾触发 Swift isolated-deinit 的 back-deploy runtime 崩溃；改回普通存储 player、显式替换通知和同步释放后，全部 16 个崩溃场景消失。第二轮 201 用例中 200 个通过，1 个动态快速返回用例未通过。定位到原生启动仍创建隐藏 WKWebView，同期 GPU 进程启动阻塞超过返回恢复期限；取消无谓实例化后，动态返回/启动/Cookie/浏览器相关 **30/30** 通过，补强登录入口测试 **1/1** 通过。没有修改恢复期限或 2pt 误差契约，也不把专项通过计作该轮全量通过。证据：`build/ClientMaturityIOS-LifecycleFix.xcresult`、`build/DynamicReturnLazyBrowserFix.xcresult`、`build/DynamicLazyBrowserStartupFinal.xcresult`。
- iOS 最终 My/历史搜索专项：**12/12**，`build/ClientMaturityIOS-MyFinal.xcresult`。无签名 iPhone Release 构建通过，`build/client-maturity-ios-release.log`，未生成或发布新 IPA。
- iOS 已导出并检查真实 SwiftUI 的个人中心成功/空态、收藏管理、历史搜索与播放器紧凑布局，见 `build/ClientMaturityIOS-my-final-render/`、`build/ClientMaturityIOS-player-render/`。已复核收藏卡时长从 `600` 修正为 `10:00`。图片为空的是离线 fixture，不请求真实账号内容。
- 两项独立审查问题（历史删除后旧 outbox 重建记录、评论异步账号检查后的迟到 UI 提交）已修复并复核。
- API/runtime 镜像、Kotlin 内嵌 JavaScript 语法与差异空白检查通过。在线 smoke 保持默认跳过。

### 验收边界

- 2026-10-30 用户选择暂不处理 Android 界面验收。ADB 显示未授权，未修改密钥或清空 AVD；不以构建或 Compose 预览代替实际 Android 界面验收。
- 未执行真实账号的评论/收藏/历史写操作；真实 CDN 弱网恢复、真机 PiP/AirPlay、耗电与长时间内存表现仍未验收。
- 本轮不提供平滑 ABR、拖动缩略图、个人内容元数据持久离线缓存；iOS 未增加亮度/音量滑动，Android 全屏保留相应手势。
- API 契约包含 52 个同级仓库校验端点和 3 个独立来源的历史搜索/删除/清空端点；脚本分别报告，不把补充来源当作已通过同级仓库校验。

## 2026-11-01：Android 播放器对齐与平板横屏

用户进一步明确只修播放器，其他页面暂不扩展。开始尝试的全局主题、导航及收藏卡调整已撤回，保留此前个人中心等已有工作。

- 播放器按 iOS 重新排列：顶栏字幕、播放设置与系统画中画；底栏播放、弹幕、倍速、画质和全屏。全屏补标题和锁定入口，定时器归入播放设置。
- 进度条使用当前 Material3 版本支持的官方 thumb/track 插槽，3dp 细轨、10dp 白色圆点、44dp 触控区域。画面横拖与进度条共用拖动位置，仅全屏启用画面横拖定位；保留长按临时三倍速与原速恢复。
- 字幕避开实际上下控制区；紧凑模式长字幕单行省略而不缩小字号。渐变位于字幕下层，不再压暗字幕；弹幕裁切在视频边界内。打开倍速、画质、字幕菜单时暂停控件自动隐藏。
- 平板实际可用窗口宽度至少 960dp、高度至少 400dp 且宽高比至少 1.15 时，视频固定左侧，320–420dp 侧栏独立滚动简介、分 P 和评论。窄窗口保留原单列整体滚动与原视频高度策略。未改全屏旋转、多窗口策略或 Media3 播放服务。

### 本轮验证与交付

- Android 单元测试 **86/86**，0 失败/跳过；包含新增 5 项窗口布局策略测试。Debug APK、Lint、Release Kotlin 编译通过：`build/android-ios-parity/final-validation.log`。
- Pixel 9 Pro 与 Pixel Tablet 模拟器已恢复调试连接。直接运行离线本地视频与生产控制层、生产布局组件，检查了紧凑长字幕、手机全屏、平板双列、平板侧栏滚动与平板全屏。截图等待真实视频首帧，并在完整写入后导出；右侧详情使用离线示例内容，不连接真实账号。
- 图片：`build/android-ios-parity/player-compact-final.png`、`player-fullscreen-final.png`、`tablet-detail-final.png`、`tablet-detail-scrolled.png`、`tablet-fullscreen-final.png`。侧栏滚动前后左侧播放器位置及 00:03 播放位置不变。
- 安装包：`build/PlayerParity-20261101/BilibiliFocus-player-parity-debug.apk`（开发签名，未发布）。手势/菜单逐项触摸、真实账号播放、实体平板多窗口及系统画中画尚未做设备端交互验收。
- 后续已存在的 iOS 未签名包：`build/ClientMaturity-IPA-20261030-1bhX9C/BilibiliFocus-client-maturity-unsigned.ipa`，对应目录 `build.log` 确认 Release 构建成功；本轮仅修改 Android 播放器，没有重新构建 iOS。
