import AppKit
import ServiceManagement

// `C200Controller --login-item on|off|status` manages the login item from the shell and exits.
if let flag = CommandLine.arguments.firstIndex(of: "--login-item") {
    let service = SMAppService.mainApp
    let action = CommandLine.arguments.dropFirst(flag + 1).first ?? "status"
    do {
        switch action {
        case "on": try service.register()
        case "off": try service.unregister()
        default: break
        }
        print("login item: \(service.status.rawValue) (0 not registered, 1 enabled, 2 requires approval, 3 not found)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("login item \(action) failed: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
