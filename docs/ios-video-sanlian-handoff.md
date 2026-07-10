# iOS 播放页三连栏交接说明

这份文档只总结当前项目里 iOS 播放页“三连栏”的实现方式，目标是让新的 Agent 进入仓库后能立刻复用，不再重复走“原生重画图标”这条错路。

## 当前结论

当前正确方向不是用 SwiftUI 重新画点赞、投币、收藏。

当前实现保留了 B 站网页原生三连 DOM，只做两件事：

- 用 CSS 把网页原生三连压缩成一行 3 等分按钮。
- 在三连栏下面插入我们自己的原生增强区，放 `UP 主卡片 + 选集卡片 + 评论卡片`。

也就是说：

- 三连的图标资源、点击逻辑、登录态联动，原则上都来自原网页。
- 我们只改布局，不重写三连业务。

## 关键文件

- [App/BilibiliFocus/FocusBrowserViewModel.swift](/Users/michaeltan/Desktop/Programming/bilibili-FOCUS-iOS/App/BilibiliFocus/FocusBrowserViewModel.swift:1048)
- [App/BilibiliFocus/FocusBrowserViewModel.swift](/Users/michaeltan/Desktop/Programming/bilibili-FOCUS-iOS/App/BilibiliFocus/FocusBrowserViewModel.swift:4508)
- [Sources/FocusCore/FocusRuleCatalog.swift](/Users/michaeltan/Desktop/Programming/bilibili-FOCUS-iOS/Sources/FocusCore/FocusRuleCatalog.swift:3427)
- [Sources/FocusCore/FocusRuleCatalog.swift](/Users/michaeltan/Desktop/Programming/bilibili-FOCUS-iOS/Sources/FocusCore/FocusRuleCatalog.swift:3539)
- [Sources/FocusCore/FocusRuleCatalog.swift](/Users/michaeltan/Desktop/Programming/bilibili-FOCUS-iOS/Sources/FocusCore/FocusRuleCatalog.swift:3712)

## 实现分层

### 1. 页面骨架

iOS 播放页仍然是 `SwiftUI + WKWebView`。

SwiftUI 不直接渲染三连按钮。SwiftUI 负责：

- 顶栏
- 底栏
- WebView 容器
- 原生视频控制栏
- Web 页面下方的原生增强区

网页负责：

- 视频播放器本体
- 三连栏的实际 DOM 与交互

## 三连栏的真实来源

三连栏来源是桌面播放页里的这些节点之一：

- `#arc_toolbar_report`
- `.video-toolbar-container`

这两个选择器在项目里被视为同一层语义的“网页原生工具栏”。

如果后续页面结构变化，优先检查这两个根节点是否还存在。

## 这一轮的核心改动

### 1. 保留网页原生三连，不再自绘

CSS 入口在 [Sources/FocusCore/FocusRuleCatalog.swift](/Users/michaeltan/Desktop/Programming/bilibili-FOCUS-iOS/Sources/FocusCore/FocusRuleCatalog.swift:3427)。

这里做了几件关键事：

- 给 `#arc_toolbar_report` / `.video-toolbar-container` 套上圆角卡片容器。
- 去掉右侧工具区 `video-toolbar-right`。
- 只保留左侧主操作区 `video-toolbar-left-main`。
- 把左侧主操作区压成 `3` 列等宽网格。
- 隐藏分享按钮。
- 隐藏数字文本，只保留图标。

最关键的布局点是：

- `grid-template-columns: repeat(3, minmax(0, 1fr))`
- 每个操作节点都 `width: 100%`
- `button/a` 都被拉成整格可点击区域

对应代码位置：

- 容器卡片样式：[FocusRuleCatalog.swift:3427](/Users/michaeltan/Desktop/Programming/bilibili-FOCUS-iOS/Sources/FocusCore/FocusRuleCatalog.swift:3427)
- 三列网格：[FocusRuleCatalog.swift:3482](/Users/michaeltan/Desktop/Programming/bilibili-FOCUS-iOS/Sources/FocusCore/FocusRuleCatalog.swift:3482)
- 隐藏分享：[FocusRuleCatalog.swift:3524](/Users/michaeltan/Desktop/Programming/bilibili-FOCUS-iOS/Sources/FocusCore/FocusRuleCatalog.swift:3524)
- 三个按钮统一点击区域：[FocusRuleCatalog.swift:3539](/Users/michaeltan/Desktop/Programming/bilibili-FOCUS-iOS/Sources/FocusCore/FocusRuleCatalog.swift:3539)
- 隐藏数字文本：[FocusRuleCatalog.swift:3637](/Users/michaeltan/Desktop/Programming/bilibili-FOCUS-iOS/Sources/FocusCore/FocusRuleCatalog.swift:3637)

### 2. 原生增强区必须挂在三连栏下面

原生增强区不是替换三连栏，而是插在三连栏后面。

挂载逻辑在 [FocusBrowserViewModel.swift](/Users/michaeltan/Desktop/Programming/bilibili-FOCUS-iOS/App/BilibiliFocus/FocusBrowserViewModel.swift:4951)。

优先顺序是：

- 如果能找到 `toolbarAnchor`，就插在三连栏后面。
- 找不到才退化到评论区、选集区、播放器壳、`viewbox` 等位置。

最重要的一句是：

- `toolbarAnchor.parentNode.insertBefore(root, toolbarAnchor.nextSibling);`

这决定了三连栏在上，原生卡片在下。

### 3. 原网页的旧选集和旧评论要隐藏

当前原生增强区会自己渲染选集卡片和评论卡片，所以原网页的旧块要隐藏掉。

隐藏逻辑有两层：

- 页面规则预隐藏，防止闪出旧内容。
- 原生增强脚本成功后再加 `focus-hide-original-video-pod` 做彻底隐藏。

相关位置：

- 预隐藏：[FocusRuleCatalog.swift:3110](/Users/michaeltan/Desktop/Programming/bilibili-FOCUS-iOS/Sources/FocusCore/FocusRuleCatalog.swift:3110)
- 增强后隐藏：[FocusBrowserViewModel.swift:4822](/Users/michaeltan/Desktop/Programming/bilibili-FOCUS-iOS/App/BilibiliFocus/FocusBrowserViewModel.swift:4822)
- class 级别总隐藏：[FocusRuleCatalog.swift:3712](/Users/michaeltan/Desktop/Programming/bilibili-FOCUS-iOS/Sources/FocusCore/FocusRuleCatalog.swift:3712)

注意：

- 不能把 `#arc_toolbar_report`
- 不能把 `.video-toolbar-container`

一起误隐藏，否则三连会直接消失。

## Swift 侧兜底交互桥

虽然策略是“尽量用网页原生交互”，但当前项目里还保留了一个 Swift 到网页的点击桥，作为兜底：

- [FocusBrowserViewModel.swift:1048](/Users/michaeltan/Desktop/Programming/bilibili-FOCUS-iOS/App/BilibiliFocus/FocusBrowserViewModel.swift:1048)

`triggerNativeVideoAction(_:)` 会：

- 根据 `like / coin / favorite`
- 在网页里找对应节点
- 找到后派发一个 `MouseEvent('click')`

这不是三连的主渲染来源，只是点击兜底。

如果以后要继续复用，请记住：

- 它依赖真实网页节点仍在 DOM 里。
- 如果你把三连节点 clone 一份或者自己重画一份，交互就会只剩高亮，不会触发真实业务。

## 当前原生增强区包含什么

当前 `FocusNativeVideoAugmentPayload` 只负责三连下方的内容：

- `UP 主卡片`
- `选集卡片`
- `评论卡片`

数据模型定义在：

- [FocusBrowserViewModel.swift:3902](/Users/michaeltan/Desktop/Programming/bilibili-FOCUS-iOS/App/BilibiliFocus/FocusBrowserViewModel.swift:3902)

JS 注入入口在：

- [FocusBrowserViewModel.swift:4510](/Users/michaeltan/Desktop/Programming/bilibili-FOCUS-iOS/App/BilibiliFocus/FocusBrowserViewModel.swift:4510)

当前版本号字符串是：

- `2026-06-22-toolbar-center-no-follow`

如果 Agent 修改了注入结构，建议同步改这个版本号，避免旧 DOM 被误判为可复用。

## 这轮踩过的坑

### 1. 不要用 SwiftUI 或自定义 HTML 重画三连

之前一旦自己重画，就会出现：

- 图标变形
- 点击只有高亮，没有真实点赞/投币/收藏
- 数字或图标状态不同步

根因是：

- 重画后的节点不是 B 站真正绑定事件的节点。

### 2. 不要把三连栏挂进原生增强区内部

如果把三连作为增强区的一部分去拷贝、搬运、重建，很容易出现：

- 挤成一团
- 事件丢失
- 被 MutationObserver 或页面重渲染打回原状

正确做法是：

- 三连保留在网页原位
- 我们只给它改 CSS
- 原生增强区挂在它后面

### 3. 不要误杀工具栏右边以外的主按钮

目前只应该去掉：

- 分享
- 投诉/更多
- 顶部/小窗/客服之类悬浮干扰按钮

不应该把：

- 点赞
- 投币
- 收藏

所在的主节点一并隐藏。

### 4. 数字隐藏方式必须是“隐藏文本”，不是“移除整个节点”

当前做法是把 `span` 压成不可见，而不是删掉父节点。

原因是很多时候事件、状态 class、图标布局都还挂在父节点结构上。

如果直接删节点，很容易把交互也删没了。

## 接手时的排查顺序

如果三连又坏了，按这个顺序查：

1. 看页面里还有没有 `#arc_toolbar_report` 或 `.video-toolbar-container`。
2. 看它有没有被 `display: none` 或被其他 prune 规则误隐藏。
3. 看 `video-toolbar-left-main` 是否还存在，结构是否还是 3 个主 action。
4. 看数字隐藏规则是否误把图标容器也一起隐藏了。
5. 看增强区是否仍然插在 `toolbarAnchor.nextSibling`。
6. 看是否有人又把三连改回了 SwiftUI 自绘或 clone DOM。

## 建议保留的不变量

- 三连必须继续使用网页原生 DOM。
- 三连只保留 `点赞 / 投币 / 收藏` 三项。
- 分享继续隐藏。
- 数字继续隐藏，只保留图标。
- 原生增强区继续插在三连下方。
- 原网页旧选集、旧评论继续隐藏。

## 和播放器状态逻辑的关系

三连本身不负责播放器状态，但播放页整体稳定性依赖 `refreshPlayerState()`。

相关位置：

- [FocusBrowserViewModel.swift:3075](/Users/michaeltan/Desktop/Programming/bilibili-FOCUS-iOS/App/BilibiliFocus/FocusBrowserViewModel.swift:3075)

这里会更新：

- `hasDetectedPlayer`
- `hasActiveVideoRoute`
- `isPlaying`
- `playbackRate`
- `isFullscreen`
- 标题信息

这部分如果失真，会连带影响底部控制栏和播放页遮罩，但不应该被拿来替代三连交互。

## 一句话复用原则

如果要在本项目里继续复用这轮三连实现，唯一正确心智模型是：

“网页原生三连保留并做 CSS 压缩；原生增强 UI 插在它下面；Swift 只做兜底点击桥，不重画三连业务。”
