import SwiftUI
import AppKit

/// 侧栏收起状态映射（spec「侧栏可收起（⌃⌘S）」）。
enum SidebarToggle {
    static func menuTitle(hidden: Bool) -> String {
        hidden ? "显示边栏" : "隐藏边栏"
    }

    static func visibility(hidden: Bool) -> NavigationSplitViewVisibility {
        hidden ? .detailOnly : .all
    }

    static func hidden(from visibility: NavigationSplitViewVisibility) -> Bool {
        visibility == .detailOnly
    }

    /// 切换收起状态；「减少动态效果」时无动画。
    @MainActor static func toggle(_ model: AppModel) {
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .default) {
            model.sidebarHidden.toggle()
        }
    }

    static func selfCheck() -> Bool {
        menuTitle(hidden: false) == "隐藏边栏"
            && menuTitle(hidden: true) == "显示边栏"
            && visibility(hidden: true) == .detailOnly
            && visibility(hidden: false) == .all
            && hidden(from: .detailOnly)
            && !hidden(from: .all)
            && !hidden(from: .doubleColumn)
            && !hidden(from: .automatic)
            && [true, false].allSatisfy { hidden(from: visibility(hidden: $0)) == $0 }
    }
}
