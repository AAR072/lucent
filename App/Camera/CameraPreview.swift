import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let service: CameraService
    let deviceID: String
    var zoom: Double = 1

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.bind(service: service, deviceID: deviceID)
        view.setZoom(zoom)
        return view
    }
    func updateUIView(_ view: CameraPreviewUIView, context: Context) {
        view.bind(service: service, deviceID: deviceID)
        view.setZoom(zoom)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CameraPreviewUIView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}

/// The camera renders directly into this layer, independent of SwiftUI's update rate.
final class CameraPreviewUIView: UIView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    private weak var service: CameraService?
    private var deviceID = ""
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var captureDevice: AVCaptureDevice?
    private var zoom: CGFloat = 1
    private var observations: [NSKeyValueObservation] = []
    private var lastPreviewAngle: CGFloat = 90
    private var lastCaptureAngle: CGFloat = 90
    private var lastDiagnosticBounds = CGRect.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
        clipsToBounds = true
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func bind(service: CameraService, deviceID: String) {
        self.service = service
        if !deviceID.isEmpty, previewLayer.session !== service.session || self.deviceID != deviceID || previewLayer.connection == nil {
            // Attach after the input exists. Reconnect the native layer when switching inputs.
            previewLayer.session = nil
            previewLayer.session = service.session
            previewLayer.connection?.isEnabled = true
        }
        service.attachPreview(previewLayer)
        guard self.deviceID != deviceID else { return }
        self.deviceID = deviceID
        observations.removeAll(); rotation = nil
        captureDevice = nil
        guard let device = AVCaptureDevice(uniqueID: deviceID) else { return }
        captureDevice = device // RotationCoordinator holds a weak device reference.
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotation = coordinator
        observations = [
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] _, _ in self?.applyRotation() },
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] _, _ in self?.applyRotation() }
        ]
        applyRotation()
        if ProcessInfo.processInfo.arguments.contains("--diagnostics") {
            print("LUCENT BIND connection=\(previewLayer.connection != nil) active=\(previewLayer.connection?.isActive == true) previewing=\(previewLayer.isPreviewing) running=\(service.session.isRunning)")
        }
    }
    override func didMoveToWindow() { super.didMoveToWindow(); applyRotation() }
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        previewLayer.frame = CGRect(x: bounds.midX - bounds.width * zoom / 2, y: bounds.midY - bounds.height * zoom / 2,
                                    width: bounds.width * zoom, height: bounds.height * zoom)
        CATransaction.commit()
        applyRotation()
        if ProcessInfo.processInfo.arguments.contains("--diagnostics"), bounds != lastDiagnosticBounds {
            lastDiagnosticBounds = bounds
            print("LUCENT PREVIEW bounds=\(bounds) window=\(window != nil) connection=\(previewLayer.connection != nil) active=\(previewLayer.connection?.isActive == true) running=\(previewLayer.session?.isRunning == true)")
        }
    }
    func setZoom(_ value: Double) {
        let next = CGFloat(min(5, max(1, value)))
        if next != zoom { zoom = next; setNeedsLayout() }
    }

    private func applyRotation() {
        guard window != nil, let rotation, let device = rotation.device else { return }
        // Keep flat/unknown orientations from resetting the display, and avoid subdegree
        // changes reconfiguring the video buffers while the phone is moving.
        if UIDevice.current.orientation.isPortrait || UIDevice.current.orientation.isLandscape {
            lastPreviewAngle = (rotation.videoRotationAngleForHorizonLevelPreview / 90).rounded() * 90
            lastCaptureAngle = (rotation.videoRotationAngleForHorizonLevelCapture / 90).rounded() * 90
        }
        let previewAngle = lastPreviewAngle
        let captureAngle = lastCaptureAngle
        let mirrored = device.position == .front
        if let connection = previewLayer.connection {
            if connection.isVideoRotationAngleSupported(previewAngle), connection.videoRotationAngle != previewAngle {
                connection.videoRotationAngle = previewAngle
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrored
            }
        }
        service?.updateRotation(preview: previewAngle, capture: captureAngle, deviceID: deviceID, mirrored: mirrored)
    }
}
