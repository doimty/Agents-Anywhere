# iOS 15 兼容说明

这份文档记录 iOS 客户端把最低系统版本从 26.5 降到 15.0 的做法、边界和验证状态。
目标是**把原仓库的完整界面移植到 iOS 15**，不是另写一套简化界面：侧栏、会话、设备、
项目、输入区、工具审批和 Markdown 渲染都保留原来的视图与样式，只在系统版本不支持
某个 API 时，为它换一条等价实现。

## 当前状态

| 项 | 值 |
| --- | --- |
| 最低系统 | `IPHONEOS_DEPLOYMENT_TARGET = 15.0`（App、Widget、扩展一致） |
| 构建 SDK | Xcode 26.6 / iPhoneOS 26.5 SDK |
| Swift tools | 6.2，`defaultIsolation(MainActor.self)` |
| 构建产物 | 未签名 arm64 Debug IPA，`MinimumOSVersion = 15.0` |
| 已验证 | 真机 iPhone 13 Pro（iOS 15.1.1）可安装、可启动、可进入新建会话页 |
| 未验证 | 真机上的完整交互与视觉对照（见文末清单） |

## 依赖改造

原工程依赖的包对系统版本有更高要求，全部本地化到 `ios/Packages/`：

| 包 | 位置 | 改动 |
| --- | --- | --- |
| Perception 2.0.11 | `ios/Packages/Perception` | 原样 vendored，作为 iOS 15/16 的 Observation 回溯 |
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
漏掉时表现为「首帧正常、点按钮没反应」——状态确实变了，但视图不重画。新增视图时务必包装。

### 时间与并发类型

`Duration`、`ContinuousClock`、`Task.sleep(for:)`、`Mutex` 都是 16+，统一换成
`Views/Domain/Common/ClientConcurrency.swift` 里的 `ClientDuration`、`ClientClock`
（`mach_continuous_time`）、`ClientTask.sleep(for:/until:)`、`ClientMutex`（`NSLock`）。
语义保持一致：可取消、单调时钟、不会因系统时间调整而漂移。

## availability 分层

所有兼容性适配集中在 `Views/Compatibility/`，其他文件不应直接写 `#available` 判断。
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
| `appScrollVisibilityChange` / `timelineVisibility` | `onScrollVisibilityChange`（18） | 挂载期间视为可见 |
| `appImpactFeedback` / `appSelectionFeedback` | `sensoryFeedback`（17） | `UIImpactFeedbackGenerator` |
| `appWithAnimation(_:completionDelay:)` | `withAnimation(completionCriteria:)`（17） | 动画时长后回调 |
| `appSidebarPanGesture` | `UIGestureRecognizerRepresentable`（18） | `UIPanGestureRecognizer` 桥 |
| `appRemoveSidebarToggle` / `appSharedBackgroundHidden` | `toolbar(removing:)`、`sharedBackgroundVisibility`（17/26） | 不注入该控件即可 |
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
带参数时为假（所有 `#available` 分支退回 15 实现）。

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
3. **滚动位置恢复**：没有 `ScrollPosition` 锚点恢复，从历史加载后回到同一行的精度略低。
4. **顶部/底部边缘效果**：没有 `scrollEdgeEffectStyle`，用 `safeAreaInset` + 渐隐近似。
5. **工具栏副标题**：没有 `.subtitle` placement，标题与状态合并到 principal 项。
6. **分享**：`ShareLink` 换成 `UIActivityViewController`，导出内容一致。
7. **键盘与列表细节**：`scrollDismissesKeyboard`、`scrollBounceBehavior` 等由适配器
   控制，行为与 16+ 相同但不是同一实现。

## 验证

### 已有证据

- CI：`.github/workflows/ios15-original-ui.yml`，macos-26 + Xcode 26.6
  - 适配器在 `arm64-apple-ios15.0` 下单独 `swiftc -typecheck`
  - 整个 App 以 `-destination 'generic/platform=iOS'`、Release/Debug 构建，`CODE_SIGNING_ALLOWED=NO`
  - 校验 `MinimumOSVersion == 15.0`，记录 `vtool`/`otool` 输出
  - 打包未签名 IPA 并给出 SHA256
- 真机：iPhone 13 Pro / iOS 15.1.1，build 13 可安装、可启动、可进入新建会话页

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
2. 适配器必须保留原生路径，`#available` 判断只写在适配器内部。
3. 新增读取 `@Perceptible` 模型的视图，`body` 要包 `AppObservationTracking`。
4. 旧系统回退不允许删功能：按钮、入口、文案都要在，可以换交互方式。
5. 改完推 CI，用真实编译诊断验证；不要只看源码断言通过。
