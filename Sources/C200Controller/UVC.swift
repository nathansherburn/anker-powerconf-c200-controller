import CUVC
import Foundation

enum UVCRequest: UInt8 {
    case cur = 0x81, min = 0x82, max = 0x83, res = 0x84, len = 0x85, info = 0x86, def = 0x87
}

/// A unit or terminal from the VideoControl descriptors, with its bmControls bitmap.
struct UVCUnit {
    let id: UInt8
    let controls: UInt64

    func supports(bit: Int) -> Bool {
        bit < 64 && controls & (1 << UInt64(bit)) != 0
    }
}

/// The parts of the UVC VideoControl topology we need to address controls.
struct UVCTopology {
    var interface: UInt8 = 0
    var camera: UVCUnit?
    var processing: UVCUnit?
    var extensions: [(unit: UVCUnit, guid: [UInt8])] = []

    init(configDescriptor d: [UInt8]) {
        var i = 0
        var inVideoControl = false
        while i + 2 <= d.count {
            let length = Int(d[i])
            guard length > 0, i + length <= d.count else { break }
            let b = Array(d[i..<i + length])

            if b[1] == 0x04, length >= 9 {
                // Interface descriptor: class 0x0E (video), subclass 0x01 (control).
                inVideoControl = b[5] == 0x0E && b[6] == 0x01
                if inVideoControl { interface = b[2] }
            } else if b[1] == 0x24, inVideoControl, length >= 4 {
                switch b[2] {
                case 0x02 where length >= 15 && (UInt16(b[4]) | UInt16(b[5]) << 8) == 0x0201:
                    // Camera input terminal.
                    camera = UVCUnit(id: b[3], controls: bitmap(b, at: 15, size: Int(b[14])))
                case 0x05 where length >= 8:
                    processing = UVCUnit(id: b[3], controls: bitmap(b, at: 8, size: Int(b[7])))
                case 0x06 where length >= 22:
                    let sizeIndex = 22 + Int(b[21])
                    guard sizeIndex < length else { break }
                    let unit = UVCUnit(id: b[3], controls: bitmap(b, at: sizeIndex + 1, size: Int(b[sizeIndex])))
                    extensions.append((unit, Array(b[4..<20])))
                default:
                    break
                }
            }
            i += length
        }
    }
}

private func bitmap(_ b: [UInt8], at start: Int, size: Int) -> UInt64 {
    var value: UInt64 = 0
    for k in 0..<min(size, 8) where start + k < b.count {
        value |= UInt64(b[start + k]) << (8 * UInt64(k))
    }
    return value
}

/// An open handle to a UVC camera's control pipe.
final class UVCDevice {
    private let handle: OpaquePointer
    let topology: UVCTopology

    init?(vendorID: UInt16, productID: UInt16) {
        guard let handle = cuvc_open(vendorID, productID) else { return nil }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let n = cuvc_config_descriptor(handle, &buffer, Int32(buffer.count))
        guard n > 0 else {
            cuvc_close(handle)
            return nil
        }
        self.handle = handle
        self.topology = UVCTopology(configDescriptor: Array(buffer[0..<Int(n)]))
    }

    deinit { cuvc_close(handle) }

    func get(_ request: UVCRequest, unit: UInt8, selector: UInt8, length: Int) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: length)
        let n = cuvc_get(handle, request.rawValue, unit, selector, topology.interface, &buffer, UInt16(length))
        return n < 0 ? nil : Array(buffer.prefix(Int(n)))
    }

    @discardableResult
    func set(unit: UInt8, selector: UInt8, data: [UInt8]) -> Bool {
        var data = data
        return cuvc_set(handle, unit, selector, topology.interface, &data, UInt16(data.count)) == 0
    }
}

/// Reports attach/detach events for a USB device for the lifetime of the process.
final class USBWatcher {
    private let onChange: (Bool) -> Void

    init(vendorID: UInt16, productID: UInt16, onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        let context = Unmanaged.passRetained(self).toOpaque()
        cuvc_watch(vendorID, productID, { context, attached in
            Unmanaged<USBWatcher>.fromOpaque(context!).takeUnretainedValue().onChange(attached)
        }, context)
    }
}
