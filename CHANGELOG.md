# Changelog

版本号与 GitHub Release tag 一致（不带 `v` 前缀）。iOS 与 Android 的版本号目前不同步：
iOS 工程为 1.0.2（build 6），Android 为 1.0.1（versionCode 2）。

## Unreleased

- 双端个人中心与播放器改进，移除“稍后再看”客户端能力，见 [双端改进记录](docs/records/2026-10-29-client-maturity.md)。
- Android 播放器与 iOS 对齐、平板横屏布局；Android 动态图片请求与滚动预取，见 [性能后续记录](docs/records/2026-10-17-performance-followup.md)。

## 1.0.2（仅本地 iOS 安装包，未发布 Release）

- build 6：进度条触摸与自动画质。
- build 5：动态自动刷新、手机播放布局、高刷新率配置。
- build 4：播放器与起播链路优化，动态返回布局交接修复。
- build 3：动态详情返回的滚动位置与可见连续性修复。

详见 [性能后续记录](docs/records/2026-10-17-performance-followup.md) 与
[滚动返回专项](docs/records/2026-10-17-dynamic-scroll-return-fix.md)。

## [1.0.1](https://github.com/Silhouette-my/bilibili-focus-mobile/releases/tag/1.0.1) - 2026-07-13

- 播放中返回桌面时自动进入系统 PiP；PiP 不可用时继续后台音频。
- iOS 控制中心、锁屏媒体信息与远程控制；Android Media3 前台服务、媒体通知和锁屏控制。
- 补齐来电/Siri、音频焦点、耳机拔出及媒体服务重置处理。
- 修复 iOS `MPMediaItemArtwork` 跨执行队列崩溃、Android 平板 PiP 画面缩放与旋转后状态错乱。

## [1.0.0](https://github.com/Silhouette-my/bilibili-focus-mobile/releases/tag/1.0.0) - 2026-07-13

- 首个预发布版本：iOS 未签名 IPA 与 Android debug APK。
