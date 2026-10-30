# Acceptance Report: settings-ui-redesign（设置界面重设计）

> Time: 2026-10-29（Asia/Singapore） | Trigger: workflow（executing-plans T20） | Scope: T01–T18 全部实施提交，spec「验收矩阵」全部行
> Spec: `.spec-dev/2026-10-29-01-settings-ui-redesign/spec/settings-ui-redesign-design.md`
> Prototype: `spec/assets/prototype-v2.html`；定稿截图 `spec/assets/screenshots/` 01–53
> Runtime: 受测候选 `a460f53`（含 T01–T18 全部实施 SHA，逐个 `git merge-base --is-ancestor` 已核对）；GitHub Actions 工作流 400445702，runner `xcode-27`（Xcode 27.1，Apple Swift 6.4，macOS 27.0.1）；命令 `./build.sh && .build/miremote --self-test`

## Result

**未完成（自动部分全部通过，人工 / 截图 / 实机部分待用户验收）。**

- 自动部分：final 运行 [40858379811](https://github.com/FlameMida/mi_remote_control/actions/runs/40858379811) 构建成功，self-test 末行 `SELF-TEST PASS`，计划新增的 11 个 selfCheck 全部 `ok`（见 Business Evidence）。液态玻璃分支（`#if compiler(>=6.2)` + macOS 26）在 Swift 6.4 / macOS 27 SDK 下实际编译通过，满足 D4 的「新 SDK 编入玻璃分支」。
- 人工部分：执行环境为 Linux，无法运行 macOS App、截图或连接实机，验收矩阵中所有「人工 / 截图 / 录屏 / 实机 / 对比度取色」行均为 manual-pending，交用户在 macOS 26 与 macOS 14/15 实机上验收。required 行不以 manual-pending 冒充 pass。
- 「旧 SDK 可编译」（spec 风险第 2 条，Swift < 6.2）未验证：CI 只有 xcode-27 镜像。

## Prototype / Behavior Comparison

Status 取值：pass（已有自动证据且该行无人工部分）/ auto-pass + manual-pending（自动部分通过，截图或人工部分待验）/ manual-pending。

| Scenario | Required | 目标票 | 期望 | Status | Evidence |
|---|---|---|---|---|---|
| 侧栏仍为 4 项 | true | T05 | 4 项，顺序、图标同现状 | manual-pending | 截图 01 |
| 缺权限时侧栏出现问题行 | true | T07 | 缺辅助功能时出现问题行，点击进入修复（需先切走再切回窗口刷新） | auto-pass + manual-pending | selfCheck「问题优先级与横幅过滤」；截图 10 |
| App 场景中继承与覆盖并存 | true | T09、T10 | 继承行灰显带「全局」，覆盖行带场景来源 | auto-pass + manual-pending | selfCheck「SlotResolver 来源与恢复继承」；截图 22 |
| 场景标签只跳转不切换 | true | T09 | 点标签跳到场景页对应行，当前编辑场景不变 | manual-pending | 录屏 |
| 第二功能模式折叠区沿用原结构 | true | T09 | 折叠区结构、顺序同现状 | manual-pending | 截图 01（adv=1） |
| 窄窗口降级 | true | T10 | 示意图与列表不重叠，标题不断词 | auto-pass + manual-pending | selfCheck「遥控器标注布局与键盘顺序」；截图 30 |
| 编辑映射跳转 / 添加 App 不跳页 | true | T09、T11 | 编辑映射跳到映射页；添加 App 后停留场景页 | manual-pending | 录屏 |
| 没有任何 App 覆盖 | true | T11 | 空态说明与添加入口 | manual-pending | 截图 29 |
| 未装 BlackHole | true | T13 | 警告横幅与「安装引导」（打开引导第 2 步） | manual-pending | 截图 |
| 恢复默认手感 | true | T14 | 恢复后 350 / 250 ms；等于默认时禁用 | auto-pass + manual-pending | selfCheck「按键手感恢复默认」；录屏 |
| 预设套用预览 | true | T11 | 套用前显示将改动的键与条数 | manual-pending | 截图 06 |
| 删除 App 专用方案立即生效 | true | T11 | 删除后前台 App 立即回落全局 | manual-pending | 截图 12 + 录屏 |
| 识别按键等待与完成 | true | T15、T08 | 等待态与完成态文案、示意图高亮 | manual-pending | 截图 08 |
| 场景映射详情 / 添加 App / 录制 / 体检 / 重新授权 | true | T12、T11、T15 | 统一 SheetScaffold 外观 | manual-pending | 截图 05、07、09、10、11 |
| 引导三步 + 配对等待中 | true | T16 | 三步指示、脉冲高亮；减弱动态效果时静态高亮；VoiceOver 读「第 N 步，共 3 步」 | manual-pending | 截图 13–15 |
| 未连接时的面板 | true | T17 | 设备名回退、状态行；16/24/34/35 各状态 | manual-pending | 截图 33、16、24、34、35 |
| 右键兜底菜单 | true | T17 | 菜单项与顺序同现状（类方法列表改前改后一致，已静态核对） | manual-pending | 截图 36 |
| 系统菜单红色项按住执行 | true | T18 | 0.6 s 环满执行，中途松开取消 | manual-pending | 截图 18 + 录屏 |
| 进入 App 控制模式 | true | T17、T18 | HUD 宽 240，末行「TV · 退出控制模式」，角标玻璃胶囊 | manual-pending | 截图 21 + 录屏 |
| 窗口选择器 / App 轮盘 / 映射速查 HintBar 文案不变 | true | T18 | 文案逐字同现状（回归守卫 rg 改前改后命中一致） | manual-pending | 截图 17、19、20 |
| 返回键短按显示说明且可编辑 | true | T02、T09 | 说明句逐字同 spec，仍可编辑 | auto-pass + manual-pending | selfCheck「BaseTapNote 文案」「BaseTapNote 与 fireTap 对拍」；截图 31 |
| 全局默认中 OK 短按的说明 | true | T02、T09 | 同上 | auto-pass + manual-pending | 同上；截图 01 |
| App 场景中 OK 短按的说明 | true | T02、T09 | 同上 | auto-pass + manual-pending | 同上；截图 22 |
| 旧配置中的值不被改写 | true | 全部 | fixture 读写前后一致 | auto-pass + manual-pending | 既有 selfCheck「旧配置 JSON 向后兼容」「Action JSON 往返」通过；本计划未新增字节级 fixture 断言，按字节一致需人工核对 config.json |
| 恢复继承 | true | T09 | 删除覆盖后回到继承显示 | auto-pass + manual-pending | selfCheck「SlotResolver 来源与恢复继承」；录屏 |
| 用按钮收起和展开 | true | T06 | 收起为 .detailOnly 再展开，宽度复原 | auto-pass + manual-pending | selfCheck「侧栏收起状态映射」；截图 25 |
| 用 ⌃⌘S 切换 | true | T06 | 菜单项标题随状态变化 | manual-pending | 录屏 |
| 收起时仍能看到问题 | true | T06、T07 | 侧栏收起时页内横幅显示问题 | auto-pass + manual-pending | selfCheck「问题优先级与横幅过滤」；截图 |
| 减少动态效果 | false | T06、T16 | 无弹簧与脉冲 | manual-pending | 录屏 |
| macOS 26 上的设置窗 | true | T01（D4） | macOS 26 实机为液态玻璃 | manual-pending（玻璃分支已在新 SDK 编译） | 截图 01（glass=on） |
| 液态玻璃回退（旧系统） | true | T01 | macOS 15 为材质回退，无崩溃或空白 | auto-pass + manual-pending | selfCheck「GlassSurface 外观选择」；截图 26 |
| 液态玻璃回退（降低透明度） | true | T01、T18 | 不透明底，正文对比度 >= 4.5:1 | auto-pass + manual-pending | 同上；截图 27 + 取色值 |
| 深色模式下的玻璃 | true | T17、T18 | 深色下文字可读 | manual-pending | 截图 23 |
| 默认配置不显示手势组 | true | T09 | 不出现手势组 | manual-pending | 截图 01 |
| 已绑定手势时显示 4 行 | true | T09 | 显示 4 行 | manual-pending | 截图 32 |
| 清空全部手势后组消失 | true | T09 | 清空后立即消失 | manual-pending | 录屏 |
| App 场景不继承显示 | true | T09、T12 | App 场景不显示全局手势继承行 | manual-pending | 截图 |
| 电量 82% 时的侧栏头 | true | T05 | 连续填充约 82%，「电量 82%」不断行 | auto-pass + manual-pending | selfCheck「侧栏头三行与电量」；截图 37 / 01 |
| 连接过程中头部不跳变 | true | T05 | 14 种状态头部高度恒定 | auto-pass + manual-pending | selfCheck「侧栏头三行与电量」；截图 41 / 42 |
| 长设备名 | true | T05 | 单行截断，头部仍三行 | manual-pending | 截图 41 |
| 连接的是 RC 2 Pro | true | T04、T08 | 0x2717 / 0x32B8 时 RC 2 Pro 画法 | auto-pass + manual-pending | selfCheck「RemoteModel 型号判定」；截图 01/08/43/49/50/53，需真实设备 |
| 银色机身上的状态对比 | true | T08 | 四种状态可辨；强调色 4.4 / 6.3:1 | manual-pending | 截图 43 / 44 + 取色值 |
| 官方渲染图银色配色 | true | T08 | 取色与截图 53 一致 | manual-pending | 截图 + 取色表 |
| 深色模式下滚动页面 | true | T06、T13、T14 | 系统深色滚动条，无硬编码浅色 | manual-pending | 截图 51 / 52 |
| 其他型号或未识别 | true | T04、T08 | 通用画法 | auto-pass + manual-pending | selfCheck「RemoteModel 型号判定」；截图 45 / 47 |
| 连接 / 断开时实时切换且不位移 | true | T08 | 180 x 480 同位置，13/13 锚点命中 | auto-pass + manual-pending | selfCheck「RC 2 Pro 示意图几何与 13 键命中」；录屏，截图 28 |
| 低电量变红 | true | T05、T17 | 低于阈值为红 | auto-pass + manual-pending | selfCheck「侧栏头三行与电量」；截图 39 / 40 |
| 电量未知 | true | T05 | 未知状态，不显示 0% | auto-pass + manual-pending | 同上；截图 37 / 28 |
| 电量变化时连续更新 | true | T05 | 连续变化无跳档 | manual-pending | 录屏 |
| 窄窗口下的映射页标题 | true | T09 | 900 px 下标题不断词、副标题可截断 | manual-pending | 截图 30 |
| 仅用键盘编辑一个键 | true | T09、T10 | Tab / 方向键 / Return 完成一次编辑（ScrollView 内 onMoveCommand 需重点核对） | auto-pass + manual-pending | selfCheck「遥控器标注布局与键盘顺序」；录屏 |
| 启动后正在编辑的是全局默认 | true | 回归 | 启动后为全局默认 | manual-pending | 录屏 |
| 关闭再打开窗口保留选择 | true | 回归 | 侧栏项与场景选择保留 | manual-pending | 录屏 |

## Business Evidence

| Check | Reused / New | Candidate / Conditions | Evidence / Result |
|---|---|---|---|
| 完整构建 + self-test（T19 final） | 新增 | `a460f53`，xcode-27 / Xcode 27.1 / Swift 6.4 / macOS 27.0.1 | run 40858379811：success，`SELF-TEST PASS`，233 条 `ok`，无 FAIL |
| 计划新增 selfCheck（11 个） | 新增 | 同上 | 全部 ok：GlassSurface 外观选择；BaseTapNote 文案；BaseTapNote 与 fireTap 对拍；SlotResolver 来源与恢复继承；RemoteModel 型号判定；侧栏头三行与电量；侧栏收起状态映射；问题优先级与横幅过滤；RC 2 Pro 示意图几何与 13 键命中；遥控器标注布局与键盘顺序；按键手感恢复默认 |
| 逐票 CI | 新增 | 各票提交 | T07 40855329208；T08 修复 7d7fe7b 40855774363；T09 40856079363；T10 40856273572；T15 40856536682；T11 40856754598；T12 40856967696；T13 40857188547；T14 40857404146；T16 40857596169；T17 40857776774；T18 40858022770，均 success。T01–T06 无逐票运行，首个运行（T06 顶端 b4a39a8，40854538800）失败，修复 1b2dede 后 40854938715 success |
| 静态红绿检查（rg） | 新增 | 本地工作树 | 各票任务文件中的 rg 期望与回归守卫均已核对（T17 类方法列表改前改后一致；T18 `regularMaterial` 0 处、`glassSurface(.overlay, in:` 5 处、选中描边 3 处不变） |

## Gaps / Findings

1. 全部人工 / 截图 / 实机行未执行（环境为 Linux，无 macOS 图形环境与遥控器实机）。
2. 旧 SDK（Swift < 6.2）编译未验证，CI 仅有 xcode-27 镜像。
3. 独立审查未由独立子代理执行（当前宿主无子代理派发能力），由主线程对 `80b1540..HEAD` 全量 diff 自审并声明非独立：未发现新增 emoji、TODO 或明显逻辑错误。自审观察到的待确认点：
   - 场景页「全局默认」行由 `Button` 改为 `onTapGesture`（与 App 行一致，以容纳行内「编辑映射」按钮），键盘 Tab 聚焦整行进入详情的能力可能减弱，请在键盘 / VoiceOver 核对时确认。
   - `SheetScaffold` 在无 footer 内容时仍保留 14pt 间距。
   - 浮动角标由黑底白字改为玻璃 + `.primary` 文字，浅色桌面上对比度需实机确认（T17 风险条）。
   - `NSPopover` 内容叠液态玻璃可能出现双层效果（T17 风险条），需 macOS 26 实机确认。
   - 浮动角标文本中原有的「鼠标模式」「录音中」两处前缀 emoji 字符 为改版前既有文案（spec 要求文案不变），未改动；KeyDisplay 中原有的麦克风 emoji 同理。

## 需用户单独确认的决定

- **D5（T12 详情表头文案）**：`BaseTapNote.detailHeader` =「基础状态下方向键为光标键、返回键为删除（Delete）、OK 为回车（Return）；App 场景明确设置的 OK 短按会替代回车。」原型未给出该句，按默认采用。
- **D7（T13 语音页自检「修复」按钮）**：第 1 项打开引导第 2 步；第 2 项打开引导第 3 步；第 3 项仅在输入模式不是「遥控器麦克风」时出现，切到该模式；第 4 项打开「系统设置 › 键盘 › 输入法」。若只保留第 1、2 项，删去第 3、4 项按钮即可。

## 实施偏差（详见各提交与 progress.yaml notes）

- 未建 worktree，直接在 `feat/ui-redesign-spec` 上实施；guardrail bind / inspect 脚本与 `execution-evidence.mjs` 回执工具未运行，验证以 GitHub Actions 运行记录为准（final 日志原件保存在 `execution/T19-final-ci-40858379811.log`，不进 Git）。
- 执行顺序：T15 先于 T11、T12（二者消费 SheetScaffold）。
- T10：映射页 maxWidth 860 改为 960，宽布局遥控器面板去掉水平内边距、检查器 minWidth 按是否显示标注设置，窄布局分段控件堆叠到标签下方（否则标注在 860 上限内永远无法显示）。
- T11：「编辑映射」由共用 sceneRow 提供，rg 计数 1 而非 2；空态第二句为新增说明文案（计划允许删去）。
- T12：骨架无图标槽，App 图标置于内容顶部（计划允许的回退）；未设置的槽位不再显示「继承全局」。
- T15：原无关闭按钮的 sheet 保持 `onClose: nil`。
- T01–T06 合并推送后首个 CI 失败（拆分提交时重复插入），以 1b2dede 前向修复；T08 actor 隔离错误以 7d7fe7b 前向修复。未改写已推送历史。
- 菜单栏健康点（D8，2026-10-30 用户决定，偏离原型 `prototype-v2.html:873`）：暂停遥控时健康点为灰色而非绿色。红 = 按键通道异常；灰 = 已暂停或未连接；绿 = 已连接且未暂停。证据：快照 `menubar-paused-glass-light` / `menubar-paused-fallback-light`。
- 暂停遥控（D9）：暂停期间遥控器完全惰性（中转键在 tap 吞弃、语音新会话忽略），真键盘不受影响。证据：自测「暂停遥控：全部遥控中转键…吞弃」「暂停遥控：语音键会话被忽略」。
- 按键提示条（D10）：只在模式或浮层激活时出现，前台 App 切换不再闪现。证据：自测「按键提示条只在模式/浮层激活时出现」。

## Requirement Reconciliation

自动证据覆盖的部分已通过；每个 Requirement 都至少有一条 required 行仍为 manual-pending，因此本表不标 DELIVERED，统一为「已实现，待人工验收」。

| Requirement | 实施票 | 状态 |
|---|---|---|
| 设置窗外壳（侧栏 4 页 + 侧栏头状态） | T05、T07 | 已实现，待人工验收 |
| 按键映射页 | T09、T10 | 已实现，待人工验收 |
| 场景配置页 | T11 | 已实现，待人工验收 |
| 语音页 | T13 | 已实现，待人工验收（D7 待确认） |
| 通用页 | T14 | 已实现，待人工验收 |
| Sheet 与对话框统一样式 | T15、T11、T12 | 已实现，待人工验收（D5 待确认） |
| 首次引导三步 | T16 | 已实现，待人工验收 |
| 菜单栏状态图标、状态面板与兜底菜单 | T17 | 已实现，待人工验收 |
| 屏幕浮层 | T17、T18、T12 | 已实现，待人工验收 |
| 基础状态短按的文字说明 | T02、T09 | 已实现，selfCheck 通过，截图待验 |
| App 场景槽位显示来源并可恢复继承 | T03、T09、T12 | 已实现，selfCheck 通过，录屏待验 |
| 侧栏可收起（⌃⌘S） | T06 | 已实现，selfCheck 通过，录屏待验 |
| macOS 26 液态玻璃与回退 | T01、T15–T18 | 已实现，新 SDK 编译通过，实机待验；旧 SDK 编译未验证 |
| OK 手势组按需显示 | T09 | 已实现，待人工验收 |
| 电量图标连续填充 | T05 | 已实现，selfCheck 通过，截图待验 |
| 侧栏头固定三行 | T05 | 已实现，selfCheck 通过，截图待验 |
| MI RC 2 Pro 专用遥控器示意图 | T04、T08 | 已实现，selfCheck 通过，需真实设备验收 |
| 短标签不断行与标题区排版 | T01、T09–T18 | 已实现，待人工验收 |
| 无障碍与主题 | T06、T10、T16 | 已实现，键盘与 VoiceOver 待验 |
| 深色模式下滚动条与滑块跟随主题 | T06、T13、T14 | 已实现，待人工验收 |
| 默认场景行为保持不变 | 回归 | 未改动相关逻辑，待人工回归 |

## Evidence Index / coverage_note

- final：run 40858379811（候选 a460f53），日志原件 `execution/T19-final-ci-40858379811.log`（未入 Git，由 T21 转存）。
- 逐票运行见 `plan/progress.yaml` 各任务 `ci` 字段。
- 覆盖裁剪：无截图、录屏、取色与实机证据；acceptance-check-items JSON 未生成（无可引用的人工证据原件）；审查非独立。以上均为 manual-pending，交用户在发布验收时处理。
