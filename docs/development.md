# 开发与构建指南

## 环境要求

- **iOS**：macOS + Xcode 16+（支持 Swift 6 工具链与 iOS 16+ SDK）。
- **Android / KMP**：JDK 17–24（**推荐 JDK 21**，如 Android Studio 内置 JBR；Gradle 8.12 工具链不支持 JDK 25+）。

如果本机未设置 `JAVA_HOME`，`Scripts/build_kmp_for_xcode.sh` 会按顺序自动探测 Android Studio 内置 JBR 与 `/usr/libexec/java_home -v 21`。

## 共享资源说明

Web 注入运行时脚本和 API 端点目录统一保存在 `Sources/FocusCore/Resources/`：

- `Sources/FocusCore/Resources/focus-runtime.js`
- `Sources/FocusCore/Resources/bilibili-api-contracts.json`

`focus-core/build.gradle.kts` 直接引用该目录作为 Android/KMP 资源源路径，修改后无需额外同步脚本，直接重新编译测试即可生效。

## 本地编译与打包

### iOS

1. 打开 `BilibiliFocus.xcodeproj`，选择 `BilibiliFocus` scheme。
2. 在 Target 的 `Signing & Capabilities` 中配置你自己的个人或开发者 Team。
3. 选择真机或模拟器运行（构建阶段会自动调用 `Scripts/build_kmp_for_xcode.sh` 编译并链接静态 `FocusKMP.framework`）。

命令行导出免签测试包（输出至 `build/dist/BilibiliFocus-unsigned.ipa`）：

```bash
./Scripts/build_unsigned_ipa.sh
```

### Android

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
./gradlew :focus-android:assembleDebug
```

生成的 Debug APK 位于 `focus-android/build/outputs/apk/debug/`。

## 单元测试

### Swift 核心模块（`FocusCore`）

```bash
swift test --disable-sandbox
# 可按需过滤单个测试类或用例：
swift test --disable-sandbox --filter FocusNavigationPolicyTests
```

### iOS 应用层测试（`BilibiliFocusTests`）

`BilibiliFocus` scheme 的 TestAction 已配置 `FOCUS_FIXTURE_TESTS=1`，确保测试宿主运行在非持久存储与离线隔离环境：

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
simulator_id="$(xcrun simctl list devices available --json | ruby -rjson -e 'data = JSON.parse(STDIN.read); device = data.fetch("devices").select { |r, _| r.include?("iOS") }.values.flatten.find { |c| c.fetch("isAvailable", true) }; abort("No Simulator") unless device; puts device.fetch("udid")')"

xcodebuild test \
  -project BilibiliFocus.xcodeproj \
  -scheme BilibiliFocus \
  -destination "platform=iOS Simulator,id=${simulator_id}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

### KMP 与 Android 单元测试

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
./gradlew :focus-core:testDebugUnitTest :focus-android:testDebugUnitTest
# 可按需运行单个测试类：
./gradlew :focus-core:testDebugUnitTest --tests 'org.bilibilifocus.core.routing.FocusNavigationPolicyTests'
```

## 清理构建产物

```bash
./Scripts/clean.sh            # 清理 build/、.build/、.tmp-*/、模块 build/ 与 .kotlin/
./Scripts/clean.sh --gradle   # 额外清理项目下的 .gradle/ 缓存
```
