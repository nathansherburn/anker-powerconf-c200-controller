import ServiceManagement

/// Launch at login via a LaunchAgent bundled in Contents/Library/LaunchAgents, which
/// starts the app with --background so it applies settings without opening a window.
@MainActor
final class LoginItem: ObservableObject {
    static let agentPlist = "com.nathansherburn.c200controller.agent.plist"

    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var error: String?

    private let service = SMAppService.agent(plistName: agentPlist)

    init() { refresh() }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

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
