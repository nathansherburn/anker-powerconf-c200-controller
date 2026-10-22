import Foundation

struct Preset: Codable, Identifiable, Equatable {
    var name: String
    var values: [String: Int]

    var id: String { name }
}

/// Everything persisted between launches, stored as JSON in Application Support.
struct StoredSettings: Codable {
    /// The settings most recently applied to the camera; re-applied on launch and reconnect.
    var last: [String: Int]?
    var presets: [Preset] = []
    var activePreset: String?
}

enum SettingsStore {
    static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("C200 Controller", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    static func load() -> StoredSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(StoredSettings.self, from: data)
        else { return StoredSettings() }
        return settings
    }

    static func save(_ settings: StoredSettings) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("C200 Controller: failed to save settings: \(error)")
        }
    }
}
