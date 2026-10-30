# 设置界面重设计（settings-ui-redesign）实施计划

> **执行方式**：使用 spec-dev 的 executing-plans skill 逐任务执行本计划；无该 skill 的环境直接从任务 0 起按序执行至最终任务。任务状态由 `plan/progress.yaml` 跟踪（唯一状态源；任务文件步骤用「**步骤 N:**」标题式、不含复选框）；脱离项目携带时连同特性目录（含 spec）整体带走。
>
> **偏差处理**：执行中发现计划与现实不符——小偏差（路径笔误、明显遗漏但意图清楚）就地修正并在提交信息中注明；接口、数据结构等契约级偏差停下向计划作者确认，不猜着改。

**目标**：按已定稿 spec 与原型 v2，把 MiRemote 设置窗、sheet、引导、菜单栏面板与屏幕浮层刷新为新视觉（macOS 26 液态玻璃 + 回退），并加入侧栏可收起、基础状态说明、来源标签与恢复继承、RC 2 Pro 专用示意图、三行侧栏头与连续电量，现有映射行为不变。

**Spec**：[`../spec/settings-ui-redesign-design.md`](../spec/settings-ui-redesign-design.md)（status: active）；原型 `../spec/assets/prototype-v2.html`，截图 `../spec/assets/screenshots/`。

**架构**：新增的规则都是纯函数（`BaseTapNote`、`SlotResolver`、`RemoteModel`、`StatusIssue`、`RemoteAnnotationLayout`、`GlassSurface.appearance`），用仓库现有 `selfCheck` + `SelfTest.expect` 做红绿；视图只消费这些函数。玻璃判断只在 `DesignSystem.swift` 的 `GlassSurface` 一处，窗体不判断系统版本。RC 2 Pro 示意图是与通用画法共享按键 id / 命中区 / 状态样式的第二套 `Path` 绘制，按 `AppModel.remoteModel` 切换。

**关键取舍**：
- 侧栏与工具栏玻璃交给系统（`NavigationSplitView` + 桥接工具栏在 macOS 26 SDK 下自动为玻璃，14–15 为系统侧栏材质），`GlassKind` 只保留需要手工处理的 `sheet / panel / overlay`（spec「macOS 26 液态玻璃与回退」、组件表）。
- 玻璃 API 用 `#if compiler(>=6.2)` 包住 `if #available(macOS 26, *)`，使 macOS 14 SDK / 旧 Xcode 仍能编译（spec「风险」第 2 条）。
- RC 2 Pro 画法放新文件 `UI/RC2ProDiagram.swift`，`RemoteDiagram` 增加 `model:` 参数；不引入 `mode` 枚举，尺寸仍由调用方 `frame` 决定（spec 组件表与约束已于执行前修订为按型号选择画法，见 D2）。
- 型号判定只用生效的 `RemoteIdentity.vendorID/productID` + 连接状态，不改 `HIDEngine`（spec「MI RC 2 Pro 专用遥控器示意图」判定规则；D3）。
- 接口细化：spec 组件表的签名是示意，本计划按代码现状细化且不改语义——`BaseTapNote.text` 只对短按调用并以 `ownTap` 区分 App 场景是否明确设置；`SlotResolver.resolve` 以 `MappingSlot`（tap / hold / double / gesture / layer）合并 trigger 与 layer；`GlassKind` 不含 sidebar / toolbar / chip（chip 用 `.overlay`）。各票「接口」节写明对应关系。
- `SelfTest.swift` 的新增断言集中放在文件末尾 `print(failures == 0 ? "SELF-TEST PASS" ...)` 之前的一个 `// ===== UI 重设计（settings-ui-redesign）=====` 块，降低与 fix/code-audit 的文本冲突。

**技术栈**：Swift 5.10+/6.x、SwiftUI + AppKit（macOS 14 下限，`arm64-apple-macosx14.0`），`./build.sh`（swiftc 直接编译 `Sources/MiRemote/*/` 全部 .swift，新文件自动纳入），无第三方依赖，无 UI 测试 target。

**关联 skill**：
- executing-plans：全程执行入口（`${CLAUDE_PLUGIN_ROOT}/skills/executing-plans/SKILL.md`）。
- test-driven-development：T01–T18 的五步红绿；纯视觉票以静态 grep 红绿 + `--ui-preview` 人工核对为有效失败测试（`${CLAUDE_PLUGIN_ROOT}/skills/test-driven-development/SKILL.md`）。
- test-strategy：验证归属与按影响复验，F 的全量与后续补验（`${CLAUDE_PLUGIN_ROOT}/skills/test-strategy/references/verification-scope.md`）。
- using-git-worktrees：T00 隔离与 D 清理（`${CLAUDE_PLUGIN_ROOT}/skills/using-git-worktrees/SKILL.md`）。
- acceptance-qa：T20 按验收矩阵执行（`${CLAUDE_PLUGIN_ROOT}/skills/acceptance-qa/SKILL.md`）。

**设计原则**：本计划遵循 spec-dev 设计原则（不留向后兼容垫片 / 最简实现 / 分层构建 / 不以未完成复杂性换可工作产品 / 模块化 / 优先成熟库 / 优先已有依赖 / 长期架构决策）；任务与代码不得违反，冲突时停下向计划作者确认。模块判据定义点：`${CLAUDE_PLUGIN_ROOT}/skills/writing-plans/references/design-principles.md`「模块判据」。

## 全局约束

- 设置窗 SHALL 保持 4 个侧栏项：按键映射 / 场景配置 / 语音 / 通用，顺序与图标沿用现状。
- 错误处理逻辑沿用现状（本次不新增错误分支），只统一呈现方式。
- 「MappingEngine」行为、`config.json` 结构与 `App/Contracts.swift` 不改；旧配置值不被自动改写。
- 玻璃的实现 SHALL 集中在一个修饰器 `GlassSurface` 中，窗体不得各自判断系统版本。
- 三种外观的信息、布局、命中区域 SHALL 完全一致。
- 内容区（表单分组、遥控器面板、表格）SHALL 保持高不透明度，以保证正文对比度不低于 WCAG AA。
- 「降低透明度」开启（`accessibilityReduceTransparency`），任何系统版本：用不透明的窗口背景色，保留圆角、层级与描边。
- 「减少动态效果」开启时 SHALL 关闭弹簧与脉冲动画，配对引导的脉冲改为静态高亮。
- 所有页面标题区、工具栏、行、标签、徽标、按钮、分段与 sheet 中的短标签 SHALL 不在词中断行（如「已保存」「识别按键」「电量 82%」）。
- 破坏性操作 SHALL 使用危险色，并且不能是默认按钮。
- 不强制 `.preferredColorScheme(.light)` 或固定 `NSAppearance`，不在滚动视图背后硬编码浅色背景。
- 文案：spec 标注「原文案」处逐字沿用现有代码字符串；新增文案逐字取自 spec（含 BaseTapNote 五句）。界面与代码注释不使用 emoji。
- 仓库没有 UI 测试 target，本计划不新建；构建只用 `./build.sh`，不用 `swift build`。
- 只在 macOS 上可构建；液态玻璃分支需要 Xcode 26（Swift 6.2）SDK 才会编入，旧 SDK 自动只编回退分支。

## 相关测试范围

- 项目无测试影响分析工具；唯一测试入口是 `./build.sh && .build/miremote --self-test`（`App/SelfTest.swift` 汇总各模块 `selfCheck()`，无法按名单独运行）。
- 本特性新增 / 修改的测试：`GlassSurface.selfCheck`、`BaseTapNote.selfCheck`、`MappingEngine.baseTapNoteParityCheck`、`SlotResolver.selfCheck`、`RemoteModel.selfCheck`、`SidebarHeaderLayout.selfCheck`、`SidebarToggle.selfCheck`、`StatusIssue.selfCheck`、`RC2ProGeometry.selfCheck`、`RemoteAnnotationLayout.selfCheck`、`FeelDefaults.selfCheck`，全部经 `App/SelfTest.swift` 末尾新块调用。直接 import 被改源文件的既有测试即同一 `--self-test` 进程，故相关范围命令与全量相同。
- 期望输出：通过时末行 `SELF-TEST PASS`、退出码 0；有效红为对应 `FAIL  <断言名>` 行 + 末行 `SELF-TEST FAIL (n)`、退出码 1。编译失败不是有效红。
- 人工可视检查：`.build/miremote --ui-preview`（不启动硬件服务，直接显示设置窗）。
- 静态快检：不适用（项目无独立 typecheck / lint 配置，`./build.sh` 的编译即检查）。

---

## 并发准备

- 共享契约来源：spec「组件与接口」表 + 本页导航表产出接口；共同前置 T01（视觉原语）、T02（BaseTapNote）、T03（SlotResolver）、T04（RemoteModel）四票互不依赖，都只依赖 T00。
- 第一条真实用户闭环：T05 完成后用 `--ui-preview` 打开设置窗即可看到新侧栏头（三行、连续电量、按型号回退设备名）；映射编辑闭环在 T09（检查器说明 + 来源 + 恢复）首次形成，T09 步骤 4 对照截图 01 / 22 / 31。
- 共享写入：`App/SelfTest.swift` 被 T01–T08、T10、T14 写入；`UI/AppModel.swift` 被 T03、T04、T06、T11 写入；`UI/RootView.swift` 被 T05、T06、T07、T09、T13 写入；`UI/MappingPage.swift` 被 T07–T10、T15 写入；`UI/OnboardingWizard.swift` 被 T07、T08、T15、T16 写入。这些是写集冲突而非语义依赖，由调度器按 scopes 排他，不加依赖边。
- 实际并发窗口：T00 后 T01–T04 均 ready，但都写 `App/SelfTest.swift`，实际逐票运行；不写 SelfTest 的 T09、T11、T12、T13、T15–T18 在各自依赖完成后可与写 SelfTest 的票重叠（仍需扣除上面的共享 UI 文件）。典型可重叠对：T12 与 T17、T13 与 T18、T11 与 T16。
- 资源：无数据库、端口或输出目录；`.build/` 在各 worktree 内独立，不入台账。必须主线程执行：T00、T19（F）、T20（A）、T21（D）。

```json spec-dev-scopes
{"version":1,"final_task":"T19","acceptance_tasks":["T20"],"tasks":{"T00":{"writes":[".gitignore"],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"},"T01":{"writes":["Sources/MiRemote/UI/DesignSystem.swift","Sources/MiRemote/App/SelfTest.swift"],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"},"T02":{"writes":["Sources/MiRemote/Mapping/BaseTapNote.swift","Sources/MiRemote/Mapping/MappingEngine.swift","Sources/MiRemote/App/SelfTest.swift"],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"},"T03":{"writes":["Sources/MiRemote/Mapping/SlotResolver.swift","Sources/MiRemote/UI/SourceTag.swift","Sources/MiRemote/UI/AppModel.swift","Sources/MiRemote/App/SelfTest.swift"],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"},"T04":{"writes":["Sources/MiRemote/UI/RemoteModel.swift","Sources/MiRemote/UI/AppModel.swift","Sources/MiRemote/App/SelfTest.swift"],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"},"T05":{"writes":["Sources/MiRemote/UI/SidebarHeader.swift","Sources/MiRemote/UI/RootView.swift","Sources/MiRemote/App/SelfTest.swift"],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"},"T06":{"writes":["Sources/MiRemote/UI/SidebarToggle.swift","Sources/MiRemote/UI/RootView.swift","Sources/MiRemote/UI/GUIAppDelegate.swift","Sources/MiRemote/UI/AppModel.swift","Sources/MiRemote/App/SelfTest.swift"],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"},"T07":{"writes":["Sources/MiRemote/UI/StatusIssue.swift","Sources/MiRemote/UI/RootView.swift","Sources/MiRemote/UI/MappingPage.swift","Sources/MiRemote/UI/ProfilePage.swift","Sources/MiRemote/UI/VoicePage.swift","Sources/MiRemote/UI/GeneralPage.swift","Sources/MiRemote/UI/OnboardingWizard.swift","Sources/MiRemote/App/SelfTest.swift"],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"},"T08":{"writes":["Sources/MiRemote/UI/RC2ProDiagram.swift","Sources/MiRemote/UI/RemoteDiagram.swift","Sources/MiRemote/UI/MappingPage.swift","Sources/MiRemote/UI/OnboardingWizard.swift","Sources/MiRemote/App/SelfTest.swift"],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"},"T09":{"writes":["Sources/MiRemote/UI/MappingPage.swift","Sources/MiRemote/UI/RootView.swift"],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"},"T10":{"writes":["Sources/MiRemote/UI/RemoteAnnotations.swift","Sources/MiRemote/UI/MappingPage.swift","Sources/MiRemote/App/SelfTest.swift"],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"},"T11":{"writes":["Sources/MiRemote/UI/ProfilePage.swift","Sources/MiRemote/UI/AppModel.swift"],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"},"T12":{"writes":["Sources/MiRemote/UI/MappingDetailView.swift"],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"},"T13":{"writes":["Sources/MiRemote/UI/VoicePage.swift","Sources/MiRemote/UI/RootView.swift"],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"},"T14":{"writes":["Sources/MiRemote/UI/GeneralPage.swift","Sources/MiRemote/App/SelfTest.swift"],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"},"T15":{"writes":["Sources/MiRemote/UI/SheetScaffold.swift","Sources/MiRemote/UI/HealthCheckSheet.swift","Sources/MiRemote/UI/ActionPicker.swift","Sources/MiRemote/UI/OnboardingWizard.swift","Sources/MiRemote/UI/MappingPage.swift"],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"},"T16":{"writes":["Sources/MiRemote/UI/OnboardingWizard.swift"],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"},"T17":{"writes":["Sources/MiRemote/UI/StatusItemController.swift"],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"},"T18":{"writes":["Sources/MiRemote/UI/OverlayCenter.swift"],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"},"T19":{"writes":[],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"},"T20":{"writes":[],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"},"T21":{"writes":[],"specs":[".spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md"],"authorization_ref":"pt26u 写实施计划吧；执行授权待用户在交接时确认"}}}
```

```yaml spec-dev-parallel
parallel:
  tasks:
    T01:
      resources: []
    T02:
      resources: []
    T03:
      resources: []
    T04:
      resources: []
    T05:
      resources: []
    T06:
      resources: []
    T07:
      resources: []
    T08:
      resources: []
    T09:
      resources: []
    T10:
      resources: []
    T11:
      resources: []
    T12:
      resources: []
    T13:
      resources: []
    T14:
      resources: []
    T15:
      resources: []
    T16:
      resources: []
    T17:
      resources: []
    T18:
      resources: []
```

## 任务导航

| 任务 | 依赖 | 消费接口 | 产出接口 |
|---|---|---|---|
| T00 [隔离工作区与基线](tasks/T00.md) | — | — | worktree `.worktrees/plan/2026-10-29-01-settings-ui-redesign`，分支 `plan/2026-10-29-01-settings-ui-redesign`；notes 中的来源根 / 分支 / HEAD |
| T01 [共享视觉原语](tasks/T01.md) | T00 | — | `enum GlassKind { case sheet, panel, overlay }`；`enum GlassAppearance { case liquidGlass, material, opaque }`；`GlassSurface.appearance(kind: GlassKind, glassAvailable: Bool, reduceTransparency: Bool) -> GlassAppearance`；`GlassSurface.glassAvailable: Bool`；`GlassSurface.selfCheck() -> Bool`；`View.glassSurface(_ kind: GlassKind, in shape: some Shape) -> some View`；`View.glassSheetBackground() -> some View`；`View.noWrap() -> some View`；`struct StatusBanner(kind: StatusBanner.Kind, title: String, actionTitle: String?, action: (() -> Void)?)`，`Kind { warning, error, info }`；`PageHeader(title:subtitle:accessory:)` |
| T02 [BaseTapNote 与引擎对拍](tasks/T02.md) | T00 | `MappingEngine.fireTap` 现行为 | `enum BaseTapNote`：`text(key: RemoteKey, profile: String, ownTap: Action?) -> String?`、`baseAction(key: RemoteKey, profile: String, ownTap: Action?) -> Action?`、`static let detailHeader: String`、`selfCheck() -> Bool`；`MappingEngine.baseTapNoteParityCheck() -> Bool` |
| T03 [槽位来源与恢复继承](tasks/T03.md) | T00 | — | `enum MappingSlot: Hashable { tap, hold, double, gesture(String), layer(Int) }`；`enum SlotSource { appOverride, inherited, unset }`；`struct SlotResolution: Equatable { action: Action?; source: SlotSource }`；`SlotResolver.resolve(config:profile:key:slot:) -> SlotResolution`；`SlotResolver.removingOverride(config:profile:key:slot:) -> MappingConfig`；`SlotResolver.selfCheck() -> Bool`；`AppModel.restoreInherited(_ key: RemoteKey, slot: MappingSlot)`；`struct SourceTag(source: SlotSource, profile: String)` |
| T04 [遥控器型号判定](tasks/T04.md) | T00 | `RemoteIdentity.vendorID/productID` | `enum RemoteModel { rc2Pro, generic }`；`RemoteModel.resolve(connected: Bool, vendorID: Int, productID: Int) -> RemoteModel`；`RemoteModel.fallbackName(vendorID: Int, productID: Int) -> String`；`RemoteModel.selfCheck() -> Bool`；`AppModel.remoteModel: RemoteModel`（计算属性）；`AppModel.displayDeviceName: String` |
| T05 [侧栏头三行与连续电量](tasks/T05.md) | T01, T04 | `View.noWrap()`；`AppModel.displayDeviceName` | `struct SidebarHeader: View`；`struct BatteryGlyph(percent: Int?)`；`SidebarHeaderLayout.fillFraction(percent: Int?) -> CGFloat?`、`isLow(percent: Int?) -> Bool`、`batteryText(percent: Int?, connected: Bool) -> String`、`selfCheck() -> Bool` |
| T06 [侧栏可收起（⌃⌘S）](tasks/T06.md) | T00 | — | `AppModel.sidebarHidden: Bool`（@Published）；`SidebarToggle.menuTitle(hidden: Bool) -> String`、`visibility(hidden: Bool) -> NavigationSplitViewVisibility`、`hidden(from: NavigationSplitViewVisibility) -> Bool`、`selfCheck() -> Bool`；主菜单「显示」项 action `toggleSidebarFromMenu(_:)` |
| T07 [问题行与页内横幅](tasks/T07.md) | T01, T05, T06 | `StatusBanner`；`SidebarHeader`；`AppModel.sidebarHidden` | `enum StatusIssue { degraded, permission(String), disconnected, paused }`；`StatusIssue.current(degraded:missingPermission:connected:suspended:) -> StatusIssue?`；`StatusIssue.banner(for: SidebarItem, issue: StatusIssue?) -> StatusIssue?`；`StatusIssue.sidebarRow(_ issue: StatusIssue?) -> StatusIssue?`；`StatusIssue.selfCheck() -> Bool`；`EnvironmentValues.statusIssue: StatusIssue?`、`EnvironmentValues.statusFix: (StatusIssue) -> Void`；`struct PageStatusBanner(page: SidebarItem)`；`struct SidebarIssueRow`；`final class PermissionStatus: ObservableObject`；`OnboardingWizard(initialStep: Int = 0)` |
| T08 [RC 2 Pro 专用示意图](tasks/T08.md) | T04 | `AppModel.remoteModel` | `enum RC2ProGeometry`：`canvas: CGSize`（180 x 480）、`anchor(of: RemoteKey) -> CGPoint`、`key(at: CGPoint) -> RemoteKey?`、`selfCheck() -> Bool`；`RemoteDiagram(model: RemoteModel, ...)`；`RemoteDiagram.anchor(of: RemoteKey, model: RemoteModel) -> CGPoint` |
| T09 [映射页标题区与检查器](tasks/T09.md) | T01, T02, T03 | `PageHeader(accessory:)`；`noWrap()`；`BaseTapNote.text`；`SlotResolver.resolve`；`SourceTag`；`AppModel.restoreInherited` | `MappingPage(onOpenProfiles: () -> Void)`；`struct SceneChip(profile: String, overrideCount: Int, onOpen: () -> Void)` |
| T10 [遥控器面板标注与键盘导航](tasks/T10.md) | T01, T03, T08 | `SlotResolver.resolve`；`RemoteDiagram(model:)`；`RemoteDiagram.anchor(of:model:)` | `enum RemoteAnnotationLayout`：`showsAnnotations(panelWidth: CGFloat) -> Bool`、`side(of: RemoteKey) -> Side`、`labels(model: RemoteModel) -> [Label]`、`next(after: RemoteKey, direction: MoveCommandDirection) -> RemoteKey`、`selfCheck() -> Bool`；`enum AnnotationLayer: CaseIterable { base, layer1, layer2, layer3 }`（`slot`、`title`）；`accessibilityText(key:layer:resolution:profile:) -> String`；`struct RemoteAnnotationStage` |
| T11 [场景配置页](tasks/T11.md) | T01, T15 | `glassSurface`；`noWrap()`；`SheetScaffold` | `AppModel.frontAppBundleID: String?`；场景行「前台 / 正在编辑」标签与「编辑映射」按钮 |
| T12 [场景映射详情](tasks/T12.md) | T01, T02, T03, T15 | `noWrap()`；`BaseTapNote.detailHeader`；`SlotResolver.resolve`；`SheetScaffold` | 详情表单元格来源标签（无新公共签名） |
| T13 [语音页](tasks/T13.md) | T01, T07 | `StatusBanner`；`PageStatusBanner`；`OnboardingWizard(initialStep:)` | `VoicePage(onOpenOnboarding: (Int) -> Void)` |
| T14 [通用页](tasks/T14.md) | T01 | `noWrap()` | `enum FeelDefaults { static func restoredHold(_ s: MappingConfig.Settings) -> MappingConfig.Settings; static func restoredDouble(_ s: MappingConfig.Settings) -> MappingConfig.Settings; static func selfCheck() -> Bool }` |
| T15 [统一 sheet 骨架](tasks/T15.md) | T01 | `glassSheetBackground()`；`noWrap()` | `struct SheetScaffold<Content: View, Footer: View>`，`init(title: String, subtitle: String?, onClose: (() -> Void)?, closeHelp: String = "关闭", @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer)` |
| T16 [首次引导三步](tasks/T16.md) | T01, T07, T08 | `glassSheetBackground()`；`noWrap()`；`OnboardingWizard(initialStep:)`；`RemoteDiagram(model:)` | 无新公共签名 |
| T17 [菜单栏面板与角标](tasks/T17.md) | T01, T04 | `glassSurface(.panel/.overlay)`；`AppModel.displayDeviceName` | 无新公共签名 |
| T18 [屏幕浮层统一外观](tasks/T18.md) | T01 | `glassSurface(.overlay)` | 无新公共签名 |
| T19 [final 完整验证（F）](tasks/T19.md) | T01-T18 | 全部实施提交 | F 的 final record |
| T20 [验收（A）](tasks/T20.md) | T19 | F record、截图、实机 | `acceptance/acceptance-report.md` |
| T21 [交付与清理（D）](tasks/T21.md) | T19, T20 | F / A 结论、T00 notes | delivery 记录、history_ref、清理回执 |

## 共用协议：任务绑定

每张写代码的票（T01–T18）开工前与收尾时执行；本票文件只给实参 `TASK=<本票ID>`。以下命令都在 T00 记录的实施 worktree 根目录执行（先 `pwd` 与 `git rev-parse --show-toplevel` 核对等于 notes 中的实施路径；本稿生成环境下为 `/workspace/mi_remote_control/.worktrees/plan/2026-10-29-01-settings-ui-redesign`），`${CLAUDE_PLUGIN_ROOT}` 为 spec-dev 插件根（本稿生成环境为 `/workspace/mi/feature-dev`）。

1. 确认 `git status --porcelain` 为空（spec / plan / 任务范围已在 HEAD 提交），该 HEAD 即 scope_commit。
2. 原子写入 binding 与 in_progress/current：

```bash
node --input-type=module - "${CLAUDE_PLUGIN_ROOT}/guardrail/lib/task-binding.mjs" "$(git rev-parse --show-toplevel)" ".spec-dev/2026-10-29-01-settings-ui-redesign/plan/index.md" "<TASK>" <<'JS'
// node --input-type=module - <实际lib/task-binding.mjs> <实际仓库根> <计划相对入口> <任务ID>
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
const [library,repo,plan,task]=process.argv.slice(2),url=pathToFileURL(library);
const {git,commitView,worktreeView}=await import(url.href);
const {readScopes,scopeFingerprint}=await import(new URL('./task-scopes.mjs',url).href);
const {parseRecord}=await import(new URL('./record-data.mjs',url).href);
const file=path.join(repo,path.dirname(plan),'progress.yaml'),state=parseRecord(fs.readFileSync(file,'utf8'));
if(state.execution||!state.tasks[task]||['completed','blocked'].includes(state.tasks[task].status)||(state.current!==null&&state.current!==task))throw Error('resolve current/blocked state before binding');
const scope_commit=git(repo,'rev-parse','HEAD'),view=commitView(repo,scope_commit);
const scope=readScopes(view.readText(plan),Object.keys(state.tasks)).tasks[task];
const scope_digest=scopeFingerprint(view,plan,task).digest;
if(scopeFingerprint(worktreeView(repo),plan,task).digest!==scope_digest)throw Error('static inputs must be committed');
state.tasks[task].binding={scope_commit,scope_digest,authorization_ref:scope.authorization_ref,worktree:fs.realpathSync(repo),branch:git(repo,'branch','--show-current'),claim_key:null,claim_checkpoint:null};
state.tasks[task].status='in_progress';state.current=task;
fs.writeFileSync(file+'.tmp',JSON.stringify(state,null,2)+'\n',{flag:'wx'});fs.renameSync(file+'.tmp',file);
JS
```

3. 独立提交状态并取得 authority：`git add -- .spec-dev/2026-10-29-01-settings-ui-redesign/plan/progress.yaml && git commit -m "chore(<TASK>): 绑定任务范围"`，然后 `git rev-parse HEAD` 得到完整 SHA（不回填进同一提交）。
4. 激活：`node "${CLAUDE_PLUGIN_ROOT}/guardrail/task-binding.mjs" bind --plan .spec-dev/2026-10-29-01-settings-ui-redesign/plan/index.md --task <TASK> --authority <上一步完整SHA>`，再 `node "${CLAUDE_PLUGIN_ROOT}/guardrail/task-binding.mjs" inspect --plan .spec-dev/2026-10-29-01-settings-ui-redesign/plan/index.md --task <TASK>` 核对回执中的 task / authority / worktree。宿主拒绝内联片段或 bind 失败：保留现状，记 blocked 并报告，不改写片段或 CLI。
5. 实施提交（本票步骤 5）由 prepare-commit-msg 补 `Spec-Task:` 行；若钩子未安装，commit 后用 `git log -1 --format=%B` 核对并在 notes 记录。
6. 收尾：`node "${CLAUDE_PLUGIN_ROOT}/guardrail/task-binding.mjs" clear --plan .spec-dev/2026-10-29-01-settings-ui-redesign/plan/index.md --task <TASK>`；再用临时文件 + rename 把本票写为 `{ status: completed, commit: <步骤 5 的实施SHA>, tests: pass }`、`current: null`，`git add -- .spec-dev/2026-10-29-01-settings-ui-redesign/plan/progress.yaml` 后独立提交 `chore(<TASK>): 记录完成状态`。

## 共用约定：红绿运行

- 运行：`./build.sh && .build/miremote --self-test; echo "exit=$?"`
- 有效红：编译成功，输出含本票新断言的 `FAIL  <断言名>` 行，末行 `SELF-TEST FAIL (n)`，`exit=1`；其余既有断言仍为 `ok`。
- 为保证红是业务断言失败而非编译错误：步骤 1 先建立接口骨架（签名齐全、返回明显错误的值，如 `nil`、空数组、`.generic`、`false`），再加断言。
- 绿：末行 `SELF-TEST PASS`，`exit=0`。
- 纯视觉票的红绿：本票列出的 `rg` 静态检查由「有命中 / 无命中」翻转，加 `.build/miremote --ui-preview` 人工对照指定截图；人工项在提交信息与 notes 中写明「人工核对：截图 NN 一致 / 不一致项」。

## 决定记录（2026-10-29 用户已全部裁决：D2 修订 spec，其余按本计划默认执行）

- D1（T14，已决定：按默认）：spec「通用页」写的分组名（启动 / 显示与反馈 / 按键手感 / 关于与诊断 / 危险操作）与现有代码和定稿原型（启动与显示 / 高级 / 关于）不一致，且原型无「恢复」。本计划默认：保留现有三组名称与顺序（Requirement 标题为「结构不变」），在「高级 › 触发阈值」两条滑杆行加「默认 350 ms / 250 ms」与「恢复」，把「退出 MiRemote」「彻底卸载指引」移到「关于」组末尾单独一段并用危险色。用户若选择按 spec 分组名重排，先改 spec 与 T14 再执行。
- D2（T08，已决定）：用户确认修订 spec。第 139 行约束增加 RC 2 Pro 例外，第 648 行组件表改为 `RemoteDiagram(model:)` 按型号选择画法，已在执行前单独提交，spec 与 RC 2 Pro Requirement 现已一致。
- D3（T04，已决定：按默认）：型号只按生效 VID/PID + 连接状态判断；是否在 `HIDEngine.handleDeviceMatched` 读取实际设备 VID/PID 并上报，本计划不做（避免改硬件层且与 fix/code-audit 无关的面扩大），如需要另起需求。
- D4（全局，已决定：按默认）：液态玻璃需要 Xcode 26 SDK 构建；仓库当前构建机若为 macOS 14 SDK，产物只有回退外观。是否要求发布构建使用 Xcode 26，由用户决定；不影响各票红绿。
- D5（T12，已决定：按默认）：spec 要求详情表头「用一句纯文字说明基础状态的原生功能」，原型未给出该句。本计划采用 `BaseTapNote.detailHeader = "基础状态下方向键为光标键、返回键为删除（Delete）、OK 为回车（Return）；App 场景明确设置的 OK 短按会替代回车。"`，验收时请用户确认文案。
- D6（T13，已决定：按默认）：语音页沿用现有代码的分组顺序（spec「结构不变」），不按原型调整顺序。
- D7（T13，已决定：按默认）：spec 要求「自检失败项 SHALL 带「修复」按钮」，但第 3 项（按语音键有音频帧）与第 4 项（当前输入法是豆包）没有现成的修复入口，原型也未画按钮。本计划默认：第 1 项打开引导第 2 步，第 2 项打开引导第 3 步；第 3 项仅在输入模式不是「遥控器麦克风」时给「修复」并切到该模式；第 4 项「修复」打开「系统设置 › 键盘 › 输入法」。用户若选择只给第 1、2 项加按钮，删去第 3、4 项的按钮即可，不影响其他票。
- D8（T17 菜单栏健康点，2026-10-30 用户决定，偏离原型）：原型 `prototype-v2.html:873` 在「已暂停遥控」时仍为绿点。用户决定暂停时改为灰点。规则：红仅表示按键通道异常；已暂停或未连接为灰；已连接且未暂停为绿。实现于 `StatusDotKind(degraded:connected:suspended:)`，自测同步更新。菜单栏图标、侧栏问题行、页内横幅不使用该健康点颜色，不受影响。
- D9（暂停遥控语义修正，2026-10-30，t54u）：上游 de75ab3 暂停时卸载 hidutil 映射，遥控键回到系统原生（方向/回车/Home/菜单/电源/音量/F5 直达系统），语音链路也未受暂停约束。改为：暂停期间映射保持在位，TapEngine 吞弃全部遥控中转键，语音新会话被忽略；真键盘不受影响，恢复后一切照旧。已在进行中的语音会话允许自然结束。
- D10（按键提示条出现时机，2026-10-30，t55u）：上游 c2c9289 在前台 App 切换时，若该 App 显式声明 `ok.tap` 就闪现 2.5 秒提示条（如「OK 发送按键 · Return」）。原型 `prototype-v2.html:710` 定义提示条「模式或浮层激活时」出现，用户也反馈切 App 时莫名出现，故移除切 App 闪现，提示条只在功能层/浮层激活时出现（`HintBarCatalog.visible`）。
- D11（Secure Input 期间遥控键泄漏，2026-10-30，pt58u）：Secure Input 期间 CGEventTap 收不到按键而 hidutil 中转映射仍在，遥控键以中转键直通前台（方向键失效、音量中转小键盘除/乘可能打出 `/` `*`）。TapEngine 每 250ms 轮询 `IsSecureEventInputEnabled()`（会话字典 `kCGSSessionSecureInputPID` 兜底），期间映射切 `MappingMode.secureInput`：方向/OK/音量不映射（原生光标/回车/音量，即基础态本来语义），Home/菜单/TV/电源映到 F21（无系统行为）静默；暂停（D9）时 `.secureInputPaused` 全部静默。退出后切回中转表。在位校验 `mappingSatisfied(_:mode:)` 按当前形态判定，健康检查不会把安全形态"修"回中转表；源键集合不变，退出/崩溃残留清理口径不变。不新增 UI。

## 与 fix/code-audit 的衔接

- fix/code-audit（d298986）与本分支同基于 main c2c9289；与本计划重叠的文件只有 `App/SelfTest.swift`（其插入点约在 316、807–821、1144 行）、`UI/AppModel.swift`（`saveConfig` 内 2 行）与 `UI/GUIAppDelegate.swift`（13–16、61–86 行）。本计划的改动点（SelfTest 末尾新块、AppModel 新属性 / 新方法、GUIAppDelegate `configureMainMenu` 内新菜单）与之不相邻。
- 推荐顺序：fix/code-audit 先合入 main，再把 `feat/ui-redesign-spec`（含本计划）rebase 到新 main 后执行 T00。若 T00 已开始而 fix/code-audit 后合入，则在某票完成、下一票开始前把 main 合入实施分支（`git merge main`），重跑一次 `./build.sh && .build/miremote --self-test` 并记 notes；冲突只可能出现在上述三个文件，按「两边都保留」解决。
