import Foundation

/// 基础状态（layer 0）短按的文字说明与实际动作（spec「基础状态短按的文字说明」）。
///
/// 规则与 `MappingEngine.fireTap` 的 layer 0 分支同源：方向键保持原生光标键，
/// 返回键恒为 Delete，OK 默认 Return，只有 App 场景明确设置的 OK 短按可替代。
/// `MappingEngine.baseTapNoteParityCheck()` 用真实引擎对拍，规则漂移时自测会红。
/// 本类型只读配置，不改写任何值（旧配置中 global OK 短按的值原样保留）。
enum BaseTapNote {

    static let layerTail = "这里的短按设置只在第二功能模式下（且该模式没有单独设置时）生效。"

    /// 详情表头的一句说明（plan D5 拟定文案，待用户在发布验收时确认）。
    static let detailHeader = "基础状态下方向键为光标键、返回键为删除（Delete）、OK 为回车（Return）；App 场景明确设置的 OK 短按会替代回车。"

    private static let arrowGlyph: [RemoteKey: String] = [
        .up: "↑", .down: "↓", .left: "←", .right: "→",
    ]

    private static let arrowKeyName: [RemoteKey: String] = [
        .up: "up_arrow", .down: "down_arrow", .left: "left_arrow", .right: "right_arrow",
    ]

    /// 「短按」槽位的说明。`ownTap` 为当前 profile 自身（不含继承）的 tap。
    /// 非方向 / 返回 / OK 键返回 nil。
    static func text(key: RemoteKey, profile: String, ownTap: Action?) -> String? {
        if let glyph = arrowGlyph[key] {
            return "基础状态下此短按保持原生光标键（\(glyph)），由引擎直接处理；" + layerTail
        }
        switch key {
        case .back:
            return "基础状态下此短按始终是删除（Delete）；" + layerTail
        case .ok:
            if profile == "global" {
                return "基础状态下 OK 短按是回车（Return），全局默认不能改写；只有 App 场景里明确设置的短按会替代回车。" + layerTail
            }
            if ownTap != nil {
                return "本场景明确设置了 OK 短按，基础状态下会替代默认的回车（Return）。"
            }
            return "基础状态下 OK 短按默认是回车（Return）；在本场景明确设置短按即可替代。"
        default:
            return nil
        }
    }

    /// 由上述规则推导的基础状态实际短按动作；其他键返回 nil（按配置执行）。
    static func baseAction(key: RemoteKey, profile: String, ownTap: Action?) -> Action? {
        if let name = arrowKeyName[key] { return .keyStroke(key: name, mods: []) }
        switch key {
        case .back:
            return .keyStroke(key: "delete", mods: [])
        case .ok:
            if profile != "global", let ownTap { return ownTap }
            return .keyStroke(key: "return", mods: [])
        default:
            return nil
        }
    }

    static func selfCheck() -> Bool {
        var ok = true
        func check(_ cond: Bool, _ msg: String) {
            if !cond { ok = false; print("[BaseTapNote.selfCheck] FAIL: \(msg)") }
        }
        for (key, glyph) in [(RemoteKey.up, "↑"), (.down, "↓"), (.left, "←"), (.right, "→")] {
            check(text(key: key, profile: "global", ownTap: nil)
                  == "基础状态下此短按保持原生光标键（\(glyph)），由引擎直接处理；" + layerTail,
                  "arrow \(key)")
        }
        check(text(key: .back, profile: "com.mitchellh.ghostty", ownTap: .keyStroke(key: "escape", mods: []))
              == "基础状态下此短按始终是删除（Delete）；" + layerTail, "back")
        check(text(key: .ok, profile: "global", ownTap: .system("spotlight"))
              == "基础状态下 OK 短按是回车（Return），全局默认不能改写；只有 App 场景里明确设置的短按会替代回车。" + layerTail,
              "ok global")
        check(text(key: .ok, profile: "com.mitchellh.ghostty", ownTap: .keyStroke(key: "return", mods: []))
              == "本场景明确设置了 OK 短按，基础状态下会替代默认的回车（Return）。", "ok app explicit")
        check(text(key: .ok, profile: "com.mitchellh.ghostty", ownTap: nil)
              == "基础状态下 OK 短按默认是回车（Return）；在本场景明确设置短按即可替代。", "ok app inherited")
        let others: [RemoteKey] = [.power, .voice, .home, .menu, .tv, .volUp, .volDown]
        for key in others {
            check(text(key: key, profile: "global", ownTap: nil) == nil, "no note for \(key)")
        }
        // 13 键中 6 键有说明，其余 7 键无；spec 写「其余 8 个键」按 13 键实际为 7 个。
        check(others.count + 6 == RemoteKey.allCases.count, "key count")
        var texts = [layerTail, detailHeader]
        for key in RemoteKey.allCases {
            for profile in ["global", "com.test.app"] {
                for own in [nil, Action.keyStroke(key: "x", mods: [])] {
                    if let t = text(key: key, profile: profile, ownTap: own) { texts.append(t) }
                }
            }
        }
        check(texts.allSatisfy { $0.unicodeScalars.allSatisfy { $0.value < 0x1F000 } }, "no emoji")
        return ok
    }
}
