import AppKit
import SwiftUI

// MARK: - 隐藏的 --snapshot <outdir> 渲染模式（开发 / CI 视觉核对专用，不在 --help 中）
//
// 用真实 NSWindow 依次摆出设置窗各页、侧栏收起、窄窗、问题态、sheet、首启向导、
// 菜单栏面板与浮层，在彩色桌面背景（原型 .desk 渐变）上用 screencapture 区域截图，
// 失败时回退 cacheDisplay（回退图不含系统玻璃 / 模糊）。引擎不启动，配置写临时目录。

@MainActor
final class SnapshotRunner: NSObject, NSApplicationDelegate {
    private let outDir: URL
    private var model: AppModel!
    private var nav: SettingsNav!
    private var permissions: PermissionStatus!
    private var assembly: SettingsWindowAssembly?
    private var backdrop: NSWindow?
    private var statusController: StatusItemController?
    private var overlayCenter: OverlayCenter?
    private var logLines: [String] = []

    init(outDir: String) {
        self.outDir = URL(fileURLWithPath: outDir, isDirectory: true)
        super.init()
    }

    private struct Step {
        let name: String
        let delay: TimeInterval
        let setup: () -> Void
        let capture: () -> CGRect?
        /// 截图完成后执行（关面板 / 浮层）；不能放在 capture 里，否则截图前就已关闭
        var teardown: (() -> Void)? = nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        PermissionGate.suppressLaunchGate = true
        PermissionStatus.snapshotMode = true
        // runner 开着「降低透明度」；环境变量 MIREMOTE_SNAPSHOT_RT=1 时保留系统设置（截不透明回退外观）
        GlassSurface.snapshotIgnoresReduceTransparency = ProcessInfo.processInfo.environment["MIREMOTE_SNAPSHOT_RT"] != "1"
        NSApp.setActivationPolicy(.regular)
        Prefs.registerDefaults()

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("miremote-snapshot-\(getpid())")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        model = AppModel(configURL: tmp.appendingPathComponent("config.json"), services: nil)
        nav = SettingsNav()
        permissions = PermissionStatus()
        permissions.setSnapshotMissing(nil)
        setConnected()

        showBackdrop()
        statusController = StatusItemController(model: model)
        overlayCenter = OverlayCenter(model: model, services: nil)
        NSApp.activate(ignoringOtherApps: true)
        note("glassAvailable=\(GlassSurface.glassAvailable) reduceTransparency=\(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency) screen=\(NSScreen.main?.frame ?? .zero)")
        run(steps: makeSteps(), index: 0)
    }

    // MARK: 状态

    private func setConnected(battery: Int? = 82) {
        model.connected = true
        model.deviceName = "小米蓝牙语音遥控器"
        model.batteryPercent = battery
        model.degraded = false
        model.remoteSuspended = false
        model.activeLayer = 0
        permissions.setSnapshotMissing(nil)
    }

    private func setTheme(dark: Bool) {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        backdrop?.contentView?.needsDisplay = true
    }

    private func openSettings(size requested: CGSize? = nil, sidebarHidden: Bool = false,
                              page: SidebarItem) {
        // 与正式启动一致：默认尺寸按屏幕可见区收窄（runner 屏幕仅 1024×768）
        let size = requested ?? GUIAppDelegate.initialWindowSize()
        model.sidebarHidden = sidebarHidden
        nav.page = page
        if assembly == nil {
            let a = SettingsWindowAssembly(model: model, nav: nav, permissions: permissions, size: size)
            assembly = a
        }
        guard let w = assembly?.window else { return }
        if w.frame.size != w.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size {
            w.setContentSize(size)
        }
        w.center()
        // 比 runner 屏幕宽的窗（原型标准 1120）贴左摆放，整窗用 screencapture -l 按窗口截
        if let sf = NSScreen.main?.visibleFrame, w.frame.width > sf.width {
            w.setFrameOrigin(NSPoint(x: sf.minX, y: w.frame.minY))
        }
        w.makeKeyAndOrderFront(nil)
    }

    private func closeSheets() {
        nav.showOnboarding = false
        nav.showHealthCheck = false
        nav.showReauth = false
    }

    private var windowRect: CGRect? {
        guard let w = assembly?.window else { return nil }
        return w.frame.insetBy(dx: -24, dy: -24)
    }

    // MARK: 步骤

    private func makeSteps() -> [Step] {
        var steps: [Step] = []
        func win(_ name: String, delay: TimeInterval = 1.2, _ setup: @escaping () -> Void) {
            steps.append(Step(name: name, delay: delay, setup: setup, capture: { [weak self] in self?.windowRect }))
        }
        for dark in [false, true] {
            let t = dark ? "dark" : "light"
            for page in SidebarItem.allCases {
                win("\(page.rawValue)-\(t)", delay: 1.4) { [self] in
                    closeSheets(); setTheme(dark: dark); setConnected(); openSettings(page: page)
                }
            }
        }
        win("mapping-sidebar-hidden-light") { [self] in
            setTheme(dark: false); openSettings(sidebarHidden: true, page: .mapping)
        }
        // 与原型截图同尺寸：01 / 22 为 1120×700 标准窗，30 / 48 为 780×580 窄窗；另截 1024 宽窗
        for (w, h, tag) in [(1120, 700, "1120"), (1024, 700, "1024")] {
            for dark in [false, true] where !dark || tag == "1120" {
                win("mapping-\(tag)-\(dark ? "dark" : "light")", delay: 1.4) { [self] in
                    setTheme(dark: dark); setConnected()
                    openSettings(size: CGSize(width: w, height: h), page: .mapping)
                }
            }
        }
        win("mapping-narrow-light") { [self] in
            setTheme(dark: false)
            openSettings(size: CGSize(width: 780, height: 580), page: .mapping)
        }
        win("mapping-disconnected-light") { [self] in
            openSettings(page: .mapping)
            model.connected = false; model.batteryPercent = nil
        }
        win("mapping-permission-light") { [self] in
            setConnected(); permissions.setSnapshotMissing("输入监控")
        }
        win("mapping-degraded-light") { [self] in
            permissions.setSnapshotMissing(nil); model.degraded = true
        }
        win("mapping-battery-low-light") { [self] in
            setConnected(battery: 12)
        }
        win("mapping-paused-light") { [self] in
            setConnected(); model.remoteSuspended = true
        }
        win("profiles-layer-light") { [self] in
            setConnected(); model.activeLayer = 2; nav.page = .profile
        }
        win("sheet-health-light", delay: 1.8) { [self] in
            setConnected(); permissions.setSnapshotMissing("输入监控"); nav.page = .general
            nav.showHealthCheck = true
        }
        win("sheet-reauth-light", delay: 1.8) { [self] in
            closeSheets()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.nav.showReauth = true }
        }
        for step in 0..<3 {
            win("onb-\(step + 1)-light", delay: 1.8) { [self] in
                closeSheets(); setConnected(); nav.page = .mapping
                if step == 2 { model.connected = false; model.batteryPercent = nil }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.nav.onboardingStep = step
                    self.nav.showOnboarding = true
                }
            }
        }
        win("general-sheet-closed-dark", delay: 1.4) { [self] in
            closeSheets(); setTheme(dark: true); setConnected(); nav.page = .general
        }
        // 展开组：折叠 / 展开两态同尺寸，核对上方布局不动（检查器头部 y 一致）
        for expanded in [false, true] {
            win("mapping-layer-\(expanded ? "expanded" : "collapsed")-dark", delay: 1.4) { [self] in
                closeSheets(); setTheme(dark: true); setConnected()
                nav.mappingLayerExpanded = expanded
                openSettings(size: CGSize(width: 1120, height: 700), page: .mapping)
            }
            win("general-advanced-\(expanded ? "expanded" : "collapsed")-dark", delay: 1.4) { [self] in
                closeSheets(); setTheme(dark: true); setConnected()
                nav.generalAdvancedExpanded = expanded
                openSettings(page: .general)
            }
        }
        // 滚动后的详情页：标题栏下不得透出正文（原型 .win 标题栏独立一行）
        for page in SidebarItem.allCases {
            win("\(page.rawValue)-scrolled-dark", delay: 1.6) { [self] in
                closeSheets(); setTheme(dark: true); setConnected()
                nav.mappingLayerExpanded = true; nav.generalAdvancedExpanded = true
                openSettings(page: page)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.scrollDetail(by: 260) }
            }
        }
        steps.append(Step(name: "reset-expanded", delay: 0.2, setup: { [self] in
            nav.mappingLayerExpanded = false; nav.generalAdvancedExpanded = false
        }, capture: { nil }))
        // 菜单栏面板：玻璃 / 回退两种外观 × 状态
        let panelStates: [(String, () -> Void)] = [
            ("connected", { [self] in setConnected() }),
            ("disconnected", { [self] in setConnected(); model.connected = false; model.batteryPercent = nil }),
            ("paused", { [self] in setConnected(); model.remoteSuspended = true }),
            ("degraded", { [self] in setConnected(); model.degraded = true }),
            ("battery-low", { [self] in setConnected(battery: 12) }),
            ("layer", { [self] in setConnected(); model.activeLayer = 2 }),
        ]
        for dark in [false, true] {
            for (state, apply) in panelStates where !dark || state == "connected" || state == "layer" {
                for glass in [true, false] {
                    let name = "menubar-\(state)-\(glass ? "glass" : "fallback")-\(dark ? "dark" : "light")"
                    var panel: NSWindow?
                    steps.append(Step(name: name, delay: 1.0, setup: { [self] in
                        closeSheets()
                        assembly?.window.orderOut(nil)
                        setTheme(dark: dark)
                        apply()
                        panel = statusController?.snapshotPanel(anchor: menubarAnchor(), glass: glass)
                    }, capture: {
                        guard let f = panel?.frame, let screen = NSScreen.main?.frame else { return nil }
                        return CGRect(x: f.minX - 60, y: f.minY - 40, width: f.width + 120,
                                      height: screen.maxY - (f.minY - 40))
                    }, teardown: {
                        panel?.orderOut(nil); panel = nil
                    }))
                }
            }
        }
        // 浮层（引擎未启动：窗口列表 / 轮盘可能为空，仅核对外框与玻璃）
        for (kind, title) in [("window_picker", "ov-window"), ("system_menu", "ov-system"),
                              ("tutorial", "ov-tutorial"), ("app_wheel", "ov-wheel")] {
            for dark in [false, true] {
                steps.append(Step(name: "\(title)-\(dark ? "dark" : "light")", delay: 1.4, setup: { [self] in
                    setTheme(dark: dark); setConnected()
                    assembly?.window.orderOut(nil)
                    overlayCenter?.open(kind)
                }, capture: {
                    NSScreen.main?.frame
                }, teardown: { [self] in
                    overlayCenter?.close()
                }))
            }
        }
        // 功能层屏底提示条（全文不省略、按内容加宽）+ 层 2 角落 HUD
        for layer in [1, 2, 3] {
            for dark in [false, true] where dark || layer == 2 {
                steps.append(Step(name: "hint-layer\(layer)-\(dark ? "dark" : "light")", delay: 1.2, setup: { [self] in
                    closeSheets(); setTheme(dark: dark); setConnected()
                    assembly?.window.orderOut(nil)
                    model.activeLayer = layer
                    overlayCenter?.noteLayer(layer)
                }, capture: {
                    NSScreen.main?.frame
                }, teardown: { [self] in
                    model.activeLayer = 0
                    overlayCenter?.noteLayer(0)
                }))
            }
        }
        return steps
    }

    /// 把设置窗详情区最大的滚动视图向下滚 dy 点（SwiftUI ScrollView 底层为 NSScrollView）。
    private func scrollDetail(by dy: CGFloat) {
        guard let root = assembly?.window.contentView else { return }
        var found: [NSScrollView] = []
        func walk(_ v: NSView) {
            if let sv = v as? NSScrollView { found.append(sv) }
            v.subviews.forEach(walk)
        }
        walk(root)
        guard let sv = found.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
              let doc = sv.documentView else {
            note("scrollDetail: 未找到滚动视图"); return
        }
        let clip = sv.contentView
        let maxY = max(0, doc.frame.height - clip.bounds.height)
        let y = doc.isFlipped ? min(clip.bounds.origin.y + dy, maxY) : max(clip.bounds.origin.y - dy, 0)
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        sv.reflectScrolledClipView(clip)
        note("scrollDetail: \(Int(dy)) → y=\(Int(y)) doc=\(Int(doc.frame.height)) clip=\(Int(clip.bounds.height))")
    }

    /// 状态栏图标位置（有真实图标用真实位置，否则取屏幕右上角假定位置）。
    private func menubarAnchor() -> CGRect {
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let barHeight = screen.maxY - (NSScreen.main?.visibleFrame.maxY ?? screen.maxY - 24)
        return CGRect(x: screen.maxX - 260, y: screen.maxY - max(barHeight, 24), width: 24, height: max(barHeight, 24))
    }

    private func run(steps: [Step], index: Int) {
        guard index < steps.count else { finish(); return }
        let step = steps[index]
        step.setup()
        DispatchQueue.main.asyncAfter(deadline: .now() + step.delay) { [weak self] in
            guard let self else { return }
            if let rect = step.capture() {
                self.capture(rect: rect, name: step.name)
            } else {
                self.note("\(step.name): 无可截图区域")
            }
            step.teardown?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.run(steps: steps, index: index + 1)
            }
        }
    }

    // MARK: 截图

    private func capture(rect: CGRect, name: String) {
        guard let screen = NSScreen.screens.first?.frame else { return }
        // 设置窗超出屏幕（runner 屏 1024×768 放不下 1120 标准窗）时按窗口 ID 截整窗
        if let win = assembly?.window, win.isVisible, !screen.contains(win.frame),
           rect == windowRect, captureWindow(win, name: name) {
            return
        }
        let r = rect.intersection(screen)
        // screencapture -R 用左上原点的全局坐标
        let x = Int(r.minX), y = Int(screen.maxY - r.maxY), w = Int(r.width), h = Int(r.height)
        let path = outDir.appendingPathComponent("\(name).png").path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-t", "png", "-R", "\(x),\(y),\(w),\(h)", path]
        var ok = false
        do {
            try p.run()
            p.waitUntilExit()
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            ok = p.terminationStatus == 0 && size > 2000
        } catch {
            note("\(name): screencapture 启动失败 \(error)")
        }
        if ok {
            note("\(name): screencapture \(w)x\(h)")
        } else if let win = assembly?.window, win.isVisible, cacheDisplay(window: win, path: path) {
            note("\(name): 回退 cacheDisplay（无系统玻璃）")
        } else {
            note("\(name): 截图失败")
        }
    }

    private func captureWindow(_ win: NSWindow, name: String) -> Bool {
        let path = outDir.appendingPathComponent("\(name).png").path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-t", "png", "-l\(win.windowNumber)", path]
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            note("\(name): screencapture -l 启动失败 \(error)")
            return false
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        guard p.terminationStatus == 0, size > 2000 else { return false }
        note("\(name): screencapture -l 整窗 \(Int(win.frame.width))x\(Int(win.frame.height))")
        return true
    }

    private func cacheDisplay(window: NSWindow, path: String) -> Bool {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }

    private func note(_ line: String) {
        print("[snapshot] \(line)")
        logLines.append(line)
    }

    private func finish() {
        let text = logLines.joined(separator: "\n") + "\n"
        try? text.write(to: outDir.appendingPathComponent("snapshot.log"), atomically: true, encoding: .utf8)
        print("[snapshot] done → \(outDir.path)")
        exit(0)
    }

    // MARK: 桌面背景（原型 .desk 渐变：橙 / 紫 / 青 径向渐变叠在粉底上）

    private func showBackdrop() {
        guard let screen = NSScreen.main else { return }
        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.stationary, .canJoinAllSpaces]
        w.contentView = NSHostingView(rootView: SnapshotDesk())
        w.orderFront(nil)
        backdrop = w
    }
}

private struct SnapshotDesk: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        GeometryReader { geo in
            ZStack {
                Color(hex: dark ? 0x2A1430 : 0xF4B8D0)
                RadialGradient(colors: [Color(hex: dark ? 0x8A2F1A : 0xFF8A5C), .clear],
                               center: UnitPoint(x: 0.15, y: 0.1), startRadius: 0,
                               endRadius: max(geo.size.width, geo.size.height) * 0.55)
                RadialGradient(colors: [Color(hex: dark ? 0x2A1F8F : 0x6A5CFF), .clear],
                               center: UnitPoint(x: 0.9, y: 0.25), startRadius: 0,
                               endRadius: max(geo.size.width, geo.size.height) * 0.5)
                RadialGradient(colors: [Color(hex: dark ? 0x04685C : 0x14C7B0), .clear],
                               center: UnitPoint(x: 0.5, y: 1.0), startRadius: 0,
                               endRadius: max(geo.size.width, geo.size.height) * 0.45)
            }
        }
        .ignoresSafeArea()
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
