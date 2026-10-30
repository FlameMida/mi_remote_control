import AppKit
import ApplicationServices
import CoreGraphics

/// 窗口切换（DESIGN §4.2）：
///   - scope "app"   ：同 app 多窗口循环（AX 枚举 → 下一个 → AXRaise）
///   - scope "global"：全局 MRU 循环（CGWindowList z 序即近似 MRU，取下一窗口 activate + AXRaise）
/// AX 调用失败一律静默降级为 NSRunningApplication.activate()，全程不抛异常。
/// 需要「辅助功能」权限（AXRaise）；无「屏幕录制」权限时窗口标题可能为空，仅影响标题匹配精度。
enum WindowSwitcher {

    static let visibleListOptions: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    static let globalListOptions: CGWindowListOption = [.optionAll, .excludeDesktopElements]

    struct WindowInfo {
        let pid: pid_t
        let windowID: CGWindowID
        let title: String
        var isMinimized: Bool = false
        /// 不在当前桌面（其他 Space）；仅在能判定时为 true
        var onOtherSpace: Bool = false
    }

    /// 窗口过滤的输入（一条 CGWindowList 记录 + 可选的 AX / Space 旁证），纯数据便于单测。
    struct Candidate {
        let pid: pid_t
        let windowID: CGWindowID
        let layer: Int
        let bounds: CGRect
        let alpha: Double
        let isOnscreen: Bool
        let cgTitle: String
        /// 该 App 的 AX 窗口列表是否成功读到（有辅助功能权限且 App 响应）
        let appAXAvailable: Bool
        /// 本窗口对应的 AX 窗口（按 CGWindowID 匹配）；nil = AX 列表里没有它
        let ax: AXMeta?
        /// 本窗口所在 Space 数；nil = 无法判定（私有接口不可用）
        let spaceCount: Int?
    }

    struct AXMeta {
        let role: String?
        let subrole: String?
        let title: String
        let minimized: Bool
    }

    /// 只保留真实的标准窗口并按 CGWindowID 去重（保持 z 序）。
    ///
    /// 根因（0634c19 起「所有 App」改用 `.optionAll`）：该选项还会返回 App 预建 / 已 orderOut
    /// 的缓存窗口、标签拖拽与弹出层等 layer 0 表面，尺寸过滤挡不住，于是一个窗口的 App
    /// 出现多张卡（magpie ×3、Chrome ×2）。判定规则：
    /// 1. layer 0、alpha > 0、尺寸 ≥ 80×60；
    /// 2. 在 AX 窗口列表里：role 为 AXWindow 且 subrole 为 AXStandardWindow / AXDialog（缺省视为标准）；
    /// 3. 不在 AX 列表里：AX 只列当前桌面与最小化窗口，所以
    ///    - 在屏上却不在 AX 列表（App 的 AX 可用）→ 非标准表面，丢弃；
    ///    - 不在屏上 → 只有确认挂在某个 Space（其他桌面）才保留；无法判定 Space 时，
    ///      仅保留有 CG 标题的（与 AX 不可用时的降级一致）。
    nonisolated static func filterStandardWindows(_ cands: [Candidate]) -> [WindowInfo] {
        var seen = Set<CGWindowID>()
        var out: [WindowInfo] = []
        for c in cands {
            guard c.layer == 0, c.alpha > 0, c.bounds.width >= 80, c.bounds.height >= 60,
                  !seen.contains(c.windowID) else { continue }
            var info: WindowInfo?
            if let ax = c.ax {
                let roleOK = ax.role == nil || ax.role == "AXWindow"
                let subOK = ax.subrole == nil || ax.subrole == "AXStandardWindow" || ax.subrole == "AXDialog"
                if roleOK && subOK {
                    info = WindowInfo(pid: c.pid, windowID: c.windowID,
                                      title: ax.title.isEmpty ? c.cgTitle : ax.title,
                                      isMinimized: ax.minimized)
                }
            } else if c.isOnscreen {
                if !c.appAXAvailable {
                    info = WindowInfo(pid: c.pid, windowID: c.windowID, title: c.cgTitle)
                }
            } else if let spaces = c.spaceCount {
                if spaces > 0 {
                    info = WindowInfo(pid: c.pid, windowID: c.windowID, title: c.cgTitle, onOtherSpace: true)
                }
            } else if !c.cgTitle.isEmpty {
                info = WindowInfo(pid: c.pid, windowID: c.windowID, title: c.cgTitle, onOtherSpace: true)
            }
            if let info {
                seen.insert(c.windowID)
                out.append(info)
            }
        }
        return out
    }

    nonisolated static func filterSelfCheck() -> Bool {
        let r = CGRect(x: 0, y: 0, width: 800, height: 600)
        func c(_ id: CGWindowID, layer: Int = 0, bounds: CGRect = r, alpha: Double = 1, on: Bool,
               title: String = "", ax: AXMeta?, axOK: Bool = true, spaces: Int?) -> Candidate {
            Candidate(pid: 42, windowID: id, layer: layer, bounds: bounds, alpha: alpha, isOnscreen: on,
                      cgTitle: title, appAXAvailable: axOK, ax: ax, spaceCount: spaces)
        }
        let std = AXMeta(role: "AXWindow", subrole: "AXStandardWindow", title: "文档 1", minimized: false)
        let mini = AXMeta(role: "AXWindow", subrole: "AXStandardWindow", title: "", minimized: true)
        let floating = AXMeta(role: "AXWindow", subrole: "AXFloatingWindow", title: "", minimized: false)
        let list = [
            c(1, on: true, ax: std, spaces: 1),                 // 标准窗：保留，标题取 AX
            c(1, on: true, ax: std, spaces: 1),                 // 同 ID 重复：去重
            c(2, on: false, ax: nil, spaces: 0),                // 缓存 / orderOut 幽灵窗：丢
            c(3, on: true, ax: nil, spaces: 1),                 // 在屏但 AX 无此窗（弹出层）：丢
            c(4, on: false, title: "其他桌面", ax: nil, spaces: 1), // 其他桌面：保留
            c(5, on: false, ax: mini, spaces: 1),               // 最小化：保留
            c(6, on: true, ax: floating, spaces: 1),            // 浮动面板：丢
            c(7, bounds: CGRect(x: 0, y: 0, width: 40, height: 40), on: true, ax: std, spaces: 1), // 太小
            c(8, alpha: 0, on: true, ax: std, spaces: 1),       // 透明
            c(9, layer: 3, on: true, ax: std, spaces: 1),       // 非普通层
            c(10, on: true, ax: nil, axOK: false, spaces: nil), // 无 AX 权限：在屏即保留
            c(11, on: false, ax: nil, axOK: false, spaces: nil),// 无 AX、无 Space、无标题：丢
        ]
        let out = filterStandardWindows(list)
        return out.map(\.windowID) == [1, 4, 5, 10]
            && out[0].title == "文档 1" && out[1].onOtherSpace && out[2].isMinimized
    }

    // MARK: - 纯逻辑（可单测）

    /// 循环取下一个下标（count<=0 时返回 0）。
    static func nextIndex(after i: Int, count: Int) -> Int {
        count <= 0 ? 0 : ((i + 1) % count + count) % count
    }

    /// 从 MRU 候选列表（前到后）里挑全局切换目标：跳过第 0 个（当前前台），有标题的优先。
    static func pickGlobalTarget(_ wins: [WindowInfo]) -> WindowInfo? {
        guard wins.count > 1 else { return nil }
        let rest = wins.dropFirst()
        return rest.first(where: { !$0.title.isEmpty }) ?? rest.first
    }

    // MARK: - 窗口枚举

    /// 当前桌面上的可见窗口（layer 0，z 序前到后 ≈ MRU）。
    static func visibleWindows() -> [WindowInfo] {
        windows(options: visibleListOptions)
    }

    /// 当前用户会话的全部普通 App 窗口，包括其他 Space/桌面和最小化窗口。
    /// `.optionAll` 会返回很多 0×0 helper/menu-bar 表面，因此统一做尺寸和 App 类型过滤。
    static func allWindows() -> [WindowInfo] {
        windows(options: globalListOptions)
    }

    private static func windows(options: CGWindowListOption) -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let myPid = getpid()
        var axCache: [pid_t: [CGWindowID: AXMeta]?] = [:]
        let cands: [Candidate] = list.compactMap { d in
            guard let layer = d[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = d[kCGWindowOwnerPID as String] as? pid_t, pid != myPid,
                  let wid = d[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = d[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width >= 80, bounds.height >= 60,
                  let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular, !app.isTerminated else { return nil }
            if axCache[pid] == nil { axCache[pid] = .some(axWindows(pid: pid)) }
            let axMap = axCache[pid] ?? nil
            return Candidate(pid: pid, windowID: wid, layer: layer, bounds: bounds,
                             alpha: (d[kCGWindowAlpha as String] as? Double) ?? 1,
                             isOnscreen: (d[kCGWindowIsOnscreen as String] as? Bool) ?? false,
                             cgTitle: d[kCGWindowName as String] as? String ?? "",
                             appAXAvailable: axMap != nil,
                             ax: axMap?[wid],
                             spaceCount: PrivateWindowServer.spaceCount(for: wid))
        }
        return filterStandardWindows(cands)
    }

    /// 某 App 的 AX 窗口（按 CGWindowID 索引）；AX 不可用或无法映射窗口 ID 时返回 nil。
    private static func axWindows(pid: pid_t) -> [CGWindowID: AXMeta]? {
        guard AXIsProcessTrusted(), PrivateWindowServer.canMapAXWindows else { return nil }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        var winsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &winsRef) == .success,
              let wins = winsRef as? [AXUIElement] else { return nil }
        var map: [CGWindowID: AXMeta] = [:]
        for w in wins {
            guard let wid = PrivateWindowServer.windowID(of: w) else { continue }
            map[wid] = AXMeta(role: axString(w, kAXRoleAttribute),
                              subrole: axString(w, kAXSubroleAttribute),
                              title: axString(w, kAXTitleAttribute) ?? "",
                              minimized: axBool(w, kAXMinimizedAttribute))
        }
        // AX 列表为空（部分 Electron / Java App 不暴露窗口）视同 AX 不可用，避免误删真实窗口
        return map.isEmpty ? nil : map
    }

    /// 卡片副标题：真实窗口标题；无标题时按状态给出说明，不重复 App 名。
    static func subtitle(for w: WindowInfo, appName: String) -> String {
        let t = w.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, t != appName { return t }
        if w.isMinimized { return "已最小化" }
        if w.onOtherSpace { return "其他桌面" }
        return "无标题窗口"
    }

    private static func axString(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private static func axBool(_ el: AXUIElement, _ attr: String) -> Bool {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return false }
        return (v as? Bool) ?? false
    }

    // MARK: - 执行入口

    static func cycle(scope: String) {
        scope == "global" ? cycleGlobal() : cycleApp()
    }

    /// 同 app 窗口循环：AX 枚举窗口 → 当前 focused 的下一个 → raise。失败降级 activate。
    private static func cycleApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var winsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &winsRef) == .success,
              let wins = winsRef as? [AXUIElement], wins.count > 1 else {
            app.activate()   // 降级：单窗口或 AX 不可用
            return
        }
        var focusedRef: CFTypeRef?
        var current = 0
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
           let f = focusedRef {
            current = wins.firstIndex(where: { CFEqual($0, f) }) ?? 0
        }
        raise(wins[nextIndex(after: current, count: wins.count)], app: app)
    }

    /// 全局 MRU 循环：z 序第二个（≈上一个用过的）窗口所属 app 前置 + 按标题 AXRaise 精确定位。
    private static func cycleGlobal() {
        guard let target = pickGlobalTarget(allWindows()),
              let app = NSRunningApplication(processIdentifier: target.pid) else { return }
        activateApplication(app) { activeApp in
            raiseMatchingWindow(target, app: activeApp)
        }
    }

    /// AXRaise + activate；AX 失败静默（activate 已保证 app 前置）。
    private static func raise(_ window: AXUIElement, app: NSRunningApplication) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        app.activate()
    }

    // MARK: - M5 v2 窗口选择器数据源与激活

    /// 选择器条目：CGWindowList 窗口 + 所属 App 的展示信息。
    struct PickerEntry {
        let window: WindowInfo
        let appName: String
        let bundleID: String?
    }

    /// 选择器候选（z 序前到后 ≈ MRU）。
    /// - currentAppOnly=true：只列 pid == frontPid 的窗口（范围「当前 App」）。
    /// - false：当前用户会话的所有 App 窗口，跨全部 Space/桌面。
    static func pickerEntries(currentAppOnly: Bool, frontPid: pid_t?) -> [PickerEntry] {
        let source = currentAppOnly ? visibleWindows() : allWindows()
        return source.compactMap { info in
            if currentAppOnly, info.pid != frontPid { return nil }
            guard let app = NSRunningApplication(processIdentifier: info.pid) else { return nil }
            return PickerEntry(window: info,
                               appName: app.localizedName ?? "未知应用",
                               bundleID: app.bundleIdentifier)
        }
    }

    /// 激活指定窗口：app 前置 + 按标题 AXRaise 精确定位（复用全局切换的成熟逻辑）。
    static func activate(_ target: WindowInfo) {
        guard let app = NSRunningApplication(processIdentifier: target.pid) else { return }
        activateApplication(app) { activeApp in
            raiseMatchingWindow(target, app: activeApp)
        }
    }

    /// 跨 App 激活统一入口。macOS 的协作式激活不保证一个后台 accessory App 直接
    /// 调用 target.activate() 能拿到焦点；NSWorkspace 会代表当前前台 App 完成交接。
    static func activateApplication(_ app: NSRunningApplication,
                                    completion: ((NSRunningApplication) -> Void)? = nil) {
        if app.isActive {
            completion?(app)
            return
        }
        guard let url = app.bundleURL else {
            _ = app.activate(options: [.activateAllWindows])
            completion?(app)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.allowsRunningApplicationSubstitution = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { running, error in
            DispatchQueue.main.async {
                let activated = running ?? app
                if error != nil {
                    _ = app.activate(options: [.activateAllWindows])
                }
                completion?(activated)
            }
        }
    }

    /// App 已前置后，按标题精确 raise 目标窗口；无标题/无 AX 权限时 App 前置即降级成果。
    private static func raiseMatchingWindow(_ target: WindowInfo, app: NSRunningApplication) {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var winsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &winsRef) == .success,
              let wins = winsRef as? [AXUIElement] else { return }
        // 优先按 CGWindowID 精确匹配（同名窗口、无标题窗口也能定位）；最小化的先还原
        if let w = wins.first(where: { PrivateWindowServer.windowID(of: $0) == target.windowID }) {
            if axBool(w, kAXMinimizedAttribute) {
                AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            return
        }
        guard !target.title.isEmpty else { return }
        for w in wins {
            var t: CFTypeRef?
            if AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t) == .success,
               let s = t as? String, s == target.title {
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
                return
            }
        }
    }
}

/// 窗口服务器私有接口（运行时 dlsym 解析，缺失即降级为纯公开 API 行为，不影响链接）。
/// - `_AXUIElementGetWindow`：AX 窗口 → CGWindowID（AltTab / Hammerspoon 等长期使用）。
/// - `CGSCopySpacesForWindows`：窗口所在 Space；orderOut 的缓存窗口不属于任何 Space。
enum PrivateWindowServer {
    private typealias AXGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private typealias MainConnFn = @convention(c) () -> Int32
    private typealias CopySpacesFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private static func sym(_ name: String) -> UnsafeMutableRawPointer? {
        let h = UnsafeMutableRawPointer(bitPattern: -2)   // RTLD_DEFAULT
        if let p = dlsym(h, name) { return p }
        if let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) {
            return dlsym(sky, name)
        }
        return nil
    }

    nonisolated(unsafe) private static let axGetWindow: AXGetWindowFn? =
        sym("_AXUIElementGetWindow").map { unsafeBitCast($0, to: AXGetWindowFn.self) }
    nonisolated(unsafe) private static let mainConn: MainConnFn? =
        (sym("CGSMainConnectionID") ?? sym("SLSMainConnectionID")).map { unsafeBitCast($0, to: MainConnFn.self) }
    nonisolated(unsafe) private static let copySpaces: CopySpacesFn? =
        (sym("CGSCopySpacesForWindows") ?? sym("SLSCopySpacesForWindows")).map { unsafeBitCast($0, to: CopySpacesFn.self) }

    static var canMapAXWindows: Bool { axGetWindow != nil }

    static func windowID(of el: AXUIElement) -> CGWindowID? {
        guard let f = axGetWindow else { return nil }
        var wid: CGWindowID = 0
        return f(el, &wid) == .success && wid != 0 ? wid : nil
    }

    /// 窗口挂在几个 Space 上（7 = 所有 Space 类型）；接口不可用返回 nil。
    static func spaceCount(for wid: CGWindowID) -> Int? {
        guard let conn = mainConn, let copy = copySpaces else { return nil }
        let arr = [NSNumber(value: wid)] as CFArray
        guard let spaces = copy(conn(), 7, arr)?.takeRetainedValue() as? [Any] else { return nil }
        return spaces.count
    }
}
