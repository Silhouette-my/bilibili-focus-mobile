# Bilibili Focus

自用的 Bilibili 移动端容器项目，当前仓库包含 iOS 和 Android 两条主线。

当前实现方向：

- `动态`、`搜索`、`视频`、`我的/历史` 优先走原生页面与 API
- iOS 使用 AVPlayer，Android 使用 Media3/ExoPlayer 承载原生视频播放
- WebView 保留给尚未原生化的页面，并负责去干扰、导流拦截和小范围布局修复
- WebView、原生请求和播放器共用登录 Cookie

## 当前能力

- 原生关注动态流
- 原生搜索入口与结果页卡片流
- 原生我的页、播放历史、关注 UP 主列表、收藏夹与合集页
- 原生 UP 主空间、专栏页、图文动态详情与富文本内容
- 原生视频详情、分 P 播放、评论、弹幕与播放历史上报
- 点赞、投币、收藏等登录态视频互动
- 跟随系统/浅色/深色主题、强调色、动态过滤与弹幕开关
- iOS unsigned IPA 与 Android debug APK 本地打包

## 仓库结构

- `App/BilibiliFocus`
  - iOS SwiftUI 应用入口、原生页面、WebView 容器
- `Sources/FocusCore`
  - iOS 侧共享核心：导航策略、页面规则、视频 API 与注入运行时
- `focus-core`
  - Android / Kotlin Multiplatform 共享模型、路由与 API service
- `focus-android`
  - Android 应用、Compose UI、ExoPlayer 播放与原生页面
- `Scripts`
  - iOS unsigned IPA 打包脚本
- `Tests/FocusCoreTests`
  - iOS 规则、路由、配置与 fixture 测试
- `localonly`
  - 本地归档或不参与远端主线的文件

## 本地运行

### iOS

1. 打开 `BilibiliFocus.xcodeproj`
2. 选择 `BilibiliFocus` scheme
3. 在 `Signing & Capabilities` 中设置个人开发 Team
4. 选择真机或模拟器运行

命令行构建：

```bash
xcodebuild -project BilibiliFocus.xcodeproj \
  -scheme BilibiliFocus \
  -destination 'generic/platform=iOS' \
  -derivedDataPath .tmp-derived \
  CODE_SIGNING_ALLOWED=NO build
```

### Android

使用 JDK 21（推荐 Android Studio 自带的 JBR）。当前 Gradle/Kotlin 工具链无法使用 JDK 25 初始化构建。

macOS 使用 Android Studio 内置 JDK 的示例：

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
```

```bash
./gradlew :focus-android:assembleDebug
```

## 打包

### iOS unsigned IPA

```bash
./Scripts/build_unsigned_ipa.sh
```

输出：

```text
Build/BilibiliFocus-unsigned.ipa
```

该 IPA 不包含代码签名，需要通过开发者证书、AltStore、SideStore 或其他侧载工具签名后安装。

### Android debug APK

```bash
./gradlew :focus-android:assembleDebug
```

输出：

```text
focus-android/build/outputs/apk/debug/focus-android-debug.apk
```

debug APK 使用本地 Android debug keystore 签名，可直接安装到允许调试应用的设备。

## 测试

### iOS 核心测试

```bash
FOCUS_INCLUDE_TESTS=1 swift test
```

### Web 注入验证

```bash
swift run FocusVerifier
```

### Android 单元测试

```bash
./gradlew :focus-android:testDebugUnitTest :focus-core:testDebugUnitTest
```

## 说明

- 默认按自用侧载方案设计，不以 App Store / 应用商店审核兼容为目标
- 播放页与部分详情页仍依赖 Bilibili 当前网页结构，网页改动后需要继续维护规则
- `Build/`、`*.ipa`、`*.apk` 与各平台构建目录默认不进入 Git
- `localonly` 下的内容不属于当前远端主线分发物
