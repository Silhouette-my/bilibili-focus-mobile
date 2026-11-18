# Changelog

版本号与 GitHub Release tag 一致（不带 `v` 前缀）。当前双端发布版本均为 `1.0.2`（iOS build 6 / Android versionCode 3）。

## [1.0.2](https://github.com/Silhouette-my/bilibili-focus-mobile/releases/tag/1.0.2) - 2026-11-18

- **动态与图文/专栏体验完善**：新增双端转发/引用动态卡片、Opus 图文详情与专栏富文本混排渲染（表情、艾特、链接、图库），支持前台自动检查刷新与深读位置保持，以及详情返回的稳定滚动锚点恢复。
- **个人中心与内容管理**：重构双端个人中心（聚合资料、继续观看与历史/收藏/关注入口），补齐观看历史关键词搜索/单条删除/清空、收藏夹新建/重命名/删除与内容移动/复制/移除，以及 UP 主空间与合集浏览，并移除“稍后再看”客户端能力。
- **播放器与评论升级**：对齐双端画面内播放器控件、全区域可点按拖动进度条、自动/手动清晰度切换与断流有界恢复、分 P 与合集切换、高刷增量弹幕、字幕与弹幕显示设置、倍速记忆、睡眠定时与可选自动下一 P；Android 新增宽屏/平板双列布局；双端支持评论图浏览、长按复制评论与评论发送/回复/点赞/删除。
- **图片与稳定性**：优化双端图片请求与预取（BFS CDN 尺寸桶适配、同在途请求合并、低电量/弱网策略），完善本地续播写入屏障与账号隔离的历史 Outbox 后台调度。
- **仓库整理与构建精简**：统一 Swift 与 KMP 共享资源目录，收敛 iOS `App/BilibiliFocus/Features/` 与 `Resources/` 目录结构，移除冗余同步校验脚本、CI 门禁与重型截图采样测试。

## [1.0.1](https://github.com/Silhouette-my/bilibili-focus-mobile/releases/tag/1.0.1) - 2026-07-13

- 播放中返回桌面时自动进入系统 PiP；PiP 不可用时继续后台音频。
- iOS 控制中心、锁屏媒体信息与远程控制；Android Media3 前台服务、媒体通知和锁屏控制。
- 补齐来电/Siri、音频焦点、耳机拔出及媒体服务重置处理。
- 修复 iOS `MPMediaItemArtwork` 跨执行队列崩溃、Android 平板 PiP 画面缩放与旋转后状态错乱。

## [1.0.0](https://github.com/Silhouette-my/bilibili-focus-mobile/releases/tag/1.0.0) - 2026-07-13

- 首个预发布版本：iOS 未签名 IPA 与 Android debug APK。
