@preconcurrency import AVFoundation
import SwiftUI

/// Runs an AVCaptureSession on the C200 while the window is visible.
@MainActor
final class PreviewController: ObservableObject {
    enum State: Equatable {
        case idle, waitingForPermission, running, noCamera, denied
    }

    @Published private(set) var state: State = .idle
    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "C200Controller.preview")
    private var wantsRunning = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.wantsRunning else { return }
                    self.configureAndRun()
                }
            })
        }
    }

    func start() {
        wantsRunning = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            state = .waitingForPermission
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self, self.wantsRunning else { return }
                    if granted { self.configureAndRun() } else { self.state = .denied }
                }
            }
        default:
            state = .denied
        }
    }

    func stop() {
        wantsRunning = false
        let session = session
        queue.async { session.stopRunning() }
        state = .idle
    }

    private static func findCamera() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external], mediaType: .video, position: .unspecified)
        let vendor = "VendorID_\(C200.vendorID)", product = "ProductID_\(C200.productID)"
        return discovery.devices.first { $0.modelID.contains(vendor) && $0.modelID.contains(product) }
    }

    private func configureAndRun() {
        guard let camera = Self.findCamera() else {
            stopSession()
            state = .noCamera
            return
        }
        let session = session
        queue.async {
            session.beginConfiguration()
            for input in session.inputs {
                session.removeInput(input)
            }
            if let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) {
                session.addInput(input)
            }
            if session.canSetSessionPreset(.hd1920x1080) {
                session.sessionPreset = .hd1920x1080
            }
            session.commitConfiguration()
            if !session.isRunning {
                session.startRunning()
            }
        }
        state = .running
    }

    private func stopSession() {
        let session = session
        queue.async {
            session.stopRunning()
            for input in session.inputs {
                session.removeInput(input)
            }
        }
    }
}

struct PreviewLayerView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
