import Foundation

/// Owns the connection to the camera, the current control values, and presets.
@MainActor
final class CameraModel: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var isAnker = false
    /// Controls the attached camera supports, with their ranges.
    @Published private(set) var available: [String: ControlRange] = [:]
    @Published private(set) var values: [String: Int] = [:]
    @Published private(set) var presets: [Preset]
    @Published private(set) var activePreset: String?
    @Published private(set) var status: String?

    /// Whether any app (including our preview) is streaming from the camera right now.
    var isCameraStreaming: () -> Bool = { false }

    /// While the window is visible, refresh values the camera is driving automatically.
    var liveRefresh = false {
        didSet { updateRefreshTimer() }
    }

    private var device: UVCDevice?
    private var watcher: USBWatcher?
    private var stored: StoredSettings
    private var saveWork: DispatchWorkItem?
    private var connectGeneration = 0
    private var refreshTimer: Timer?

    init() {
        stored = SettingsStore.load()
        presets = stored.presets
        activePreset = stored.activePreset
    }

    func start() {
        watcher = USBWatcher(vendorID: C200.vendorID, productID: C200.productID) { [weak self] attached in
            MainActor.assumeIsolated {
                if attached {
                    self?.scheduleConnect(after: 1.5)
                } else {
                    self?.disconnect()
                }
            }
        }
        if !connect() {
            status = "Camera not connected"
        }
    }

    // MARK: - Connection

    private func scheduleConnect(after delay: TimeInterval, attempt: Int = 0) {
        connectGeneration += 1
        let generation = connectGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.connectGeneration else { return }
                if self.connect() {
                    // The camera can still be settling after enumeration; apply once more to be sure.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self, self.connected, generation == self.connectGeneration else { return }
                            self.apply(self.savableValues, persist: false)
                        }
                    }
                } else if attempt < 5 {
                    self.scheduleConnect(after: 1, attempt: attempt + 1)
                }
            }
        }
    }

    @discardableResult
    private func connect() -> Bool {
        device = nil
        guard let device = UVCDevice(vendorID: C200.vendorID, productID: C200.productID) else {
            connected = false
            return false
        }
        self.device = device
        isAnker = device.topology.extensions.contains { $0.guid == C200.extensionGUID }
        loadCapabilities()
        guard !available.isEmpty else {
            self.device = nil
            connected = false
            return false
        }
        readCurrentValues()
        connected = true
        status = nil

        if let last = stored.last {
            apply(last, persist: false)
        } else {
            persist()
        }
        return true
    }

    private func disconnect() {
        connectGeneration += 1
        device = nil
        connected = false
        status = "Camera disconnected"
    }

    // MARK: - Reading

    private func unitID(for spec: ControlSpec) -> UInt8? {
        guard let topology = device?.topology else { return nil }
        switch spec.unit {
        case .camera: return topology.camera?.id
        case .processing: return topology.processing?.id
        case .ankerExtension:
            return topology.extensions.first { $0.guid == C200.extensionGUID }?.unit.id
        }
    }

    private func isSupported(_ spec: ControlSpec) -> Bool {
        guard let topology = device?.topology else { return false }
        if spec.inertOnC200 && isAnker { return false }
        guard let bit = spec.bit else { return spec.unit == .ankerExtension && isAnker }
        switch spec.unit {
        case .camera: return topology.camera?.supports(bit: bit) ?? false
        case .processing: return topology.processing?.supports(bit: bit) ?? false
        case .ankerExtension: return isAnker
        }
    }

    private func query(_ request: UVCRequest, _ spec: ControlSpec) -> Int? {
        guard let device, let unit = unitID(for: spec) else { return nil }
        return device.get(request, unit: unit, selector: spec.selector, length: spec.length).flatMap(spec.decode)
    }

    private func loadCapabilities() {
        var ranges: [String: ControlRange] = [:]
        for spec in Catalog.all where isSupported(spec) {
            if let fixed = spec.fixedRange {
                ranges[spec.id] = fixed
                continue
            }
            switch spec.kind {
            case .slider:
                guard let lo = query(.min, spec), let hi = query(.max, spec), hi > lo else { continue }
                let def = query(.def, spec) ?? lo
                let step = max(query(.res, spec) ?? 1, 1)
                ranges[spec.id] = ControlRange(min: lo, max: hi, step: step, def: min(max(def, lo), hi))
            case .toggle(let on, let off):
                guard query(.cur, spec) != nil else { continue }
                let def = query(.def, spec).map { $0 == off ? off : on } ?? on
                ranges[spec.id] = ControlRange(min: off, max: on, step: 1, def: def)
            case .choice(let options):
                guard query(.cur, spec) != nil, let first = options.first, let last = options.last else { continue }
                ranges[spec.id] = ControlRange(min: first.value, max: last.value, step: 1,
                                               def: query(.def, spec) ?? first.value)
            }
        }
        available = ranges
    }

    private func normalized(_ spec: ControlSpec, _ value: Int) -> Int {
        switch spec.kind {
        case .toggle(let on, let off):
            return value == off ? off : on
        case .slider:
            guard let range = available[spec.id] else { return value }
            return min(max(value, range.min), range.max)
        case .choice:
            return value
        }
    }

    private func readCurrentValues() {
        var current = values
        let streaming = isAnker && isCameraStreaming()
        for spec in Catalog.all {
            guard let range = available[spec.id] else { continue }
            if spec.readable, var value = query(.cur, spec) {
                if streaming, let fix = spec.streamingReadback {
                    value = fix(value)
                }
                current[spec.id] = normalized(spec, value)
            } else if current[spec.id] == nil {
                current[spec.id] = range.def
            }
        }
        values = current
    }

    private func refresh(_ ids: [String]) {
        for id in ids {
            guard let spec = Catalog.byID[id], available[id] != nil, spec.readable,
                  let raw = query(.cur, spec)
            else { continue }
            let value = normalized(spec, raw)
            if values[id] != value {
                values[id] = value
            }
        }
    }

    /// True while the camera is driving this control itself (e.g. exposure under auto exposure).
    func isAutomatic(_ id: String) -> Bool {
        guard let spec = Catalog.byID[id], let auto = spec.autoControl,
              let autoSpec = Catalog.byID[auto], let mode = values[auto]
        else { return false }
        return mode != autoSpec.offValue
    }

    private func updateRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard liveRefresh else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.connected else { return }
                self.refresh(Catalog.all.map(\.id).filter(self.isAutomatic))
            }
        }
    }

    // MARK: - Writing

    @discardableResult
    private func write(_ spec: ControlSpec, _ value: Int) -> Bool {
        guard let device, let unit = unitID(for: spec) else { return false }
        var payload = [UInt8](repeating: 0, count: spec.length)
        // Controls that share a payload (pan and tilt) are written together.
        for other in Catalog.all where other.unit == spec.unit && other.selector == spec.selector {
            other.encode(other.id == spec.id ? value : values[other.id] ?? 0, into: &payload)
        }
        return device.set(unit: unit, selector: spec.selector, data: payload)
    }

    func set(_ id: String, _ value: Int) {
        guard let spec = Catalog.byID[id], available[id] != nil else { return }
        let value = normalized(spec, value)
        guard values[id] != value else { return }
        values[id] = value
        guard write(spec, value) else {
            status = "Couldn't set \(spec.name.lowercased())"
            return
        }
        status = nil

        // Leaving an auto mode: pin dependent controls where the camera had them.
        if value == spec.offValue {
            for dependent in Catalog.all where dependent.autoControl == id {
                if let current = query(.cur, dependent) {
                    values[dependent.id] = normalized(dependent, current)
                    write(dependent, values[dependent.id]!)
                }
            }
        }
        persistSoon()
    }

    func resetToDefault(_ id: String) {
        if let def = available[id]?.def {
            set(id, def)
        }
    }

    /// Selects one of the camera's FOV presets. The camera implements these as zoom
    /// levels, so the zoom value is read back afterwards and is what gets persisted.
    func setFOV(_ degrees: Int) {
        guard let device, isAnker,
              let unit = topologyExtensionUnit(), let _ = available["zoom"]
        else { return }
        var payload = [UInt8](repeating: 0, count: C200.extensionPayloadLength)
        payload[1] = 0x01
        payload[2] = UInt8(truncatingIfNeeded: degrees)
        payload[3] = UInt8(truncatingIfNeeded: degrees >> 8)
        guard device.set(unit: unit, selector: C200.fovSelector, data: payload) else {
            status = "Couldn't set field of view"
            return
        }
        status = nil
        refresh(["zoom", "pan", "tilt"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated {
                self?.refresh(["zoom", "pan", "tilt"])
                self?.persistSoon()
            }
        }
    }

    var currentFOV: Int? {
        guard let zoom = values["zoom"] else { return nil }
        return C200.fovPresets.first { $0.zoom == zoom }?.degrees
    }

    private func topologyExtensionUnit() -> UInt8? {
        device?.topology.extensions.first { $0.guid == C200.extensionGUID }?.unit.id
    }

    /// Writes a full set of values, auto-mode toggles first, skipping anything an auto
    /// mode is in charge of.
    func apply(_ settings: [String: Int], persist shouldPersist: Bool = true) {
        guard connected else { return }
        var merged = values
        for (id, value) in settings {
            guard let spec = Catalog.byID[id], available[id] != nil else { continue }
            merged[id] = normalized(spec, value)
        }
        values = merged

        var failures = 0
        for spec in Catalog.all where available[spec.id] != nil && settings[spec.id] != nil {
            if isAutomatic(spec.id) { continue }
            if !write(spec, merged[spec.id]!) { failures += 1 }
        }
        status = failures > 0 ? "Couldn't apply \(failures) setting\(failures == 1 ? "" : "s")" : nil
        if shouldPersist { persist() }
    }

    /// Re-sends the controls the camera only accepts mid-stream, once the stream has had
    /// a moment to start (and again shortly after, in case it was slow).
    func cameraStreamingChanged(_ streaming: Bool) {
        guard streaming else { return }
        for delay in [0.5, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.connected else { return }
                    for spec in Catalog.all where spec.onlyWhileStreaming {
                        if self.available[spec.id] != nil, let value = self.values[spec.id] {
                            self.write(spec, value)
                        }
                    }
                }
            }
        }
    }

    func reapply() {
        apply(savableValues, persist: false)
    }

    func resetAllToDefaults() {
        activePreset = nil
        apply(available.mapValues(\.def))
    }

    // MARK: - Presets

    /// Values worth saving: supported controls that aren't currently under auto control.
    var savableValues: [String: Int] {
        values.filter { id, _ in available[id] != nil && !isAutomatic(id) }
    }

    var activePresetIsModified: Bool {
        guard let name = activePreset, let preset = presets.first(where: { $0.name == name }) else { return false }
        return preset.values != savableValues
    }

    func applyPreset(_ preset: Preset) {
        activePreset = preset.name
        apply(preset.values)
    }

    func savePreset(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let preset = Preset(name: name, values: savableValues)
        if let index = presets.firstIndex(where: { $0.name == name }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        activePreset = name
        persist()
    }

    func deletePreset(named name: String) {
        presets.removeAll { $0.name == name }
        if activePreset == name { activePreset = nil }
        persist()
    }

    // MARK: - Persistence

    private func persistSoon() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.persist() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func persist() {
        saveWork?.cancel()
        if connected {
            stored.last = savableValues
        }
        stored.presets = presets
        stored.activePreset = activePreset
        SettingsStore.save(stored)
    }
}
