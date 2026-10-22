import AppKit
import Combine

/// The menu bar icon and its quick-access menu. The menu is rebuilt each time it opens,
/// so it always reflects the current camera state.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: CameraModel
    private let loginItem: LoginItem
    private let openWindow: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var cancellables: Set<AnyCancellable> = []

    init(model: CameraModel, loginItem: LoginItem, openWindow: @escaping () -> Void) {
        self.model = model
        self.loginItem = loginItem
        self.openWindow = openWindow
        super.init()

        statusItem.button?.image = Self.cameraIcon()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        model.$connected
            .sink { [weak self] connected in self?.updateIcon(connected: connected) }
            .store(in: &cancellables)
    }

    /// The C200 seen from the front: a rounded-square body with a square lens window
    /// and a round lens. A template image, so macOS tints it for the menu bar.
    private static func cameraIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let body = NSBezierPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), xRadius: 4.2, yRadius: 4.2)
            body.append(NSBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), xRadius: 2.3, yRadius: 2.3))
            body.windingRule = .evenOdd
            NSColor.black.setFill()
            body.fill()
            let lens: CGFloat = 5.8
            NSBezierPath(ovalIn: NSRect(x: rect.midX - lens / 2, y: rect.midY - lens / 2, width: lens, height: lens)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "C200 Controller"
        return image
    }

    private func updateIcon(connected: Bool) {
        statusItem.button?.appearsDisabled = !connected
        statusItem.button?.toolTip = connected ? "C200 Controller" : "C200 Controller — camera not connected"
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        loginItem.refresh()
        menu.removeAllItems()
        let connected = model.connected

        let status = NSMenuItem(title: connected ? "PowerConf C200" : "Camera not connected", action: nil, keyEquivalent: "")
        status.image = NSImage(systemSymbolName: connected ? "circle.fill" : "circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [connected ? .systemGreen : .secondaryLabelColor]))
        status.isEnabled = false
        menu.addItem(status)
        if let message = model.status, connected {
            let warning = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
        }
        menu.addItem(actionItem("Open Controller…", key: "o") { [openWindow] in openWindow() })
        menu.addItem(.separator())

        menu.addItem(presetsItem(enabled: connected))
        if model.isAnker, model.available["zoom"] != nil {
            menu.addItem(fovItem(enabled: connected))
        }
        for id in ["mirror", "hdr"] {
            guard let spec = Catalog.byID[id], model.available[id] != nil,
                  case .toggle(let on, _) = spec.kind
            else { continue }
            let item = actionItem(spec.name, enabled: connected) { [model] in
                model.set(id, model.values[id] == on ? spec.offValue ?? 0 : on)
            }
            item.state = model.values[id] == on ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        menu.addItem(actionItem("Re-apply Settings", enabled: connected) { [model] in model.reapply() })
        menu.addItem(.separator())

        let login = actionItem("Launch at Login") { [loginItem] in loginItem.setEnabled(!loginItem.isEnabled) }
        login.state = loginItem.isEnabled ? .on : .off
        menu.addItem(login)
        if loginItem.needsApproval {
            menu.addItem(actionItem("Allow in System Settings…") { [loginItem] in loginItem.openSystemSettings() })
        }
        menu.addItem(NSMenuItem(title: "Quit C200 Controller", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func presetsItem(enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        if model.presets.isEmpty {
            let empty = NSMenuItem(title: "No presets yet — save one in the controller", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }
        for preset in model.presets {
            let isActive = preset.name == model.activePreset
            let title = isActive && model.activePresetIsModified ? "\(preset.name) (edited)" : preset.name
            let presetItem = actionItem(title, enabled: enabled) { [model] in model.applyPreset(preset) }
            presetItem.state = isActive ? .on : .off
            submenu.addItem(presetItem)
        }
        submenu.addItem(.separator())
        submenu.addItem(actionItem("Reset to Camera Defaults", enabled: enabled) { [model] in model.resetAllToDefaults() })
        item.submenu = submenu
        return item
    }

    private func fovItem(enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: "Field of View", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for preset in C200.fovPresets {
            let fov = actionItem("\(preset.degrees)° \(preset.label)", enabled: enabled) { [model] in
                model.setFOV(preset.degrees)
            }
            fov.state = model.currentFOV == preset.degrees ? .on : .off
            submenu.addItem(fov)
        }
        item.submenu = submenu
        return item
    }

    /// A menu item that runs a closure. NSMenuItem keeps a strong reference to its
    /// representedObject, which keeps the closure alive for as long as the item.
    private func actionItem(_ title: String, key: String = "", enabled: Bool = true,
                            action: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: enabled ? #selector(runAction(_:)) : nil, keyEquivalent: key)
        item.target = self
        item.representedObject = action
        item.isEnabled = enabled
        return item
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
    }
}
