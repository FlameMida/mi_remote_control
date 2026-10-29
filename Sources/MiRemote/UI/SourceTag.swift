import SwiftUI

/// App 场景中槽位来源标签：「App 覆盖」（强调色胶囊）/「继承全局」（次要色虚线描边胶囊）。
/// 全局默认或未设置时不显示。
struct SourceTag: View {
    let source: SlotSource
    let profile: String

    init(source: SlotSource, profile: String) {
        self.source = source
        self.profile = profile
    }

    var body: some View {
        if profile == "global" || source == .unset {
            EmptyView()
        } else if source == .appOverride {
            Text("App 覆盖")
                .font(.caption2)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel("App 覆盖")
        } else {
            Text("继承全局")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.6),
                                                style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel("继承全局")
        }
    }
}
