import SwiftUI
import AppKit

// MARK: - 几何（纯函数，与通用示意图同一 180x480 逻辑坐标系；坐标取自定稿原型 RC 2 Pro svg）

enum RC2ProGeometry {
    static let canvas = CGSize(width: 180, height: 480)
    /// 机身：宽 W = 99.2，高 448（高:宽 约 4.52），圆角 7
    static let body = CGRect(x: 40.4, y: 6, width: 99.2, height: 448)
    static let bodyCorner: CGFloat = 7

    static let ringCenter = CGPoint(x: 90, y: 110.7)
    static let ringOuter: CGFloat = 45.2
    static let ringInner: CGFloat = 24.8
    static let okRadius: CGFloat = 23.6
    static let okHitRadius: CGFloat = 24.6

    /// 电源 / 语音凸起圆键
    static let raised: [RemoteKey: CGPoint] = [
        .power: CGPoint(x: 62.1, y: 37.2),
        .voice: CGPoint(x: 118.2, y: 37.2),
    ]
    static let raisedRadius: CGFloat = 12.6
    static let raisedHitRadius: CGFloat = 15.6

    /// 返回 / 主页 / 菜单 / TV 黑色圆键
    static let blackKeys: [RemoteKey: CGPoint] = [
        .back: CGPoint(x: 67.9, y: 179.5),
        .home: CGPoint(x: 67.9, y: 222),
        .menu: CGPoint(x: 67.9, y: 264.3),
        .tv:   CGPoint(x: 112.6, y: 264.3),
    ]
    static let blackRadius: CGFloat = 18
    static let blackHitRadius: CGFloat = 20

    /// 音量竖胶囊：x 94…131.2，y 161…240.6，分缝 200.8
    static let volRect = CGRect(x: 94, y: 161, width: 37.2, height: 79.6)
    static let volSplitY: CGFloat = 200.8
    static let volRadius: CGFloat = 18.6

    /// 方向键锚点（环上小圆点位置附近，距环心 35）
    static let directionAnchors: [RemoteKey: CGPoint] = [
        .up: CGPoint(x: 90, y: 75.7), .down: CGPoint(x: 90, y: 145.7),
        .left: CGPoint(x: 55, y: 110.7), .right: CGPoint(x: 125, y: 110.7),
    ]

    static func anchor(of key: RemoteKey) -> CGPoint {
        if let p = raised[key] { return p }
        if let p = blackKeys[key] { return p }
        if let p = directionAnchors[key] { return p }
        switch key {
        case .ok:      return ringCenter
        case .volUp:   return CGPoint(x: 112.6, y: 180.9)
        case .volDown: return CGPoint(x: 112.6, y: 220.7)
        default:       return ringCenter
        }
    }

    static func key(at p: CGPoint) -> RemoteKey? {
        let dx = p.x - ringCenter.x, dy = p.y - ringCenter.y
        let dist = (dx * dx + dy * dy).squareRoot()
        if dist <= okHitRadius { return .ok }
        if dist <= ringOuter {
            let deg = atan2(Double(dy), Double(dx)) * 180 / .pi
            return RemoteDiagramGeometry.direction(forAngle: deg)
        }
        for (key, c) in raised where distance(p, c) <= raisedHitRadius { return key }
        for (key, c) in blackKeys where distance(p, c) <= blackHitRadius { return key }
        if volRect.contains(p) {
            return p.y < volSplitY ? .volUp : .volDown
        }
        return nil
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// 方向键环形扇区（命中 / 高亮底色用）
    static func sectorPath(_ key: RemoteKey) -> Path? {
        guard let (start, end) = RemoteDiagramGeometry.sectorAngles(key) else { return nil }
        var p = Path()
        p.addArc(center: ringCenter, radius: ringOuter,
                 startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        p.addArc(center: ringCenter, radius: ringInner,
                 startAngle: .degrees(end), endAngle: .degrees(start), clockwise: true)
        p.closeSubpath()
        return p
    }

    /// 方向键状态弧（半径 43，两端各收 9 度，与原型 arc 一致）
    static func arcPath(_ key: RemoteKey) -> Path? {
        guard let (start, end) = RemoteDiagramGeometry.sectorAngles(key) else { return nil }
        var p = Path()
        p.addArc(center: ringCenter, radius: 43,
                 startAngle: .degrees(start + 9), endAngle: .degrees(end - 9), clockwise: false)
        return p
    }

    /// 音量上 / 下半（各带一端半圆）
    static func volumeHalf(_ key: RemoteKey) -> Path {
        var p = Path()
        let cx = volRect.midX
        if key == .volUp {
            p.move(to: CGPoint(x: volRect.minX, y: volSplitY))
            p.addLine(to: CGPoint(x: volRect.minX, y: volRect.minY + volRadius))
            p.addArc(center: CGPoint(x: cx, y: volRect.minY + volRadius), radius: volRadius,
                     startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            p.addLine(to: CGPoint(x: volRect.maxX, y: volSplitY))
        } else {
            p.move(to: CGPoint(x: volRect.minX, y: volSplitY))
            p.addLine(to: CGPoint(x: volRect.minX, y: volRect.maxY - volRadius))
            p.addArc(center: CGPoint(x: cx, y: volRect.maxY - volRadius), radius: volRadius,
                     startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
            p.addLine(to: CGPoint(x: volRect.maxX, y: volSplitY))
        }
        p.closeSubpath()
        return p
    }

    static func selfCheck() -> Bool {
        var ok = true
        func near(_ a: CGPoint, _ x: CGFloat, _ y: CGFloat) -> Bool {
            abs(a.x - x) <= 0.5 && abs(a.y - y) <= 0.5
        }
        if canvas != CGSize(width: 180, height: 480) { ok = false }
        if body != CGRect(x: 40.4, y: 6, width: 99.2, height: 448) { ok = false }
        let ratio = body.height / body.width
        if !(ratio >= 4.46 && ratio <= 4.56) { ok = false }
        let expected: [(RemoteKey, CGFloat, CGFloat)] = [
            (.power, 62.1, 37.2), (.voice, 118.2, 37.2), (.up, 90, 75.7), (.left, 55, 110.7),
            (.right, 125, 110.7), (.down, 90, 145.7), (.ok, 90, 110.7), (.back, 67.9, 179.5),
            (.home, 67.9, 222), (.menu, 67.9, 264.3), (.volUp, 112.6, 180.9),
            (.volDown, 112.6, 220.7), (.tv, 112.6, 264.3),
        ]
        for (k, x, y) in expected where !near(anchor(of: k), x, y) { ok = false }
        for k in RemoteKey.allCases {
            if key(at: anchor(of: k)) != k { ok = false }
            if RemoteDiagramGeometry.key(at: RemoteDiagram.anchor(of: k, model: .generic)) != k { ok = false }
            if RemoteDiagram.anchor(of: k, model: .rc2Pro) != anchor(of: k) { ok = false }
        }
        if key(at: CGPoint(x: 10, y: 10)) != nil { ok = false }
        if key(at: CGPoint(x: 90, y: 400)) != nil { ok = false }
        return ok
    }
}

// MARK: - 取色（spec「画法」全部常量集中于此；浅 / 深色用动态色）

enum RC2ProPalette {
    static func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255,
                green: CGFloat((v >> 8) & 0xff) / 255,
                blue: CGFloat(v & 0xff) / 255, alpha: a)
    }
    static func dynamic(_ light: UInt32, _ dark: UInt32, _ a: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? hex(dark, a) : hex(light, a) })
    }
    static func fixed(_ v: UInt32, _ a: CGFloat = 1) -> Color { Color(nsColor: hex(v, a)) }

    // 机身横向渐变（左亮右暗）；深色主题整体压暗约 5%
    static let shell: [(Color, CGFloat)] = [
        (dynamic(0xc9c7c8, 0xbdbbbc), 0), (dynamic(0xd7d5d6, 0xcbc9ca), 0.07),
        (dynamic(0xc6c4c5, 0xbab8b9), 0.5), (dynamic(0xb3b1b2, 0xa8a6a7), 0.93),
        (dynamic(0xa5a3a4, 0x9a9899), 1),
    ]
    static let edge = dynamic(0x8f8d8e, 0xe2e0e1)
    static let edgeOpacityDark: CGFloat = 0.35
    static let edgeInner = fixed(0xffffff)
    // 抛光倒角带
    static let chamferLeft: [(Color, CGFloat)] = [
        (fixed(0xa9a7a8), 0), (fixed(0xeeeced), 0.22), (fixed(0xbab8b9), 0.42),
        (fixed(0xfaf6f7), 0.7), (fixed(0xfaf6f7, 0), 1),
    ]
    static let chamferRight: [(Color, CGFloat)] = [
        (fixed(0xa9a7a8, 0), 0), (fixed(0x8c8a8b), 0.3), (fixed(0x626061), 0.62),
        (fixed(0x767475), 0.85), (fixed(0xb4b4b4), 1),
    ]
    // 黑键
    static let keyFace = fixed(0x202021)
    static let keyFaceStroke = fixed(0x80848a, 0.35)
    static let keyPressed = fixed(0x3a3a3c)
    static let keyGloss: [(Color, CGFloat)] = [
        (fixed(0xffffff, 0), 0), (fixed(0xffffff, 0.015), 0.35), (fixed(0xffffff, 0.12), 1),
    ]
    static let keyRim = fixed(0x000000, 0.85)
    static let icon = fixed(0xb4b3b1)
    // 方向环 / OK
    static let ring = fixed(0x313131)
    static let ringGradient: [(Color, CGFloat)] = [(fixed(0x2d2d2d), 0), (fixed(0x373737), 1)]
    static let ringInnerEdge = fixed(0x6a6a6a, 0.75)
    static let ringDot = fixed(0x060606)
    static let okGroove = fixed(0x060708)
    static let okOuterLine = fixed(0x727272, 0.8)
    static let okRadial: [(Color, CGFloat)] = [(fixed(0x2a2b2e), 0), (fixed(0x141517), 1)]
    static let okLinear: [(Color, CGFloat)] = [(fixed(0x3a3a3a, 0.6), 0), (fixed(0x2b2b2b, 0.6), 1)]
    static let volumeBase = fixed(0x141517)
    static let volumeSplit = fixed(0x0c0c0c, 0.7)
    // 电源 / 语音凸起键
    static let bevel: [(Color, CGFloat)] = [(fixed(0xffffff), 0), (fixed(0xcfcdce), 0.45), (fixed(0x858384), 1)]
    static let dome: [(Color, CGFloat)] = [(fixed(0xeeecee), 0), (fixed(0xd5d3d4), 0.6), (fixed(0xbbb9ba), 1)]
    static let raisedRim = fixed(0x1c1d20, 0.9)
    static let raisedIcon = fixed(0x545254)
    // 丝印
    static let print = dynamic(0x4a494b, 0x48474a)
}

// MARK: - 绘制

/// 单键的显示状态（与通用画法共用同一套判定来源：selected / flashing / emphasized / 悬停）。
struct RC2ProKeyState {
    var selected = false
    var pulse = false
    var hovered = false
    var pressed = false
    var accented: Bool { selected || pulse }
}

struct RC2ProCanvas: View {
    var scale: CGFloat
    var state: (RemoteKey) -> RC2ProKeyState
    var connected: Bool
    var interactive: Bool
    @State private var hoveredKey: RemoteKey?

    init(scale: CGFloat, connected: Bool, interactive: Bool,
         state: @escaping (RemoteKey) -> RC2ProKeyState) {
        self.scale = scale
        self.connected = connected
        self.interactive = interactive
        self.state = state
    }

    private typealias G = RC2ProGeometry
    private typealias P = RC2ProPalette
    @Environment(\.colorScheme) private var colorScheme

    /// 喷砂颗粒：固定种子点阵，重绘不变化（避免闪烁）。
    private static let grain: [(CGPoint, CGFloat, Bool)] = {
        var seed: UInt64 = 3
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) % 10_000) / 10_000
        }
        return (0..<1400).map { _ in
            let x = G.body.minX + next() * G.body.width
            let y = G.body.minY + next() * G.body.height
            return (CGPoint(x: x, y: y), 0.25 + next() * 0.35, next() > 0.5)
        }
    }()

    private func gradient(_ stops: [(Color, CGFloat)]) -> Gradient {
        Gradient(stops: stops.map { Gradient.Stop(color: $0.0, location: $0.1) })
    }

    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    private var hoverColor: Color {
        Color(nsColor: NSColor.controlAccentColor.blended(withFraction: 0.3, of: .white) ?? .controlAccentColor)
    }

    /// 状态描边：选中 2.2 / 识别中 2.6 / 悬停 1.6 / 按下 1.8；强调态外加深色晕与强调色外发光。
    private func strokeState(_ ctx: inout GraphicsContext, _ path: Path, _ s: RC2ProKeyState,
                             base: (Color, CGFloat)?) {
        if s.accented || s.pressed {
            let width: CGFloat = s.pulse ? 2.6 : (s.selected ? 2.2 : 1.8)
            var halo = ctx
            halo.addFilter(.shadow(color: .black, radius: 0.9))
            if s.accented {
                halo.addFilter(.shadow(color: Color.accentColor.opacity(0.85), radius: 2.8))
            }
            halo.stroke(path, with: .color(Color.accentColor), lineWidth: width)
        } else if s.hovered {
            var halo = ctx
            halo.addFilter(.shadow(color: .black.opacity(0.85), radius: 0.7))
            halo.stroke(path, with: .color(hoverColor), lineWidth: 1.6)
        } else if let base {
            ctx.stroke(path, with: .color(base.0), lineWidth: base.1)
        }
    }

    private func line(_ points: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(points)
        return p
    }

    private func iconStroke(_ ctx: GraphicsContext, _ path: Path, _ color: Color) {
        let w = max(0.8 / max(scale, 0.01), 1.15)
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }

    var body: some View {
        Canvas { ctx, _ in
            ctx.scaleBy(x: scale, y: scale)
            drawBody(&ctx)
            drawRaised(&ctx)
            drawRing(&ctx)
            drawBlackKeys(&ctx)
            drawPrint(&ctx)
            drawStatus(&ctx)
        }
        .onContinuousHover { phase in
            guard interactive else { hoveredKey = nil; return }
            switch phase {
            case .active(let location):
                let logical = CGPoint(x: location.x / max(scale, 0.01), y: location.y / max(scale, 0.01))
                let key = G.key(at: logical)
                if key != hoveredKey { hoveredKey = key }
            case .ended:
                hoveredKey = nil
            }
        }
    }

    /// 外部状态 + 本视图悬停
    private var keyState: (RemoteKey) -> RC2ProKeyState {
        let hovered = hoveredKey
        let base = state
        return { key in
            var s = base(key)
            s.hovered = hovered == key
            return s
        }
    }

    // 1. 机身
    private func drawBody(_ ctx: inout GraphicsContext) {
        let body = Path(roundedRect: G.body, cornerRadius: G.bodyCorner, style: .circular)
        var shadowed = ctx
        shadowed.addFilter(.shadow(color: .black.opacity(0.22), radius: 2.4, x: 0, y: 2))
        shadowed.fill(body, with: .linearGradient(gradient(P.shell),
                                                  startPoint: CGPoint(x: G.body.minX, y: 0),
                                                  endPoint: CGPoint(x: G.body.maxX, y: 0)))
        var clipped = ctx
        clipped.clip(to: body)
        for (p, r, light) in Self.grain {
            clipped.fill(circle(p, r), with: .color((light ? Color.white : Color.black).opacity(0.07)))
        }
        clipped.fill(Path(G.body), with: .linearGradient(
            Gradient(stops: [.init(color: .white.opacity(0.10), location: 0),
                             .init(color: .white.opacity(0), location: 0.25),
                             .init(color: .black.opacity(0), location: 0.8),
                             .init(color: .black.opacity(0.18), location: 1)]),
            startPoint: CGPoint(x: 0, y: G.body.minY), endPoint: CGPoint(x: 0, y: G.body.maxY)))
        let band = G.body.width * 0.055
        let left = CGRect(x: G.body.minX, y: G.body.minY, width: band, height: G.body.height)
        let right = CGRect(x: G.body.maxX - band, y: G.body.minY, width: band, height: G.body.height)
        clipped.fill(Path(left), with: .linearGradient(gradient(P.chamferLeft),
            startPoint: CGPoint(x: left.minX, y: 0), endPoint: CGPoint(x: left.maxX, y: 0)))
        clipped.fill(Path(right), with: .linearGradient(gradient(P.chamferRight),
            startPoint: CGPoint(x: right.minX, y: 0), endPoint: CGPoint(x: right.maxX, y: 0)))
        let dark = colorScheme == .dark
        let inner = Path(roundedRect: G.body.insetBy(dx: 0.6, dy: 0.6), cornerRadius: G.bodyCorner - 0.6, style: .circular)
        ctx.stroke(inner, with: .color(P.edgeInner.opacity(dark ? 0.25 : 0.35)), lineWidth: 0.8)
        ctx.stroke(body, with: .color(P.edge.opacity(dark ? P.edgeOpacityDark : 1)), lineWidth: 0.8)
    }

    // 4. 电源 / 语音凸起圆键
    private func drawRaised(_ ctx: inout GraphicsContext) {
        for key in [RemoteKey.power, .voice] {
            guard let c = G.raised[key] else { continue }
            let s = keyState(key)
            var drop = ctx
            drop.addFilter(.blur(radius: 0.8))
            drop.fill(circle(CGPoint(x: c.x + 0.5, y: c.y + 1.4), 12.9),
                      with: .color(.black.opacity(s.pressed ? 0.12 : 0.34)))
            let r = G.raisedRadius
            ctx.fill(circle(c, r), with: .linearGradient(gradient(P.bevel),
                startPoint: CGPoint(x: c.x - r + 0.3 * r, y: c.y - r + 0.2 * r),
                endPoint: CGPoint(x: c.x - r + 1.7 * r, y: c.y - r + 1.8 * r)))
            let face = circle(c, 11.1)
            ctx.fill(face, with: .radialGradient(gradient(P.dome),
                center: CGPoint(x: c.x - 11.1 + 0.8 * 11.1, y: c.y - 11.1 + 0.68 * 11.1),
                startRadius: 0, endRadius: 0.72 * 22.2))
            if s.pressed {
                ctx.fill(face, with: .color(.black.opacity(0.12)))
                ctx.fill(circle(c, r), with: .color(.black.opacity(0.18)))
            }
            ctx.stroke(face, with: .color(.black.opacity(0.18)), lineWidth: 0.5)
            var spark = Path()
            spark.move(to: CGPoint(x: c.x - 10, y: c.y - 3.6))
            spark.addQuadCurve(to: CGPoint(x: c.x + 3.6, y: c.y - 10),
                               control: CGPoint(x: c.x - 8.6, y: c.y - 9.6))
            ctx.stroke(spark, with: .color(.white.opacity(0.9 * 0.38)),
                       style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
            strokeState(&ctx, circle(c, r), s, base: (P.raisedRim, 0.7))
            if key == .power {
                var arc = Path()
                arc.addArc(center: CGPoint(x: 62.1, y: 37.43), radius: 5,
                           startAngle: .degrees(218.7), endAngle: .degrees(-38.7), clockwise: true)
                iconStroke(ctx, line([CGPoint(x: 62.1, y: 32), CGPoint(x: 62.1, y: 36.6)]), P.raisedIcon)
                iconStroke(ctx, arc, P.raisedIcon)
            } else {
                iconStroke(ctx, Path(roundedRect: CGRect(x: 116.1, y: 31.6, width: 4.2, height: 7),
                                     cornerRadius: 2.1), P.raisedIcon)
                var cradle = Path()
                cradle.addArc(center: CGPoint(x: 118.2, y: 36.8), radius: 4.6,
                              startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
                cradle.move(to: CGPoint(x: 118.2, y: 41.4))
                cradle.addLine(to: CGPoint(x: 118.2, y: 43.2))
                iconStroke(ctx, cradle, P.raisedIcon)
            }
        }
    }

    // 2. 方向环与 OK
    private func drawRing(_ ctx: inout GraphicsContext) {
        let c = G.ringCenter
        var shadow = ctx
        shadow.addFilter(.blur(radius: 0.8))
        shadow.fill(circle(CGPoint(x: c.x, y: c.y + 1.2), G.ringOuter), with: .color(.black.opacity(0.28)))
        let ring = circle(c, G.ringOuter)
        ctx.fill(ring, with: .color(P.ring))
        ctx.fill(ring, with: .linearGradient(gradient(P.ringGradient),
            startPoint: CGPoint(x: c.x - G.ringOuter, y: 0), endPoint: CGPoint(x: c.x + G.ringOuter, y: 0)))
        ctx.stroke(ring, with: .color(.black.opacity(0.9)), lineWidth: 0.7)
        ctx.stroke(circle(c, 44.3), with: .color(P.ringInnerEdge), lineWidth: 0.7)
        for p in [CGPoint(x: 90, y: 69.1), CGPoint(x: 131.6, y: 110.7),
                  CGPoint(x: 90, y: 152.3), CGPoint(x: 48.4, y: 110.7)] {
            ctx.fill(circle(p, 0.75), with: .color(P.ringDot))
        }
        for dir in [RemoteKey.up, .right, .down, .left] {
            let s = keyState(dir)
            if s.pressed, let sector = G.sectorPath(dir) {
                ctx.fill(sector, with: .color(P.keyPressed.opacity(0.6)))
            }
            guard let arc = G.arcPath(dir) else { continue }
            if s.accented || s.pressed || s.hovered {
                var styled = ctx
                let width: CGFloat = s.pulse ? 2.6 : (s.selected ? 2.2 : (s.pressed ? 2.5 : 1.6))
                styled.addFilter(.shadow(color: .black.opacity(s.accented ? 1 : 0.85), radius: s.accented ? 0.9 : 0.7))
                if s.accented {
                    styled.addFilter(.shadow(color: Color.accentColor.opacity(0.85), radius: 2.8))
                }
                let color: Color = s.hovered && !s.accented && !s.pressed
                    ? hoverColor : Color.accentColor.opacity(s.pressed && !s.accented ? 0.85 : 1)
                styled.stroke(arc, with: .color(color),
                              style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
        // OK 凸起黑盘 + 凹槽
        ctx.stroke(circle(c, 25.3), with: .color(P.okOuterLine), lineWidth: 0.5)
        ctx.fill(circle(c, 24.7), with: .color(P.okGroove))
        let okState = keyState(.ok)
        var okShadow = ctx
        okShadow.addFilter(.blur(radius: 0.8))
        okShadow.fill(circle(CGPoint(x: c.x, y: c.y + 1), G.okRadius), with: .color(.black.opacity(0.5)))
        let ok = circle(c, G.okRadius)
        ctx.fill(ok, with: .radialGradient(gradient(P.okRadial),
            center: CGPoint(x: c.x, y: c.y - G.okRadius + 0.38 * G.okRadius * 2),
            startRadius: 0, endRadius: 0.62 * G.okRadius * 2))
        ctx.fill(ok, with: .linearGradient(gradient(P.okLinear),
            startPoint: CGPoint(x: 0, y: c.y - G.okRadius), endPoint: CGPoint(x: 0, y: c.y + G.okRadius)))
        if okState.pressed { ctx.fill(ok, with: .color(.black.opacity(0.18))) }
        strokeState(&ctx, ok, okState, base: nil)
    }

    // 3. 返回 / 主页 / 菜单 / TV 黑键与音量胶囊
    private func drawBlackKeys(_ ctx: inout GraphicsContext) {
        for (key, c) in G.blackKeys.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let s = keyState(key)
            ctx.fill(circle(CGPoint(x: c.x, y: c.y + 0.9), G.blackRadius), with: .color(.black.opacity(0.3)))
            let face = circle(c, G.blackRadius)
            ctx.fill(face, with: .color(s.pressed ? P.keyPressed : P.keyFace))
            ctx.fill(face, with: .linearGradient(gradient(P.keyGloss),
                startPoint: CGPoint(x: c.x - G.blackRadius + 0.6 * G.blackRadius, y: c.y - G.blackRadius),
                endPoint: CGPoint(x: c.x - G.blackRadius + 1.4 * G.blackRadius, y: c.y + G.blackRadius)))
            strokeState(&ctx, face, s, base: (P.keyFaceStroke, 0.8))
            switch key {
            case .back:
                iconStroke(ctx, line([CGPoint(x: 69.5, y: 175.1), CGPoint(x: 65.1, y: 179.5),
                                      CGPoint(x: 69.5, y: 183.9)]), P.icon)
            case .home:
                var house = line([CGPoint(x: 63.3, y: 221.6), CGPoint(x: 67.9, y: 217.2),
                                  CGPoint(x: 72.5, y: 221.6), CGPoint(x: 72.5, y: 226.6),
                                  CGPoint(x: 63.3, y: 226.6)])
                house.closeSubpath()
                iconStroke(ctx, house, P.icon)
            case .menu:
                var bars = Path()
                for y in [261.1, 264.3, 267.5] as [CGFloat] {
                    bars.move(to: CGPoint(x: 63.5, y: y))
                    bars.addLine(to: CGPoint(x: 72.3, y: y))
                }
                iconStroke(ctx, bars, P.icon)
            case .tv:
                iconStroke(ctx, Path(roundedRect: CGRect(x: 107, y: 260.3, width: 11.2, height: 8),
                                     cornerRadius: 2), P.icon)
                ctx.draw(Text("TV").font(.system(size: 5.2, weight: .semibold)).foregroundStyle(P.icon),
                         at: CGPoint(x: 112.6, y: 264.4))
            default:
                break
            }
        }
        // 音量竖胶囊
        let vol = Path(roundedRect: G.volRect, cornerRadius: G.volRadius, style: .circular)
        ctx.fill(Path(roundedRect: G.volRect.offsetBy(dx: 0, dy: 0.9), cornerRadius: G.volRadius, style: .circular),
                 with: .color(.black.opacity(0.3)))
        ctx.fill(Path(roundedRect: G.volRect.insetBy(dx: 0.4, dy: 0.4), cornerRadius: G.volRadius - 0.4, style: .circular),
                 with: .color(P.volumeBase))
        // 两半的填充/光泽裁进胶囊外形，保证与底座、外沿描边严丝合缝（左右边缘一致，无毛边）
        var volCtx = ctx
        volCtx.clip(to: vol)
        for key in [RemoteKey.volUp, .volDown] {
            let s = keyState(key)
            let half = G.volumeHalf(key)
            volCtx.fill(half, with: .color(s.pressed ? P.keyPressed
                                         : (key == .volUp ? RC2ProPalette.fixed(0x292929) : RC2ProPalette.fixed(0x262626))))
            let b = half.boundingRect
            volCtx.fill(half, with: .linearGradient(gradient(P.keyGloss),
                startPoint: CGPoint(x: b.minX + 0.3 * b.width, y: b.minY),
                endPoint: CGPoint(x: b.minX + 0.7 * b.width, y: b.maxY)))
        }
        ctx.stroke(vol, with: .color(P.keyRim), lineWidth: 0.7)
        var split = Path()
        split.move(to: CGPoint(x: 94.8, y: G.volSplitY))
        split.addLine(to: CGPoint(x: 130.4, y: G.volSplitY))
        ctx.stroke(split, with: .color(P.volumeSplit), lineWidth: 0.6)
        for key in [RemoteKey.volUp, .volDown] {
            strokeState(&ctx, G.volumeHalf(key), keyState(key), base: nil)
        }
        var plus = Path()
        plus.move(to: CGPoint(x: 112.6, y: 175.3)); plus.addLine(to: CGPoint(x: 112.6, y: 183.9))
        plus.move(to: CGPoint(x: 108.3, y: 179.6)); plus.addLine(to: CGPoint(x: 116.9, y: 179.6))
        iconStroke(ctx, plus, P.icon)
        iconStroke(ctx, line([CGPoint(x: 108.3, y: 222), CGPoint(x: 116.9, y: 222)]), P.icon)
    }

    // 5. 丝印
    private func drawPrint(_ ctx: inout GraphicsContext) {
        ctx.stroke(line([CGPoint(x: 86.6, y: 347.4), CGPoint(x: 86.6, y: 340.2),
                         CGPoint(x: 93.4, y: 347.4), CGPoint(x: 93.4, y: 340.2)]),
                   with: .color(P.print), style: StrokeStyle(lineWidth: 1.1, lineJoin: .round))
        ctx.stroke(Path(roundedRect: CGRect(x: 84.5, y: 338.3, width: 11, height: 11), cornerRadius: 2.4, style: .circular),
                   with: .color(P.print), lineWidth: 0.8)
        ctx.draw(Text("xiaomi").font(.system(size: 8.6, weight: .semibold)).tracking(1.1)
                    .foregroundStyle(P.print),
                 at: CGPoint(x: 90, y: 422.5))
    }

    // 连接状态（与通用画法同位置同样式）
    private func drawStatus(_ ctx: inout GraphicsContext) {
        let dot = Path(ellipseIn: CGRect(x: 90 - 26 - 3, y: 463, width: 6, height: 6))
        ctx.fill(dot, with: .color(connected ? Color.accentColor : Color(white: 0.6)))
        ctx.draw(Text(connected ? "已连接" : "未连接").font(.system(size: 9)).foregroundStyle(.secondary),
                 at: CGPoint(x: 90 + 8, y: 466))
    }
}
