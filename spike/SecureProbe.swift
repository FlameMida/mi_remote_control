// Spike: Secure Input receive/deliver feasibility probe (throwaway, not part of the app).
// Modes:
//   target                 AppKit window with a plain NSTextField and an NSSecureTextField; obeys /tmp/spike/cmd
//   listener NAME [flags]  background receiver: CGEventTap (HID+session), NSEvent global monitor, IOHIDManager listen + seize
//                          flags: --no-tap --no-ns --no-hid
//   inject KIND [ARG]      cghid | cgsession | unicode TEXT | click X Y
//   vhid SECONDS           (root) virtual HID keyboard via IOHIDUserDevice; types usages listed in /tmp/spike/vhid-keys on demand
//   secure-helper SECONDS  EnableSecureEventInput() for N seconds in a separate process
//   status                 print IsSecureEventInputEnabled + kCGSSessionSecureInputPID + permission preflights
import AppKit
import Carbon.HIToolbox
import IOKit.hid
import ApplicationServices

setvbuf(stdout, nil, _IOLBF, 0)
let dir = "/tmp/spike"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

func ts() -> String {
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f.string(from: Date())
}
func phase() -> String {
    (try? String(contentsOfFile: dir + "/phase", encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
}
var who = "probe"
func log(_ s: String) { print("\(ts()) [\(who)] [\(phase())] \(s)") }

func securePID() -> Int {
    guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return -1 }
    return (d["kCGSSessionSecureInputPID"] as? Int) ?? 0
}
func secureStatus() -> String {
    "IsSecureEventInputEnabled=\(IsSecureEventInputEnabled()) kCGSSessionSecureInputPID=\(securePID())"
}
func permStatus() -> String {
    let hidListen = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    let hidPost = IOHIDCheckAccess(kIOHIDRequestTypePostEvent)
    return "uid=\(getuid()) AXIsProcessTrusted=\(AXIsProcessTrusted()) CGPreflightListen=\(CGPreflightListenEventAccess()) CGPreflightPost=\(CGPreflightPostEventAccess()) IOHIDListen=\(hidListen.rawValue) IOHIDPost=\(hidPost.rawValue) (0=granted 1=denied 2=unknown)"
}

let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "status"

// MARK: - target

final class TargetDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let plain = NSTextField(frame: NSRect(x: 20, y: 120, width: 360, height: 24))
    let secure = NSSecureTextField(frame: NSRect(x: 20, y: 60, width: 360, height: 24))
    var lastCmd = ""
    func applicationDidFinishLaunching(_ n: Notification) {
        window = NSWindow(contentRect: NSRect(x: 200, y: 300, width: 400, height: 200),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "SecureProbe target"
        plain.placeholderString = "plain"; secure.placeholderString = "secure"
        window.contentView?.addSubview(plain); window.contentView?.addSubview(secure)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
    }
    func rectCG(_ v: NSView) -> NSRect {
        let r = v.window!.convertToScreen(v.convert(v.bounds, to: nil))
        let h = NSScreen.screens.first!.frame.height
        return NSRect(x: r.midX, y: h - r.midY, width: r.width, height: r.height)
    }
    func dump() {
        let resp = window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
        let p = rectCG(plain), s = rectCG(secure)
        let st = "active=\(NSApp.isActive) key=\(window.isKeyWindow) responder=\(resp) plain=\"\(plain.stringValue)\" secure=\"\(secure.stringValue)\" secureLen=\(secure.stringValue.count) \(secureStatus()) plainXY=\(Int(p.minX)),\(Int(p.minY)) secureXY=\(Int(s.minX)),\(Int(s.minY)) myPID=\(getpid())"
        try? st.write(toFile: dir + "/target-state", atomically: true, encoding: .utf8)
    }
    func tick() {
        dump()
        guard let c = try? String(contentsOfFile: dir + "/cmd", encoding: .utf8), c != lastCmd else { return }
        lastCmd = c
        let parts = c.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map(String.init)
        guard let op = parts.first else { return }
        switch op {
        case "activate": NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        case "focusPlain": NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(plain)
        case "focusSecure": NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(secure)
        case "clear": plain.stringValue = ""; secure.stringValue = ""
        case "shot":
            if let v = window.contentView?.superview ?? window.contentView,
               let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/shots/target-\(parts.count > 1 ? parts[1] : "x").png"))
            }
        default: break
        }
        dump()
        print("\(ts()) [target] cmd=\(c.trimmingCharacters(in: .whitespacesAndNewlines)) -> \((try? String(contentsOfFile: dir + "/target-state", encoding: .utf8)) ?? "")")
    }
}

// MARK: - listener

var listenerTaps: [CFMachPort] = []
func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let name = refcon.map { Unmanaged<NSString>.fromOpaque($0).takeUnretainedValue() as String } ?? "?"
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        log("RECV \(name) tap disabled type=\(type.rawValue)")
        for t in listenerTaps { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    let kc = event.getIntegerValueField(.keyboardEventKeycode)
    var len = 0; var buf = [UniChar](repeating: 0, count: 8)
    event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &len, unicodeString: &buf)
    let s = String(utf16CodeUnits: buf, count: len)
    log("RECV \(name) type=\(type == .keyDown ? "down" : "up") keycode=\(kc) chars=\"\(s)\" srcPID=\(event.getIntegerValueField(.eventSourceUnixProcessID))")
    return Unmanaged.passUnretained(event)
}

func makeTap(_ loc: CGEventTapLocation, _ name: String) {
    let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
    let ref = Unmanaged.passRetained(name as NSString).toOpaque()
    if let t = CGEvent.tapCreate(tap: loc, place: .headInsertEventTap, options: .listenOnly,
                                 eventsOfInterest: mask, callback: tapCallback, userInfo: ref) {
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        listenerTaps.append(t)
        log("SETUP \(name) created enabled=\(CGEvent.tapIsEnabled(tap: t))")
    } else {
        log("SETUP \(name) FAILED (tapCreate returned nil)")
    }
}

func devName(_ d: IOHIDDevice) -> String {
    let p = IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String ?? "?"
    let v = IOHIDDeviceGetProperty(d, kIOHIDVendorIDKey as CFString) as? Int ?? 0
    let pr = IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) as? Int ?? 0
    let t = IOHIDDeviceGetProperty(d, kIOHIDTransportKey as CFString) as? String ?? "?"
    return "\(p)(\(String(format: "%04X:%04X", v, pr)),\(t))"
}

final class HIDCtx { let name: String; init(_ n: String) { name = n } }
var hidManagers: [IOHIDManager] = []
var hidCtxs: [HIDCtx] = []

func makeHID(_ name: String, seize: Bool, match: [String: Any]) {
    let opt = IOOptionBits(seize ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone)
    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, opt)
    IOHIDManagerSetDeviceMatching(mgr, match as CFDictionary)
    let ctx = HIDCtx(name); hidCtxs.append(ctx)
    let p = Unmanaged.passUnretained(ctx).toOpaque()
    IOHIDManagerRegisterDeviceMatchingCallback(mgr, { c, r, _, d in
        let n = Unmanaged<HIDCtx>.fromOpaque(c!).takeUnretainedValue().name
        log("SETUP \(n) device matched \(devName(d)) result=\(String(format: "0x%08X", r))")
    }, p)
    IOHIDManagerRegisterInputValueCallback(mgr, { c, _, _, v in
        let n = Unmanaged<HIDCtx>.fromOpaque(c!).takeUnretainedValue().name
        let e = IOHIDValueGetElement(v)
        let page = IOHIDElementGetUsagePage(e), usage = IOHIDElementGetUsage(e)
        let iv = IOHIDValueGetIntegerValue(v)
        if usage == 0xFFFFFFFF || (page == 7 && (usage < 4 || usage > 0xE7)) { return }
        if page == 7 && usage >= 0xE0 && iv == 0 { return } // modifier releases noise
        let d = IOHIDElementGetDevice(e)
        log("RECV \(n) value page=0x\(String(page, radix: 16)) usage=0x\(String(usage, radix: 16)) value=\(iv) dev=\(devName(d))")
    }, p)
    IOHIDManagerRegisterInputReportCallback(mgr, { c, _, sender, _, rid, rep, len in
        let n = Unmanaged<HIDCtx>.fromOpaque(c!).takeUnretainedValue().name
        let bytes = (0..<len).map { String(format: "%02X", rep[$0]) }.joined(separator: " ")
        var dn = "?"
        if let s = sender { dn = devName(Unmanaged<IOHIDDevice>.fromOpaque(s).takeUnretainedValue()) }
        log("RECV \(n) report id=\(rid) [\(bytes)] dev=\(dn)")
    }, p)
    IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    let r = IOHIDManagerOpen(mgr, opt)
    log("SETUP \(name) IOHIDManagerOpen(\(seize ? "seize" : "listen")) = \(String(format: "0x%08X", r))")
    hidManagers.append(mgr)
}

let vVID = 0x1209, vPID = 0x5EC1   // pid.codes test VID; only used for the virtual keyboard

func runListener() {
    who = args.count > 2 ? args[2] : "listener"
    let flags = Set(args.dropFirst(3))
    log("START \(permStatus()) \(secureStatus())")
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    if !flags.contains("--no-tap") {
        makeTap(.cghidEventTap, "tapHID")
        makeTap(.cgSessionEventTap, "tapSession")
    }
    if !flags.contains("--no-ns") {
        let m = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { e in
            log("RECV nsGlobal keyDown keycode=\(e.keyCode) chars=\"\(e.characters ?? "")\"")
        }
        log("SETUP nsGlobal monitor=\(m != nil)")
    }
    if !flags.contains("--no-hid") {
        makeHID("hidListenKbd", seize: false, match: [kIOHIDDeviceUsagePageKey as String: 1, kIOHIDDeviceUsageKey as String: 6])
        makeHID("hidListenVirt", seize: false, match: [kIOHIDVendorIDKey as String: vVID, kIOHIDProductIDKey as String: vPID])
        makeHID("hidSeizeVirt", seize: true, match: [kIOHIDVendorIDKey as String: vVID, kIOHIDProductIDKey as String: vPID])
    }
    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
        let s = secureStatus()
        let last = (try? String(contentsOfFile: dir + "/\(who)-sec", encoding: .utf8)) ?? ""
        if s != last { try? s.write(toFile: dir + "/\(who)-sec", atomically: true, encoding: .utf8); log("STATUS \(s) taps=\(listenerTaps.map { CGEvent.tapIsEnabled(tap: $0) })") }
    }
    app.run()
}

// MARK: - inject

let letters: [Character: CGKeyCode] = ["a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46]

func typeKeycodes(_ text: String, at loc: CGEventTapLocation) {
    let src = CGEventSource(stateID: .hidSystemState)
    for ch in text {
        guard let kc = letters[ch],
              let d = CGEvent(keyboardEventSource: src, virtualKey: kc, keyDown: true),
              let u = CGEvent(keyboardEventSource: src, virtualKey: kc, keyDown: false) else { continue }
        d.post(tap: loc); usleep(30_000); u.post(tap: loc); usleep(60_000)
    }
}
func typeUnicode(_ text: String) {
    // Same technique as Sources/MiRemote/Actions/Macro.swift (virtualKey 0 + unicode string, HID tap)
    let src = CGEventSource(stateID: .combinedSessionState)
    for unit in Array(text.utf16) {
        var u = [unit]
        guard let d = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) else { continue }
        d.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u)
        up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u)
        d.post(tap: .cghidEventTap); usleep(20_000); up.post(tap: .cghidEventTap); usleep(40_000)
    }
}
func click(_ x: Double, _ y: Double) {
    let p = CGPoint(x: x, y: y)
    let src = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(100_000)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(60_000)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}

// MARK: - virtual HID keyboard (root)

func runVHID() {
    who = "vhid"
    let secs = Double(args.count > 2 ? args[2] : "120") ?? 120
    // Boot keyboard: 8-byte input report [mods, reserved, k1..k6]
    let desc: [UInt8] = [0x05,0x01,0x09,0x06,0xA1,0x01,0x05,0x07,0x19,0xE0,0x29,0xE7,0x15,0x00,0x25,0x01,
                         0x75,0x01,0x95,0x08,0x81,0x02,0x95,0x01,0x75,0x08,0x81,0x01,0x95,0x06,0x75,0x08,
                         0x15,0x00,0x25,0x65,0x05,0x07,0x19,0x00,0x29,0x65,0x81,0x00,0xC0]
    let props: [String: Any] = [
        kIOHIDReportDescriptorKey as String: Data(desc),
        kIOHIDVendorIDKey as String: vVID, kIOHIDProductIDKey as String: vPID,
        kIOHIDProductKey as String: "SpikeVirtualKeyboard",
        kIOHIDTransportKey as String: "Bluetooth Low Energy",
    ]
    log("START \(permStatus())")
    guard let dev = IOHIDUserDeviceCreateWithProperties(kCFAllocatorDefault, props as CFDictionary, 0) else {
        log("SETUP IOHIDUserDeviceCreateWithProperties FAILED (nil)"); exit(2)
    }
    let q = DispatchQueue(label: "vhid")
    IOHIDUserDeviceSetDispatchQueue(dev, q)
    IOHIDUserDeviceActivate(dev)
    log("SETUP virtual keyboard created and activated")
    try? "".write(toFile: dir + "/vhid-keys", atomically: true, encoding: .utf8)
    let deadline = Date().addingTimeInterval(secs)
    while Date() < deadline {
        if let s = try? String(contentsOfFile: dir + "/vhid-keys", encoding: .utf8),
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? "".write(toFile: dir + "/vhid-keys", atomically: true, encoding: .utf8)
            for tok in s.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
                guard let usage = UInt8(tok, radix: 16) else { continue }
                var down: [UInt8] = [0, 0, usage, 0, 0, 0, 0, 0]
                var up: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0]
                let r1 = IOHIDUserDeviceHandleReportWithTimeStamp(dev, mach_absolute_time(), &down, down.count)
                usleep(40_000)
                let r2 = IOHIDUserDeviceHandleReportWithTimeStamp(dev, mach_absolute_time(), &up, up.count)
                usleep(80_000)
                log("SEND usage=0x\(String(usage, radix: 16)) down=\(String(format: "0x%08X", r1)) up=\(String(format: "0x%08X", r2))")
            }
        }
        usleep(100_000)
    }
    log("END")
}

// MARK: - main

switch mode {
case "target":
    who = "target"
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let del = TargetDelegate()
    app.delegate = del
    app.run()
case "listener":
    runListener()
case "inject":
    who = "inject"
    let kind = args.count > 2 ? args[2] : ""
    log("INJECT \(kind) \(args.dropFirst(3).joined(separator: " ")) \(permStatus())")
    switch kind {
    case "cghid": typeKeycodes(args.count > 3 ? args[3] : "a", at: .cghidEventTap)
    case "cgsession": typeKeycodes(args.count > 3 ? args[3] : "b", at: .cgSessionEventTap)
    case "unicode": typeUnicode(args.count > 3 ? args[3] : "U")
    case "click": click(Double(args[3]) ?? 0, Double(args[4]) ?? 0)
    default: log("unknown inject kind")
    }
case "vhid":
    runVHID()
case "secure-helper":
    who = "helper"
    let secs = UInt32(args.count > 2 ? args[2] : "10") ?? 10
    let r = EnableSecureEventInput()
    log("EnableSecureEventInput()=\(r) -> \(secureStatus()) helperPID=\(getpid())")
    sleep(secs)
    let r2 = DisableSecureEventInput()
    log("DisableSecureEventInput()=\(r2) -> \(secureStatus())")
default:
    who = "status"
    log("\(permStatus()) \(secureStatus())")
}
