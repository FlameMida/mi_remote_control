import Foundation

/// 绑定中的一个动作位：短按 / 长按 / 双击 / OK 手势方向 / 某模式的短按替代。
enum MappingSlot: Hashable {
    case tap, hold, double, gesture(String), layer(Int)
}

/// 槽位来源：本 profile 显式设置 / 继承全局 / 未设置。
enum SlotSource: Equatable {
    case appOverride, inherited, unset
}

struct SlotResolution: Equatable {
    let action: Action?
    let source: SlotSource
}

/// 槽位来源解析与「恢复继承」（spec「App 场景槽位显示来源并可恢复继承」）。
/// 合并语义与 `MappingDetailResolver.binding` 一致：逐槽位覆盖，手势 / 模式字典逐键合并。
enum SlotResolver {

    static func value(of binding: KeyBinding?, slot: MappingSlot) -> Action? {
        guard let binding else { return nil }
        switch slot {
        case .tap:              return binding.tap
        case .hold:             return binding.hold
        case .double:           return binding.double
        case .gesture(let dir): return binding.gesture?[dir]
        case .layer(let n):     return binding.layers?["\(n)"]
        }
    }

    static func resolve(config: MappingConfig, profile: String, key: RemoteKey, slot: MappingSlot) -> SlotResolution {
        let own = value(of: config.profiles[profile]?[key.rawValue], slot: slot)
        if let own { return SlotResolution(action: own, source: .appOverride) }
        if profile == "global" { return SlotResolution(action: nil, source: .unset) }
        if let inherited = value(of: config.profiles["global"]?[key.rawValue], slot: slot) {
            return SlotResolution(action: inherited, source: .inherited)
        }
        return SlotResolution(action: nil, source: .unset)
    }

    /// 移除非 global profile 中某槽位的显式设置。空字典置 nil；五个字段全空时移除该键条目；
    /// profile 本身即使变空也保留（场景列表不变）。对 global 原样返回。
    static func removingOverride(config: MappingConfig, profile: String, key: RemoteKey, slot: MappingSlot) -> MappingConfig {
        guard profile != "global",
              var entries = config.profiles[profile],
              var binding = entries[key.rawValue] else { return config }
        switch slot {
        case .tap:    binding.tap = nil
        case .hold:   binding.hold = nil
        case .double: binding.double = nil
        case .gesture(let dir):
            binding.gesture?.removeValue(forKey: dir)
            if binding.gesture?.isEmpty == true { binding.gesture = nil }
        case .layer(let n):
            binding.layers?.removeValue(forKey: "\(n)")
            if binding.layers?.isEmpty == true { binding.layers = nil }
        }
        if binding.tap == nil, binding.hold == nil, binding.double == nil,
           binding.gesture == nil, binding.layers == nil {
            entries.removeValue(forKey: key.rawValue)
        } else {
            entries[key.rawValue] = binding
        }
        var out = config
        out.profiles[profile] = entries
        return out
    }

    static func selfCheck() -> Bool {
        var ok = true
        func check(_ cond: Bool, _ msg: String) {
            if !cond { ok = false; print("[SlotResolver.selfCheck] FAIL: \(msg)") }
        }
        let ghostty = "com.mitchellh.ghostty"
        let ctrlC = Action.keyStroke(key: "c", mods: ["control"])
        var cfg = MappingConfig()
        cfg.profiles["global"] = [
            "home": KeyBinding(tap: .system("show_desktop")),
            "ok": KeyBinding(gesture: ["up": .system("mission_control")]),
        ]
        cfg.profiles[ghostty] = ["home": KeyBinding(tap: ctrlC)]

        check(resolve(config: cfg, profile: "global", key: .home, slot: .tap)
              == SlotResolution(action: .system("show_desktop"), source: .appOverride), "global home tap")
        check(resolve(config: cfg, profile: "global", key: .back, slot: .tap)
              == SlotResolution(action: nil, source: .unset), "global back tap")
        check(resolve(config: cfg, profile: ghostty, key: .home, slot: .tap)
              == SlotResolution(action: ctrlC, source: .appOverride), "ghostty home tap")
        check(resolve(config: cfg, profile: ghostty, key: .home, slot: .hold)
              == SlotResolution(action: nil, source: .unset), "ghostty home hold")
        check(resolve(config: cfg, profile: ghostty, key: .ok, slot: .gesture("up"))
              == SlotResolution(action: .system("mission_control"), source: .inherited), "ghostty ok gesture up")
        check(resolve(config: cfg, profile: ghostty, key: .volUp, slot: .tap)
              == SlotResolution(action: nil, source: .unset), "ghostty volUp tap")

        let restored = removingOverride(config: cfg, profile: ghostty, key: .home, slot: .tap)
        check(resolve(config: restored, profile: ghostty, key: .home, slot: .tap)
              == SlotResolution(action: .system("show_desktop"), source: .inherited), "restored inherits")
        check(restored.profiles[ghostty]?["home"] == nil, "empty entry removed")
        check(restored.profiles[ghostty] != nil, "profile kept")

        var withHold = cfg
        withHold.profiles[ghostty]?["home"]?.hold = .system("lock_screen")
        let onlyTap = removingOverride(config: withHold, profile: ghostty, key: .home, slot: .tap)
        check(onlyTap.profiles[ghostty]?["home"]?.hold == .system("lock_screen"), "hold kept")
        check(onlyTap.profiles[ghostty]?["home"]?.tap == nil, "tap removed")

        var gest = cfg
        gest.profiles[ghostty]?["ok"] = KeyBinding(gesture: ["up": .system("launchpad"),
                                                            "down": .system("mute")],
                                                  layers: ["1": .system("mute")])
        let g1 = removingOverride(config: gest, profile: ghostty, key: .ok, slot: .gesture("up"))
        check(g1.profiles[ghostty]?["ok"]?.gesture == ["down": .system("mute")], "gesture key removed")
        let g2 = removingOverride(config: g1, profile: ghostty, key: .ok, slot: .gesture("down"))
        check(g2.profiles[ghostty]?["ok"]?.gesture == nil, "empty gesture -> nil")
        check(g2.profiles[ghostty]?["ok"]?.layers == ["1": .system("mute")], "layers kept")
        let g3 = removingOverride(config: g2, profile: ghostty, key: .ok, slot: .layer(1))
        check(g3.profiles[ghostty]?["ok"] == nil, "entry removed after last slot")

        let same = removingOverride(config: cfg, profile: "global", key: .home, slot: .tap)
        check(same.profiles["global"]?["home"]?.tap == .system("show_desktop"), "global untouched")
        return ok
    }
}
