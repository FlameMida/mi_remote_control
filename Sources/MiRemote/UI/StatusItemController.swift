import AppKit
import SwiftUI
import Combine

// MARK: - 菜单栏图标（菜单栏优先形态的主入口）
//
// 左键点击 = SwiftUI 状态面板（NSPopover）；右键 / Option+左键 = 传统 NSMenu 兜底。
// 图标为模板图（单色随系统着色），6 态用着色/透明度/角标短名表达而不换整图；
// autosaveName 固定以保留排序；“显示菜单栏图标”偏好是可见性权威数据源。
// 用户 Cmd+拖走可在当前会话隐藏，但下次启动（或开关重开）会按偏好恢复，
// 避免旧 autosave 的 false 让图标永久消失。

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let model: AppModel
    private var cancellables: Set<AnyCancellable> = []

    var onOpenWindow: (() -> Void)?
    var onQuit: (() -> Void)?

    init(model: AppModel) {
        self.model = model
        super.init()
        // 任一状态变化 → 重绘图标与菜单
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // objectWillChange 在属性真正写入前发送；延后一拍才能读到新电量/连接状态。
                DispatchQueue.main.async { self?.refresh() }
            }
            .store(in: &cancellables)
        refresh()
    }

    /// 图标当前是否可见（用户可能 Cmd+拖走；autosave 持久，供通用页开关状态同步/恢复）。
    var itemVisible: Bool {
        get { statusItem?.isVisible ?? false }
        set { statusItem?.isVisible = newValue }
    }

    private func refresh() {
        if !model.showStatusItem {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
            return
        }
        if statusItem == nil {
            // variableLength：层激活时图标旁要放语义短名
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "com.miremote.statusitem"
            item.behavior = .removalAllowed
            // 设置 autosaveName 后系统会读取历史 isVisible；显式覆盖为偏好值。
            item.isVisible = true
            if let button = item.button {
                button.target = self
                button.action = #selector(statusItemClicked(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            statusItem = item
        }
        guard let button = statusItem?.button else { return }
        let (tint, dimmed, desc) = iconState()
        // 模板底图恒为遥控器轮廓，状态用着色/透明度表达（失联=降透明度）
        var img = NSImage(systemSymbolName: "av.remote", accessibilityDescription: desc)
        if dimmed, let base = img {
            let faded = NSImage(size: base.size, flipped: false) { rect in
                base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.35)
                return true
            }
            faded.isTemplate = true
            img = faded
        } else {
            img?.isTemplate = tint == nil
        }
        button.image = img
        button.contentTintColor = tint
        // 层激活时叠加语义短名（P3：显示名字而非数字）；精简模式仅图标
        button.title = (!model.statusItemCompact && model.activeLayer != 0)
            ? " \(layerShortText(model.activeLayer))" : ""
        button.toolTip = tooltipText()
        button.imagePosition = .imageLeading
    }

    /// 6 态：故障红 > 语音 > 鼠标 > 层 > 未连接（降透明度）> 空闲
    private func iconState() -> (tint: NSColor?, dimmed: Bool, desc: String) {
        if model.degraded { return (.systemRed, false, "故障") }
        if model.voiceActive { return (.controlAccentColor, false, "语音中") }
        if model.mouseModeActive { return (.systemGreen, false, "鼠标模式") }
        if model.activeLayer != 0 { return (.controlAccentColor, false, modeDisplayName(model.activeLayer)) }
        if !model.connected { return (nil, true, "未连接") }
        return (nil, false, "已连接")
    }

    /// tooltip 与浮动角标同步的完整语义描述（P3/P9）。
    private func tooltipText() -> String {
        var parts: [String] = ["MiRemote"]
        if model.degraded { parts.append("故障：按键通道异常，打开体检修复") }
        if model.voiceActive { parts.append("录音中") }
        if model.mouseModeActive { parts.append("鼠标模式") }
        if model.activeLayer != 0 {
            parts.append(layerBadgeText(model.activeLayer, frontAppName: model.frontAppNameForBadge))
        }
        if parts.count == 1 { parts.append(model.connected ? "已连接 · 空闲" : "遥控器未连接") }
        return parts.joined(separator: " · ")
    }

    // MARK: 点击路由：左键=状态面板，右键/Option=传统菜单兜底

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.option) == true
        if isRight {
            showFallbackMenu()
        } else {
            togglePanel()
        }
    }

    /// 玻璃面板（macOS 26 液态玻璃可用时）：无箭头、圆角 18、状态栏下方 8pt（原型 glass-on .mpop）。
    private var glassPanel: StatusGlassPanel?
    private var panelMonitors: [Any] = []
    private var panelResignObserver: NSObjectProtocol?
    private var lastPanelClose = Date.distantPast

    /// 当前面板外观：液态玻璃 → 自绘玻璃浮窗；否则（旧系统 / 降低透明度）→ 原版 NSPopover（带箭头）。
    static func panelUsesGlass() -> Bool {
        GlassSurface.appearance(kind: .panel, glassAvailable: GlassSurface.glassAvailable,
                                reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
            == .liquidGlass
    }

    func togglePanel() {
        if let glassPanel, glassPanel.isVisible {
            closeGlassPanel()
            return
        }
        // 点状态栏图标关闭面板时，失去 key 的关闭先于本次点击到达：避免「关了又开」
        if Date().timeIntervalSince(lastPanelClose) < 0.25 { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem?.button else { return }
        if Self.panelUsesGlass() {
            showGlassPanel(below: button)
        } else {
            showPopover(relativeTo: button)
        }
    }

    private func makePanelView(glass: Bool) -> some View {
        StatusPanelView(
            glass: glass,
            onOpenWindow: { [weak self] in
                self?.closeAnyPanel()
                self?.onOpenWindow?()
            },
            onHealthCheck: { [weak self] in
                self?.closeAnyPanel()
                self?.onOpenWindow?()
                NotificationCenter.default.post(name: .miremoteShowHealthCheck, object: nil)
            },
            onQuit: { [weak self] in self?.onQuit?() })
            .environmentObject(model)
    }

    private func closeAnyPanel() {
        popover?.performClose(nil)
        closeGlassPanel()
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        let p = NSPopover()
        p.behavior = .transient
        p.delegate = self
        // 外观跟随 App（NSApp.appearance 覆盖优先）：popover 从状态栏窗口继承的外观
        // 不一定等于 App 外观，显式下发到 popover 与内容视图两层，浅色下必须是浅色面板。
        let appearance = NSApp.appearance ?? NSApp.effectiveAppearance
        p.appearance = appearance
        let hosting = NSHostingController(rootView: makePanelView(glass: false))
        hosting.view.appearance = appearance
        // 内容固定宽 300，高度按内容：popover 尺寸取 SwiftUI 理想尺寸，避免内容比 popover 宽被裁
        hosting.sizingOptions = [.preferredContentSize]
        p.contentViewController = hosting
        popover = p
        p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// 面板在屏幕上的位置：水平居中于状态栏图标、贴屏幕可见区边缘夹紧；顶边在菜单栏下方 8pt。
    nonisolated static func glassPanelFrame(size: CGSize, anchor: CGRect, visible: CGRect) -> CGRect {
        let gap: CGFloat = 8, margin: CGFloat = 8
        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + margin), visible.maxX - margin - size.width)
        let top = min(anchor.minY, visible.maxY) - gap
        return CGRect(x: x.rounded(), y: (top - size.height).rounded(), width: size.width, height: size.height)
    }

    /// 玻璃面板窗 = 可见面板 + 自绘阴影边距（GlassPanelShadow.insets）。按可见面板尺寸定位后向外扩。
    nonisolated static func glassPanelWindowFrame(size windowSize: CGSize, anchor: CGRect, visible: CGRect) -> CGRect {
        let i = GlassPanelShadow.insets
        let inner = CGSize(width: windowSize.width - i.leading - i.trailing,
                           height: windowSize.height - i.top - i.bottom)
        let f = glassPanelFrame(size: inner, anchor: anchor, visible: visible)
        return CGRect(x: f.minX - i.leading, y: f.minY - i.bottom, width: windowSize.width, height: windowSize.height)
    }

    nonisolated static func selfCheck() -> Bool {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let mid = glassPanelFrame(size: CGSize(width: 300, height: 200),
                                  anchor: CGRect(x: 1000, y: 875, width: 30, height: 25), visible: visible)
        let edge = glassPanelFrame(size: CGSize(width: 300, height: 200),
                                   anchor: CGRect(x: 1420, y: 875, width: 20, height: 25), visible: visible)
        // 玻璃面板窗含自绘阴影边距：可见面板仍在状态栏图标下方 8pt、水平居中
        let i = GlassPanelShadow.insets
        let win = CGSize(width: 300 + i.leading + i.trailing, height: 200 + i.top + i.bottom)
        let padded = glassPanelWindowFrame(size: win, anchor: CGRect(x: 1000, y: 875, width: 30, height: 25),
                                           visible: visible)
        let paddedOK = padded.minX + i.leading == 865 && padded.maxY - i.top == 867 && padded.size == win
        return paddedOK && mid.midX == 1015 && mid.maxY == 867 && edge.maxX == 1432 && edge.width == 300
    }

    private func showGlassPanel(below button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? anchor
        let host = NSHostingView(rootView: makePanelView(glass: true).modifier(GlassPanelShadow()))
        host.appearance = NSApp.appearance ?? NSApp.effectiveAppearance
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let panel = StatusGlassPanel(contentRect: NSRect(origin: .zero, size: size),
                                     styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // 不用窗口服务器阴影：它在无边框透明窗外圈再描一道 1px 深色轮廓（深色外观下即「黑描边」）。
        // 阴影改由 GlassPanelShadow 在窗内透明边距里自绘（原型 glass-on .pop：0 24px 70px 25% 黑）。
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .ignoresCycle, .moveToActiveSpace]
        panel.contentView = host
        panel.onCancel = { [weak self] in self?.closeGlassPanel() }
        panel.setFrame(Self.glassPanelWindowFrame(size: size, anchor: anchor, visible: visible), display: true)
        glassPanel = panel

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.makeKeyAndOrderFront(nil)
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
        // 与 .transient popover 一致：点面板外任意处 / 失去 key / Esc 关闭
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown],
                                                     handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.closeGlassPanel() }
        }) {
            panelMonitors.append(m)
        }
        panelResignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeGlassPanel() }
        }
    }

    private func closeGlassPanel() {
        guard let panel = glassPanel else { return }
        glassPanel = nil
        panelMonitors.forEach { NSEvent.removeMonitor($0) }
        panelMonitors.removeAll()
        if let o = panelResignObserver { NotificationCenter.default.removeObserver(o) }
        panelResignObserver = nil
        lastPanelClose = Date()
        panel.orderOut(nil)
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            self.popover = nil
            self.lastPanelClose = Date()
        }
    }

    // MARK: 快照模式（隐藏 --snapshot）用：在指定锚点下方摆出面板，返回窗口
    func snapshotPanel(anchor: CGRect, glass: Bool) -> NSWindow {
        let host: NSView
        if glass {
            host = NSHostingView(rootView: makePanelView(glass: true).modifier(GlassPanelShadow()))
        } else {
            host = NSHostingView(rootView: makePanelView(glass: false))
        }
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let panel = StatusGlassPanel(contentRect: NSRect(origin: .zero, size: size),
                                     styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = glass ? .clear : .windowBackgroundColor
        panel.hasShadow = !glass
        panel.contentView = host
        let visible = NSScreen.main?.visibleFrame ?? anchor
        panel.setFrame(glass ? Self.glassPanelWindowFrame(size: size, anchor: anchor, visible: visible)
                             : Self.glassPanelFrame(size: size, anchor: anchor, visible: visible), display: true)
        panel.orderFrontRegardless()
        return panel
    }

    /// 传统 NSMenu 兜底（statusItem.menu 常态必须为 nil，否则会吞掉左键面板）。
    private func showFallbackMenu() {
        guard let item = statusItem else { return }
        item.menu = buildMenu()
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let open = NSMenuItem(title: "打开设置窗口", action: #selector(openWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let health = NSMenuItem(title: "一键体检与修复…", action: #selector(showHealth), keyEquivalent: "")
        health.target = self
        menu.addItem(health)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 MiRemote", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func openWindow() { onOpenWindow?() }
    @objc private func quit() { onQuit?() }
    @objc private func showHealth() {
        onOpenWindow?()
        NotificationCenter.default.post(name: .miremoteShowHealthCheck, object: nil)
    }
}

// MARK: - 菜单栏状态面板（SwiftUI，NSPopover 内容）

struct StatusPanelView: View {
    @EnvironmentObject var model: AppModel
    /// true = 自绘液态玻璃浮窗（圆角 18）；false = NSPopover 内容（popover 自带背景与箭头）
    var glass: Bool = false
    var onOpenWindow: () -> Void
    var onHealthCheck: () -> Void
    var onQuit: () -> Void

    static let width: CGFloat = 300
    static let cornerRadius: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusCard
            PanelSeparator()
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("暂停遥控").font(.system(size: 12.5))
                    Text("按键与手势暂不生效，真实键盘不受影响")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("暂停遥控", isOn: Binding(
                    get: { model.remoteSuspended },
                    set: { model.setRemoteSuspended($0) }))
                    .toggleStyle(.switch).tint(.green)
                    .controlSize(.mini)
                    .labelsHidden()
                    .disabled(!model.canSuspendRemote)
                    .help(model.canSuspendRemote ? "" : "按键服务未运行")
            }
            PanelSeparator()
            Text("语音输入")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.bottom, 6)
            PanelSegmented(selection: $model.voiceMode, glass: glass, options: [
                (VoiceMode.remoteMic, "遥控器麦克风"),
                (VoiceMode.macMic, "Mac 麦克风"),
                (VoiceMode.off, "关闭"),
            ])
            .accessibilityLabel("语音输入")
            PanelSeparator()
            HStack(spacing: 8) {
                Button("打开设置", action: onOpenWindow).noWrap()
                Button("一键体检", action: onHealthCheck).noWrap()
                Spacer(minLength: 0)
                Button(role: .destructive, action: onQuit) {
                    Image(systemName: "power").foregroundStyle(.red)
                }
                .help("退出 MiRemote（恢复真实键盘）")
                .accessibilityLabel("退出 MiRemote")
            }
            .controlSize(.small)
            .modifier(PanelButtonShape(glass: glass))
        }
        .font(.system(size: 12.5))
        .padding(12)
        .frame(width: Self.width, alignment: .leading)
        .modifier(PanelChrome(glass: glass))
        .onAppear { model.syncRemoteSuspended() }
    }

    // 顶部状态卡：设备名 + 连接/模式行 + 电量环 + 健康点
    private var statusCard: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.12)],
                                         startPoint: .top, endPoint: .bottom))
                Image(systemName: "av.remote")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayDeviceName)
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                // 窄时整段换到第二行，不拆开「已连接」等短语
                ViewThatFits(in: .horizontal) {
                    Text(statusLine).noWrap()
                    VStack(alignment: .leading, spacing: 0) {
                        Text(statusParts[0] + " ·").noWrap()
                        Text(statusParts.dropFirst().joined(separator: " · ")).noWrap()
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let pct = model.batteryPercent {
                BatteryRingView(percent: pct)
            }
            // 原型 .hdot：degraded=红「按键通道异常」/ 已连接且未暂停=绿「运行正常」/ 暂停或未连接=灰
            let dot = StatusDotKind(degraded: model.degraded, connected: model.connected,
                                    suspended: model.remoteSuspended)
            Circle()
                .fill(dot.color)
                .frame(width: 8, height: 8)
                .help(dot.help)
        }
    }

    private var statusLine: String {
        statusParts.joined(separator: " · ")
    }

    private var statusParts: [String] {
        // 拼接结果与原文案逐字相同：「未连接 · 长按 主页+返回 配对」「已连接 · 已暂停遥控」
        if !model.connected { return ["未连接", "长按 主页+返回 配对"] }
        if model.remoteSuspended { return ["已连接", "已暂停遥控"] }
        var parts = ["已连接"]
        if model.activeLayer != 0 {
            parts.append(layerBadgeText(model.activeLayer, frontAppName: model.frontAppNameForBadge))
        } else if model.mouseModeActive {
            parts.append("鼠标模式")
        } else if model.voiceActive {
            parts.append("录音中")
        } else {
            parts.append("空闲")
        }
        return parts
    }
}

/// 面板分隔线（原型 .msep：1px、上下 8）。
private struct PanelSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .padding(.vertical, 8)
    }
}

/// 面板外观：玻璃 = 液态玻璃圆角 18（无箭头）；popover = 不加背景（NSPopover 自绘）。
private struct PanelChrome: ViewModifier {
    let glass: Bool

    func body(content: Content) -> some View {
        if glass {
            content.glassSurface(.panel, in: RoundedRectangle(cornerRadius: StatusPanelView.cornerRadius,
                                                              style: .continuous))
        } else {
            content
        }
    }
}

/// 玻璃时按钮为胶囊（原型 glass-on .btn）。
private struct PanelButtonShape: ViewModifier {
    let glass: Bool

    func body(content: Content) -> some View {
        if glass {
            content.buttonStyle(.bordered).buttonBorderShape(.capsule)
        } else {
            content
        }
    }
}

/// 等宽三段选择（原型 .seg.full）：段宽均分整行，不随文字撑宽面板；玻璃时为胶囊。
/// 菜单栏面板健康点（原型 `.hdot green/red/grey`）。
/// 用户决定（偏离原型 prototype-v2.html:873）：暂停遥控时为灰点，不再保持绿点。
/// 红 = 按键通道异常；灰 = 已暂停或未连接；绿 = 已连接且未暂停。
enum StatusDotKind: Equatable {
    case ok, fault, paused, off
    init(degraded: Bool, connected: Bool, suspended: Bool) {
        if degraded { self = .fault }
        else if !connected { self = .off }
        else if suspended { self = .paused }
        else { self = .ok }
    }
    var color: Color {
        switch self {
        case .ok: return .green
        case .fault: return .red
        case .paused, .off: return Color.secondary.opacity(0.4)
        }
    }
    var help: String {
        switch self {
        case .ok: return "运行正常"
        case .fault: return "按键通道异常"
        case .paused: return "遥控已暂停"
        case .off: return "未连接"
        }
    }
}

struct PanelSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let glass: Bool
    let options: [(Value, String)]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shapeRadius: CGFloat = glass ? 999 : 7
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let (value, title) = options[i]
                let on = value == selection
                Button {
                    selection = value
                } label: {
                    Text(title)
                        .font(.system(size: 12, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 4)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: glass ? 999 : 5, style: .continuous)
                                    .fill(selectedFill)
                                    .shadow(color: .black.opacity(glass ? 0 : 0.12), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: shapeRadius, style: .continuous).fill(trackFill))
        .overlay {
            if glass {
                RoundedRectangle(cornerRadius: shapeRadius, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.65), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var selectedFill: Color {
        if glass { return Color.white.opacity(colorScheme == .dark ? 0.2 : 0.85) }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var trackFill: Color {
        if glass { return Color.white.opacity(colorScheme == .dark ? 0.10 : 0.35) }
        return Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08)
    }
}

/// 玻璃面板的自绘阴影（原型 glass-on .pop：box-shadow 0 24px 70px rgba(0,0,0,.25)）。
/// 只画在面板形状之外：阴影层用反向形状遮罩挖空，透过半透明玻璃看不到阴影本体。
struct GlassPanelShadow: ViewModifier {
    nonisolated static let insets = EdgeInsets(top: 16, leading: 40, bottom: 56, trailing: 40)

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: StatusPanelView.cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(Color.black)
                    .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 14)
                    .mask {
                        Rectangle()
                            .padding(-80)
                            .overlay(shape.fill(Color.black).blendMode(.destinationOut))
                            .compositingGroup()
                    }
                    .allowsHitTesting(false)
            }
            .padding(Self.insets)
    }
}

/// 自绘玻璃面板窗：可成为 key（接收 Esc 与控件键盘操作），不激活 App。
final class StatusGlassPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// 小电量环：弧线按电量分档着色（与侧栏电量图标同档：≥60 绿、常规 accent、≤30 橙、≤15 红）+ 百分比数字。
struct BatteryRingView: View {
    let percent: Int

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(100, percent))) / 100)
                .stroke(SidebarHeaderLayout.tierColor(percent: percent) ?? Color.accentColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(percent)")
                .font(.caption2.weight(.semibold).monospacedDigit())
        }
        .frame(width: 28, height: 28)
        .help("电量 \(percent)%")
    }
}

// MARK: - 浮动角标（NSPanel，非侵入，右下角小徽章）

@MainActor
final class FloatingBadgeController {
    private var panel: NSPanel?
    private let model: AppModel
    private var cancellables: Set<AnyCancellable> = []
    /// 场景切换闪现（gamepad-ux C2：前台 App 变化致 per-app 覆盖生效时提示「XX 布局」）
    private var flashUntil: Date?
    private var lastProfileBundle: String?

    init(model: AppModel) {
        self.model = model
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in self?.noteFrontApp(app) }
        }
    }

    /// 前台 App 变化：切进有专用场景的 App 时闪现「<App名> 布局」1.2s（复用本角标，不新造浮窗）。
    private func noteFrontApp(_ app: NSRunningApplication?) {
        guard let app, let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier else { return }
        let hasOverlay = model.config.profiles[bundleID] != nil
        defer { lastProfileBundle = hasOverlay ? bundleID : nil }
        guard hasOverlay, bundleID != lastProfileBundle else { return }
        flash(text: "\(app.localizedName ?? bundleID) 布局")
    }

    private func flash(text: String, duration: TimeInterval = 1.2) {
        flashUntil = Date().addingTimeInterval(duration)
        show(text: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, let until = self.flashUntil, Date() >= until else { return }
            self.flashUntil = nil
            self.refresh()
        }
    }

    /// 模式态（层/鼠标/语音）常驻显示语义名（P3/P9：屏幕角落胶囊是模式可见性的主渠道，
    /// 不再只做菜单栏图标关闭后的兜底——20px 小图标瞟一眼分不清在哪个模式）。
    private func refresh() {
        // 闪现期间不被常规状态刷新覆盖
        if let until = flashUntil, Date() < until { return }
        var texts: [String] = []
        if model.activeLayer != 0 {
            texts.append(layerBadgeText(model.activeLayer, frontAppName: model.frontAppNameForBadge))
        }
        if model.mouseModeActive { texts.append("🖱 鼠标模式") }
        if model.voiceActive { texts.append("🎙 录音中") }
        if !texts.isEmpty {
            show(text: texts.joined(separator: " · "))
        } else {
            hide()
        }
    }

    private func show(text: String) {
        let content = NSHostingView(rootView:
            Text(text)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassSurface(.overlay, in: Capsule())
                .overlay(Capsule().stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        )
        content.frame.size = content.fittingSize

        if panel == nil {
            let p = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
            p.level = .statusBar
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = true            // 可点穿
            p.collectionBehavior = [.canJoinAllSpaces, .stationary]
            panel = p
        }
        guard let panel else { return }
        panel.contentView = content
        let size = content.fittingSize
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrame(NSRect(x: f.maxX - size.width - 24, y: f.minY + 24,
                                  width: size.width, height: size.height), display: true)
        }
        // 进入模式：淡入（已在前台则只换内容不重播动画）
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Motion.fadeInDuration
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func hide() {
        guard let panel, panel.isVisible else { return }
        // 退出模式：淡出后收起
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Motion.fadeOutDuration
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }
}
