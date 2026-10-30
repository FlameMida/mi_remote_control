import SwiftUI
import AppKit
import CoreBluetooth

enum SidebarItem: String, CaseIterable, Identifiable {
    case mapping, profile, voice, general
    var id: String { rawValue }

    var title: String {
        switch self {
        case .mapping: return "按键映射"
        case .profile: return "场景配置"
        case .voice:   return "语音"
        case .general: return "通用"
        }
    }
    var icon: String {
        switch self {
        case .mapping: return "slider.horizontal.3"
        case .profile: return "rectangle.stack"
        case .voice:   return "mic"
        case .general: return "gearshape"
        }
    }
}

/// 设置窗详情区：当前页 + 页面级 sheet + 启动权限门槛。侧栏见 SettingsSidebar（SettingsWindow.swift）。
@MainActor
struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: SettingsNav
    @EnvironmentObject var permissions: PermissionStatus

    var body: some View {
        Group {
            switch nav.page {
            case .mapping: MappingPage(onOpenProfiles: { nav.page = .profile })
            case .profile: ProfilePage(selection: $nav.page)
            case .voice:   VoicePage(onOpenOnboarding: { step in nav.onboardingStep = step; nav.showOnboarding = true })
            case .general: GeneralPage(onShowOnboarding: { nav.onboardingStep = 0; nav.showOnboarding = true },
                                       onShowHealthCheck: { nav.showHealthCheck = true })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 原型 .win：标题栏是独立一行，.main 在其下方滚动。fullSizeContentView 下 ScrollView
        // 内容会画进标题栏安全区（滚动后正文从「MiRemote 设置」背后透出）；按安全区内边界裁剪，
        // 所有详情页（映射 / 场景 / 语音 / 通用）一致。
        .clipped()
        .sheet(isPresented: $nav.showOnboarding) { OnboardingWizard(initialStep: nav.onboardingStep) }
        .sheet(isPresented: $nav.showHealthCheck) { HealthCheckSheet() }
        .sheet(isPresented: $nav.showReauth) { ReauthSheet() }
        .onAppear {
            guard !PermissionGate.suppressLaunchGate else { return }
            let lostPermissions = PermissionMemory.lostPermissions()
            // 每次进程启动都按当前真实权限重检。完成过向导只代表用户走完流程，
            // 不能掩盖后来拒绝/撤销/签名变化导致的失权。
            // 已完成过首启但 AX/输入监控失权时优先走精简重授权，不重复 BlackHole/配对。
            if PermissionGate.shouldUseReauth(
                hasCompletedOnboarding: model.hasCompletedOnboarding,
                bluetooth: CBCentralManager.authorization,
                lostCorePermissions: lostPermissions) {
                nav.showReauth = true
            } else if PermissionGate.needsOnboarding(
                hasCompletedOnboarding: model.hasCompletedOnboarding,
                bluetooth: CBCentralManager.authorization,
                accessibility: EnvironmentCheck.accessibility().state,
                inputMonitoring: EnvironmentCheck.inputMonitoring().state) {
                nav.onboardingStep = 0
                nav.showOnboarding = true
            }
            PermissionMemory.snapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: .miremoteShowHealthCheck)) { _ in
            nav.showHealthCheck = true
        }
        .settingsStatusEnvironment(model: model, nav: nav, permissions: permissions)
    }
}

/// 启动权限门槛的纯判定，避免 UI 生命周期把「向导已完成」误当成「权限仍有效」。
enum PermissionGate {
    /// 仅隐藏的 --snapshot 渲染模式置真：不弹首启 / 重授权，保证截图状态可控。
    nonisolated(unsafe) static var suppressLaunchGate = false

    static func shouldUseReauth(hasCompletedOnboarding: Bool,
                                bluetooth: CBManagerAuthorization,
                                lostCorePermissions: [String]) -> Bool {
        hasCompletedOnboarding && bluetooth == .allowedAlways && !lostCorePermissions.isEmpty
    }

    static func needsOnboarding(hasCompletedOnboarding: Bool,
                                bluetooth: CBManagerAuthorization,
                                accessibility: EnvCheckState,
                                inputMonitoring: EnvCheckState) -> Bool {
        !hasCompletedOnboarding
            || bluetooth != .allowedAlways
            || accessibility != .granted
            || inputMonitoring != .granted
    }
}

extension Notification.Name {
    static let miremoteShowHealthCheck = Notification.Name("com.miremote.showHealthCheck")
}
