import AppKit
import SwiftUI

/// Profile 详情页与遥控器速查浮层共用的映射解析，保证两处展示的是实际生效结果。
enum MappingDetailResolver {
    static func binding(in config: MappingConfig, profile: String, key: RemoteKey) -> KeyBinding? {
        let global = config.profiles["global"]?[key.rawValue]
        guard profile != "global", let overlay = config.profiles[profile]?[key.rawValue] else {
            return global
        }
        guard var merged = global else { return overlay }
        if let v = overlay.tap { merged.tap = v }
        if let v = overlay.hold { merged.hold = v }
        if let v = overlay.double { merged.double = v }
        if let values = overlay.gesture {
            var result = merged.gesture ?? [:]
            for (name, action) in values { result[name] = action }
            merged.gesture = result
        }
        if let values = overlay.layers {
            var result = merged.layers ?? [:]
            for (name, action) in values { result[name] = action }
            merged.layers = result
        }
        return merged
    }

    static func ownsOverride(in config: MappingConfig, profile: String, key: RemoteKey) -> Bool {
        profile == "global" || config.profiles[profile]?[key.rawValue] != nil
    }
}

/// 一张能完整看到短按、长按、双击、功能模式和 OK 手势的映射表。
struct MappingDetailView: View {
    let config: MappingConfig
    let profile: String
    var appName: String? = nil
    var isQuickLook = false
    var onEdit: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil

    private let keys: [RemoteKey] = [
        .up, .down, .left, .right, .ok, .back, .home, .menu, .tv,
        .volUp, .volDown, .voice, .power,
    ]

    @Environment(\.dismiss) private var dismiss

    private static let footnote = "长按主页键可随时打开这张表；浮层打开期间遥控键不会触发原动作。"

    private var titleText: String {
        appName ?? (profile == "global" ? "全局默认" : profileDisplayName(profile))
    }

    private var subtitleText: String {
        profile == "global" ? "所有 App 的基础映射" : "当前实际生效映射 · 未覆盖项继承全局"
    }

    var body: some View {
        if isQuickLook {
            quickLookBody
        } else {
            SheetScaffold(title: titleText, subtitle: subtitleText, onClose: { dismiss() }) {
                // 骨架无图标位：应用图标放在正文顶部（T12 允许的小偏差）
                appIcon
                table
            } footer: {
                Text(Self.footnote)
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if let onEdit {
                    Button("编辑映射", action: onEdit)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .noWrap()
                }
            }
        }
    }

    /// 映射速查浮层：保留原布局，背景换成统一浮层外观。
    private var quickLookBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                appIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(.title.bold())
                    Text(subtitleText)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("再按主页 / 返回键或 Esc 关闭")
                    .font(.caption).foregroundStyle(.secondary)
                if let onEdit {
                    Button("编辑映射", action: onEdit).buttonStyle(.borderedProminent)
                }
                if let onClose {
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).help("关闭")
                }
            }

            table

            Text(Self.footnote)
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(Spacing.sheetPadding)
        .frame(minWidth: 760, minHeight: 500)
        .glassSurface(.overlay, in: RoundedRectangle(cornerRadius: Radius.overlay))
    }

    /// 表头说明 + 表头行 + 13 行映射表（sheet 与速查共用）。
    private var table: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(BaseTapNote.detailHeader)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 0) {
                tableHeader("遥控键", width: 116)
                tableHeader("短按", width: 170)
                tableHeader("长按", width: 170)
                tableHeader("双击", width: 150)
                tableHeader("更多", width: nil)
            }
            .padding(.horizontal, 10)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                        if index > 0 { Divider() }
                        mappingRow(key)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        }
    }

    private func tableHeader(_ title: String, width: CGFloat?) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .noWrap()
            .frame(width: width, alignment: .leading)
    }

    private func mappingRow(_ key: RemoteKey) -> some View {
        let binding = MappingDetailResolver.binding(in: config, profile: profile, key: key)
        let overlay = profile == "global" ? nil : config.profiles[profile]?[key.rawValue]
        return HStack(alignment: .top, spacing: 0) {
            HStack(spacing: 7) {
                Text(KeyDisplay.badge(key)).font(.caption2.weight(.bold))
                    .frame(width: 27, height: 24)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.small))
                VStack(alignment: .leading, spacing: 1) {
                    Text(KeyDisplay.name(key)).font(.caption)
                    if profile != "global" {
                        Text(overlay == nil ? "全部继承" : "含 App 覆盖")
                            .font(.caption2).foregroundStyle(overlay == nil ? .secondary : Color.accentColor)
                    }
                }
            }
            .frame(width: 116, alignment: .leading)
            actionText(binding?.tap, width: 170,
                       source: SlotResolver.resolve(config: config, profile: profile, key: key, slot: .tap).source)
            actionText(binding?.hold, width: 170,
                       source: SlotResolver.resolve(config: config, profile: profile, key: key, slot: .hold).source)
            actionText(binding?.double, width: 150,
                       source: SlotResolver.resolve(config: config, profile: profile, key: key, slot: .double).source)
            VStack(alignment: .leading, spacing: 2) {
                Text(moreSummary(binding))
                    .font(.caption).foregroundStyle(moreSummary(binding) == "—" ? .tertiary : .secondary)
                    .lineLimit(3)
                if moreSummary(binding) != "—" {
                    SourceTag(source: (overlay?.gesture != nil || overlay?.layers != nil) ? .appOverride : .inherited,
                              profile: profile)
                }
            }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func actionText(_ action: Action?, width: CGFloat, source: SlotSource) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ActionSummary.describe(action))
                .font(.caption)
                .foregroundStyle(action == nil || action == Action.none ? .tertiary : .primary)
                .lineLimit(2)
            SourceTag(source: source, profile: profile)
        }
            .frame(width: width, alignment: .leading)
    }

    private func moreSummary(_ binding: KeyBinding?) -> String {
        var parts: [String] = []
        if let layers = binding?.layers {
            for (number, action) in layers.sorted(by: { $0.key < $1.key }) {
                let name = Int(number).map(modeDisplayName) ?? "模式 \(number)"
                parts.append("\(name)：\(ActionSummary.describe(action))")
            }
        }
        if let gestures = binding?.gesture {
            let names = ["up": "↑", "down": "↓", "left": "←", "right": "→"]
            for direction in ["up", "down", "left", "right"] {
                if let action = gestures[direction] {
                    parts.append("按住 OK+\(names[direction]!)：\(ActionSummary.describe(action))")
                }
            }
        }
        return parts.isEmpty ? "—" : parts.joined(separator: "\n")
    }

    @ViewBuilder private var appIcon: some View {
        if profile == "global" {
            Image(systemName: "globe").font(.title2).foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: profile) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
                .frame(width: 38, height: 38)
        } else {
            Image(systemName: "app").font(.title2).foregroundStyle(.secondary)
                .frame(width: 38, height: 38)
        }
    }
}

/// 不抢焦点、跨桌面显示的当前 App 映射速查窗。
@MainActor
final class MappingQuickLookController {
    private weak var model: AppModel?
    private var panel: NSPanel?
    private(set) var isVisible = false

    init(model: AppModel) { self.model = model }

    func setVisible(_ visible: Bool, bundleID: String?, appName: String?) {
        visible ? show(bundleID: bundleID, appName: appName) : hide()
    }

    private func show(bundleID: String?, appName: String?) {
        guard let model else { return }
        let profile = bundleID ?? "global"
        let root = MappingDetailView(config: model.config, profile: profile,
                                     appName: appName, isQuickLook: true,
                                     onClose: nil)
        // 与其余浮层同款 HUD：无边框透明面板 + 材质圆角大卡（视觉体系统一）
        let host = NSHostingView(rootView: root
            .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
            .padding(28))
        let p = panel ?? NSPanel(contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: true)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host
        // 高度尽量容纳全部 13 行（约 880pt 含外边距），超出屏幕 90% 时回退为内部滚动
        let maxHeight = (NSScreen.main?.visibleFrame.height ?? 900) * 0.9
        p.setContentSize(NSSize(width: 960, height: min(880, maxHeight)))
        p.center()
        panel = p
        isVisible = true
        p.orderFrontRegardless()
    }

    private func hide() {
        isVisible = false
        panel?.orderOut(nil)
    }
}
