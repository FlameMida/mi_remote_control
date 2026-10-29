---
# —— spec-dev 漂移守卫锚点（机器可校验，勿删）——
spec_dev:
  version: 1
  feature: settings-ui-redesign
  status: draft            # DRAFT：待用户批准；批准前不进入 writing-plans、不改代码
  covers:
    - "Sources/MiRemote/UI/RootView.swift"
    - "Sources/MiRemote/UI/MappingPage.swift"
    - "Sources/MiRemote/UI/ProfilePage.swift"
    - "Sources/MiRemote/UI/MappingDetailView.swift"
    - "Sources/MiRemote/UI/VoicePage.swift"
    - "Sources/MiRemote/UI/GeneralPage.swift"
    - "Sources/MiRemote/UI/RemoteDiagram.swift"
    - "Sources/MiRemote/UI/ActionPicker.swift"
    - "Sources/MiRemote/UI/DesignSystem.swift"
    - "Sources/MiRemote/UI/OnboardingWizard.swift"
    - "Sources/MiRemote/UI/HealthCheckSheet.swift"
    - "Sources/MiRemote/UI/StatusItemController.swift"
    - "Sources/MiRemote/UI/OverlayCenter.swift"
  sync_commit: null
  supersedes: []
  superseded_by: null
---

> **⚠️ DRAFT（第 2 版）· 待用户批准**
> 本文是 spec-dev「需求分析」阶段的设计草稿（standard 档）。第 1 版里的代理推荐 Q1–Q5 已被用户在 2026-10-29 的回答替换（见「已确认的关键决策」），之后又追加了两项要求：「侧栏可收起」和「macOS 26 液态玻璃」。
> HARD-GATE：批准前不写实施计划、不改任何 App 代码。
> 依据：`godarrenw/mi_remote_control` main 分支源码只读快照（2026-10-29）、`docs/polish-r3/*.png` 现状截图、`DESIGN.md` §3.1b/§6、`docs/UI-REVIEW-BACKLOG.md`、`mockups/v3-macos.html`，以及用户改过的 `prototype-v1.html` 遥控器画法。

# MiRemote 全窗体 UI 重设计 设计

## 背景与目标

MiRemote 的界面由三类窗体组成：主设置窗（4 个侧栏页和若干 sheet / 对话框）、首次引导，以及屏幕浮层和菜单栏面板。它们各自演进，现在有 4 个问题：
1. 视觉层级、间距、状态色不统一。
2. 编辑器允许改动引擎会忽略的槽位（见「约束归属」），用户保存后不生效。
3. 「未连接 / 缺权限 / 通道故障」只在部分窗体中露出。
4. 不支持 macOS 26 的液态玻璃外观，侧栏也不能收起。

本次在**不改信息架构、不改术语、不改行为**的前提下，重画全部窗体。

**成功标准**：
1. 范围清单中的每一个窗体（见「窗体清单」）都有新设计稿、浅色 / 深色截图和对应的验收行。
2. 侧栏仍为 4 页：按键映射 / 场景配置 / 语音 / 通用。模式与功能名称与现有代码完全一致。
3. 引擎会忽略的槽位显示「🔒 固定」并说明原因，不能再「保存成功但不生效」。
4. 侧栏可通过标题栏按钮和 ⌃⌘S 收起或展开。
5. 在 macOS 26 上，侧栏、工具栏、浮层、菜单栏面板使用液态玻璃。在 macOS 14–15 上，或开启「降低透明度」时，自动回退到不透明材质，信息与布局一致。
6. 浅色 / 深色以及最小窗口下都没有截断和重叠。`config.json` 格式不变，现有映射行为不变。

## 非目标

- 不合并页面：「场景配置」仍是独立的侧栏页，只在原位重画（用户决定 2）。
- 不新增页面：不加「概览」页。状态改进只放进已有界面，即侧栏头、页内横幅、菜单栏面板和体检 sheet（用户决定 3）。
- 不改术语和结构：保留「快捷控制模式 / App 控制模式 / App 导航模式」和「第二功能模式（高级）」折叠区（用户决定 4）。
- 不改默认场景行为（用户决定 5，见「默认场景行为（现状，保持不变）」）。
- 不改按键引擎、手势时序、层语义、基础层保护规则、浮层的触发键与 HintBar 键位，也不改 `config.json` 结构与版本。
- 不引入第三方依赖（零依赖 Swift 6 / SwiftUI，macOS 14+）。液态玻璃只用系统 API。
- **不可接受的结果**：重设计后任何既有映射或浮层行为发生变化，或者用户在新 UI 里能「成功保存」一个引擎不会执行的绑定。

## 术语表（沿用现有代码文案，不改名）

- **全局默认 / 按 App 覆盖**：场景（代码中为 `profile`）。「全局默认」是所有 App 的起点。按 App 覆盖只改需要不同的键，其余继承全局。
- **第二功能模式（高级）**：映射页检查器中的折叠区，标题和说明文字沿用现有代码。区内三行分别是：
  - **快捷控制模式**（层 1，按住 OK）
  - **App 控制模式**（层 2，单击 TV 进出）
  - **App 导航模式**（层 3）
  - 显示名取自 `AppModel.modeDisplayName`。
- **触发方式**：短按 / 长按 / 双击（沿用现有文案「短按」）。
- **来源标签**：「App 覆盖」「继承全局」「🔒 固定」，是新增的展示样式，不是新术语。
- **🔒 固定**：引擎在基础层强制的槽位，`MappingEngine.fireTap` 536–545 行：
  - 方向键短按 = 光标
  - 返回短按 = Delete
  - 全局默认中 OK 短按 = Return，只有 App 场景可显式覆盖
- **液态玻璃（Liquid Glass）**：macOS 26 的半透明折射材质，SwiftUI 中为 `glassEffect`。
- **回退材质**：macOS 14–15 上，或「降低透明度」开启时使用的 `.regularMaterial` / 不透明窗口背景。

## 参与者与适用行为

- **普通用户**：查看和修改映射、管理场景、处理「按了没反应」。
- **重度用户**：维护多个 App 场景与 App 控制模式（AI 批准流），常开着设置窗，需要收起侧栏换取空间。
- **辅助技术用户**：用键盘 / VoiceOver 操作，可能开启「降低透明度」或「增强对比度」。
- **系统（自主触发）**：连接、权限、通道状态与前台 App 变化时，刷新侧栏头、横幅、菜单栏图标与面板、浮层角标。

## 窗体清单（本次全部重画）

| 组 | 窗体 | 代码位置 | 原型 `screen=` |
|---|---|---|---|
| 设置窗口 | 按键映射 | `MappingPage` + `RemoteDiagram` | `mapping` |
| | 场景配置 | `ProfilePage` | `profiles` |
| | 语音 | `VoicePage` | `voice` |
| | 通用 | `GeneralPage` | `general` |
| Sheet / 对话框 | 场景映射详情 | `MappingDetailView` | `sheet-detail` |
| | 预设库 | `ProfilePage` 内 sheet | `sheet-presets` |
| | 从运行中的 App 添加 | `ProfilePage` 内 sheet | `sheet-addapp` |
| | 识别按键 | `MappingPage` 内 sheet | `sheet-keylearn` |
| | 录制快捷键 | `ActionPicker` | `sheet-recorder` |
| | 一键体检与修复 | `HealthCheckSheet` | `sheet-health` |
| | 更新后重新授权 | `RootView` alert | `sheet-reauth` |
| | 删除场景确认 | `ProfilePage` confirmationDialog | `dialog-delete` |
| 首次引导 | 第 1 步 · 授权 / 第 2 步 · BlackHole 虚拟声卡 / 第 3 步 · 配对遥控器 | `OnboardingWizard` | `onb-1` `onb-2` `onb-3` |
| 菜单栏 | 状态面板（popover）+ 状态图标 + 右键菜单 | `StatusItemController` | `menubar` |
| 浮层 | 窗口选择器 window_picker | `OverlayCenter` | `ov-window` |
| | 系统功能菜单 system_menu | `OverlayCenter` | `ov-system` |
| | App 轮盘 app_wheel | `OverlayCenter` | `ov-wheel` |
| | 映射速查 tutorial | `OverlayCenter` + `MappingDetailView` | `ov-tutorial` |
| | App 控制模式 HUD / 模式角标 / 「XX 布局」提示 / HintBar | `OverlayCenter`、`FloatingBadgeController`（`StatusItemController.swift:312`） | `ov-hud`（`state=loading` 显示「XX 布局」闪现） |

## 影响面

- **视觉层**：上表全部窗体。`DesignSystem.swift` 新增两部分：
  - `GlassSurface` 修饰器：macOS 26 用 `glassEffect`，否则用 material 回退；同时读取 `accessibilityReduceTransparency`。
  - 来源标签样式。
- **结构层**：`RootView` 改为 `NavigationSplitView`，或保留现结构，加上 `columnVisibility` 切换与 ⌃⌘S 菜单命令。侧栏仍为 4 项。
- **只读依赖**：`AppModel`、`MappingEngine`。需要抽出一个纯函数 `SlotPolicy` 暴露基础层保护规则，供 UI 与引擎共用。
- **不影响**：BLE / HID / 音频链路、浮层触发与键位、配置格式、默认场景逻辑。

## 已确认的关键决策（来源：用户回答，2026-10-29）

1. **范围 = 所有窗体都要改**：设置页、sheet / 对话框、首次引导、菜单栏面板、全部浮层。
2. **不合并**：「场景配置」保持独立的侧栏页，原位重设计。映射页的场景标签只负责「跳到场景配置」，不提供页内切换。
3. **不新增**：没有「概览」页，侧栏仍是 4 项。状态改进放进侧栏头的问题行、各页横幅、菜单栏面板和体检 sheet。
4. **保留原有术语和结构**：「快捷控制模式 / App 控制模式 / App 导航模式」「第二功能模式（高级）」折叠区、「短按 / 长按 / 双击」、「全局默认 / 按 App 覆盖」都不改。
5. **默认场景按目前行为，不做变更**（详见下节）。
6. **追加要求：侧栏可收起**。标题栏有切换按钮，快捷键 ⌃⌘S，收起形态遵循 macOS `NavigationSplitView` 惯例。
7. **追加要求：支持 macOS 26 液态玻璃**。范围是侧栏、工具栏、浮层、菜单栏面板，并为旧系统和「降低透明度」提供回退。
- 已有项目约束：视觉延续 `mockups/v3-macos.html` 的 macOS 系统设置风格。遥控器一律使用用户指定的画法（`REMOTE_SVG` / `RemoteDiagram`：`.rsvgwrap` / `.rshell` / `.remote-key`），所有出现遥控器的窗体都不另画，包括映射页、识别按键、配对引导第 3 步、映射速查浮层。

## 默认场景行为（现状，保持不变）

基于源码只读分析：
- **启动时**：`AppModel.currentProfile` 初始化为 `"global"`（`AppModel.swift:224`），不持久化。每次启动 App，「正在编辑」的场景都是**全局默认**。
- **进程内保留**：`AppModel` 每个进程只创建一次（`GUIAppDelegate.swift:37`）。关闭再打开设置窗，保留上次选中的场景，退出 App 后才回到全局默认。
- **只有以下 4 处会改变它**：
  - 场景详情里点「编辑映射」，切到该场景并跳到「按键映射」页（`ProfilePage.swift:78`）。
  - 「从运行中的 App 添加」，切到新场景，但**不跳页**（`ProfilePage.swift:214`）。
  - 删除当前正在编辑的场景后，回到全局默认（`ProfilePage.swift:125`）。
  - 导入 JSON 后，回到全局默认（`ProfilePage.swift:159`）。
- **从不使用前台 App 自动选择场景**。前台 App 只影响运行时生效的映射，不影响设置窗正在编辑哪个场景。
- **新设计如何呈现，不改逻辑**：
  - 映射页标题下有一个场景标签（如「Ghostty · 覆盖 10 项 · 其余继承全局」）。标签上的「在场景配置中切换 ›」只跳到「场景配置」页。
  - 场景配置列表中，正在编辑的场景显示「正在编辑」标签，前台 App 显示「● 前台」标签。
  - 副标题沿用原文案：「点击左侧遥控器上的按键…」，或「正在编辑场景「X」的覆盖绑定。」。

## 约束归属与拒绝的解读

| 约束 | 负责边界 | 验证位置 | Scenario |
|---|---|---|---|
| 方向键短按 = 光标、返回短按 = Delete，任何场景都不可改写 | `MappingEngine.fireTap`（`MappingEngine.swift:536-545`）；UI 只读展示 | 纯函数 `SlotPolicy` 的 selfCheck 与引擎对拍 | 「被保护槽位显示为固定」 |
| 全局默认的 OK 短按 = Return，只有 App 场景可显式覆盖 | 同上 | 同上 | 「全局 OK 短按固定，App 场景可覆盖」 |
| 第二功能模式只有短按替代（`KeyBinding.layers` 没有长按 / 双击槽） | `Contracts.KeyBinding` | UI 每个模式只渲染一行 | 「第二功能模式折叠区沿用原结构」 |
| 默认场景逻辑（启动 = 全局默认，只在 4 处改变） | `AppModel` / `ProfilePage` | 回归抽查 | 「启动后正在编辑的是全局默认」 |
| 液态玻璃只在 macOS 26+ 启用；「降低透明度」时一律不透明 | `DesignSystem.GlassSurface` | 截图（26 / 15 / 降低透明度） | 「液态玻璃回退」 |
| 浮层触发键与 HintBar 键位不变 | `OverlayCenter` | 回归抽查 | 各浮层 Scenario |

现状证据：当前 `MappingPage` / `ActionPicker` 对上述槽位不做禁用。在全局场景把 OK 短按改成别的动作，界面会显示「已保存」，但引擎仍发 Return。
**拒绝的解读**：「固定」不等于隐藏，要保留显示并给出原因，否则用户会以为键没配置。「不新增页面」也不允许把概览做成侧栏里的第 5 项，或做成一个弹窗页。

## 取代与共存

- 目标仓库没有 `.spec-dev/` 目录，**也没有相交的 active spec**。
- 非 spec 的先例：`DESIGN.md` §6 的页面结构（4 页）保持不变；`mockups/v3-macos.html` 的视觉方向被本设计延续并扩展到全部窗体。批准后，实施阶段同步更新 DESIGN.md 的视觉章节，不登记 `supersedes`。

## 方案对比

| | A. 统一视觉体系 + 原位重画（**推荐**） | B. 只换皮 | C. 先做设置窗，浮层另开 spec |
|---|---|---|---|
| 做法 | 抽出 `GlassSurface`、来源标签、横幅、HintBar 等共享组件，全部窗体原位重画；结构、术语、行为不变 | 只调颜色 / 圆角 / 间距 | 先完成 4 页 + sheet，浮层、引导、菜单栏下一期 |
| 符合用户决定 1–5 | ✅ | ⚠️ 不能解决「🔒 固定」与状态露出 | ❌ 违背决定 1 |
| 液态玻璃 / 侧栏收起 | ✅ 一处实现，全窗体复用 | ⚠️ 各窗体分别处理 | ⚠️ 分两期 |
| 风险 | 改动面广 → 按窗体组切片交付（设置窗 → sheet → 引导 → 菜单栏 → 浮层） | 痛点残留 | 两期之间风格不一致 |

推荐 A，按上述顺序切片交付。

## MODIFIED Requirements

### Requirement: 设置窗外壳（侧栏 4 页 + 侧栏头状态）（改：原侧栏头只显示电量）

设置窗 SHALL 保持 4 个侧栏项：按键映射 / 场景配置 / 语音 / 通用，顺序与图标沿用现状。侧栏头 SHALL 显示遥控器名称、连接状态与电量。当存在「缺输入监控 / 辅助功能权限」「按键通道异常」「遥控器未连接」之一时，侧栏头下方 SHALL 出现一行问题提示，点击可直达修复入口，分别是体检 sheet 或配对引导。优先级：通道故障 > 缺权限 > 未连接。

#### Scenario: 侧栏仍为 4 项
- **GIVEN** 任意状态
- **WHEN** 打开设置窗
- **THEN** 侧栏只有「按键映射、场景配置、语音、通用」4 项，没有「概览」

#### Scenario: 缺权限时侧栏出现问题行
- **GIVEN** 输入监控未授权
- **WHEN** 打开设置窗
- **THEN** 侧栏头下出现「⚠️ 缺少输入监控权限 · 修复」，点击打开「一键体检与修复」sheet

### Requirement: 按键映射页（改：视觉与来源标签；结构不变）

映射页 SHALL 沿用现有结构：标题 + 原副标题文案 + 「已保存」+「识别按键」，左侧遥控器示意图（用户指定的 `REMOTE_SVG` 画法），右侧键检查器。检查器分三组：「触发方式 短按 / 长按 / 双击」、OK 手势组、「第二功能模式（高级）· 已设置 n/3」折叠区，折叠区内为「模式开启时，这个键执行」+ 3 行原模式名。新增的展示内容只有以下几项：
- 13 键标注（显示当前短按动作）
- 来源标签（App 覆盖 / 继承全局 / 🔒 固定）
- 场景标签：只读，带「在场景配置中切换 ›」跳转
- 示意图上方的「示意图显示」分段（短按 / 快捷控制 / App 控制 / App 导航）：只改变标注显示哪一层，不改变编辑对象

#### Scenario: App 场景中继承与覆盖并存
- **GIVEN** 正在编辑 Ghostty 场景（覆盖 10 项）
- **WHEN** 查看映射页
- **THEN** 被覆盖的键标注为强调色，未覆盖的键为「继承全局」样式（虚线引线），方向键与返回键带 🔒；副标题为「正在编辑场景「Ghostty」的覆盖绑定。」

#### Scenario: 场景标签只跳转不切换
- **GIVEN** 映射页正在编辑全局默认
- **WHEN** 用户点击场景标签上的「在场景配置中切换 ›」
- **THEN** 侧栏选中「场景配置」页，正在编辑的场景不变

#### Scenario: 第二功能模式折叠区沿用原结构
- **GIVEN** 选中 OK 键
- **WHEN** 用户展开「第二功能模式（高级）」
- **THEN** 依次显示原说明文字、「模式开启时，这个键执行」以及「快捷控制模式 / App 控制模式 / App 导航模式」3 行，每行一个短按动作；未设置的显示「回落到短按」

#### Scenario: 窄窗口降级
- **GIVEN** 窗口为最小尺寸
- **WHEN** 映射页渲染
- **THEN** 隐藏标注与引线，只保留遥控器与检查器，没有文字重叠或水平滚动

### Requirement: 场景配置页（改：视觉、标签与空状态；仍为独立页）

场景配置页 SHALL 包含以下内容：
- 「全局默认」行
- 「按 App 覆盖」列表：每行显示 App 图标、名称、「继承全局 · 已覆盖 n 项（键名…）」，以及「● 前台」「正在编辑」标签和「编辑映射」按钮（不新增搜索等控件）
- 底部操作：从运行中的 App 添加 / 预设库… / 导入 JSON… / 导出 JSON
- 刚套用过预设时，顶部显示「撤销本次套用」横幅

点击行 SHALL 打开「场景映射详情」sheet。

#### Scenario: 编辑映射跳转
- **GIVEN** 场景配置页
- **WHEN** 用户点击 Claude 行的「编辑映射」
- **THEN** 正在编辑的场景变为 Claude，并跳到按键映射页（与 `ProfilePage.swift:78` 现行为一致）

#### Scenario: 没有任何 App 覆盖
- **GIVEN** 配置中只有全局默认
- **WHEN** 打开场景配置页
- **THEN** 列表区显示「还没有按 App 的覆盖」的说明，以及「从运行中的 App 添加」「浏览预设库」两个入口

### Requirement: 语音页（改：视觉与状态；结构不变）

语音页 SHALL 沿用以下结构：输入方式（遥控器麦克风 / Mac 麦克风 / 关闭）、链路自检 4 项、实时电平、按 App 的语音快捷键、豆包输入法设置步骤（折叠）。自检失败项 SHALL 带「修复」按钮。检测中显示「检测中…」，不显示过期结果。

#### Scenario: 未装 BlackHole
- **GIVEN** BlackHole 2ch 未安装
- **WHEN** 打开语音页
- **THEN** 顶部出现原文案「BlackHole 未安装，遥控器麦克风模式不可用」的横幅和「安装引导」按钮（打开引导第 2 步），自检对应项为警告色

### Requirement: 通用页（改：视觉；结构不变）

通用页 SHALL 沿用以下分组：启动 / 显示与反馈 / 按键手感 / 关于与诊断 / 危险操作。滑杆行 SHALL 显示默认值与「恢复」。「退出」「卸载」SHALL 使用危险色，并与普通操作分组隔开。

#### Scenario: 恢复默认手感
- **GIVEN** 长按判定被改为 500 ms
- **WHEN** 用户点击该行「恢复」
- **THEN** 值回到 350 ms，并即时生效

### Requirement: Sheet 与对话框统一样式

以下窗体 SHALL 使用统一的 sheet 骨架：标题、副标题、正文、底部操作区（左侧说明 + 右侧按钮，主按钮在最右）。
- 场景映射详情：只读表格，列为 按键 / 短按 / 长按 / 双击 / 3 个模式；本场景值用强调色，固定值带 🔒
- 预设库：预设列表、「建议应用到」、套用方式「仅填空位（推荐，保护已有绑定）/ 全部覆盖（预设优先）」、变化预览「新增 n / 冲突 n / 🔒 跳过 n」
- 从运行中的 App 添加
- 识别按键：用 `REMOTE_SVG` 高亮识别到的键
- 录制快捷键：提示冲突
- 一键体检与修复：6 项，按钮为 重新体检 / 退出并重新打开 / 尝试自动修复
- 更新后重新授权：稍后再说 / 重启 App 生效
- 删除场景确认

破坏性操作 SHALL 使用危险色，并且不能是默认按钮。

#### Scenario: 预设套用预览
- **GIVEN** Ghostty 已有 9 项覆盖
- **WHEN** 打开预设库并选择「AI 终端 · 仅填空位」
- **THEN** 预览显示「新增 4 / 冲突 2（保留现有）/ 🔒 跳过 1」，主按钮为「套用到 Ghostty」

#### Scenario: 删除场景需确认
- **GIVEN** 存在 Ghostty 场景且正在编辑它
- **WHEN** 用户选择删除
- **THEN** 确认框说明覆盖项数和「删除后切回全局默认」；点取消则不变，点删除后正在编辑的场景变为全局默认（现行为）

#### Scenario: 识别按键等待与完成
- **GIVEN** 打开识别按键 sheet
- **WHEN** 尚未按键
- **THEN** 显示「请按一下遥控器上的任意键…」，「选中这个键」按钮不可用；按下菜单键后，示意图高亮菜单键，按钮可用，点击后跳到映射页并选中该键

### Requirement: 首次引导三步（改：视觉；步骤与文案不变）

引导 SHALL 保持 3 步：授权（蓝牙 / 输入监控 / 辅助功能）、BlackHole 虚拟声卡、配对遥控器。顶部显示步骤指示（已完成 ✓ / 当前 / 未到）。第 3 步 SHALL 用 `REMOTE_SVG` 示意「主页 + 返回」两键同时长按（脉冲高亮），并显示原文案「正在等待遥控器出现…」与排障提示。引导 SHALL 可从「通用 › 诊断」重新运行。

#### Scenario: 配对等待中
- **GIVEN** 第 3 步尚未发现遥控器
- **WHEN** 引导持续显示
- **THEN** 显示「正在等待遥控器出现…」与原排障提示（指示灯快速闪烁 = 配对模式…），不自动关闭、不新增超时逻辑；发现后显示「已连接」

### Requirement: 菜单栏状态图标与面板（改：视觉；信息不变）

状态图标 SHALL 沿用现有优先级：故障（红）> 语音 > 鼠标 > 层 > 未连接（变暗）> 空闲。左键面板 SHALL 显示以下内容：
- 遥控器名称、电量环，以及原 statusLine 文案：「未连接 · 长按 主页+返回 配对」/「已连接 · 已暂停遥控」/「已连接 · 空闲」等
- 遥控开关
- 有问题时的修复横幅
- 当前生效场景与语音链路摘要
- 「打开设置窗口」「一键体检与修复…」「退出 MiRemote」

右键菜单 SHALL 保持原 3 项。

#### Scenario: 未连接时的面板
- **GIVEN** 遥控器未连接
- **WHEN** 用户左键点击菜单栏图标
- **THEN** 图标变暗；面板显示「未连接 · 长按 主页+返回 配对」，电量环为空

### Requirement: 屏幕浮层（改：视觉；触发、键位与 HintBar 文案不变）

窗口选择器、系统功能菜单、App 轮盘、映射速查、App 控制模式 HUD、模式角标、「XX 布局」提示 SHALL 使用统一的浮层外观：玻璃材质、选中项强调描边、底部 HintBar 键帽样式。HintBar 文案 SHALL 与现状一致：
- 窗口选择器：选窗（按住加速）/ 全局 → 当前 → 关闭 / 前往 / 关闭
- 系统功能菜单：选择 / 执行 · 红色项按住 / 关闭
- App 轮盘：选 App / 切换 / 取消
- 映射速查：关闭教程

系统功能菜单的红色项 SHALL 显示按住进度条。映射速查 SHALL 用缩小的 `REMOTE_SVG` 配映射表。「XX 布局」提示 SHALL 显示 1.2 s。

#### Scenario: 系统菜单红色项按住执行
- **GIVEN** 系统功能菜单打开，选中「睡眠」
- **WHEN** 用户按住 OK
- **THEN** 该项下方进度条前进，满 1 秒后执行；中途松开则不执行

#### Scenario: 进入 App 控制模式
- **GIVEN** 前台为 Ghostty
- **WHEN** 用户单击 TV
- **THEN** 右上角出现「App 控制模式 · Ghostty」HUD（列出 OK / 音量− / 菜单 / ↑↓ / TV 的作用），屏幕角落出现角标「App 控制 · Ghostty」

## ADDED Requirements

### Requirement: 被保护槽位显示为固定且不可编辑

对引擎会忽略的槽位，检查器 SHALL 显示「🔒 固定」标签、固定值和一句原因，不提供 ActionPicker。遥控器标注 SHALL 在键名后加 🔒。

#### Scenario: 被保护槽位显示为固定
- **GIVEN** 任一场景
- **WHEN** 用户选中返回键
- **THEN** 短按槽位显示「🔒 固定 · Delete 删除」及原因，没有下拉；长按 / 双击仍可编辑

#### Scenario: 全局 OK 短按固定，App 场景可覆盖
- **GIVEN** 正在编辑全局默认
- **WHEN** 用户选中 OK 键
- **THEN** 短按为固定 Return，说明「全局 OK 短按固定为 Return；只有 App 场景可显式覆盖」；切到 Ghostty 场景后同一槽位可编辑，显示「App 覆盖 · Return 确认」

#### Scenario: 旧配置中已存在被保护槽位的值
- **GIVEN** config.json 的 global 中 OK 短按 = Spotlight（旧 UI 可以写入）
- **WHEN** 打开映射页
- **THEN** 槽位仍显示固定 Return，并提示「配置中的 Spotlight 不会生效」，配置文件不被自动改写

### Requirement: App 场景槽位显示来源并可恢复继承

在 App 场景中，每个可编辑槽位 SHALL 显示来源标签（App 覆盖 / 继承全局）。对「App 覆盖」的值 SHALL 提供「↺ 恢复」，执行后该槽位回到全局值，覆盖计数减 1。

#### Scenario: 恢复继承
- **GIVEN** Ghostty 场景覆盖了主页短按 = ⌃C 中断
- **WHEN** 用户点击该槽位的「↺ 恢复」
- **THEN** 槽位显示「继承全局 · 显示桌面」，场景标签的覆盖数减 1，并显示「✓ 已保存」

### Requirement: 侧栏可收起（⌃⌘S）

设置窗标题栏 / 工具栏 SHALL 有侧栏切换按钮（SF Symbol `sidebar.left`）。主菜单 SHALL 新增「显示 › 隐藏边栏 / 显示边栏」，快捷键 ⌃⌘S。现在主菜单由 `GUIAppDelegate` 手工构建，没有「显示」菜单。收起形态 SHALL 遵循 `NavigationSplitView` 惯例，即完全隐藏（`columnVisibility = .detailOnly`），不使用仅图标栏。

侧栏隐藏时：
- 标题栏 SHALL 显示当前页名，避免用户失去位置感
- 详情区 SHALL 占满宽度
- 侧栏头的问题行 SHALL 不丢失，它对应的横幅仍在页内显示

窗口宽度小于侧栏 + 详情最小宽度时，系统可以自动收起侧栏，用户随时可以再展开。

#### Scenario: 用按钮收起和展开
- **GIVEN** 侧栏展开，当前页为按键映射
- **WHEN** 用户点击标题栏侧栏按钮
- **THEN** 侧栏以系统动画滑出隐藏，标题显示「按键映射」，检查器变宽；再点一次恢复，选中页不变

#### Scenario: 用 ⌃⌘S 切换
- **GIVEN** 设置窗为前台 key window
- **WHEN** 用户按 ⌃⌘S
- **THEN** 侧栏在展开与隐藏之间切换，菜单项标题随之在「隐藏边栏 / 显示边栏」间切换

#### Scenario: 收起时仍能看到问题
- **GIVEN** 侧栏已隐藏且缺少输入监控权限
- **WHEN** 查看映射页
- **THEN** 页顶横幅「缺少输入监控权限 · 一键体检与修复」仍可见

#### Scenario: 减少动态效果
- **GIVEN** 系统开启「减少动态效果」
- **WHEN** 切换侧栏
- **THEN** 不播放滑动动画，直接切换

### Requirement: macOS 26 液态玻璃与回退

在 macOS 26 及以上，以下表面 SHALL 使用系统液态玻璃（`glassEffect` / 系统默认的玻璃侧栏与工具栏）：
- 设置窗侧栏（浮起的圆角玻璃面板）
- 标题栏 / 工具栏和其中的按钮（胶囊玻璃按钮）
- 分段控件
- sheet
- 菜单栏面板
- 全部浮层（窗口选择器、系统功能菜单、App 轮盘、映射速查、HUD、角标、HintBar）

内容区（表单分组、遥控器面板、表格）SHALL 保持高不透明度，以保证正文对比度不低于 WCAG AA。

以下情况 SHALL 回退：
- macOS 14–15：用 `.regularMaterial` / `.ultraThinMaterial` 加现有阴影。
- 「降低透明度」开启（`accessibilityReduceTransparency`），任何系统版本：用不透明的窗口背景色，保留圆角、层级与描边。

三种外观的信息、布局、命中区域 SHALL 完全一致。玻璃的实现 SHALL 集中在一个修饰器 `GlassSurface` 中，窗体不得各自判断系统版本。

#### Scenario: macOS 26 上的设置窗
- **GIVEN** macOS 26，彩色壁纸
- **WHEN** 打开设置窗
- **THEN** 侧栏为浮起的圆角玻璃面板，能透出并折射下方颜色，边缘有高光；工具栏按钮为胶囊玻璃；正文区可读

#### Scenario: 液态玻璃回退（旧系统）
- **GIVEN** macOS 15
- **WHEN** 打开设置窗与任一浮层
- **THEN** 使用毛玻璃材质（不折射），布局与 macOS 26 相同，没有 API 不可用导致的崩溃或空白

#### Scenario: 液态玻璃回退（降低透明度）
- **GIVEN** 任意系统版本开启「降低透明度」
- **WHEN** 打开窗口选择器浮层
- **THEN** 浮层背景不透明，选中描边与 HintBar 仍清晰，文字对比度 ≥ 4.5:1

#### Scenario: 深色模式下的玻璃
- **GIVEN** macOS 26 深色外观
- **WHEN** 打开系统功能菜单
- **THEN** 玻璃为深色调，红色项、选中项、HintBar 键帽均可辨识

### Requirement: 无障碍与主题

所有控件 SHALL 可用 Tab / 方向键到达，并有 VoiceOver 标签。遥控器标注读作「<键名>，<触发方式或模式>，<动作>，<来源>」。浅色与深色下正文对比度 SHALL ≥ 4.5:1。「减少动态效果」开启时 SHALL 关闭弹簧与脉冲动画，配对引导的脉冲改为静态高亮。

#### Scenario: 仅用键盘编辑一个键
- **GIVEN** 焦点在侧栏
- **WHEN** 用户 Tab 到遥控器图，用方向键选到 OK，回车打开长按槽位的动作选择
- **THEN** 不用鼠标即可完成选择并保存

### Requirement: 默认场景行为保持不变（回归保护）

重设计 SHALL NOT 改变「正在编辑的场景」的初始值与变更点（见「默认场景行为（现状，保持不变）」）。新增的场景标签、「正在编辑」「● 前台」标签只用于展示。

#### Scenario: 启动后正在编辑的是全局默认
- **GIVEN** 上次退出前正在编辑 Ghostty
- **WHEN** 重新启动 App 并打开设置窗
- **THEN** 映射页显示全局默认；场景配置页中「正在编辑」标签在「全局默认」行，即使前台是 Ghostty

#### Scenario: 关闭再打开窗口保留选择
- **GIVEN** 本次进程中正在编辑 Claude
- **WHEN** 关闭设置窗后从菜单栏再次打开
- **THEN** 仍在编辑 Claude

#### Scenario: 添加 App 不跳页
- **GIVEN** 场景配置页
- **WHEN** 通过「从运行中的 App 添加」添加 Visual Studio Code
- **THEN** 正在编辑的场景变为 Visual Studio Code，页面仍停在场景配置页

## REMOVED Requirements

无。（第 1 版草稿中的「合并场景配置页」「新增概览页」「模式改名 / 一级模式分段」「表格视图」均已撤回，现状行为保持不变，不构成 REMOVED。）

## 设计

### 组件与接口（只定义边界，不写实现计划）

| 组件 | 职责 | 消费方 |
|---|---|---|
| `GlassSurface(kind: .sidebar/.toolbar/.sheet/.panel/.overlay/.chip)` | 唯一判断 macOS 26 / 14–15 / 降低透明度，输出玻璃、材质或不透明背景 | 全部窗体 |
| `SlotPolicy.isLocked(key, trigger, profile) -> LockReason?` | 纯函数，和 `MappingEngine.fireTap` 的保护规则同源 | 检查器、标注、预设预览、映射详情 |
| `SlotResolver.resolve(key, trigger, layer, profile) -> (action, source)` | 来源：appOverride / inherited / locked / unset | 检查器、标注、速查浮层 |
| `SourceTag` / `SceneChip` / `StatusBanner` / `HintBar` | 共享展示组件 | 映射页、场景页、语音页、菜单栏、浮层 |
| `RemoteDiagram(mode: .editor/.compact/.pairing/.learn)` | 统一沿用 `REMOTE_SVG` 画法，只按尺寸缩放 | 映射页、识别按键、引导第 3 步、映射速查 |
| 侧栏可见性 | `NavigationSplitView(columnVisibility:)` + 工具栏 `sidebar.left` 按钮 + 主菜单「显示 › 隐藏边栏 ⌃⌘S」 | RootView、GUIAppDelegate 菜单 |

### 错误与边界

错误处理逻辑沿用现状（本次不新增错误分支），只统一呈现方式：
- 已有的失败、警告信息（体检失败项、BlackHole 未安装、缺权限、未连接）统一用 `StatusBanner` 或带「修复」的行内提示。
- 浮层没有内容时沿用现有处理，只换外观。
- App 图标取不到时，退回首字母圆形占位（纯展示）。

## 原型参照

| 项 | 内容 |
|---|---|
| 文件 | `spec/assets/prototype-v2.html`（= `index.html`，单文件、离线可开）。`prototype-v1.html` 为第 1 版（含用户改过的遥控器画法），只作参照，**已被 v2 取代** |
| URL 参数 | `screen=<见窗体清单>&scene=global\|ghostty\|claude\|chrome\|wechat\|iina\|feishu&key=<键 id：power/voice/up/down/left/right/ok/back/home/menu/tv>&state=ok\|disc\|perm\|degraded\|layer\|empty\|loading\|paused&lbl=base\|1\|2\|3&adv=0\|1&side=open\|hidden&glass=on\|off\|rt&theme=light\|dark&width=wide\|narrow`；加 `shot=1` 隐藏开发栏 |
| 开发栏 | 窗体、场景、状态、示意图显示、第二功能模式展开、侧栏、玻璃（on = macOS 26 / off = 14–15 / rt = 降低透明度）、主题、宽度；按 ⌃⌘S 切换侧栏 |
| 模拟边界 | 所有数据为假数据：遥控器状态、场景、覆盖数、体检结果、电量、前台 App。玻璃用 CSS `backdrop-filter` 与高光模拟，不代表 macOS 26 的真实折射。原型中的设置窗宽度（1120）只为截图清晰，不规定窗口尺寸 |
| 截图 | `spec/assets/screenshots/` 共 30 张：每个窗体的浅色图（01–21）+ 深色图（22–24）+ 侧栏隐藏（25）+ 玻璃关闭 / 降低透明度（26–27）+ 未连接 / 空状态 / 窄窗（28–30） |
| 未在原型中展示 | 「保存失败」、旧配置「不会生效」提示、VoiceOver 朗读、减少动态效果 |
| 未确认 | 见 open-questions.md 的 N1–N3 |

## 测试放置声明

本 spec 不改 app 代码。实施阶段：
- `SlotPolicy` / `SlotResolver` 是纯函数，放在 `Sources/MiRemote/Mapping/` 旁边，用仓库现有的 selfCheck 方式与 `MappingEngine` 对拍。
- 视觉与交互用截图验收，加人工在 macOS 26 / 15 两台机器上检查。
- 仓库没有 UI 测试 target，本 spec 不新建。

## 验收矩阵

| Scenario | 维度 | 执行方式 | required | Lane | 验收证据 |
|---|---|---|---|---|---|
| 侧栏仍为 4 项 | 结构 | 人工 + 截图 01 | ✅ | 设置窗 | 截图 |
| 缺权限时侧栏出现问题行 | 状态 | 人工 + 截图 10 | ✅ | 设置窗 | 截图 |
| App 场景中继承与覆盖并存 | 视觉 | 截图 22 | ✅ | 设置窗 | 截图 |
| 场景标签只跳转不切换 | 行为 | 人工 | ✅ | 设置窗 | 录屏 |
| 第二功能模式折叠区沿用原结构 | 结构 | 截图 01（adv=1） | ✅ | 设置窗 | 截图 |
| 窄窗口降级 | 布局 | 截图 30 | ✅ | 设置窗 | 截图 |
| 编辑映射跳转 / 添加 App 不跳页 | 行为（回归） | 人工 | ✅ | 设置窗 | 录屏 |
| 没有任何 App 覆盖 | 状态 | 截图 29 | ✅ | 设置窗 | 截图 |
| 未装 BlackHole | 状态 | 人工 | ✅ | 设置窗 | 截图 |
| 恢复默认手感 | 行为 | 人工 | ✅ | 设置窗 | 录屏 |
| 预设套用预览 | 行为 | 截图 06 + 人工 | ✅ | Sheet | 截图 |
| 删除场景需确认 | 行为（回归） | 截图 12 + 人工 | ✅ | Sheet | 截图 |
| 识别按键等待与完成 | 行为 | 截图 08 + 人工 | ✅ | Sheet | 录屏 |
| 场景映射详情 / 添加 App / 录制 / 体检 / 重新授权 | 视觉 | 截图 05、07、09、10、11 | ✅ | Sheet | 截图 |
| 引导三步 + 配对等待中 | 视觉 / 状态 | 截图 13–15 + 人工 | ✅ | 引导 | 截图 |
| 未连接时的面板 | 状态 | 截图 16 / 24 + 人工 | ✅ | 菜单栏 | 截图 |
| 系统菜单红色项按住执行 | 行为（回归） | 截图 18 + 人工 | ✅ | 浮层 | 录屏 |
| 进入 App 控制模式 | 行为（回归） | 截图 21 + 人工 | ✅ | 浮层 | 录屏 |
| 窗口选择器 / App 轮盘 / 映射速查 HintBar 文案不变 | 回归 | 截图 17、19、20 与现状对照 | ✅ | 浮层 | 截图对照 |
| 被保护槽位显示为固定 | 规则 | `SlotPolicy` selfCheck + 截图 | ✅ | 规则 | 测试输出 |
| 全局 OK 短按固定，App 场景可覆盖 | 规则 | selfCheck + 人工 | ✅ | 规则 | 测试输出 |
| 旧配置中已存在被保护槽位的值 | 规则 | selfCheck（fixture config）+ 人工 | ✅ | 规则 | 测试输出 |
| 恢复继承 | 行为 | 人工 | ✅ | 设置窗 | 录屏 |
| 用按钮收起和展开 | 行为 | 截图 25 + 人工 | ✅ | 侧栏 | 录屏 |
| 用 ⌃⌘S 切换 | 行为 | 人工 | ✅ | 侧栏 | 录屏 |
| 收起时仍能看到问题 | 状态 | 人工（side=hidden&state=perm） | ✅ | 侧栏 | 截图 |
| 减少动态效果 | a11y | 人工 | ⬜ | 侧栏 | 录屏 |
| macOS 26 上的设置窗 | 视觉 | 截图 01（glass=on）+ macOS 26 实机 | ✅ | 玻璃 | 截图 |
| 液态玻璃回退（旧系统） | 兼容 | 截图 26 + macOS 15 实机 | ✅ | 玻璃 | 截图 |
| 液态玻璃回退（降低透明度） | a11y | 截图 27 + 对比度检测 | ✅ | 玻璃 | 截图 + 对比度值 |
| 深色模式下的玻璃 | 视觉 | 截图 23 | ✅ | 玻璃 | 截图 |
| 仅用键盘编辑一个键 | a11y | 人工 | ✅ | a11y | 录屏 |
| 启动后正在编辑的是全局默认 | 回归 | 人工 | ✅ | 回归 | 录屏 |
| 关闭再打开窗口保留选择 | 回归 | 人工 | ✅ | 回归 | 录屏 |

## 风险

- **玻璃在花哨壁纸上可读性下降**：内容区保持高不透明度；浮层用 `.regular` 而不是 `.clear` 玻璃；以降低透明度截图为底线。
- **macOS 14 上没有 `glassEffect` API**：全部经 `GlassSurface` 加 `if #available(macOS 26, *)`，CI 用 14 SDK 下限编译。
- **规则漂移**：`SlotPolicy` 与 `fireTap` 不同源时会显示错误的 🔒，所以用 selfCheck 对拍。
- **改动面广**：按「设置窗 → sheet → 引导 → 菜单栏 → 浮层」切片，每片可以单独发布。
- **⌃⌘S 冲突**：系统与常见 App 的「显示边栏」都用 ⌃⌘S，与 MiRemote 自己的全局快捷键不冲突。只有设置窗为 key window 时才生效。

<HARD-GATE>
本 spec 为 DRAFT。在用户确认 open-questions.md 的 N1–N3（或接受默认值）并将 status 改为 approved 之前，不得编写实施计划或修改 app 代码。
</HARD-GATE>

待确认问题见 `open-questions.md`。
