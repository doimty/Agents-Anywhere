# iOS 15 兼容说明

这份文档记录 iOS 客户端把最低系统版本从 26.5 降到 15.0 的做法、边界和验证状态。
目标是**把原仓库的完整界面移植到 iOS 15**，不是另写一套简化界面：侧栏、会话、设备、
项目、输入区、工具审批和 Markdown 渲染都保留原来的视图与样式，只在系统版本不支持
某个 API 时，为它换一条等价实现。

## 当前状态

| 项 | 值 |
| --- | --- |
| 最低系统 | `IPHONEOS_DEPLOYMENT_TARGET = 15.0`（当前 App target） |
| 构建 SDK | Xcode 26.6 / iPhoneOS 26.5 SDK |
| Swift tools | 6.2，`defaultIsolation(MainActor.self)` |
| 构建产物 | 未签名 arm64 Debug IPA，`MinimumOSVersion = 15.0` |
| 已验证 | 用户的 iPhone 13 Pro Max（iOS 15.1.1）可安装、可启动并查看会话；build 13 的侧栏和加载卡顿问题仍在修复验收中 |
| 未验证 | 真机上的完整交互与视觉对照（见文末清单） |

## 依赖改造

原工程依赖的包对系统版本有更高要求，全部本地化到 `ios/Packages/`：

| 包 | 位置 | 改动 |
| --- | --- | --- |
| Perception 2.0.11 | `ios/Packages/Perception` | vendored；保留原实现，增加仅 DEBUG 的回溯后端测试开关 |
| Textual | `ios/Packages/Textual` | 楼层降到 15；参数包改有限 arity；`#Preview` 隔离在 `#if DEBUG`；TextKit1 排版与选中 |
| SwiftUIMath | `ios/Packages/SwiftUIMath/swiftui-math-0.1.0` | 楼层降到 15；`TypographicBounds` 与宽度拟合接口对跨 target 可见 |

`ios/Package.swift` 的 `platforms` 同步为 `.iOS(.v15)`，`project.pbxproj` 增加
`XCLocalSwiftPackageReference` 指向 `Packages/Perception`。

### Observation 回溯

iOS 17 的 `@Observable` 在 15/16 用 Perception 的 `@Perceptible` 表达，写法和原代码一致：

- `@Observable` → `@Perceptible`，`@ObservationIgnored` → `@PerceptionIgnored`
- `@Bindable` → `@Perception.Bindable`
- `@Environment(T.self)` 不变

**关键约束**：Perception 不会自动失效视图。每个读取模型状态的 `body` 必须落在
`AppObservationTracking { }` 里（iOS 17+ 等价于系统观察，15/16 走 `WithPerceptionTracking`）。
漏掉时可能表现为「首帧正常、点按钮没反应」——状态改变，负责视觉的子树却没订阅。
除了 `var body`，`ViewModifier.body(content:)` 以及 `GeometryReader`、`ScrollViewReader`、
`ForEach`、sheet、overlay、safeAreaInset 等延迟执行的闭包也必须在实际读取点建 scope。
build 13 只覆盖普通 body，没有覆盖动画 modifier 和延迟闭包；不能据此声称观察迁移已全部完成。

### 时间与并发类型

`Duration`、`ContinuousClock`、`Task.sleep(for:)`、`Mutex` 都是 16+，统一换成
`Domain/Common/ClientConcurrency.swift` 里的 `ClientDuration`、`ClientClock`
（`mach_continuous_time`）、`ClientTask.sleep(for:/until:)`、`ClientMutex`（`NSLock`）。
语义保持一致：可取消、单调时钟、不会因系统时间调整而漂移。

## availability 分层

共享适配集中在 `Views/Compatibility/`；必须使用新系统类型的布局、滚动和绘制实现以独立 availability 类型隔离。
适配器保留原生路径，只在旧系统上替换：

| 适配器 | 原生路径 | iOS 15 回退 |
| --- | --- | --- |
| `AppNavigationStack` / `AppRouteNavigationStack` | `NavigationStack` | `NavigationView` + 隐藏 `NavigationLink` 路由 |
| `AppContentUnavailableView` | `ContentUnavailableView` | 同版式的图标 + 标题 + 说明 |
| `AppLabeledContent` | `LabeledContent` | 左右两列 `HStack` |
| `AppMultilineTextField` | `TextField(axis: .vertical)` | `TextEditor` + 占位与行高 |
| `AppPhotoPicker` / `appPhotosPicker` | `PhotosPicker` | `PHPickerViewController`，自持 `AppPickedPhoto` |
| `appGlassEffect` / `AppGlassEffectContainer` | `.glassEffect`（iOS 26） | `ultraThinMaterial` + 连续圆角 |
| `appScrollEdgeEffect` / `appSafeAreaBar` | `scrollEdgeEffectStyle` / `safeAreaBar` | `safeAreaInset` + 渐隐 |
| `appOnChange` / `appOnGeometryChange` | 两参数 `onChange`、`onGeometryChange` | 单参数 `onChange`、`GeometryReader` |
| `appScrollVisibilityChange` / `timelineVisibility` | `onScrollVisibilityChange`（18） | 一般附件按挂载生命周期；时间线另用真实 UIScrollView 视口探针 |
| `appImpactFeedback` / `appSelectionFeedback` | `sensoryFeedback`（17） | `UIImpactFeedbackGenerator` |
| `appWithAnimation(_:completionDelay:)` | `withAnimation(completionCriteria:)`（17） | 动画时长后回调 |
| `appSidebarPanGesture` | `UIGestureRecognizerRepresentable`（18） | `UIPanGestureRecognizer` 桥 |
| `appRemoveSidebarToggle` | `toolbar(removing:)`（17） | 不注入额外的系统侧栏按钮 |
| `AppConcentricCardShape` | `ConcentricRectangle`（26） | 连续圆角 / 全出血矩形 |

滚动相关（`ScrollPosition`、`onScrollPhaseChange`、`onScrollGeometryChange`、
`defaultScrollAnchor`、`scrollTargetBehavior`）只在 iOS 18+ 保留：时间线在 15–17 用
`ScrollViewReader` 跟随底部，审批坞用显式「上一项/下一项」翻页，提示卡用横向滑动。
两种路径共用同一份内容视图（`ChatTimelineContent`、`SessionInteractionCard`），
不复制卡片或文案。

布局协议的实现（`ComposerLayout`、`MarkdownBlockLayout`、`TableGridLayout`、
`NewSessionContentLayout`）标 `@available(iOS 16)`，15 用等价视图实现同一套摆位：
同样的列宽上限、同样的行高、同样的输入区高度与最大编辑高度。

## 强制走旧路径

任一构建都可以用启动参数强制使用 iOS 15 分支，用来在新系统上回归旧代码：

```sh
xcrun simctl launch booted com.agentsanywhere.app --force-ios15-paths
```

实现是 `AppCompatibility.useNativeUI`：不带参数时为真（新系统走原生实现），
带参数时为假（使用该开关的适配器退回旧实现，不能改变真实系统的 availability）。

### 验证观察回溯，而不仅是旧布局

在 DEBUG 构建中同时传入下列参数，Perception 的 registrar、tracking 函数和 SwiftUI wrapper
都切换到回溯实现；新系统的自动 Observation 不会再掩盖漏注册的子树：

```sh
xcrun simctl launch booted com.agentsanywhere.app --force-ios15-paths --force-perception-backport
```

`--force-perception-backport` 只在 DEBUG 生效，没有该参数时包保持原来的系统版本选择。
`CompatibilityRegression` XCTest scheme 用离线数据运行原 `SidebarDrawer`、工具栏、
`ChatTimelineView` 和 Composer；分别验证 native 和两个强制参数组合的路径。
检查包括多次点开/关闭、边缘和关闭 pan、100 条完整 Markdown 消息加载时再打开侧栏、输入和发送。
测试截图、结果包和原始日志由 CI 上传；它们不能替代 iOS 15.1.1 实机和真实服务的联调。

### 长会话与运行时失败的处理

- 旧时间线按组使用 LazyVStack，保留完整正文与原卡片；视口探针只观察自己祖先的 UIScrollView，不替换 delegate。
- 上下两个历史方向分别持有请求状态；网络结束即结束 spinner，滚动点位恢复有自己的有界生命周期。
- 只有实际底部可见才继续跟随；工具组共用稳定 tail，流式高度变化按固定窗口合并，用户上翻后停止跟随。
- 后台或侧栏完全遮挡时保留最新完整消息投影，暂停隐藏正文发布；恢复时一次发布，不停止仓库订阅、不重放消息。
- 运行时 RPC 写失败后，旧 live facts 立即失效。保留原错误和草稿，只做一轮合并的只读恢复；完整新状态成功后才恢复操作。
- `runtime instance ... is not running (status='starting')` 表示设备端实例生命周期尚未就绪，不等于会话回合的 running/idle。不能凭这条文本猜测后台故障，亦不能把缓存回合状态当作新事实。

## 已移植范围

- **登录与配对**：`Views/Auth`、`Views/Pairing`，含二维码、手机号登录、服务地址
- **侧栏**：`SidebarDrawer` 全部交互（拖拽、边缘触发、动画、卡片圆角），`ChatSidebarView`
  的设备、项目、会话分区与筛选
- **新建会话**：`NewSessionView`、`SessionTargetSheet`、项目编辑器与目录选择
- **会话**：`SessionChatView`、时间线行、工具卡片、审批坞、附件、错误提示、分享与复制
- **设备**：`DeviceOverviewSections`、工作区文件预览、Runtime 配置
- **设置**：账户、身份、头像、密码、语言等页面
- **Markdown**：`StructuredText` 全部样式、GitHub 主题、表格、代码块与 Prism 高亮、
  公式（SwiftUIMath）、图片与链接预览

## 已知差异

旧系统上无法 1:1 复刻的部分，都是有意的等价替代：

1. **逐字流式动画**：iOS 18 的 `TextRenderer`/`TextAttribute` 不可用，15–17 直接显示同一段
   文本，没有逐字淡入；排版、行距、强调和内联样式不变。
2. **审批坞动画**：没有 `scrollTransition` 的缩放淡出，卡片切换改为翻页按钮 + 默认动画。
3. **滚动位置恢复**：没有 `ScrollPosition`，改为记录实际可见组的坐标和正文内部偏移，历史 prepend 后校正；懒布局完成时间与新系统不同，仍需真机对照。
4. **顶部/底部边缘效果**：没有 `scrollEdgeEffectStyle`，用 `safeAreaInset` + 渐隐近似。
5. **工具栏副标题**：没有 `.subtitle` placement，标题与状态合并到 principal 项。
6. **分享**：`ShareLink` 换成 `UIActivityViewController`，导出内容一致。
7. **键盘与列表细节**：`scrollDismissesKeyboard`、`scrollBounceBehavior` 等由适配器
   控制，行为与 16+ 相同但不是同一实现。

## 验证

### 已有证据

- CI：`.github/workflows/ios15-original-ui.yml`，macos-26 + Xcode 26.6
  - 适配器在 `arm64-apple-ios15.0` 下单独 `swiftc -typecheck`
  - 整个 App 以 `-destination 'generic/platform=iOS'`、Debug 配置构建，`CODE_SIGNING_ALLOWED=NO`；Release 遇到编译器 SIL 优化崩溃，未宣称通过
  - 校验 `MinimumOSVersion == 15.0`，记录 `vtool`/`otool` 输出
  - 打包未签名 IPA 并给出 SHA256
- 真机截图反馈：iPhone 13 Pro Max / iOS 15.1.1 可启动并展示新建会话、设备和历史正文；build 13 的侧栏无响应和长对话卡顿尚未完成新版真机验收。

### 真机验收清单（未完成）

- [ ] 侧栏滑出、遮罩、返回、边缘拖拽与手势冲突
- [ ] 会话列表滚动、进入会话、返回后状态保持
- [ ] 输入区：打字、换行、附件、@ 命令、键盘顶起
- [ ] 发送消息后时间线追加、流式输出、滚动跟随
- [ ] 工具卡片展开/折叠、审批按钮、审批坞翻页
- [ ] Markdown：标题、列表、表格、代码块、公式、图片、链接预览
- [ ] 设备页、工作区文件预览、Runtime 配置
- [ ] 设置页全部入口、退出登录、深浅色切换
- [ ] 冷启动、后台恢复、断网提示

## 维护规则

1. 新代码不要直接使用 iOS 16+ API。先查本文件表格，再在 `Views/Compatibility/` 增加适配器。
2. 适配器必须保留原生路径；新系统专有类型声明要放在完整 availability 边界内。
3. 新增读取 `@Perceptible` 模型的视图，`body` 要包 `AppObservationTracking`。
4. 旧系统回退不允许删功能：按钮、入口、文案都要在，可以换交互方式。
5. 改完推 CI，用真实编译诊断验证；不要只看源码断言通过。
