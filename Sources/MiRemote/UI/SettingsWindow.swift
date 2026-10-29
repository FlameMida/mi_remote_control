import AppKit
import SwiftUI
import Combine

// MARK: - 设置窗（AppKit 外壳 + SwiftUI 内容）
//
// macOS 26 的浮动玻璃侧栏只由 NSSplitViewController 的 sidebar 分栏项绘制；
// 手工 NSWindow + NSHostingView(NavigationSplitView) 拿不到（v0.3.0 验收问题 1/2）。
// 这里用 NSSplitViewController：侧栏项与详情项各一个 NSHostingController，共享 SettingsNav。

/// 设置窗导航状态：侧栏与详情分属两个 hosting controller，选中页与页面级 sheet 放这里共享。
@MainActor
final class SettingsNav: ObservableObject {
    @Published var page: SidebarItem = .mapping
    @Published var showOnboarding = false
    @Published var showHealthCheck = false
    @Published var showReauth = false
    @Published var onboardingStep = 0
}

/// 设置窗尺寸常量（定稿原型：窗 1120×700；侧栏 216 + 浮动玻璃左右各 8 的外边距）。
enum SettingsWindowLayout {
    static let defaultSize = CGSize(width: 1120, height: 700)
    static let minSize = CGSize(width: 760, height: 560)
    /// 侧栏分栏厚度（含浮动玻璃外边距）
    static let sidebarThickness: CGFloat = 232
    static let sidebarMinThickness: CGFloat = 208
    static let sidebarMaxThickness: CGFloat = 300
    static let detailMinThickness: CGFloat = 540
    static let mainTitle = "MiRemote 设置"

    /// 侧栏收起时标题改为当前页名（原型 winHtml）。
    static func title(sidebarHidden: Bool, page: SidebarItem) -> String {
        sidebarHidden ? page.title : mainTitle
    }

    static func selfCheck() -> Bool {
        title(sidebarHidden: false, page: .voice) == "MiRemote 设置"
            && title(sidebarHidden: true, page: .voice) == "语音"
            && title(sidebarHidden: true, page: .mapping) == "按键映射"
            && sidebarMinThickness <= sidebarThickness && sidebarThickness <= sidebarMaxThickness
            && sidebarThickness + detailMinThickness <= minSize.width + 20
            && defaultSize == CGSize(width: 1120, height: 700)
    }
}

/// 窗口底：macOS 26 液态玻璃开启时为半透明窗底（原型 glass-on .win：白 80% + 背景模糊），
/// 否则（旧系统 / 降低透明度）保持系统不透明窗底。
final class SettingsBackdropView: NSVisualEffectView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .underWindowBackground
        blendingMode = .behindWindow
        state = .followsWindowActiveState
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
final class SettingsSplitViewController: NSSplitViewController {
    private let model: AppModel
    private let nav: SettingsNav
    private let permissions: PermissionStatus
    private(set) var sidebarItem: NSSplitViewItem?
    private var cancellables: Set<AnyCancellable> = []
    private var collapseObservation: NSKeyValueObservation?
    private var didApplyInitialWidth = false

    init(model: AppModel, nav: SettingsNav, permissions: PermissionStatus) {
        self.model = model
        self.nav = nav
        self.permissions = permissions
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.dividerStyle = .thin
        splitView.autosaveName = "com.miremote.settings.split"

        let sidebarHost = NSHostingController(rootView:
            SettingsSidebar()
                .environmentObject(model)
                .environmentObject(nav)
                .environmentObject(permissions))
        sidebarHost.sizingOptions = []
        let side = NSSplitViewItem(sidebarWithViewController: sidebarHost)
        side.minimumThickness = SettingsWindowLayout.sidebarMinThickness
        side.maximumThickness = SettingsWindowLayout.sidebarMaxThickness
        side.canCollapse = true
        side.allowsFullHeightLayout = true
        side.titlebarSeparatorStyle = .none
        side.holdingPriority = .defaultLow + 10
        addSplitViewItem(side)
        sidebarItem = side

        let detailHost = NSHostingController(rootView:
            RootView()
                .environmentObject(model)
                .environmentObject(nav)
                .environmentObject(permissions))
        detailHost.sizingOptions = []
        let detail = NSSplitViewItem(viewController: detailHost)
        detail.minimumThickness = SettingsWindowLayout.detailMinThickness
        detail.titlebarSeparatorStyle = .none
        addSplitViewItem(detail)

        side.isCollapsed = model.sidebarHidden
        // 系统手势 / 拖拽收起侧栏 → 回写模型（⌃⌘S 菜单标题、窗口标题跟随）
        collapseObservation = side.observe(\.isCollapsed, options: [.new]) { [weak self] item, _ in
            let collapsed = item.isCollapsed
            DispatchQueue.main.async {
                guard let self, self.model.sidebarHidden != collapsed else { return }
                self.model.sidebarHidden = collapsed
            }
        }
        // 模型（⌃⌘S / 工具栏按钮）→ 分栏收起；「减少动态效果」时无动画
        model.$sidebarHidden
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hidden in
                guard let item = self?.sidebarItem, item.isCollapsed != hidden else { return }
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    item.isCollapsed = hidden
                } else {
                    item.animator().isCollapsed = hidden
                }
            }
            .store(in: &cancellables)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !didApplyInitialWidth else { return }
        didApplyInitialWidth = true
        if sidebarItem?.isCollapsed == false {
            splitView.setPosition(SettingsWindowLayout.sidebarThickness, ofDividerAt: 0)
        }
    }

    /// 快照模式：恢复默认侧栏宽度（不受 autosave 影响）。
    func resetSidebarWidth() {
        if sidebarItem?.isCollapsed == false {
            splitView.setPosition(SettingsWindowLayout.sidebarThickness, ofDividerAt: 0)
        }
    }
}

/// 窗口内容根：玻璃开启时垫一层半透明窗底，分栏控制器作为子控制器铺满。
@MainActor
final class SettingsContainerViewController: NSViewController {
    let split: SettingsSplitViewController
    private let translucent: Bool

    init(split: SettingsSplitViewController, translucent: Bool) {
        self.split = split
        self.translucent = translucent
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root: NSView = translucent ? SettingsBackdropView(frame: .zero) : NSView(frame: .zero)
        root.frame = NSRect(origin: .zero, size: SettingsWindowLayout.defaultSize)
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(split)
        let v = split.view
        v.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            v.topAnchor.constraint(equalTo: view.topAnchor),
            v.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

/// 工具栏：仅一个侧栏开关（原型 .sbtn，紧跟红绿灯），标题跟随。
@MainActor
final class SettingsToolbarController: NSObject, NSToolbarDelegate {
    static let toggleID = NSToolbarItem.Identifier("com.miremote.settings.toggleSidebar")
    private let model: AppModel
    private weak var toggleItem: NSToolbarItem?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func makeToolbar() -> NSToolbar {
        let t = NSToolbar(identifier: "com.miremote.settings.toolbar")
        t.delegate = self
        t.displayMode = .iconOnly
        t.allowsUserCustomization = false
        return t
    }

    // 切换按钮放在侧栏区（紧跟红绿灯，原型 titlebar 布局），侧栏追踪分隔之后才是详情区
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.toggleID, .sidebarTrackingSeparator]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.toggleID, .sidebarTrackingSeparator]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == Self.toggleID else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)
        item.isBordered = true
        item.target = self
        item.action = #selector(toggle(_:))
        toggleItem = item
        refresh()
        return item
    }

    @objc private func toggle(_ sender: Any?) {
        SidebarToggle.toggle(model)
    }

    func refresh() {
        let title = SidebarToggle.menuTitle(hidden: model.sidebarHidden)
        toggleItem?.label = title
        toggleItem?.toolTip = "\(title)（⌃⌘S）"
    }
}

/// 设置窗装配：窗口、工具栏、分栏与标题联动。
@MainActor
final class SettingsWindowAssembly {
    let window: NSWindow
    let nav: SettingsNav
    let split: SettingsSplitViewController
    private let toolbarController: SettingsToolbarController
    private var cancellables: Set<AnyCancellable> = []

    convenience init(model: AppModel, size: CGSize = SettingsWindowLayout.defaultSize) {
        self.init(model: model, nav: SettingsNav(), permissions: PermissionStatus(), size: size)
    }

    init(model: AppModel, nav: SettingsNav, permissions: PermissionStatus,
         size: CGSize = SettingsWindowLayout.defaultSize) {
        self.nav = nav
        let translucent = GlassSurface.appearance(
            kind: .panel, glassAvailable: GlassSurface.glassAvailable,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency) == .liquidGlass
        let split = SettingsSplitViewController(model: model, nav: nav, permissions: permissions)
        self.split = split
        let container = SettingsContainerViewController(split: split, translucent: translucent)
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.contentViewController = container
        w.setContentSize(size)
        w.contentMinSize = SettingsWindowLayout.minSize
        w.title = SettingsWindowLayout.mainTitle
        w.titleVisibility = .visible
        w.titlebarAppearsTransparent = true
        let tc = SettingsToolbarController(model: model)
        toolbarController = tc
        w.toolbar = tc.makeToolbar()
        w.toolbarStyle = .unified
        if translucent {
            w.isOpaque = false
            w.backgroundColor = .clear
        }
        w.isReleasedWhenClosed = false
        window = w

        Publishers.CombineLatest(model.$sidebarHidden, nav.$page)
            .receive(on: DispatchQueue.main)
            .sink { [weak w, weak tc] hidden, page in
                w?.title = SettingsWindowLayout.title(sidebarHidden: hidden, page: page)
                tc?.refresh()
            }
            .store(in: &cancellables)
    }
}

// MARK: - 侧栏内容（原型 .side：头部 + 问题行 + 四个导航行）

@MainActor
struct SettingsSidebar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: SettingsNav
    @EnvironmentObject var permissions: PermissionStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SidebarHeader()
                .padding(.top, 4)
                .padding(.horizontal, 6)
                .padding(.bottom, 12)
            SidebarIssueRow()
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            ForEach(SidebarItem.allCases) { item in
                SidebarNavRow(item: item, selected: nav.page == item) {
                    nav.page = item
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, SidebarMetrics.topInset)
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(SidebarGlassCard())
        .settingsStatusEnvironment(model: model, nav: nav, permissions: permissions)
    }
}

/// 原型 glass-on .side：浮动玻璃卡片（外边距 0 8 8、圆角 16、亮边 + 轻投影）；
/// 玻璃关闭（旧系统 / 降低透明度）时保持系统侧栏原样（原型 26 glass-off）。
private struct SidebarGlassCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let glass = GlassSurface.appearance(kind: .panel, glassAvailable: GlassSurface.glassAvailable,
                                            reduceTransparency: reduceTransparency) == .liquidGlass
        if glass {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            let dark = colorScheme == .dark
            content
                .background {
                    shape.fill(LinearGradient(
                        colors: dark ? [Color(red: 70/255, green: 70/255, blue: 80/255).opacity(0.55),
                                        Color(red: 30/255, green: 30/255, blue: 36/255).opacity(0.35)]
                                     : [Color.white.opacity(0.52), Color.white.opacity(0.22)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .glassSurface(.panel, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(dark ? 0.12 : 0.6), lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        } else {
            content
        }
    }
}

enum SidebarMetrics {
    /// 侧栏顶部避让红绿灯 + 工具栏（全高侧栏，原型 titlebar 38 + .side padding 14）
    static let topInset: CGFloat = 4
}

/// 原型 .nav：padding 7×10、圆角 7、图标列 18、间距 9；选中 = 强调色文字 + 半透明白底（玻璃）/ 强调色淡底（回退）。
struct SidebarNavRow: View {
    let item: SidebarItem
    let selected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var selectedFill: Color {
        let glass = GlassSurface.appearance(kind: .panel, glassAvailable: GlassSurface.glassAvailable,
                                            reduceTransparency: reduceTransparency) == .liquidGlass
        if glass { return Color.white.opacity(colorScheme == .dark ? 0.14 : 0.55) }
        return Color.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.10)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: item.icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(item.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? selectedFill : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - 两个 hosting controller 共用的状态问题环境

private struct SettingsStatusEnvironment: ViewModifier {
    @ObservedObject var model: AppModel
    @ObservedObject var nav: SettingsNav
    @ObservedObject var permissions: PermissionStatus

    func body(content: Content) -> some View {
        content
            .environment(\.statusIssue, StatusIssue.current(degraded: model.degraded,
                                                             missingPermission: permissions.missing,
                                                             connected: model.connected,
                                                             suspended: model.remoteSuspended))
            .environment(\.statusFix, { issue in
                switch issue {
                case .degraded, .permission:
                    nav.showHealthCheck = true
                case .disconnected:
                    nav.onboardingStep = 2
                    nav.showOnboarding = true
                case .paused:
                    break
                }
            })
    }
}

extension View {
    func settingsStatusEnvironment(model: AppModel, nav: SettingsNav, permissions: PermissionStatus) -> some View {
        modifier(SettingsStatusEnvironment(model: model, nav: nav, permissions: permissions))
    }
}
