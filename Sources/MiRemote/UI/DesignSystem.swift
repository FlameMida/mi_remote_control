import SwiftUI

// MARK: - 全局设计常量（HIG 对齐：统一间距 / 圆角 / 动效，消灭散落的魔法数字）

/// 间距体系：页面 24 / 组间 20 / 组内 10 / 行内 14×8。
enum Spacing {
    /// 页面内容四周留白
    static let page: CGFloat = 24
    /// 分组（卡片）之间的垂直距离
    static let section: CGFloat = 20
    /// 组内元素间距（图标与文字、标题与卡片）
    static let intra: CGFloat = 10
    /// 行左右内边距
    static let rowH: CGFloat = 14
    /// 行上下内边距
    static let rowV: CGFloat = 8
    /// 表单行最小高度
    static let rowMinHeight: CGFloat = 38
    /// 卡片内自由布局的内边距
    static let cardPadding: CGFloat = 14
    /// sheet / 浮层容器的内边距
    static let sheetPadding: CGFloat = 20
}

/// 圆角体系：小微章 6 / 控件徽标 7 / 卡片 10 / HUD 12 / 浮层 16。
enum Radius {
    static let small: CGFloat = 6
    static let badge: CGFloat = 7
    static let card: CGFloat = 10
    static let hud: CGFloat = 12
    static let overlay: CGFloat = 16
}

/// 动效体系：浮层弹入用 spring，选中/焦点切换用 0.15s 缓动；
/// AppKit 侧（NSAnimationContext）淡入/淡出统一走这两个时长。
enum Motion {
    static let overlay = Animation.spring(response: 0.3, dampingFraction: 0.85)
    static let select = Animation.easeInOut(duration: 0.15)
    static let focus = Animation.easeInOut(duration: 0.2)
    static let fadeInDuration: TimeInterval = 0.18
    static let fadeOutDuration: TimeInterval = 0.2
    /// 微提示出现 / 退场（「已保存」一类 toast）
    static let quickFade = Animation.easeIn(duration: 0.1)
    static let toastFade = Animation.easeOut(duration: 0.4)
    /// 实时电平表刷新
    static let meter = Animation.linear(duration: 0.08)
}

/// 每页统一的大标题 + 副标题（复刻系统设置左对齐版式）。
/// 标题行可带右侧附件（如「已保存」「识别按键」），副标题单独一行占满宽度，
/// 不被右侧按钮挤压（spec「短标签不断行与标题区排版」）。
struct PageHeader<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let accessory: Accessory

    init(title: String, subtitle: String?, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.title2.weight(.semibold)).noWrap()
                accessory
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension PageHeader where Accessory == EmptyView {
    init(title: String, subtitle: String?) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - 玻璃表面（macOS 26 液态玻璃 + 回退）
//
// 玻璃判断的唯一落点：窗体不各自判断系统版本（spec「macOS 26 液态玻璃与回退」）。
// 侧栏与工具栏交给系统（NavigationSplitView + 桥接工具栏），这里只处理需要手工上材质的表面。

enum GlassKind {
    case sheet, panel, overlay
}

enum GlassAppearance: Equatable {
    case liquidGlass, material, opaque
}

enum GlassSurface {
    /// 外观选择规则（纯函数）：降低透明度一律不透明；有玻璃 API 用液态玻璃；
    /// 否则菜单栏面板保持原版不透明，其余用 material。
    static func appearance(kind: GlassKind, glassAvailable: Bool, reduceTransparency: Bool) -> GlassAppearance {
        if reduceTransparency { return .opaque }
        if glassAvailable { return .liquidGlass }
        return kind == .panel ? .opaque : .material
    }

    /// 运行时是否可用液态玻璃：需要 Swift 6.2（Xcode 26 SDK）编译且运行在 macOS 26+。
    static var glassAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26, *) { return true }
        #endif
        return false
    }

    static func selfCheck() -> Bool {
        var ok = true
        func check(_ cond: Bool, _ msg: String) {
            if !cond { ok = false; print("[GlassSurface.selfCheck] FAIL: \(msg)") }
        }
        check(appearance(kind: .overlay, glassAvailable: true, reduceTransparency: false) == .liquidGlass,
              "overlay + glass = liquidGlass")
        check(appearance(kind: .sheet, glassAvailable: false, reduceTransparency: false) == .material,
              "sheet fallback = material")
        check(appearance(kind: .panel, glassAvailable: false, reduceTransparency: false) == .opaque,
              "panel fallback = opaque")
        for kind in [GlassKind.sheet, .panel, .overlay] {
            for glass in [true, false] {
                check(appearance(kind: kind, glassAvailable: glass, reduceTransparency: true) == .opaque,
                      "reduceTransparency = opaque (\(kind), glass=\(glass))")
            }
        }
        return ok
    }
}

/// 三种外观只改背景，不改 padding / frame，保证信息、布局与命中区一致。
private struct GlassSurfaceModifier<S: Shape>: ViewModifier {
    let kind: GlassKind
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        switch GlassSurface.appearance(kind: kind,
                                       glassAvailable: GlassSurface.glassAvailable,
                                       reduceTransparency: reduceTransparency) {
        case .liquidGlass:
            liquidGlass(content)
        case .material:
            content
                .background(.regularMaterial, in: shape)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        case .opaque:
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.stroke(Color(nsColor: .separatorColor)))
        }
    }

    @ViewBuilder
    private func liquidGlass(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
        #else
        content.background(.regularMaterial, in: shape)
        #endif
    }
}

private struct GlassSheetBackgroundModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        switch GlassSurface.appearance(kind: .sheet,
                                       glassAvailable: GlassSurface.glassAvailable,
                                       reduceTransparency: reduceTransparency) {
        case .liquidGlass:
            // 系统 sheet 在 macOS 26 自带玻璃
            content
        case .material:
            content.presentationBackground(.regularMaterial)
        case .opaque:
            content.presentationBackground(Color(nsColor: .windowBackgroundColor))
        }
    }
}

extension View {
    /// 按 GlassSurface 规则给表面上玻璃 / 材质 / 不透明背景。
    func glassSurface<S: Shape>(_ kind: GlassKind, in shape: S) -> some View {
        modifier(GlassSurfaceModifier(kind: kind, shape: shape))
    }

    /// sheet 背景：macOS 26 交给系统玻璃，回退时用材质或不透明窗口背景。
    func glassSheetBackground() -> some View {
        modifier(GlassSheetBackgroundModifier())
    }

    /// 短标签不在词中断行（「已保存」「识别按键」「电量 82%」）。
    func noWrap() -> some View {
        lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - 页内横幅

/// 统一的状态横幅：线条图标（非填充、非 emoji）+ 标题（可换行，左缘对齐文字列）+ 可选按钮。
struct StatusBanner: View {
    enum Kind { case warning, error, info }

    let kind: Kind
    let title: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(kind: Kind, title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.kind = kind
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    private var symbol: String {
        switch kind {
        case .warning: return "exclamationmark.triangle"
        case .error:   return "xmark.octagon"
        case .info:    return "info.circle"
        }
    }

    private var tint: Color {
        switch kind {
        case .warning: return .orange
        case .error:   return .red
        case .info:    return .accentColor
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
                    .noWrap()
            }
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, Spacing.rowV + 2)
        .glassSurface(.overlay, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card)
            .fill(tint.opacity(0.10))
            .allowsHitTesting(false))
        .accessibilityElement(children: .combine)
    }
}
