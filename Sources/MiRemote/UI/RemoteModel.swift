import Foundation

/// 遥控器型号判定（spec「MI RC 2 Pro 专用遥控器示意图」判定规则）。
/// 只看「已连接」与生效的 VID/PID（RemoteIdentity，可被 config.json 覆盖）；
/// 未连接时一律通用示意图。不读取 HIDEngine 实际匹配到的设备（plan D3）。
enum RemoteModel: Equatable {
    case rc2Pro, generic

    static let rc2ProVendorID = 0x2717
    static let rc2ProProductID = 0x32B8

    static func resolve(connected: Bool, vendorID: Int, productID: Int) -> RemoteModel {
        connected && vendorID == rc2ProVendorID && productID == rc2ProProductID ? .rc2Pro : .generic
    }

    /// 设备名回退：按配置的型号取名（与 ATVVBridge 连接回退「MI RC」一致），
    /// 未连接时侧栏与菜单栏仍显示原版默认「MI RC 2 Pro」。
    static func fallbackName(vendorID: Int, productID: Int) -> String {
        vendorID == rc2ProVendorID && productID == rc2ProProductID ? "MI RC 2 Pro" : "MI RC"
    }

    static func selfCheck() -> Bool {
        resolve(connected: true, vendorID: 0x2717, productID: 0x32B8) == .rc2Pro
            && resolve(connected: false, vendorID: 0x2717, productID: 0x32B8) == .generic
            && resolve(connected: true, vendorID: 0x2717, productID: 0x1234) == .generic
            && resolve(connected: true, vendorID: 0x046D, productID: 0x32B8) == .generic
            && fallbackName(vendorID: 0x2717, productID: 0x32B8) == "MI RC 2 Pro"
            && fallbackName(vendorID: 0x046D, productID: 0xC52B) == "MI RC"
            && rc2ProVendorID == RemoteIdentity.defaultVendorID
            && rc2ProProductID == RemoteIdentity.defaultProductID
    }
}
