# iOS 15 兼容适配

## 状态

- 审查基线：`anywhere-labs/Agents-Anywhere` `main` @ `e5c0179d2b84f1f5a19403ca9dc9254c4dacf4b6`（官方 codeload 快照，归档 SHA256 `a9cba39e…`）。
- 当前阶段：**M1 兼容基础**。已落地共享适配器、可用性清单门禁和 macOS CI；**App 尚未能在 iOS 15 上构建，更未在真机验收**。仓库里的 iOS target 仍是 `IPHONEOS_DEPLOYMENT_TARGET = 26.5`，没有为了"看起来支持"而调低。
- 交付边界：只改 `ios/` 与工作流；Server、Connector、Web、Android 未动。

## 为什么只降 deployment target 不行

| 阻断项 | 现状 | 结论 |
| --- | --- | --- |
| Observation（`@Observable`/`@Bindable`/`@Environment(T.self)`） | 141 处状态标注、21 个 `import Observation`，分布在 Stores、Models、Repositories、Network 与视图 | Observation 框架 iOS 17 才有，iOS 15 上连编译都过不了 |
| Markdown 渲染 | `ios/Packages/Textual` 要求 iOS 18，依赖 `swiftui-math` 要求 iOS 17 | 不能靠"降 target"绕过 SPM 平台下限 |
| 滚动与几何 | `ScrollPosition`、`onScrollGeometryChange`、`onScrollPhaseChange` 为 iOS 18 | 聊天时间线需要独立的旧系统滚动实现 |
| Liquid Glass | `glassEffect`、`.buttonStyle(.glass)`、`scrollEdgeEffectStyle`、`safeAreaBar`、`ConcentricRectangle` 为 iOS 26 | 需要材质回退，不能删除控件 |
| 输入与导航 | 双参数 `onChange`（iOS 17）、`NavigationStack`/`NavigationSplitView`（16）、`PhotosPicker`（16）、`LabeledContent`（16）、`ContentUnavailableView`（17） | 需要逐项适配，且 `TextField` 放进 `.alert` 在 iOS 15 不会出现输入框，改名类功能要改成表单 |

OpenMinis 的经验同样指向这一点：只把 `IPHONEOS_DEPLOYMENT_TARGET` 改成 15 会得到"能装、能启动、随即崩溃"的产物；真正费力的是旧系统分支、依赖最低版本和真机验收。本次按"先建可复现的反馈回路，再分批迁移"推进。

## 已完成（本阶段）

### 1. 共享适配器

新增 `ios/Agents Anywhere/Agents Anywhere/Compatibility/AppCompatibility.swift`，统一提供 iOS 15 可用的等价实现；调用点保留原有布局、状态与命中区：

- `appGlassEffect(_:in:)`：iOS 26 用 Liquid Glass，旧系统用同形状的材质卡片。
- `appGlassButtonStyle(prominent:)`、`appCircularButtonShape(_:)`：按钮样式与形状回退。
- `appScrollEdgeEffect(_:for:)`、`appHiddenScrollIndicators()`、`appScrollBounceBasedOnSize(axes:)`、`appScrollDismissesKeyboardInteractively()`、`appHiddenNavigationBarBackground()`。
- `appHapticFeedback(_:trigger:)`：iOS 17 `sensoryFeedback` → `UIImpactFeedbackGenerator`/`UINotificationFeedbackGenerator`。
- `appOnChange(of:initial:perform:)`：把 iOS 17 的双参数 `onChange` 语义复刻到旧系统（首个采样只作基线）。
- `appPresentationDetents(_:selection:)`、`appSheetScrollContentInteraction()`、`appSheetDragIndicator()`：iOS 15 保留标准 sheet。
- `appSymbolReplaceTransition()`、`appViewAlignedScrollTargetIfAvailable()`。

### 2. 首批采用点

| 文件 | 改动 |
| --- | --- |
| `Views/Components/AppGlassButton.swift` | 玻璃按钮样式与圆形边框形状改用适配器 |
| `Views/Components/CompletionFeedback.swift` | 触感反馈与两处 `onChange` 改用适配器 |
| `Views/Components/AppSheetPresentation.swift` | detent 状态改为 `AppSheetDetent`，旧系统退回标准 sheet |
| `Views/RootView.swift` | 断线提示卡片的玻璃背景 |
| `Views/Chat/ChatTimelineView.swift` | 「到底部」悬浮按钮的玻璃背景 |

这些文件在 iOS 26 上的外观与行为不变；旧系统分支只在 iOS 15 上生效。

### 3. 可执行的清单门禁

- `ios/scripts/check_ios15_availability.py`：按规则扫描 Swift 源码，统计 iOS 15 不可用 API。**它是清单与棘轮，不是编译器**：不禁用 `#available` 分支内的调用，也不声称剩余调用安全。
- `ios/Tests/test_ios15_availability.py`：7 个单元测试，纯字符串夹具，可在没有 Swift 工具链的机器上运行。
- `ios/ios15-availability-baseline.json`：当前 27 类、共 419 处已审阅基线；数量只允许下降。

当前基线（节选）：`observation` 141、`task-sleep-duration` 31、`layout-protocol` 30、`navigation-stack` 25、`textual` 22、`observation-import` 21、`scroll-edge-effect` 18、`geometry-change` 16、`scroll-modifiers` 16、`glass` 15、`scroll-position` 13、`localized-string-resource` 11。

### 4. CI 反馈回路

`.github/workflows/ios15-compat.yml`：

- `inventory`（门禁）：跑单元测试并执行 `--check`，新增未审阅的用法会让 PR 变红。
- `modern-build`（门禁）：用当前 Xcode 构建 shipped target，确认兼容改动没有破坏现有 App。
- `probe-15`（诊断）：以 `IPHONEOS_DEPLOYMENT_TARGET=15.0` 编译并上传完整日志。它在依赖迁移完成前必然失败，因此不参与门禁，也**不会**被当成通过。

## 编译通过也不等于能用：必须单独处理的行为陷阱

这些调用在 iOS 15 上"能编译"或"被 no-op 掉"，但会静默丢功能，迁移时必须逐个保留行为：

| 陷阱 | 位置 | 后果 |
| --- | --- | --- |
| `.alert` 内放 `TextField` | 会话改名 `ChatSidebarView.swift:426`、Agent 改名 `DeviceAgentSection.swift:56`、设备改名 `DeviceManagementView.swift:142` | iOS 16 前不显示输入框，改名入口变成空对话框 |
| `onScrollVisibilityChange` 驱动缩略图请求 | `ChatMessageAttachments.swift:71` | 把可见性 hook 改成 no-op 后 `visible` 永远为 false，图片永不下载 |
| 双参数 `onChange` 的 `previous` | `ManualLoginView.swift:74`、`ChatShellView.swift:24` 等 42 处 | 机械删除旧值会让取消登录、会话切换、草稿清理失效 |
| `Duration`/`ContinuousClock`/`Task.sleep(for:)` | 31 处，含 `NewSessionWelcomeView.swift:90` | iOS 15 需 `Task.sleep(nanoseconds:)`，且取消语义要保持 |
| `LocalizedStringResource` 出现在模型/默认参数 | 11 处，如 `AppAppearance.swift:12` | 只门控 `Text` 调用不够，公开签名仍会阻断编译 |
| iOS 26 的 `safeAreaBar`/`ConcentricRectangle`/`scrollEdgeEffectStyle` | `SidebarDrawer.swift:15,615,649,685` | 换成 no-op 会让侧栏 header 与 inset 消失 |
| `UIGestureRecognizerRepresentable` | `SidebarDrawerPanGesture.swift:6` | `canImport(UIKit)` 在 iOS 15 同样成立，不能当版本门控 |

## 不要按"API 首次发布年份"误伤

迁移时容易把下面这些当成高版本 API 一并门控或降级，实际不需要，改了反而制造分支：

- `.topBarLeading` / `.topBarTrailing`：iOS 14 起可用，SDK 以 `@backDeployed` 回部署。`ChatPageToolbar` 里真正需要处理的是 `.subtitle`、`navigationSubtitle`、`sharedBackgroundVisibility`（iOS 26）。
- `UIViewController.viewIsAppearing(_:)`（iOS 13+）与 `contentScrollView`/`setContentScrollView`（iOS 15+），`MacCatalystWindowTitle`、`ChatPageScrollEdge` 中的这些调用可以保留。
- `AnyShapeStyle`、`menuIndicator`、`Button(String, systemImage:action:)` 等经 SDK 回部署的便利 API。
- `@Entry` 是编译期宏，展开为 `EnvironmentKey`，不构成 iOS 18 运行时依赖（本仓库仍统一走显式 key，便于审计）。
- 普通 `UITextView`/IME、`FocusState`、`onSubmit`、`dismiss`、`task`、`safeAreaInset`、`fileImporter`/`fileExporter`、`WKDownload`、CoreText 字体注册在 iOS 15 均可用。

判断依据应是**实际使用 SDK 的注解**，不是文档里"某年发布"的直觉；`ios15-probe` 的编译诊断是最终裁决。

## 尚未完成

| 里程碑 | 内容 | 验收 |
| --- | --- | --- |
| M2 状态层 | 用 Perception（`@Perceptible`/`WithPerceptionTracking`，iOS 13+）或独立旧系统模型替换 Observation；保持"视图不持有第二份网络状态"的既有所有权 | 双 target 编译 + 状态测试 |
| M3 聊天渲染 | 旧系统滚动栈（`GeometryReader`+`PreferenceKey` 或 UIKit `UIScrollView`）与轻量 Markdown 渲染；不引入 Textual | 长会话流式、向上翻页、键盘切换 |
| M4 导航与表单 | `NavigationStack`→`NavigationView` 适配、`PhotosPicker`→`PHPickerViewController`、`LabeledContent`/`ContentUnavailableView` 回退、`UIAlertController` 文本输入替代 | iPhone/iPad 真机走查 |
| 打包 | iOS 15 core 版的 target、签名与分发方式 | 真机安装启动 |

路线选择：**保留现代 target 原样，新增 iOS 15 core target 复用 API/Domain 层**，而不是在同一 target 里全量门控。理由是 Observation 与 Textual 的改动面横跨 24 个模型文件和 6 个渲染文件，一次性改完无法在没有编译器的环境里验证；分 target 可以让现代 App 继续可发布。

## 验证情况（必须如实区分）

| 项目 | 状态 |
| --- | --- |
| 清单脚本 + 单元测试 | 已在本机运行，`7 tests OK`；`--check` 与基线一致 |
| Swift 编译（iOS 26） | 已由云端 macOS runner 验证通过（见下节） |
| Swift 编译（iOS 15） | 现代 target 的 15.0 探针仍失败（Textual，见下节）；独立 target `AgentsAnywhereLegacy` 已在 15.0 编译通过并产出 IPA |
| 模拟器/真机 | 用户真机（iOS 15）已确认登录态列表与时间线可用；完整回归按[真机验收清单](ios15-device-acceptance.md)执行，多数用例仍未验证 |
| 外观与交互回归 | 旧系统分支未经逐项走查 |

## 云端编译记录（2026-10-29）

真机验收的执行步骤、用例与证据要求见 [ios15-device-acceptance.md](ios15-device-acceptance.md)。

- 仓库：fork [`doimty/Agents-Anywhere`](https://github.com/doimty/Agents-Anywhere)，分支 `feat/ios/ios15-compat-foundation`，提交 `51983d5c`。
- 运行：[Actions #40853042627](https://github.com/doimty/Agents-Anywhere/actions/runs/40853042627)。
- `Availability inventory`：通过（7 个单元测试 + 基线 `--check`）。
- `Modern target still builds`：通过。首轮曾在 `AppCompatibility.swift` 的 `strokeBorder` 上报错（`some Shape` 没有该方法，只有 `InsettableShape` 有），改为 `shape.stroke(Color.primary…)` 后通过；静态审查不能替代编译器。
- `Probe iOS 15 deployment target`：`xcodebuild_exit=65`，首个阻断是 Textual 的传递依赖：

  ```text
  SourcePackages/checkouts/swiftui-math/Sources/SwiftUIMath/Math.swift:100:23:
  error: 'ProposedViewSize' is only available in iOS 16.0 or newer
  ```

  这与 [M2–M4 方案](ios15-implementation-plan.md) 的判断一致：`Textual` 与 `swiftui-math` 必须移除，而不是绕过。探针保持非门禁，但失败时会输出红色注解与 step summary，不会伪装成通过。

### iOS 15 core 客户端（可安装 IPA）

现代界面依赖 Observation/Textual/Liquid Glass，逐项迁移周期长；为了让 iOS 15 上先有可用客户端，新增了独立 target `ios/Legacy/AgentsAnywhereLegacy.xcodeproj`：

- 复用 `API`、`Domain`、`Network`、`Models/APIModels.swift`、`KeychainStore` 等 50 个共享文件，只替换 SwiftUI 视图层（登录、设备/会话列表、时间线、发送、中断）。
- 部署目标 `IPHONEOS_DEPLOYMENT_TARGET = 15.0`，`MinimumOSVersion` 实测为 `15.0`，arm64。
- 输出为未签名 IPA（`Payload/AgentsAnywhereLegacy.app`），可用 TrollStore、AltStore/Sideloadly 或自行重签安装；App Store 分发仍需证书与描述文件。

首次通过记录：[Actions #40867009328](https://github.com/doimty/Agents-Anywhere/actions/runs/40867009328)，提交 `b3e642a5`，产物 `AgentsAnywhereLegacy-unsigned.ipa`（约 735 KB，bundle id `com.agentsanywhere.legacy`）。加入审批/输入请求后：[Actions #40867732985](https://github.com/doimty/Agents-Anywhere/actions/runs/40867732985)，提交 `04623faa`。加入 Markdown 渲染后：[Actions #40869655352](https://github.com/doimty/Agents-Anywhere/actions/runs/40869655352)，提交 `95e907e1`，IPA 约 780 KB。

能力边界（已知）：实时更新以会话 WebSocket 作为「有变化」信号，收到事件后用增量 `timelineChanges(afterSeq:)` 拉取；事件负载本身不参与合并，3 秒轮询继续作为断线兜底。进入会话时拉取最近 80 条并支持向上翻页，也可手动刷新。审批卡片支持无输入动作，需要输入的动作以 `{"text": "..."}` 提交，未解释 action schema。消息正文用 `AttributedString(markdown:)` 渲染（强调、行内代码、链接、列表）并把围栏代码块单独等宽展示；工具调用显示真实标题、命令与状态，点按可展开完整输出与文件变更 diff。附件通过 `PHPickerViewController` 选图（无需相册权限）和 `fileImporter` 选文件，先上传再以 `fileId` 随消息发送，单文件上限 25 MiB。草稿按会话保存在本地，重启后仍可继续输入；回到前台立即拉取增量，不等下一次轮询。首页底部显示 `v0.7.0 (7)`，便于确认安装的是哪一版 IPA。这些能力在后续里程碑补齐，现代 App 不受影响。

## 复现

```bash
python3 ios/Tests/test_ios15_availability.py -v
python3 ios/scripts/check_ios15_availability.py --report   # 逐条清单
python3 ios/scripts/check_ios15_availability.py --check    # CI 门禁
# macOS：
xcodebuild -project "ios/Agents Anywhere/Agents Anywhere.xcodeproj" \
  -scheme "Agents Anywhere" -destination 'generic/platform=iOS' \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 CODE_SIGNING_ALLOWED=NO build
```

## 回滚

本阶段不改变运行时行为：删除 `Compatibility/`、还原上表 5 个文件的改动即可；清单与工作流可独立保留或删除。
