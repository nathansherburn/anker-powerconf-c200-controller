import SwiftUI

struct ContentView: View {
    @ObservedObject var model: CameraModel
    @ObservedObject var preview: PreviewController
    @ObservedObject var loginItem: LoginItem

    var body: some View {
        VStack(spacing: 0) {
            PresetBar(model: model)
            Divider()
            HStack(spacing: 0) {
                PreviewPane(model: model, preview: preview)
                    .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                Sidebar(model: model, loginItem: loginItem)
                    .frame(width: 330)
            }
        }
        .frame(minWidth: 860, minHeight: 540)
    }
}

// MARK: - Preset bar

private struct PresetBar: View {
    @ObservedObject var model: CameraModel
    // A @StateObject rather than @State: the Command Line Tools SDK declares @State as a
    // macro whose plugin only ships with Xcode.
    @StateObject private var ui = PresetBarState()

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(model.presets) { preset in
                    Button(preset.name) { model.applyPreset(preset) }
                }
                if model.presets.isEmpty {
                    Text("No presets yet")
                }
            } label: {
                Text(presetLabel)
            }
            .fixedSize()
            .disabled(!model.connected)

            if let name = model.activePreset, model.activePresetIsModified {
                Button("Update") { model.savePreset(named: name) }
                    .help("Save the current settings into “\(name)”")
            }

            Button("Save As…") {
                ui.newName = ""
                ui.showingSave = true
            }
            .disabled(!model.connected)
            .popover(isPresented: $ui.showingSave, arrowEdge: .bottom) {
                SavePresetForm(name: $ui.newName, existing: model.presets.map(\.name)) {
                    model.savePreset(named: ui.newName)
                    ui.showingSave = false
                }
            }

            if let name = model.activePreset {
                Button {
                    ui.confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                        .accessibilityLabel("Delete preset")
                }
                .help("Delete “\(name)”")
                .confirmationDialog("Delete preset “\(name)”?", isPresented: $ui.confirmingDelete) {
                    Button("Delete", role: .destructive) { model.deletePreset(named: name) }
                }
            }

            Spacer()

            ConnectionBadge(model: model)

            Button {
                model.reapply()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .accessibilityLabel("Re-apply settings")
            }
            .help("Send the current settings to the camera again")
            .disabled(!model.connected)

            Button("Reset All") { model.resetAllToDefaults() }
                .help("Restore the camera's factory defaults")
                .disabled(!model.connected)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var presetLabel: String {
        guard let name = model.activePreset else { return "Presets" }
        return model.activePresetIsModified ? "\(name) (edited)" : name
    }
}

private final class PresetBarState: ObservableObject {
    @Published var showingSave = false
    @Published var confirmingDelete = false
    @Published var newName = ""
}

private struct SavePresetForm: View {
    @Binding var name: String
    let existing: [String]
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Save preset").font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit(save)
            if existing.contains(trimmed) {
                Text("Replaces the existing preset.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(14)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        if !trimmed.isEmpty { onSave() }
    }
}

private struct ConnectionBadge: View {
    @ObservedObject var model: CameraModel

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.connected ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Text(model.status ?? (model.connected ? "PowerConf C200" : "Camera not connected"))
                .font(.callout)
                .foregroundStyle(model.status != nil && model.connected ? Color.orange : Color.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Preview

private struct PreviewPane: View {
    @ObservedObject var model: CameraModel
    @ObservedObject var preview: PreviewController

    var body: some View {
        ZStack {
            Color.black
            PreviewLayerView(session: preview.session)
            if let message {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash").font(.system(size: 32))
                    Text(message)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            }
        }
    }

    private var message: String? {
        switch preview.state {
        case .running: return model.connected ? nil : "Camera not connected"
        case .idle: return "Preview paused"
        case .waitingForPermission: return "Allow camera access to see the preview"
        case .noCamera: return "Camera not connected"
        case .denied: return "Camera access denied — allow it in System Settings › Privacy & Security › Camera"
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @ObservedObject var model: CameraModel
    @ObservedObject var loginItem: LoginItem
    @AppStorage("collapsedSections") private var collapsed = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.available.isEmpty {
                        Text("Connect the camera to adjust its settings.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(ControlSection.allCases) { section in
                        let ids = (Catalog.layout[section] ?? []).filter { model.available[$0] != nil }
                        if !ids.isEmpty {
                            DisclosureGroup(isExpanded: expanded(section)) {
                                VStack(alignment: .leading, spacing: 12) {
                                    sectionHeader(section)
                                    ForEach(ids, id: \.self) { id in
                                        ControlRow(spec: Catalog.byID[id]!, model: model)
                                    }
                                    sectionFooter(section)
                                }
                                .padding(.top, 8)
                                .padding(.leading, 4)
                            } label: {
                                Text(section.rawValue).font(.headline)
                            }
                        }
                    }
                }
                .padding(14)
            }
            Divider()
            LoginItemFooter(loginItem: loginItem)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ section: ControlSection) -> some View {
        if section == .framing && model.isAnker {
            FOVPicker(model: model)
        }
    }

    @ViewBuilder
    private func sectionFooter(_ section: ControlSection) -> some View {
        switch section {
        case .framing:
            if model.available["pan"] != nil {
                HStack {
                    Text("Pan and tilt move the crop when zoomed in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Center") {
                        model.set("pan", 0)
                        model.set("tilt", 0)
                    }
                    .controlSize(.small)
                    .disabled(model.values["pan"] == 0 && model.values["tilt"] == 0)
                }
            }
        case .anker:
            Text("The camera only accepts these while it's streaming, so they're re-sent whenever an app starts using it. HDR can't be read back, so its switch shows the last value set here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }

    private func expanded(_ section: ControlSection) -> Binding<Bool> {
        Binding(
            get: { !collapsed.split(separator: ",").contains(Substring(section.rawValue)) },
            set: { isExpanded in
                var set = Set(collapsed.split(separator: ",").map(String.init))
                if isExpanded { set.remove(section.rawValue) } else { set.insert(section.rawValue) }
                collapsed = set.sorted().joined(separator: ",")
            }
        )
    }
}

private struct FOVPicker: View {
    @ObservedObject var model: CameraModel

    var body: some View {
        HStack {
            Text("Field of view")
            Spacer()
            Picker("Field of view", selection: Binding<Int?>(
                get: { model.currentFOV },
                set: { if let degrees = $0 { model.setFOV(degrees) } }
            )) {
                ForEach(C200.fovPresets, id: \.degrees) { preset in
                    Text("\(preset.degrees)°").tag(Optional(preset.degrees))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Wide 95°, medium 78°, narrow 65°. These are zoom presets.")
        }
    }
}

private struct ControlRow: View {
    let spec: ControlSpec
    @ObservedObject var model: CameraModel

    var body: some View {
        if let range = model.available[spec.id] {
            let value = model.values[spec.id] ?? range.def
            switch spec.kind {
            case .slider:
                slider(range: range, value: value)
            case .toggle(let on, let off):
                HStack {
                    Text(spec.name)
                    Spacer()
                    Toggle(spec.name, isOn: Binding(
                        get: { value != off },
                        set: { model.set(spec.id, $0 ? on : off) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .accessibilityLabel(spec.name)
                }
            case .choice(let options):
                HStack {
                    Text(spec.name)
                    Spacer()
                    Picker(spec.name, selection: Binding(
                        get: { value },
                        set: { model.set(spec.id, $0) }
                    )) {
                        ForEach(options, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    private func slider(range: ControlRange, value: Int) -> some View {
        let automatic = model.isAutomatic(spec.id)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(spec.name)
                Spacer()
                Text(automatic ? "Auto · \(spec.format(value))" : spec.format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button {
                    model.resetToDefault(spec.id)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .accessibilityLabel("Reset \(spec.name.lowercased())")
                }
                .buttonStyle(.borderless)
                .help("Reset to default (\(spec.format(range.def)))")
                .opacity(value == range.def || automatic ? 0 : 1)
                .disabled(value == range.def || automatic)
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { raw in
                        let steps = ((raw - Double(range.min)) / Double(range.step)).rounded()
                        model.set(spec.id, range.min + Int(steps) * range.step)
                    }
                ),
                in: Double(range.min)...Double(range.max)
            )
            .controlSize(.small)
            .accessibilityLabel(spec.name)
            .accessibilityValue(spec.format(value))
            .disabled(automatic)
        }
    }
}

private struct LoginItemFooter: View {
    @ObservedObject var loginItem: LoginItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Launch at login", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }
            ))
            .toggleStyle(.checkbox)
            .help("Starts in the background at login and keeps your settings applied when the camera reconnects.")
            if loginItem.needsApproval {
                Button("Allow in System Settings…") { loginItem.openSystemSettings() }
                    .controlSize(.small)
            }
            if let error = loginItem.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
