# iOS 15 实现方案（M2–M4 设计）

> 配套文档：[ios15-compatibility.md](ios15-compatibility.md)（现状、清单、行为陷阱）。
> 目标：把 shipped App 的部署下限从 iOS 26.5 降到 15.0，同时保留 iOS 17+/18+/26 的原生表现。
> 原则（来自 OpenMinis 的教训）：原生分支优先、旧系统必须"有功能"而不是"能编译"、每一批都用真实编译诊断收口。

## 1. 路线选择

| 方案 | 代价 | 结论 |
| --- | --- | --- |
| A. 单 target 降到 15.0，逐项 availability 分支 | 需要替换 Observation 与 Textual，改动面大但只有一套 UI | **采用** |
| B. 新增 iOS 15 core target，复用 API/Domain | 现有 `Views/Models/Stores` 全部依赖 Observation，无法直接复用；等于长期维护第二套客户端 | 否决 |

关键事实：`Textual` 最低 iOS 18 且其 `swiftui-math` 依赖最低 17，SPM 解析阶段就会拒绝 15.0，**必须移除**，不能靠门控。Observation 是 OS 框架（非 SPM），可以换成回部署实现。因此 A 是唯一不需要复制 UI 的路径。

## 2. 依赖替换

### 2.1 Observation → Perception

`pointfreeco/swift-perception` 把 `@Observable`、`withObservationTracking`、`@Bindable`、`@Environment(T.self)` 回部署到 iOS 13。仓库现状：32 个 `@Observable` 类型（24 个文件）、141 处状态标注、18 处 `@Bindable`。

- 固定 **2.0.11**（`swift-tools-version: 6.0`，`platforms: .iOS(.v13)`）。2.0.12 的 manifest 已升到 tools 6.4，与仓库 `ios/Package.swift` 的 6.2 不匹配。
- 约定：
  - `@Observable` → `@Perceptible`
  - `@ObservationIgnored` → `@PerceptionIgnored`
  - `@Bindable` → `@Perception.Bindable`
  - `import Observation` → `import Perception`
  - 读取 perceptible 状态的每个视图 `body` 外层加 `WithPerceptionTracking { ... }`
- 漏包 `WithPerceptionTracking` 的后果是**静默不刷新**（Debug 下只有运行时警告），所以必须整树迁移，不能只改叶子组件；迁移后用现有 `ios/Tests/ClientCoreTests` 的状态测试 + `DrawerUpdateProbe`、`ViewModelLifetimeProbe` 回归。

### 2.2 Textual → 自研渲染器

iOS 15 的 Foundation 已提供 `AttributedString(markdown:)`，`PresentationIntent`（代码块、表格、列表）也是 15+，因此无需第三方依赖：

```swift
var options = AttributedString.MarkdownParsingOptions()
options.interpretedSyntax = .full
let document = try AttributedString(markdown: text, options: options)
```

渲染策略（保留现有 `MarkdownBlocks` / `MarkdownStreamSplit` 的分块与流式前缀缓存，只替换视图层）：

- 段落/标题/引用：`Text(attributedString)`，标题按 `presentationIntent` 映射字号。
- 代码块：按 `presentationIntent` 取出原文，`ScrollView(.horizontal)` + 等宽 `Text` + 复制按钮。
- 表格：`presentationIntent` 的 table 组件 → `VStack`/`HStack` 行渲染（不用 `Grid`，那是 16+）。
- 图片：`AsyncImage`（15+）+ 现有 `ChatImageLoader`；链接沿用 `openURL` 环境。
- 流式逐字动画：`TextRenderer`/`TextAttribute` 是 18+，旧系统降级为"按批整体出现"；现代系统继续用现有 `StreamingGlyphReveal`（加 `#available(iOS 18)`）。
- 文本选择：iOS 15 用 `.textSelection(.enabled)`；Textual 的范围选择能力在旧系统不可得，需在发布说明中列为限制。

移除 `XCLocalSwiftPackageReference ../Packages/Textual`、`ios/Package.swift` 的 Textual 相关引用（`Clients Anywhere` target 只留 ClientCore），并保留 `Packages/Textual` 目录不删除（现代分支不再引用即可，或后续单独清理）。

### 2.3 其余系统 API

| 能力 | iOS 15 实现 |
| --- | --- |
| 导航 | `NavigationView` + 隐藏 `NavigationLink(isActive:)` 的受控路径（OpenMinis `CompatNavigationPath` 同款）；iPad 用 `DoubleColumnNavigationViewStyle` |
| 聊天滚动 | SwiftUI `ScrollView` + `ScrollViewReader` + `GeometryReader`/`PreferenceKey` 记录 offset/inset；到底、历史锚点、用户阅读时不强制跟随、键盘避让逐条迁移；不够再退到 `UIScrollView` 桥 |
| 审批分页 | 显示全部卡片 + 明确的上一项/下一项按钮（不隐藏审批） |
| 照片/视频 | `PHPickerViewController` + `NSItemProvider`，结果模型 `PickedMedia(id, name, utType, data)`；`PhotosPickerItem` 只出现在 `@available(iOS 16,*)` 的实现里 |
| 分享 | `UIActivityViewController`（`UIViewControllerRepresentable`） |
| 文本输入弹窗 | `UIAlertController.addTextField`（改名三处：会话、Agent、设备） |
| 多层输入框 | `TextEditor` 或持续 `UITextView`；不用单行 `TextField` 冒充多行 |
| 触感 | `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator` |
| 单调时钟 | `ProcessInfo.processInfo.systemUptime` 替代 `ContinuousClock`；`Task.sleep(nanoseconds:)` 替代 `sleep(for:)` |
| 本地化 | `String(localized:)`（15+）替代 `LocalizedStringResource` 字段 |
| 26 外观 | 已在 `Compatibility/AppCompatibility.swift` 提供材质/按钮/滚动边缘回退；`safeAreaBar`→`safeAreaInset` |

## 3. 落地顺序（每步都可独立合并）

1. **P1（当前已提交）**：适配器 + 清单门禁 + CI probe。shipped target 不变。
2. **P2 状态层**：引入 Perception，脚本批量改宏与 `body`，再人工抽查 `AppState`、`V2SessionRepository`、`V2DashboardRepository`、`SessionChatModel` 的嵌套通知；现代 target 编译通过后再合。
3. **P3 渲染层**：新增 `LegacyMarkdownView`，把 6 个 `import Textual` 文件改为协议式渲染器（`ChatMarkdownRenderer`），现代分支继续用 Textual（若保留）或统一用自研渲染器（推荐后者，减少两套）。
4. **P4 交互层**：导航、滚动、照片、分享、文本输入、时间 API。
5. **P5 降下限**：`IPHONEOS_DEPLOYMENT_TARGET = 15.0`，`probe-15` 由诊断转门禁，scanner 基线归零。
6. **P6 真机**：iPhone（含 iOS 15 设备）与 iPad 走查，重点：长会话流式、历史锚点、键盘、IME 候选、审批、附件、断网重连。

## 4. 批量迁移脚本（示意）

```python
# 1) 宏替换（逐文件）
text = text.replace("import Observation", "import Perception")
text = text.replace("@ObservationIgnored", "@PerceptionIgnored")
text = text.replace("@MainActor @Observable", "@MainActor @Perceptible")
text = text.replace("@Observable", "@Perceptible")
text = text.replace("@Bindable var", "@Perception.Bindable var")

# 2) body 包裹：只处理 var body: some View { ... } 的单表达式
#    用括号配平找到 body 结束位置，再包 WithPerceptionTracking { ... }
```

脚本必须是**幂等**的，并在提交前用 `swift-format`/`swiftc -parse` 在 CI 上校验；本地无法编译时以 `probe` 日志为准。

## 5. 验收与回滚

- 每步保持 `modern-build` 绿色（现代 App 可发布），旧系统问题只让 `probe-15` 暴露。
- 旧系统行为验收看"功能是否可达"，不看"是否无警告"：
  - 改名三处必须能输入并保存；
  - 缩略图必须真的加载（`visible` 语义不能变成常量 false）；
  - `onChange` 的 `initial/previous` 语义必须保留（登录取消失效即回归）。
- 回滚粒度：P2/P3 各自独立提交，出问题按提交回退，不影响 P1 的适配器与 CI。
