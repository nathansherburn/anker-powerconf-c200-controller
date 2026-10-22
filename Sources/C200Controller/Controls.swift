import Foundation

enum C200 {
    static let vendorID: UInt16 = 0x291A
    static let productID: UInt16 = 0x3369

    /// GUID of the vendor extension unit that carries FOV, mirror and HDR.
    static let extensionGUID: [UInt8] = [
        0xA2, 0x9E, 0x76, 0x41, 0xDE, 0x04, 0x47, 0xE3,
        0x8B, 0x2B, 0xF4, 0x34, 0x1A, 0xFF, 0x00, 0x3B,
    ]
    static let extensionPayloadLength = 60
    static let fovSelector: UInt8 = 0x10

    /// While streaming, the C200 reports sharpness below 50 on a stretched, wrapping
    /// scale (written 42 reads back as 36, written 0 as 217). Undo that, to within ±1.
    static func unstretchSharpness(_ raw: Int) -> Int {
        let reported = raw > 127 ? raw - 256 : raw
        guard reported < 50 else { return reported }
        return Int((50 + Double(reported - 50) / 1.78).rounded())
    }

    /// FOV presets, widest first. The camera implements each as a zoom level.
    static let fovPresets: [(degrees: Int, zoom: Int, label: String)] = [
        (95, 100, "Wide"),
        (78, 175, "Medium"),
        (65, 295, "Narrow"),
    ]
}

enum ControlSection: String, CaseIterable, Identifiable {
    case framing = "Framing"
    case image = "Image"
    case exposure = "Exposure & Color"
    case focus = "Focus"
    case anker = "Anker"

    var id: String { rawValue }
}

enum ControlUnit {
    case camera, processing, ankerExtension
}

enum ControlKind {
    case slider
    case toggle(on: Int, off: Int)
    case choice([(value: Int, label: String)])
}

struct ControlRange: Equatable {
    var min: Int
    var max: Int
    var step: Int
    var def: Int
}

struct ControlSpec: Identifiable {
    let id: String
    let name: String
    let section: ControlSection
    let unit: ControlUnit
    let selector: UInt8
    /// Bit in the unit's bmControls; nil for vendor controls, which aren't advertised that way.
    var bit: Int? = nil
    /// Full payload length, and where this control's value sits inside it.
    var length: Int
    var offset = 0
    var size: Int? = nil
    var signed = false
    var kind: ControlKind = .slider
    /// While this toggle is on, the camera drives this control itself.
    var autoControl: String? = nil
    /// False when the camera can't report the control's state (Anker HDR always reads back as on).
    var readable = true
    var fixedRange: ControlRange? = nil
    /// Maps a GET_CUR reading taken while the camera is streaming back to the written scale.
    var streamingReadback: ((Int) -> Int)? = nil
    /// Advertised by the C200 but has no effect there.
    var inertOnC200 = false
    /// The camera ignores writes unless it's streaming.
    var onlyWhileStreaming = false
    var format: (Int) -> String = { "\($0)" }

    var valueSize: Int { size ?? length }

    var offValue: Int? {
        if case .toggle(_, let off) = kind { return off }
        return nil
    }

    func decode(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= offset + valueSize else { return nil }
        var raw: UInt64 = 0
        for k in 0..<valueSize {
            raw |= UInt64(bytes[offset + k]) << (8 * UInt64(k))
        }
        let bits = UInt64(valueSize * 8)
        if signed, bits < 64, raw & (1 << (bits - 1)) != 0 {
            raw |= ~0 << bits
        }
        return Int(Int64(bitPattern: raw))
    }

    func encode(_ value: Int, into bytes: inout [UInt8]) {
        let raw = UInt64(bitPattern: Int64(value))
        for k in 0..<valueSize {
            bytes[offset + k] = UInt8(truncatingIfNeeded: raw >> (8 * UInt64(k)))
        }
    }
}

enum Catalog {
    /// Every control, in the order they're applied: auto-mode toggles before the
    /// values they gate, zoom before pan/tilt.
    static let all: [ControlSpec] = [
        ControlSpec(id: "autoExposure", name: "Auto exposure", section: .exposure, unit: .camera,
                    selector: 0x02, bit: 1, length: 1, kind: .toggle(on: 8, off: 1)),
        ControlSpec(id: "autoWhiteBalance", name: "Auto white balance", section: .exposure, unit: .processing,
                    selector: 0x0B, bit: 12, length: 1, kind: .toggle(on: 1, off: 0)),
        ControlSpec(id: "autoFocus", name: "Autofocus", section: .focus, unit: .camera,
                    selector: 0x08, bit: 17, length: 1, kind: .toggle(on: 1, off: 0)),
        ControlSpec(id: "powerLine", name: "Anti-flicker", section: .exposure, unit: .processing,
                    selector: 0x05, bit: 10, length: 1,
                    kind: .choice([(0, "Off"), (1, "50 Hz"), (2, "60 Hz")])),

        ControlSpec(id: "zoom", name: "Zoom", section: .framing, unit: .camera,
                    selector: 0x0B, bit: 9, length: 2,
                    format: { String(format: "%.2f×", Double($0) / 100) }),
        ControlSpec(id: "pan", name: "Pan", section: .framing, unit: .camera,
                    selector: 0x0D, bit: 11, length: 8, offset: 0, size: 4, signed: true,
                    format: { String(format: "%+.0f°", Double($0) / 3600) }),
        ControlSpec(id: "tilt", name: "Tilt", section: .framing, unit: .camera,
                    selector: 0x0D, bit: 11, length: 8, offset: 4, size: 4, signed: true,
                    format: { String(format: "%+.0f°", Double($0) / 3600) }),

        ControlSpec(id: "exposure", name: "Exposure time", section: .exposure, unit: .camera,
                    selector: 0x04, bit: 3, length: 4, autoControl: "autoExposure",
                    format: { String(format: "%.1f ms", Double($0) / 10) }),
        ControlSpec(id: "whiteBalance", name: "Temperature", section: .exposure, unit: .processing,
                    selector: 0x0A, bit: 6, length: 2, autoControl: "autoWhiteBalance",
                    format: { "\($0) K" }),
        ControlSpec(id: "focus", name: "Focus", section: .focus, unit: .camera,
                    selector: 0x06, bit: 5, length: 2, autoControl: "autoFocus"),

        ControlSpec(id: "brightness", name: "Brightness", section: .image, unit: .processing,
                    selector: 0x02, bit: 0, length: 2, signed: true),
        ControlSpec(id: "contrast", name: "Contrast", section: .image, unit: .processing,
                    selector: 0x03, bit: 1, length: 2),
        ControlSpec(id: "saturation", name: "Saturation", section: .image, unit: .processing,
                    selector: 0x07, bit: 3, length: 2),
        ControlSpec(id: "sharpness", name: "Sharpness", section: .image, unit: .processing,
                    selector: 0x08, bit: 4, length: 2, streamingReadback: C200.unstretchSharpness),
        ControlSpec(id: "gamma", name: "Gamma", section: .image, unit: .processing,
                    selector: 0x09, bit: 5, length: 2),
        ControlSpec(id: "hue", name: "Hue", section: .image, unit: .processing,
                    selector: 0x06, bit: 2, length: 2, signed: true, inertOnC200: true),
        ControlSpec(id: "backlight", name: "Backlight compensation", section: .image, unit: .processing,
                    selector: 0x01, bit: 8, length: 2),
        ControlSpec(id: "gain", name: "Gain", section: .image, unit: .processing,
                    selector: 0x04, bit: 9, length: 2),

        ControlSpec(id: "hdr", name: "HDR", section: .anker, unit: .ankerExtension,
                    selector: 0x13, length: C200.extensionPayloadLength, size: 1,
                    kind: .toggle(on: 1, off: 0), readable: false,
                    fixedRange: ControlRange(min: 0, max: 1, step: 1, def: 1), onlyWhileStreaming: true),
        ControlSpec(id: "mirror", name: "Mirror image", section: .anker, unit: .ankerExtension,
                    selector: 0x11, length: C200.extensionPayloadLength, size: 1,
                    kind: .toggle(on: 1, off: 0),
                    fixedRange: ControlRange(min: 0, max: 1, step: 1, def: 0), onlyWhileStreaming: true),
    ]

    static let byID: [String: ControlSpec] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Display order within each sidebar section.
    static let layout: [ControlSection: [String]] = [
        .framing: ["zoom", "pan", "tilt"],
        .image: ["brightness", "contrast", "saturation", "sharpness", "gamma", "hue", "backlight", "gain"],
        .exposure: ["autoExposure", "exposure", "autoWhiteBalance", "whiteBalance", "powerLine"],
        .focus: ["autoFocus", "focus"],
        .anker: ["hdr", "mirror"],
    ]
}
