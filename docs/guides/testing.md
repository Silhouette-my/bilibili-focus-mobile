# 测试与同步检查

本地迭代先跑改动对应的测试；提交前看 Debug 回归，发布候选再做完整 Release 验收。

## 第 1 层：只跑改动相关测试

例如修改导航策略，分别验证实际改动的平台，不必每次重跑全部平台：

```bash
# Swift FocusCore：按测试类型过滤；也可进一步指定单个测试方法。
FOCUS_INCLUDE_TESTS=1 swift test --disable-sandbox --filter FocusNavigationPolicyTests

# KMP：只运行导航策略测试类，不附带其他模块的测试任务。
./gradlew :focus-core:testDebugUnitTest --tests 'org.bilibilifocus.core.routing.FocusNavigationPolicyTests'
```

测试输出应包含所选类型，零项匹配不能当作通过。修改 Web 注入或 API 契约时，
另跑下方对应的同步／语法检查；涉及 Swift/KMP 共享行为时，两边对应测试都跑。

## 第 2 层：提交前的核心回归

Pull Request 和 `main` 分支更新自动执行 Debug 回归与构建。修改共享配置、
跨模块接口、登录或持久化时，不只依赖单个测试；运行受影响平台的完整核心测试。

* **iOS 核心测试**：`FOCUS_INCLUDE_TESTS=1 swift test --disable-sandbox`
* **iOS Release 边界测试**：`FOCUS_INCLUDE_TESTS=1 swift test -c release --disable-sandbox`
* **Web 注入规则验证**：`swift run FocusVerifier`
* **Android 单元测试**：`./gradlew :focus-android:testDebugUnitTest :focus-core:testDebugUnitTest`
* **KMP iOS 编译/链接门禁**：`./gradlew :focus-core:compileKotlinIosSimulatorArm64 :focus-core:linkDebugFrameworkIosSimulatorArm64`
* **跨平台运行时一致性**：`./Scripts/sync_focus_runtime.sh --check`
* **Kotlin 内嵌 JavaScript 语法**：`node Scripts/check_kotlin_feature_scripts.mjs`（不访问网络）
* **Bilibili API 契约一致性**：`./Scripts/sync_bilibili_api_contracts.mjs --check`
* **在线 API smoke（默认跳过）**：`node ./Scripts/run_online_smoke.mjs`

Pull Request 和 `main` 分支更新运行 Debug 核心测试、运行时／API 契约检查、
FocusVerifier、KMP iOS 编译链接、Xcode 单元测试、Android Lint 与 Debug APK 构建。

## 第 3 层：发布候选完整验收

发布候选在 GitHub Actions 手动运行 **CI**（`workflow_dispatch`）。它会在第 2 层
之外执行 Release Swift 测试、无签名 iOS Release 构建与 Android Release 编译，
这三项不再随每次提交重复执行。单独执行命令保持可用。真实账号在线 smoke
仍须显式选择，按 [在线 Smoke 说明](online-smoke.md) 执行，不因本地测试通过而自动发起。

## Web 注入运行时同步

`Sources/FocusCore/Resources/focus-runtime.js` 是 Web 注入运行时的唯一编辑源；
`focus-core/src/commonMain/resources/focus-runtime.js` 是供 Kotlin Multiplatform
打包的提交内镜像。修改运行时后执行：

```bash
./Scripts/sync_focus_runtime.sh --sync
./Scripts/sync_focus_runtime.sh --check
```

Gradle 的测试与 assemble 任务也依赖同一份一致性门禁，未同步时会直接失败。

## API 契约

Swift 与 KMP 共享一份独立维护、仅含协议事实的 Bilibili API 端点子集。
当前 52 个端点的 URL 与 HTTP method 可用同级 `bilibili-api` 仓库校验；历史搜索、删除与
清空另有 3 个补充来源，记录在 catalog 的 `source.supplementalEndpoints` 中，
不会被报告为通过同级仓库校验：

```bash
./Scripts/sync_bilibili_api_contracts.mjs --validate-source ../bilibili-api
```

## 本地产物与清理

验证产物放在 `build/validation/<日期>-<主题>/`，交付包放在 `build/dist/`
（`./Scripts/build_unsigned_ipa.sh` 默认输出到这里）。两者都不进入 Git。
清理构建产物和临时目录：

```bash
./Scripts/clean.sh            # build/、.build/、.tmp-*/、模块 build/、.kotlin/
./Scripts/clean.sh --gradle   # 另外清理 .gradle/ 与 .gradle-home/ 缓存
```
