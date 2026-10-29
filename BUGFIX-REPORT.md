# 代码审计缺陷报告（fix/code-audit）

- 基线：origin/main @ c2c9289
- 范围：Sources/MiRemote/**、Package.swift、scripts/*.sh
- 方式：纯静态审阅。审计环境没有 Swift 工具链，**以下修复均未编译、未运行 `--self-test`**，合并前请在本机执行 `swift build` 与 `.build/miremote --self-test` 验证。
- 原则：只修高置信度的真实缺陷，改动最小化，每个修复单独提交并尽量补 SelfTest 断言；低置信度或属设计取舍的问题只列出，不改代码。
- 按设计保留、未视为缺陷的行为：基础层方向键/返回/OK 硬编码；OK 单击仅允许按 App profile 覆盖；默认配置不含组合键（chord）。

行号以本分支 HEAD 为准。

## 一、已修复

| # | 严重度 | 位置 | 提交 |
|---|---|---|---|
| F1 | 高 | Bluetooth/ATVVBridge.swift:221 `resetSessionState()` | 052de61 |
| F2 | 中 | App/AppServices.swift:397 `atvvVoiceStarted` / :486 `atvvAudioFrame` | b9e876a |
| F3 | 高 | App/main.swift:227；UI/GUIAppDelegate.swift:66、:73 | b1aa149 |
| F4 | 中 | Integrations/ClaudeHooks.swift:75、:180 `uninstall` | a33f9b5 |
| F5 | 低 | Actions/Macro.swift:73 `utf16Chunks`、:101 `typeText` | ef0a5c0 |
| F6 | 中 | UI/AppModel.swift:369 `saveConfig`；App/AppServices.swift:40 `backupIfUnreadable` | 98a29d3 |

### F1 蓝牙断链时语音会话不结束（高）
- 现象：用户正在按住语音键说话时遥控器断开（超出距离、没电、蓝牙关闭）。之后语音触发键一直处于按下状态，系统默认输入一直停在虚拟声卡，要等下一次完整的语音会话才能恢复。
- 根因：只有收到 AUDIO_STOP 时才会回调 `atvvVoiceStopped()`。断链路径（`didDisconnectPeripheral`、`didFailToConnect`、`teardownConnection`、重新 `connect`）都走 `resetSessionState()`，但它只清理内部状态，没有通知 delegate。
- 修复：在 `resetSessionState()` 开头，如果 `streaming` 仍为真，就置为 false 并回调 `atvvVoiceStopped()`。链路已断，所以不再发送 MIC_CLOSE。

### F2 新会话取消待执行的麦克风还原后，还原责任丢失（中）
- 现象：一次会话结束后，在延迟还原执行前马上开始下一次会话；如果这次会话没有音频帧，或者 engage 失败，系统默认输入就会一直停在 BlackHole。
- 根因：`atvvVoiceStarted` 会取消上一会话挂起的 `restoreWork`，同时把 `sessionSwitchedMic` 重置为 false。`atvvAudioFrame` 又用 engage 的结果直接赋值覆盖它，所以本会话结束时认为“无需还原”。
- 修复：取消前记录“是否有未执行的还原”，作为 `sessionSwitchedMic` 的初值继承下来；`atvvAudioFrame` 只在 engage 成功时置 true，不再清零。

### F3 SIGTERM 不清理，hidutil 中转映射残留（高）
- 现象：用 `kill <pid>`（单实例提示里给出的方式）或 launchd 停止进程后，遥控器按键仍被 hidutil 重映射到中转键码，表现为按键失灵或乱码，只能手动执行 `hidutil property --set` 或重启。语音触发键、默认麦克风也可能残留。
- 根因：只处理了 SIGINT。SIGTERM 的默认动作是直接终止进程，`AppServices.stop()` 和 `applicationWillTerminate` 都不会执行。
- 修复：CLI 分支仿照 SIGINT 增加 SIGTERM 的 DispatchSource。GUI 在启动时安装 SIGTERM 源，在主线程同步执行 `services.stop()` 后 `exit(0)`。这里不走 `NSApp.terminate`，因为退出确认弹窗会阻塞清理。

### F4 部分安装时卸载跳过清理，留下失效 hook（中）
- 现象：settings.json 里只剩部分本工具的 hook 条目时（旧版本只注入了部分条目，或用户手删过一条），点击卸载提示“未安装，无需卸载”，却删除了发信脚本。剩下的 hook 每次触发都去执行一个不存在的脚本，Claude Code 会报错。
- 根因：`uninstall` 用要求条目齐全的 `isInstalled` 作为前置判断。
- 修复：新增 `hasAnyEntry`（只要残留任意一条带 `miremote-notify.sh` 的命令即为真），卸载改用它判断。SelfTest EV-3 增加部分安装场景。

### F5 宏文本分段拆开 UTF-16 代理对（低）
- 现象：宏的 text 步骤里含 emoji 或 CJK 扩展 B 等 BMP 以外的字符，而且这个字符恰好跨过第 20 个 UTF-16 单元时，目标 App 会收到两个替换符或乱码。
- 根因：按固定 20 个 UTF-16 单元切片，没有考虑代理对。
- 修复：抽出 `MacroEngine.utf16Chunks`，当某段末尾是高位代理时把它顺延到下一段。SelfTest 新增 M4-4b。

### F6 界面保存静默覆盖无法解析的 config.json（中）
- 现象：用户手改 config.json 写错了 JSON 后启动 GUI，界面会回退到默认配置。此后只要在界面上改动任意一项，原文件就被默认配置整体覆盖，手写内容全部丢失，没有备份。
- 根因：`AppModel.init` 解析失败时回退 `defaultConfig()`，`saveConfig()` 直接写回原路径。CLI 的 `loadOrCreateConfig` 明确承诺不覆盖用户的问题文件，GUI 路径却违背了这一点。体检页的“恢复默认”会先移到 config.broken.json，那条路径不受影响。
- 修复：新增 `ConfigStore.backupIfUnreadable(at:)`：文件存在但无法解析时，先移动到同目录的 config.broken.json（已存在则改名为 config.broken-时间戳-序号.json）。`saveConfig()` 写入前调用它。SelfTest 新增 M5-1b。

## 二、仅列出，未修改

| # | 严重度 | 位置 | 问题 | 未修原因 |
|---|---|---|---|---|
| L1 | 中 | Bluetooth/ATVVBridge.swift:389、:412、:453 | 服务发现、特征发现、开启 notify 出错时只打日志，连接停在半开状态，没有断开重连，语音不可用，需等系统断链或重启 | 重连策略涉及 CoreBluetooth 行为与重试节奏，无法在无硬件环境下验证，建议出错时 `cancelPeripheralConnection` 让既有断链重连逻辑接管 |
| L2 | 低 | Mapping/MappingEngine.swift:332 | 方向键在调度中心激活前按下、激活后松开：keyDown 已进入普通状态机，keyUp 却被调度中心分支吞掉，可能留下长按或重复状态 | 时序窄，且 `_resetInputState` 会在多处兜底；改动会影响调度中心交互，需实机确认 |
| L3 | 低 | Mapping/MappingEngine.swift:534-546 | 按住 OK（layer 0）期间方向键的长按、重复语义与手势判定交织，边界行为难以从静态代码完全确认 | 属交互设计取舍，OK 双击 layerToggle 的延迟按设计如此 |
| L4 | 低 | HID/KeyRemapper.swift:364、:376 | `stop()` 把 PressState 整体重置，`suspended` 一并被清零；如果同一进程内 stop 后再 start，暂停状态与 MappingEngine 不一致，健康检查可能在暂停期间重装映射 | 当前 stop 仅在进程退出时调用（AppServices.stop 只执行一次），实际不可达 |
| L5 | 低 | App/AppServices.swift:21、:67 | `defaultURL` 直接取 `urls(...)[0]`；`save` 写到自定义路径时不创建父目录 | 前者在 macOS 上恒有值；后者仅影响 `--config` 指向不存在的目录，失败会打日志 |
| L6 | 低 | App/AppServices.swift:835 | `stop()` 后未把 keyMapper、tapEngine 置 nil | stop 仅在退出时执行一次，无实际影响 |
| L7 | 低 | Actions/VoiceTrigger.swift:48、:171 | 静态 `config` 在串行 queue 内写，其他线程可能直接读 | 未发现 queue 外的读取路径会导致错误结果，属 Swift 6 严格并发下的潜在隐患，需编译器诊断确认 |
| L8 | 中 | Actions/ActionRunner.swift:171-174 | lock_screen 调用的 `User.menu/.../CGSession` 在较新的 macOS 上已不存在，锁屏动作可能无效 | 需在目标系统版本上确认，替代方案（如 Ctrl+Cmd+Q 按键或 SACLockScreenImmediate）属行为变更 |
| L9 | 低 | Integrations/EventListener.swift:213 | 单连接数据超过 maxBytes 时直接收尾解析，被截断的最后一行（可能截在 UTF-8 多字节中间）解析失败，若只有一行则整条事件丢失 | 正常 hook 负载远小于 64 KB |
| L10 | 低 | Integrations/ClaudeHooks.swift:53 | Notification 的 matcher 用了 "agent_needs_input"，与 Claude Code 实际的通知类型名可能不符，导致该 hook 永不触发 | 需对照当前 Claude Code 文档确认，改动会影响已安装用户的幂等判断 |
| L11 | 低 | Integrations/ClaudeHooks.swift:145 | `.atomic` 写入会把符号链接形式的 settings.json 替换成普通文件（dotfiles 仓库用户受影响） | 属于边缘场景，修复需要解析符号链接后写回，暂不改 |
| L12 | 低 | Bluetooth/ATVVBridge.swift:84、:221 | 断链时 `batteryPercent` 不清空，再次读取会得到旧值 | UI 侧在 AppModel.swift:429 断链时已清空显示，影响有限 |
| L13 | 低 | App/AppServices.swift:397 起 | 还原任务已开始执行时新会话 engage 存在竞态；还原执行后 `restoreWork` 不置 nil，下次会话可能多做一次无害的还原 | `restore` 在 savedDevice 为 nil 时为空操作；彻底消除需要重构切换状态机 |
| L14 | 低 | Actions/MouseMode.swift:153 | 光标被限制在主显示器范围内，多显示器无法移动到副屏 | 已知 v1 限制 |
| L15 | 低 | Actions/WindowSwitcher.swift:13、:91、:102 | `.optionAll` 的 z 序只是近似 MRU；AXRaise 不会取消窗口最小化 | 属功能局限而非错误 |
| L16 | 低 | Audio/AudioBridge.swift:195 | `streamStarted` 中 `ring.clear()` 异步执行，与首批音频帧写入可能竞争，极少数情况下丢掉开头几毫秒 | 影响极小，修复需调整 ring 的线程模型 |

## 三、审阅后无问题

WorkspaceActions、MouseMode（除 L14）、FocusInput、WindowSwitcher（除 L15）、OverlayCenter（定时器生命周期正确）、AppModel（除 F6）、AudioBridge（除 L16）、Package.swift、scripts/*.sh。
