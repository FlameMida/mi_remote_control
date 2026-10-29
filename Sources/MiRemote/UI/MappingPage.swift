import SwiftUI

// MARK: - 通用卡片组件（复刻 macOS 系统设置分组外观）

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) { content }
                .cardBackground(in: RoundedRectangle(cornerRadius: Radius.card))
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    var icon: String
    var iconColor: Color = .accentColor
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        // 原型行无前置图标（icon 参数保留给调用方，不再绘制）
        HStack(spacing: Spacing.intra) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, Spacing.rowH)
        .padding(.vertical, Spacing.rowV)
        .frame(minHeight: Spacing.rowMinHeight)
    }
}

struct RowDivider: View {
    var body: some View {
        Divider().padding(.leading, Spacing.rowH)
    }
}

// MARK: - 映射页

@MainActor
struct MappingPage: View {
    @EnvironmentObject var model: AppModel
    @State private var showKeyLearn = false
    @State private var showSaved = false
    @State private var annotationLayer: AnnotationLayer = .base
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let onOpenProfiles: () -> Void

    private var glassOn: Bool {
        GlassSurface.appearance(kind: .panel, glassAvailable: GlassSurface.glassAvailable,
                                reduceTransparency: reduceTransparency) == .liquidGlass
    }

    init(onOpenProfiles: @escaping () -> Void) {
        self.onOpenProfiles = onOpenProfiles
    }

    var body: some View {
        // 直接按详情栏实宽排版（减页边距与可能出现的常驻滚动条），不走 preference 回传，避免首帧停在窄态
        GeometryReader { geo in
            content(contentWidth: geo.size.width - Spacing.page * 2 - 16)
        }
    }

    private func content(contentWidth: CGFloat) -> some View {
        let pl = RemoteAnnotationLayout.panelLayout(contentWidth: contentWidth)
        let pad: CGFloat = pl.annotated ? 0 : (Spacing.page - 16) * 2
        let inspectorWidth = contentWidth + pad - RemoteAnnotationLayout.columnGap - pl.panelWidth
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                header
                PageStatusBanner(page: .mapping)
                SceneChip(profile: model.currentProfile,
                          overrideCount: model.config.profiles[model.currentProfile]?.count ?? 0,
                          onOpen: onOpenProfiles)
                if model.activeLayer != 0 {
                    Label("已开启：\(modeDisplayName(model.activeLayer))（同一按键现在使用第二功能）", systemImage: "switch.2")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                HStack(alignment: .top, spacing: RemoteAnnotationLayout.columnGap) {
                    remotePanel(pl)
                    keyEditor
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .environment(\.compactSlotRows, inspectorWidth < RemoteAnnotationLayout.inspectorMinWidth)
                }
            }
            // 原型 .win.narrow .main padding 16（宽态 24）
            .padding(.horizontal, pl.annotated ? Spacing.page : 16)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showKeyLearn) { KeyLearnSheet() }
        .onChange(of: model.savedTick) {
            withAnimation(Motion.quickFade) { showSaved = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                withAnimation(Motion.toastFade) { showSaved = false }
            }
        }
    }

    private var header: some View {
        PageHeader(title: "按键映射",
                   subtitle: model.currentProfile == "global"
                   ? "点击左侧遥控器上的按键，编辑它的触发动作。改动即时保存并生效。"
                   : "正在编辑场景「\(profileDisplayName(model.currentProfile))」的覆盖绑定。") {
            if showSaved {
                Label("已保存", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .noWrap()
                    .transition(.opacity)
            }
            Spacer(minLength: 12)
            Button {
                showKeyLearn = true
            } label: {
                Label("识别按键", systemImage: "dot.radiowaves.left.and.right").noWrap()
            }
            .help("按一下遥控器上的键，识别它是哪个键")
            .glassButton()
        }
    }

    /// 原型 .mwrap：宽态遥控器面板 520（标注两侧 + 引线）为主栏，检查器取剩余宽；
    /// 面板不够 520 时等比缩小标注舞台，再窄才退回 240 窄态（只留缩小的示意图）
    private func remotePanel(_ pl: RemoteAnnotationLayout.PanelLayout) -> some View {
        let annotated = pl.annotated
        return VStack(alignment: annotated ? .leading : .center, spacing: Spacing.intra) {
            // 原型 .rtop：「示意图显示」在分段左侧同行；窄态 240 面板放不下时换到下一行（flex-wrap）
            let layout = annotated
                ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 4))
            layout {
                Text("示意图显示")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .noWrap()
                PanelSegmented(selection: $annotationLayer,
                               glass: glassOn,
                               options: AnnotationLayer.allCases.map { ($0, $0.title) })
                    .fixedSize()
                    .accessibilityLabel("示意图显示")
            }
            .frame(maxWidth: .infinity, alignment: annotated ? .leading : .center)
            RemoteAnnotationStage(layer: $annotationLayer, showsAnnotations: annotated, scale: pl.scale)
                .frame(maxWidth: .infinity)
            Text("深色圆键为遥控器实体按键位置示意，选中的按键以强调色描边高亮")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: annotated ? .infinity : 190)
            HStack(spacing: 12) {
                legendItem(model.currentProfile == "global" ? "已设置" : "App 覆盖", color: .accentColor)
                if annotated {
                    legendItem("继承全局（虚线）", color: Color(nsColor: .tertiaryLabelColor))
                }
            }
            .padding(.horizontal, 4)
        }
        // 原型 .rpanel padding 10 10 8；宽 520（不足时缩），窄态 240
        .padding(.horizontal, RemoteAnnotationLayout.panelPadding)
        .padding(.top, RemoteAnnotationLayout.panelPadding)
        .padding(.bottom, 8)
        .frame(width: pl.panelWidth)
        .cardBackground(in: RoundedRectangle(cornerRadius: Radius.hud))
        .overlay(RoundedRectangle(cornerRadius: Radius.hud)
            .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
    }

    private func legendItem(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption2).foregroundStyle(.secondary).noWrap()
        }
    }

    // MARK: KeyEditor

    private var keyEditor: some View {
        let key = model.selectedKey
        let binding = model.binding(for: key)
        return VStack(alignment: .leading, spacing: Spacing.section) {
            // 头部
            HStack(spacing: Spacing.intra) {
                Text(KeyDisplay.badge(key))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.badge))
                VStack(alignment: .leading, spacing: 1) {
                    Text(KeyDisplay.name(key)).font(.title3.weight(.semibold))
                    Text(KeyDisplay.usage(key)).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .animation(Motion.select, value: key)

            // 分组 A：触发方式
            SettingsGroup(title: "触发方式") {
                SlotRow(key: key, slot: .tap, icon: "checkmark", iconColor: .blue,
                        title: "短按", subtitle: "松开时立即触发",
                        note: BaseTapNote.text(key: key, profile: model.currentProfile, ownTap: binding.tap)) { new in
                    model.updateBinding(for: key) { $0.tap = new }
                }
                RowDivider()
                SlotRow(key: key, slot: .hold, icon: "clock", iconColor: .orange, title: "长按",
                        subtitle: "超过 \(model.config.settings.holdMs) ms 触发", note: nil) { new in
                    model.updateBinding(for: key) { $0.hold = new }
                }
                RowDivider()
                SlotRow(key: key, slot: .double, icon: "ellipsis", iconColor: .purple, title: "双击",
                        subtitle: model.config.settings.doubleMs > 0
                            ? "\(model.config.settings.doubleMs)ms 窗口内连按两次；配了双击后此键短按需等窗口确认"
                            : "已关闭（在通用页开启）", note: nil) { new in
                    model.updateBinding(for: key) { $0.double = new }
                }
            }

            // 分组 B：手势（仅 OK；零同按原则——默认配置无同按手势时不展示此组，
            // 配置里有绑定才显示，高级用户可经 config.json 自配后在此编辑）
            if key == .ok, binding.gesture?.isEmpty == false {
                SettingsGroup(title: "手势（按住 OK + 方向键）") {
                    ForEach(Array(zip(["up", "down", "left", "right"],
                                      ["arrow.up", "arrow.down", "arrow.left", "arrow.right"])), id: \.0) { dir, sym in
                        if dir != "up" { RowDivider() }
                        SlotRow(key: key, slot: .gesture(dir), icon: sym, iconColor: .teal,
                                title: gestureTitle(dir), subtitle: nil, note: nil) { new in
                            model.updateBinding(for: key) { b in
                                var g = b.gesture ?? [:]
                                if let new { g[dir] = new } else { g.removeValue(forKey: dir) }
                                b.gesture = g.isEmpty ? nil : g
                            }
                        }
                    }
                }
            }

            // 分组 C：第二功能模式（底层仍沿用 layer 配置格式，UI 不暴露术语）
            DisclosureGroup {
                Text("功能模式类似遥控器的 Fn：按住 OK 使用快捷控制（切 App、桌面空间等）；单击 TV 进出 App 控制模式（批准、拒绝、切换 agent，屏幕角落有键位提示）。")
                    .font(.caption).foregroundStyle(.secondary).padding(.bottom, 4)
                SettingsGroup(title: "模式开启时，这个键执行") {
                    ForEach(1...3, id: \.self) { layer in
                        if layer != 1 { RowDivider() }
                        SlotRow(key: key, slot: .layer(layer), icon: "switch.2", iconColor: .blue,
                                title: modeDisplayName(layer), subtitle: nil, note: nil) { new in
                            model.updateBinding(for: key) { b in
                                var l = b.layers ?? [:]
                                if let new { l["\(layer)"] = new } else { l.removeValue(forKey: "\(layer)") }
                                b.layers = l.isEmpty ? nil : l
                            }
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                Text("第二功能模式（高级）").font(.callout)
            }

            Text("绑定组合键可点击「录制快捷键」。如果不确定当前状态，可再按一下 TV 键退出 App 控制模式。")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func gestureTitle(_ dir: String) -> String {
        ["up": "上", "down": "下", "left": "左", "right": "右"][dir].map { "OK + \($0)" } ?? dir
    }
}

// MARK: - 检查器槽位行（来源标签 / 恢复继承 / 基础状态说明）

@MainActor
private struct SlotRow: View {
    @EnvironmentObject var model: AppModel
    let key: RemoteKey
    let slot: MappingSlot
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    let note: String?
    let onChange: (Action?) -> Void
    @Environment(\.compactSlotRows) private var compact

    init(key: RemoteKey, slot: MappingSlot, icon: String, iconColor: Color, title: String,
         subtitle: String?, note: String?, onChange: @escaping (Action?) -> Void) {
        self.key = key
        self.slot = slot
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.note = note
        self.onChange = onChange
    }

    var body: some View {
        let r = SlotResolver.resolve(config: model.config, profile: model.currentProfile, key: key, slot: slot)
        VStack(alignment: .leading, spacing: 0) {
            // 与 SettingsRow 同布局，标题列下方加来源标签
            HStack(spacing: Spacing.intra) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body).noWrap()
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    if model.currentProfile != "global", r.source != .unset {
                        SourceTag(source: r.source, profile: model.currentProfile)
                            .padding(.top, 2)
                    }
                }
                // 窄检查器里标题不让位给动作选择器（否则「短按」被挤没）；副标题可换行。
                // 原型 .slot .nm 有固定列宽；窄态检查器用 64 列宽，选择器可截断而不是挤出卡片
                .frame(minWidth: compact ? 64 : 96, maxWidth: compact ? 64 : nil, alignment: .leading)
                .layoutPriority(1)
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                    ActionPicker(action: r.action, compact: compact, onChange: onChange)
                        .foregroundStyle(r.source == .inherited ? .secondary : .primary)
                    if r.source == .appOverride && model.currentProfile != "global" {
                        Button("↺ 恢复") { model.restoreInherited(key, slot: slot) }
                            .buttonStyle(.link)
                            .noWrap()
                            .help("恢复继承（删除本 App 的覆盖）")
                    }
                }
            }
            .padding(.horizontal, Spacing.rowH)
            .padding(.vertical, Spacing.rowV)
            .frame(minHeight: Spacing.rowMinHeight)
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, Spacing.rowH)
                    .padding(.trailing, Spacing.rowH)
                    .padding(.bottom, Spacing.rowV)
            }
        }
    }
}

// MARK: - 场景标签（只读；点击只跳到场景配置页，不切换场景）

struct SceneChip: View {
    let profile: String
    let overrideCount: Int
    let onOpen: () -> Void

    init(profile: String, overrideCount: Int, onOpen: @escaping () -> Void) {
        self.profile = profile
        self.overrideCount = overrideCount
        self.onOpen = onOpen
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Text(profile == "global" ? "全局默认" : profileDisplayName(profile))
                    .font(.callout.weight(.semibold))
                    .noWrap()
                Text(profile == "global" ? "适用于所有未单独配置的 App"
                                         : "已覆盖 \(overrideCount) 个键 · 其余继承全局")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .noWrap()
                Text("在场景配置中切换 ›")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .noWrap()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .glassSurface(.overlay, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("场景在「场景配置」页选择；本页只显示当前场景")
    }
}

func profileDisplayName(_ bundleID: String) -> String {
    if bundleID == "global" { return "全局默认（Global）" }
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
        return FileManager.default.displayName(atPath: url.path)
    }
    return bundleID
}

// MARK: - 识别按键 sheet（学习模式：显示下一个按下的遥控键）

@MainActor
struct KeyLearnSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var learned: RemoteKey?

    var body: some View {
        SheetScaffold(title: "识别按键", subtitle: nil, onClose: { dismiss() }) {
          VStack(spacing: 14) {
            if let key = learned {
                RemoteDiagram(selected: .constant(key), flashing: key, connected: model.connected,
                              interactive: false, model: model.remoteModel)
                    .frame(width: 76)
                VStack(spacing: 6) {
                    Text(KeyDisplay.badge(key))
                        .font(.title.bold())
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                    Text(KeyDisplay.name(key)).font(.title3.weight(.semibold))
                    Text(KeyDisplay.usage(key)).font(.caption).foregroundStyle(.secondary)
                }
            } else if model.connected || model.services?.started == true {
                ProgressView().controlSize(.small)
                Text("请按一下遥控器上的任意键…")
                    .font(.callout)
                Text("识别期间按键不触发映射之外的额外动作")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("引擎未运行（预览模式或遥控器未连接），无法识别").font(.callout)
            }
          }
          .frame(maxWidth: .infinity)
        } footer: {
            if let key = learned {
                Spacer()
                Button("再识别一个") { learned = nil }
                Button("编辑此键") {
                    model.selectedKey = key
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 320)
        .onChange(of: model.lastPressedKey) { _, new in
            if let new, learned == nil { learned = new }
        }
    }
}

private struct CompactSlotRowsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// 窄态检查器（窄于 inspectorMinWidth）：槽位标题列固定 64，动作选择器可截断
    var compactSlotRows: Bool {
        get { self[CompactSlotRowsKey.self] }
        set { self[CompactSlotRowsKey.self] = newValue }
    }
}
