import CoreMediaIO
import Foundation

/// Watches whether any process is streaming from the C200, via CoreMediaIO's
/// "device is running somewhere" property. (AVCaptureDevice.isInUseByAnotherApplication
/// doesn't report other processes' streams reliably.)
@MainActor
final class CameraActivityMonitor {
    private(set) var isStreaming = false
    var onChange: ((Bool) -> Void)?

    private var device: CMIOObjectID?
    private var deviceListener: CMIOObjectPropertyListenerBlock?
    private var runningListener: CMIOObjectPropertyListenerBlock?

    init() {
        var devicesAddress = Self.address(kCMIOHardwarePropertyDevices)
        let listener: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachToCamera() }
        }
        deviceListener = listener
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &devicesAddress, .main, listener)
        attachToCamera()
    }

    private func attachToCamera() {
        let camera = Self.findCamera()
        if camera != device {
            if let old = device, let listener = runningListener {
                var address = Self.runningAddress
                CMIOObjectRemovePropertyListenerBlock(old, &address, .main, listener)
            }
            device = camera
            runningListener = nil
            if let camera {
                let listener: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.update() }
                }
                runningListener = listener
                var address = Self.runningAddress
                CMIOObjectAddPropertyListenerBlock(camera, &address, .main, listener)
            }
        }
        update()
    }

    private func update() {
        let streaming = device.map(Self.isRunning) ?? false
        guard streaming != isStreaming else { return }
        isStreaming = streaming
        onChange?(streaming)
    }

    // MARK: - CoreMediaIO helpers

    private static var runningAddress: CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
    }

    private static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func isRunning(_ device: CMIOObjectID) -> Bool {
        var address = runningAddress
        var value: UInt32 = 0
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value)
        return status == 0 && value != 0
    }

    private static func findCamera() -> CMIOObjectID? {
        var address = address(kCMIOHardwarePropertyDevices)
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == 0 else { return nil }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == 0 else { return nil }

        let vendor = "VendorID_\(C200.vendorID)", product = "ProductID_\(C200.productID)"
        return devices.first { device in
            var modelAddress = Self.address(kCMIODevicePropertyModelUID)
            var model: Unmanaged<CFString>?
            var used: UInt32 = 0
            guard CMIOObjectGetPropertyData(device, &modelAddress, 0, nil,
                                            UInt32(MemoryLayout<Unmanaged<CFString>?>.size), &used, &model) == 0,
                  let uid = model?.takeRetainedValue() as String?
            else { return false }
            return uid.contains(vendor) && uid.contains(product)
        }
    }
}
