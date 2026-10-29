import SwiftUI

// MARK: - 标注层（「示意图显示」分段；只切换标注取哪一层的值，不改编辑对象）

enum AnnotationLayer: Hashable, CaseIterable {
    case base, layer1, layer2, layer3

    var slot: MappingSlot {
        switch self {
        case .base:   return .tap
        case .layer1: return .layer(1)
        case .layer2: return .layer(2)
        case .layer3: return .layer(3)
        }
    }

    var title: String {
        switch self {
        case .base:   return "短按"
        case .layer1: return "快捷控制"
        case .layer2: return "App 控制"
        case .layer3: return "App 导航"
        }
    }

    /// VoiceOver 第二段：基础层读「短按」，模式层读原模式名。
    var spokenName: String {
        switch self {
        case .base:   return "短按"
        case .layer1: return modeDisplayName(1)
        case .layer2: return modeDisplayName(2)
        case .layer3: return modeDisplayName(3)
        }
    }
}

// MARK: - 标注布局（纯函数；坐标取自定稿原型 KEYS / RC2PRO_POS）

enum RemoteAnnotationLayout {
    static let stage = CGSize(width: 500, height: 490)
    static let diagramOrigin = CGPoint(x: 160, y: 0)
    static let inspectorMinWidth: CGFloat = 300
    static let narrowScale: CGFloat = 0.86

    enum Side { case left, right }

    struct Label {
        let key: RemoteKey
        let side: Side
        let labelY: CGFloat
        let labelX: CGFloat
        let elbowX: CGFloat
        let end: CGPoint
    }

    /// 键盘与标注顺序
    static let order: [RemoteKey] = [.power, .voice, .up, .left, .ok, .right, .down,
                                     .back, .volUp, .home, .volDown, .menu, .tv]

    private static let leftKeys: Set<RemoteKey> = [.power, .up, .left, .back, .home, .menu]

    private static let genericLabelY: [RemoteKey: CGFloat] = [
        .power: 46, .voice: 46, .up: 112, .ok: 112, .left: 168, .right: 168, .down: 222,
        .back: 271, .home: 317, .menu: 363, .volUp: 264, .volDown: 318, .tv: 372,
    ]
    private static let rc2ProLabelY: [RemoteKey: CGFloat] = [
        .power: 37, .voice: 37, .up: 75, .ok: 80, .left: 113, .right: 122, .down: 164,
        .back: 175, .home: 222, .menu: 268, .volUp: 206, .volDown: 248, .tv: 290,
    ]

    static func radius(of key: RemoteKey, model: RemoteModel) -> CGFloat {
        let rc2 = model == .rc2Pro
        switch key {
        case .power, .voice:              return rc2 ? 12.6 : 17
        case .up, .down, .left, .right:   return 6
        case .ok:                         return rc2 ? 23.6 : 33
        case .back, .home, .menu, .tv:    return rc2 ? 18 : 19
        case .volUp, .volDown:            return rc2 ? 18.6 : 22
        default:                          return 6
        }
    }

    static func showsAnnotations(panelWidth: CGFloat) -> Bool {
        panelWidth >= stage.width
    }

    static func side(of key: RemoteKey) -> Side {
        leftKeys.contains(key) ? .left : .right
    }

    static func labels(model: RemoteModel) -> [Label] {
        let ys = model == .rc2Pro ? rc2ProLabelY : genericLabelY
        return order.map { key in
            let s = side(of: key)
            let a = RemoteDiagram.anchor(of: key, model: model)
            let r = radius(of: key, model: model)
            let end = CGPoint(x: a.x + diagramOrigin.x + (s == .left ? -r : r),
                              y: a.y + diagramOrigin.y)
            return Label(key: key, side: s, labelY: ys[key] ?? 0,
                         labelX: s == .left ? 158 : 342,
                         elbowX: s == .left ? 166 : 334,
                         end: end)
        }
    }

    /// 下 / 右前进，上 / 左后退，两端不回绕。
    static func next(after key: RemoteKey, direction: MoveCommandDirection) -> RemoteKey {
        guard let i = order.firstIndex(of: key) else { return key }
        switch direction {
        case .down, .right: return order[min(i + 1, order.count - 1)]
        case .up, .left:    return order[max(i - 1, 0)]
        @unknown default:   return key
        }
    }

    static func sourceWord(_ source: SlotSource, profile: String) -> String {
        switch source {
        case .appOverride: return profile == "global" ? "已设置" : "App 覆盖"
        case .inherited:   return "继承全局"
        case .unset:       return "未设置"
        }
    }

    static func accessibilityText(key: RemoteKey, layer: AnnotationLayer,
                                  resolution: SlotResolution, profile: String) -> String {
        [KeyDisplay.name(key), layer.spokenName, ActionSummary.describe(resolution.action),
         sourceWord(resolution.source, profile: profile)].joined(separator: "，")
    }

    static func selfCheck() -> Bool {
        var ok = true
        if showsAnnotations(panelWidth: 499) != false || showsAnnotations(panelWidth: 500) != true { ok = false }
        for model in [RemoteModel.generic, .rc2Pro] {
            let expectedY = model == .rc2Pro ? rc2ProLabelY : genericLabelY
            let ls = labels(model: model)
            if ls.count != 13 || Set(ls.map(\.key)).count != 13 { ok = false }
            if Set(ls.filter { $0.side == .left }.map(\.key)) != [.power, .up, .left, .back, .home, .menu] { ok = false }
            for l in ls {
                if let y = expectedY[l.key], abs(l.labelY - y) > 0.5 { ok = false }
                if l.labelX != (l.side == .left ? 158 : 342) || l.elbowX != (l.side == .left ? 166 : 334) { ok = false }
                let a = RemoteDiagram.anchor(of: l.key, model: model)
                let r = radius(of: l.key, model: model)
                let ex = a.x + diagramOrigin.x + (l.side == .left ? -r : r)
                if abs(l.end.x - ex) > 0.5 || abs(l.end.y - (a.y + diagramOrigin.y)) > 0.5 { ok = false }
            }
            for s in [Side.left, .right] {
                let ys = ls.filter { $0.side == s }.map(\.labelY).sorted()
                for (a, b) in zip(ys, ys.dropFirst()) where b - a < 30 { ok = false }
            }
        }
        // 抽查原型坐标
        if let p = labels(model: .generic).first(where: { $0.key == .power }),
           abs(p.end.x - 200) > 0.5 || abs(p.end.y - 46) > 0.5 { ok = false }
        if let p = labels(model: .rc2Pro).first(where: { $0.key == .tv }),
           abs(p.end.x - 290.6) > 0.5 || abs(p.end.y - 264.3) > 0.5 { ok = false }
        if next(after: .power, direction: .down) != .voice { ok = false }
        if next(after: .ok, direction: .up) != .left { ok = false }
        if next(after: .tv, direction: .down) != .tv { ok = false }
        if next(after: .power, direction: .left) != .power { ok = false }
        let ghostty = "com.mitchellh.ghostty"
        let desk = Action.system("show_desktop")
        if accessibilityText(key: .home, layer: .base,
                             resolution: SlotResolution(action: desk, source: .inherited), profile: ghostty)
            != "主页键，短按，" + ActionSummary.describe(desk) + "，继承全局" { ok = false }
        if accessibilityText(key: .home, layer: .layer2,
                             resolution: SlotResolution(action: desk, source: .appOverride), profile: ghostty)
            != "主页键，" + modeDisplayName(2) + "，" + ActionSummary.describe(desk) + "，App 覆盖" { ok = false }
        if accessibilityText(key: .home, layer: .base,
                             resolution: SlotResolution(action: desk, source: .appOverride), profile: "global")
            != "主页键，短按，" + ActionSummary.describe(desk) + "，已设置" { ok = false }
        if accessibilityText(key: .home, layer: .base,
                             resolution: SlotResolution(action: nil, source: .unset), profile: "global")
            != "主页键，短按，无，未设置" { ok = false }
        return ok
    }
}

// MARK: - 遥控器面板舞台（示意图 + 引线 + 标注；窄态只留缩小的示意图）

@MainActor
struct RemoteAnnotationStage: View {
    @EnvironmentObject var model: AppModel
    @Binding var layer: AnnotationLayer
    let showsAnnotations: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private typealias L = RemoteAnnotationLayout

    init(layer: Binding<AnnotationLayer>, showsAnnotations: Bool) {
        self._layer = layer
        self.showsAnnotations = showsAnnotations
    }

    private var diagram: RemoteDiagram {
        RemoteDiagram(selected: $model.selectedKey,
                      flashing: model.lastPressedKey,
                      connected: model.connected,
                      model: model.remoteModel)
    }

    private func resolution(_ key: RemoteKey) -> SlotResolution {
        SlotResolver.resolve(config: model.config, profile: model.currentProfile, key: key, slot: layer.slot)
    }

    var body: some View {
        content
            .focusable()
            .focusEffectDisabled()   // 键盘方向键选键保留；不画系统蓝色焦点框（验收问题 3）
            .onMoveCommand { dir in
                let next = L.next(after: model.selectedKey, direction: dir)
                if reduceMotion {
                    model.selectedKey = next
                } else {
                    withAnimation(Motion.select) { model.selectedKey = next }
                }
            }
            .accessibilityLabel("遥控器示意图")
    }

    @ViewBuilder
    private var content: some View {
        if showsAnnotations {
            let labels = L.labels(model: model.remoteModel)
            let selected = model.selectedKey
            let sources = Dictionary(uniqueKeysWithValues: labels.map { ($0.key, resolution($0.key)) })
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    for l in labels {
                        var p = Path()
                        p.move(to: CGPoint(x: l.labelX, y: l.labelY))
                        p.addLine(to: CGPoint(x: l.elbowX, y: l.labelY))
                        p.addLine(to: l.end)
                        let isSel = l.key == selected
                        let src = sources[l.key]?.source ?? .unset
                        let dashed = src == .inherited || src == .unset
                        ctx.stroke(p, with: .color(isSel ? Color.accentColor : Color(nsColor: .tertiaryLabelColor)),
                                   style: StrokeStyle(lineWidth: isSel ? 1.4 : 0.8, dash: dashed ? [3, 3] : []))
                    }
                }
                .frame(width: L.stage.width, height: L.stage.height)
                .allowsHitTesting(false)

                diagram
                    .frame(width: 180, height: 480)
                    .offset(x: L.diagramOrigin.x, y: L.diagramOrigin.y)

                ForEach(labels, id: \.key) { l in
                    labelView(l, resolution: sources[l.key] ?? SlotResolution(action: nil, source: .unset),
                              selected: l.key == selected)
                }
            }
            .frame(width: L.stage.width, height: L.stage.height, alignment: .topLeading)
        } else {
            diagram
                .frame(width: 180 * L.narrowScale, height: 480 * L.narrowScale)
        }
    }

    private func labelView(_ l: L.Label, resolution r: SlotResolution, selected: Bool) -> some View {
        let alignment: HorizontalAlignment = l.side == .left ? .trailing : .leading
        let action = Text(ActionSummary.describe(r.action))
            .font(.system(size: 12, weight: r.source == .appOverride ? .semibold : .regular))
            .italic(r.source == .unset)
            .foregroundStyle(actionStyle(r.source))
        return VStack(alignment: alignment, spacing: 0) {
            Text(KeyDisplay.name(l.key))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            action
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(width: 150, alignment: l.side == .left ? .trailing : .leading)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(selected ? Color.accentColor.opacity(0.14) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture {
            if reduceMotion { model.selectedKey = l.key } else {
                withAnimation(Motion.select) { model.selectedKey = l.key }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.accessibilityText(key: l.key, layer: layer, resolution: r,
                                                profile: model.currentProfile))
        .accessibilityAddTraits(.isButton)
        .fixedSize(horizontal: false, vertical: true)
        .alignmentGuide(.top) { d in d[VerticalAlignment.center] - l.labelY }
        .alignmentGuide(.leading) { d in
            l.side == .left ? d[.trailing] - l.labelX : -l.labelX
        }
    }

    private func actionStyle(_ source: SlotSource) -> AnyShapeStyle {
        switch source {
        case .appOverride: return AnyShapeStyle(Color.accentColor)
        case .inherited:   return AnyShapeStyle(.secondary)
        case .unset:       return AnyShapeStyle(.tertiary)
        }
    }
}
