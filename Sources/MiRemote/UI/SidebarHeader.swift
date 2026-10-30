import SwiftUI

/// 侧栏头布局常量与电量规则（spec「侧栏头固定三行，电量固定在第 3 行」「电量图标连续填充」）。
enum SidebarHeaderLayout {
    static let rowHeights: [CGFloat] = [18, 14, 14]
    static let rowSpacing: CGFloat = 8
    static let headerHeight: CGFloat = 62
    static let iconSlotWidth: CGFloat = 20

    /// 内芯填充比例：0…100 线性，无档位；未知为 nil。
    static func fillFraction(percent: Int?) -> CGFloat? {
        guard let percent else { return nil }
        return CGFloat(min(max(percent, 0), 100)) / 100
    }

    /// 低电量（与菜单栏图标一致：≤15%）。
    static func isLow(percent: Int?) -> Bool {
        guard let percent else { return false }
        return percent <= 15
    }

    /// 电量分档（原型只定义 ≤15% 红色；高电量绿色为验收补充）：
    /// ≤15 低（红）、16–30 偏低（橙）、31–59 常规（中性）、≥60 高（绿）。
    enum Tier: Equatable { case low, caution, normal, high }

    static func tier(percent: Int) -> Tier {
        if percent <= 15 { return .low }
        if percent <= 30 { return .caution }
        if percent < 60 { return .normal }
        return .high
    }

    /// 分档色；常规档返回 nil，由调用方用各自的中性色（图标内芯 secondary、电量环 accent）。
    static func tierColor(percent: Int) -> Color? {
        switch tier(percent: percent) {
        case .low: return .red
        case .caution: return .orange
        case .normal: return nil
        case .high: return .green
        }
    }

    static func batteryText(percent: Int?, connected: Bool) -> String {
        if let percent { return "\(percent)%" }
        return connected ? "正在读取电量…" : "电量待连接"
    }

    static func selfCheck() -> Bool {
        var ok = true
        func check(_ cond: Bool, _ msg: String) {
            if !cond { ok = false; print("[SidebarHeaderLayout.selfCheck] FAIL: \(msg)") }
        }
        check(fillFraction(percent: 82) == 0.82, "82")
        check(fillFraction(percent: 0) == 0, "0")
        check(fillFraction(percent: 100) == 1, "100")
        check(fillFraction(percent: 120) == 1, "120 clamp")
        check(fillFraction(percent: -5) == 0, "-5 clamp")
        check(fillFraction(percent: nil) == nil, "nil")
        if let a = fillFraction(percent: 41), let b = fillFraction(percent: 39) {
            check(abs((a - b) - 0.02) < 1e-6, "continuous")
        } else {
            check(false, "continuous nil")
        }
        check(isLow(percent: 15), "15 low")
        check(!isLow(percent: 16), "16 not low")
        check(isLow(percent: 12), "12 low")
        check(!isLow(percent: nil), "nil not low")
        check(tier(percent: 15) == .low && tier(percent: 16) == .caution, "tier low/caution")
        check(tier(percent: 30) == .caution && tier(percent: 31) == .normal, "tier caution/normal")
        check(tier(percent: 59) == .normal && tier(percent: 60) == .high && tier(percent: 98) == .high, "tier high")
        check(batteryText(percent: 82, connected: true) == "82%", "text 82")
        check(batteryText(percent: nil, connected: true) == "正在读取电量…", "text reading")
        check(batteryText(percent: nil, connected: false) == "电量待连接", "text waiting")
        check(headerHeight == rowHeights.reduce(0, +) + 2 * rowSpacing && headerHeight == 62, "height")
        return ok
    }
}

/// 自绘电池：机身描边 + 正极帽 + 按比例连续填充的内芯；≤15% 内芯为系统红。
struct BatteryGlyph: View {
    let percent: Int?

    init(percent: Int?) { self.percent = percent }

    @ScaledMetric(relativeTo: .caption2) private var width: CGFloat = 18
    @ScaledMetric(relativeTo: .caption2) private var height: CGFloat = 9
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let capWidth: CGFloat = 1.5
        let bodyWidth = width - capWidth - 0.5
        let inset: CGFloat = 1.5
        let fraction = SidebarHeaderLayout.fillFraction(percent: percent)
        let tint: Color = percent.flatMap { SidebarHeaderLayout.tierColor(percent: $0) } ?? .secondary
        HStack(spacing: 0.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5)
                    .stroke(lineWidth: 1)
                    .foregroundStyle(fraction == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                if let fraction {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(tint)
                        .frame(width: max(0, (bodyWidth - inset * 2) * fraction),
                               height: max(0, height - inset * 2))
                        .padding(.leading, inset)
                }
            }
            .frame(width: bodyWidth, height: height)
            RoundedRectangle(cornerRadius: 0.75)
                .fill(fraction == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                .frame(width: capWidth, height: height * 0.45)
        }
        .frame(width: width, height: height)
        .animation(reduceMotion ? nil : .default, value: percent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(percent.map { "电量 \($0)%" } ?? "电量待连接")
    }
}

/// 侧栏头：图标 + 固定三行（标题 / 设备名 / 电量），总高 62，连接过程中不跳变。
struct SidebarHeader: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let rows = SidebarHeaderLayout.rowHeights
        let reading = model.batteryPercent == nil && model.connected
        HStack(spacing: Spacing.intra) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.badge)
                    .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.04)],
                                         startPoint: .top, endPoint: .bottom))
                Image(systemName: "av.remote")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: SidebarHeaderLayout.rowSpacing) {
                Text("遥控器控制台")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: rows[0], alignment: .leading)
                Text(model.displayDeviceName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(model.displayDeviceName)
                    .frame(height: rows[1], alignment: .leading)
                HStack(spacing: 4) {
                    ZStack {
                        if model.batteryPercent != nil {
                            BatteryGlyph(percent: model.batteryPercent)
                        } else if reading {
                            ProgressView().controlSize(.mini).scaleEffect(0.7)
                        } else {
                            BatteryGlyph(percent: nil)
                        }
                    }
                    .frame(width: SidebarHeaderLayout.iconSlotWidth, height: rows[2])
                    Text(SidebarHeaderLayout.batteryText(percent: model.batteryPercent,
                                                         connected: model.connected))
                        .font(.caption2)
                        .foregroundStyle(model.connected ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                        .noWrap()
                }
                .frame(height: rows[2], alignment: .leading)
            }
            .frame(height: SidebarHeaderLayout.headerHeight, alignment: .leading)
        }
    }
}
