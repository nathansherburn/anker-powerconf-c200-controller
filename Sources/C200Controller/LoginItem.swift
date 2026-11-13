import AppKit
import ServiceManagement

/// Launch at login as a login item for the app itself. macOS opens the app at login and
/// the app stays in the menu bar without a window (see `wasLaunchedAtLogin`).
///
/// This used to be a bundled LaunchAgent, but macOS pins an agent to the exact build that
/// first registered it, so after a rebuild launchd killed it at login.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var error: String?

    private let service = SMAppService.mainApp

    init() { refresh() }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    /// True when macOS opened the app as a login item. Valid in applicationDidFinishLaunching,
    /// while the "open application" Apple event is being handled.
    static var wasLaunchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        status = service.status
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
