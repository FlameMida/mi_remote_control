import SwiftUI
import AppKit

/// 设置窗当前最需要处理的一个问题。优先级：通道故障 > 缺权限 > 未连接 > 已暂停。
/// 侧栏问题行与四页横幅共用同一判定，保证两处说的是同一件事。
enum StatusIssue: Equatable {
    case degraded
    case permission(String)
    case disconnected
    case paused

    static func current(degraded: Bool, missingPermission: String?,
                        connected: Bool, suspended: Bool) -> StatusIssue? {
        if degraded { return .degraded }
        if let missingPermission { return .permission(missingPermission) }
        if !connected { return .disconnected }
        if suspended { return .paused }
        return nil
    }

    /// 页内横幅过滤：映射 / 场景显示全部；语音只显示未连接、已暂停；通用只显示缺权限、通道故障。
    static func banner(for page: SidebarItem, issue: StatusIssue?) -> StatusIssue? {
        guard let issue else { return nil }
        switch page {
        case .mapping, .profile:
            return issue
        case .voice:
            switch issue {
            case .disconnected, .paused: return issue
            default: return nil
            }
        case .general:
            switch issue {
            case .permission, .degraded: return issue
            default: return nil
            }
        }
    }

    /// 侧栏问题行：已暂停不占侧栏（菜单栏与横幅已说明）。
    static func sidebarRow(_ issue: StatusIssue?) -> StatusIssue? {
        guard let issue, issue != .paused else { return nil }
        return issue
    }

    var rowText: String {
        switch self {
        case .permission(let name): return "缺少\(name)权限"
        case .degraded:             return "按键通道异常"
        case .disconnected:         return "遥控器未连接"
        case .paused:               return "遥控已暂停"
        }
    }

    var rowAction: String {
        switch self {
        case .permission:   return "修复"
        case .degraded:     return "体检"
        case .disconnected: return "配对"
        case .paused:       return ""
        }
    }

    var rowSymbol: String {
        switch self {
        case .permission:   return "exclamationmark.triangle"
        case .degraded:     return "xmark.octagon"
        case .disconnected: return "antenna.radiowaves.left.and.right.slash"
        case .paused:       return "pause.circle"
        }
    }

    var rowTint: Color {
        switch self {
        case .degraded:   return .red
        case .permission: return .orange
        default:          return .secondary
        }
    }

    var bannerTitle: String {
        switch self {
        case .permission(let name): return "缺少\(name)权限"
        case .degraded:             return "按键通道异常"
        case .disconnected:         return "遥控器未连接"
        case .paused:               return "遥控已暂停"
        }
    }

    var bannerDetail: String {
        switch self {
        case .permission:   return "遥控器按键暂时无法被接管。"
        case .degraded:     return "事件注入通道失效，映射暂不生效。"
        case .disconnected: return "可以继续编辑映射，连上后即时生效。长按「主页 + 返回」进入配对。"
        case .paused:       return "按键与手势暂不生效，真实键盘不受影响。"
        }
    }

    var bannerAction: String? {
        switch self {
        case .permission:   return "一键体检与修复"
        case .degraded:     return "打开体检"
        case .disconnected: return "配对引导"
        case .paused:       return nil
        }
    }

    var bannerKind: StatusBanner.Kind {
        switch self {
        case .degraded:                   return .error
        case .permission, .disconnected:  return .warning
        case .paused:                     return .info
        }
    }

    static func selfCheck() -> Bool {
        var ok = true
        func check(_ c: Bool) { if !c { ok = false } }

        check(current(degraded: true, missingPermission: "输入监控", connected: false, suspended: true) == .degraded)
        check(current(degraded: false, missingPermission: "输入监控", connected: false, suspended: false) == .permission("输入监控"))
        check(current(degraded: false, missingPermission: nil, connected: false, suspended: true) == .disconnected)
        check(current(degraded: false, missingPermission: nil, connected: true, suspended: true) == .paused)
        check(current(degraded: false, missingPermission: nil, connected: true, suspended: false) == nil)

        let all: [StatusIssue] = [.degraded, .permission("输入监控"), .disconnected, .paused]
        for issue in all {
            check(banner(for: .mapping, issue: issue) == issue)
            check(banner(for: .profile, issue: issue) == issue)
            let voiceShows = issue == .disconnected || issue == .paused
            check(banner(for: .voice, issue: issue) == (voiceShows ? issue : nil))
            let generalShows: Bool
            if case .permission = issue { generalShows = true } else { generalShows = issue == .degraded }
            check(banner(for: .general, issue: issue) == (generalShows ? issue : nil))
            check(sidebarRow(issue) == (issue == .paused ? nil : issue))
        }
        for page in SidebarItem.allCases { check(banner(for: page, issue: nil) == nil) }
        check(sidebarRow(nil) == nil)

        let p = StatusIssue.permission("输入监控")
        check(p.rowText == "缺少输入监控权限" && p.rowAction == "修复"
              && p.bannerTitle == "缺少输入监控权限" && p.bannerDetail == "遥控器按键暂时无法被接管。"
              && p.bannerAction == "一键体检与修复")
        let d = StatusIssue.degraded
        check(d.rowText == "按键通道异常" && d.rowAction == "体检"
              && d.bannerTitle == "按键通道异常" && d.bannerDetail == "事件注入通道失效，映射暂不生效。"
              && d.bannerAction == "打开体检")
        let n = StatusIssue.disconnected
        check(n.rowText == "遥控器未连接" && n.rowAction == "配对"
              && n.bannerTitle == "遥控器未连接"
              && n.bannerDetail == "可以继续编辑映射，连上后即时生效。长按「主页 + 返回」进入配对。"
              && n.bannerAction == "配对引导")
        let s = StatusIssue.paused
        check(s.bannerTitle == "遥控已暂停" && s.bannerDetail == "按键与手势暂不生效，真实键盘不受影响。"
              && s.bannerAction == nil)
        return ok
    }
}

// MARK: - 环境值

private struct StatusIssueKey: EnvironmentKey {
    static let defaultValue: StatusIssue? = nil
}

private struct StatusFixKey: EnvironmentKey {
    static let defaultValue: (StatusIssue) -> Void = { _ in }
}

extension EnvironmentValues {
    var statusIssue: StatusIssue? {
        get { self[StatusIssueKey.self] }
        set { self[StatusIssueKey.self] = newValue }
    }
    var statusFix: (StatusIssue) -> Void {
        get { self[StatusFixKey.self] }
        set { self[StatusFixKey.self] = newValue }
    }
}

// MARK: - 视图

/// 页标题下的问题横幅；按页过滤，侧栏隐藏时同样显示。
struct PageStatusBanner: View {
    let page: SidebarItem
    @Environment(\.statusIssue) private var statusIssue
    @Environment(\.statusFix) private var statusFix

    var body: some View {
        if let issue = StatusIssue.banner(for: page, issue: statusIssue) {
            StatusBanner(kind: issue.bannerKind,
                         title: issue.bannerTitle,
                         detail: issue.bannerDetail,
                         actionTitle: issue.bannerAction,
                         action: { statusFix(issue) })
        }
    }
}

/// 侧栏头下方的一行问题提示：图标 + 文案 + 右侧动作，整行可点。
struct SidebarIssueRow: View {
    @Environment(\.statusIssue) private var statusIssue
    @Environment(\.statusFix) private var statusFix

    var body: some View {
        if let issue = StatusIssue.sidebarRow(statusIssue) {
            Button {
                statusFix(issue)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: issue.rowSymbol)
                        .foregroundStyle(issue.rowTint)
                        .accessibilityHidden(true)
                    Text(issue.rowText)
                        .font(.callout)
                        .noWrap()
                    Spacer(minLength: 4)
                    Text(issue.rowAction)
                        .font(.callout)
                        .foregroundStyle(Color.accentColor)
                        .noWrap()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(issue.rowText)，\(issue.rowAction)")
        }
    }
}

/// 输入监控 / 辅助功能授权状态。系统不推送变化，启动与 App 激活时刷新。
@MainActor
final class PermissionStatus: ObservableObject {
    @Published private(set) var missing: String?
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() {
        let value: String?
        if EnvironmentCheck.inputMonitoring().state != .granted {
            value = "输入监控"
        } else if EnvironmentCheck.accessibility().state != .granted {
            value = "辅助功能"
        } else {
            value = nil
        }
        if value != missing { missing = value }
    }
}
