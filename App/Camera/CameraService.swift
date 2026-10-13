import AVFoundation
import CoreImage
import UIKit
import LucentCore

struct LensInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let front: Bool
    var magnification: Double = 1

    /// Keep physical rear lenses and one canonical selfie camera, without discovery aliases.
    static func selectable(_ discovered: [LensInfo], preferredFrontID: String?) -> [LensInfo] {
        var seen = Set<String>()
        let unique = discovered.filter { seen.insert($0.id).inserted }
        let front = unique.first { $0.front && $0.id == preferredFrontID } ?? unique.first { $0.front }
        return unique.filter { !$0.front } + (front.map { [$0] } ?? [])
    }
}

struct CameraState {
    var lenses: [LensInfo] = []
    var selectedLens = ""
    var capabilities = CaptureCapabilities(sensorRAW: false, proRAW: false, flash: false)
    var isoRange: ClosedRange<Double> = 25...1600
    var shutterRange: ClosedRange<Double> = 0.000125...1
    var apertureRange: ClosedRange<Double> = 1.8...1.8
    var iso: Double = 100
    var shutter: Double = 1 / 125
    var aperture: Double = 1.8
    var meter: Double = 0
    var manualFocus = false
    var whiteBalance = false
    var running = false
    var framesPerSecond: Double = 0
}

struct CameraControls: Equatable {
    var mode: ExposureMode = .automatic
    var iso: Double = 100
    var shutter: Double = 1 / 125
    var aperture: Double = 1.8
    var bias: Double = 0
    var focus: Double = 0.5
    var autofocus = true
    var customWhiteBalance = false
    var temperature: Double = 6500
    var tint: Double = 0
    var zoom: Double = 1
}

struct CaptureRequest {
    var format: CaptureFormat
    var retainNegative: Bool
    var flashMode: FlashMode
    var highResolution: Bool
    var heic: Bool
    var recipe: DevelopmentSettings
    var processingPriority: Int = 3
    var prioritizeResponsiveness = false
    var lossyProRAW = false
    var location: CaptureLocation?
}

enum CameraEvent {
    case state(CameraState)
    case analysis(FrameAnalysis?, loupe: UIImage?)
    case captured(CaptureRecord)
    case failed(String)
    case interrupted(String)
}

/// Live display belongs to AVCaptureVideoPreviewLayer; this delegate only samples analysis.
final class CameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "org.lucentcamera.session")
    private let frameQueue = DispatchQueue(label: "org.lucentcamera.preview", qos: .userInitiated)
    private let developmentQueue = DispatchQueue(label: "org.lucentcamera.development", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private var input: AVCaptureDeviceInput?
    private var devices: [AVCaptureDevice] = []
    private var state = CameraState()
    private var controls = CameraControls()
    private var processors: [Int64: PhotoProcessor] = [:]
    private var lastFrameTime: Double = 0
    private var lastPriorityTime: Double = 0
    private var cadenceStart: Double = 0
    private var cadenceFrames = 0
    private let recipeLock = NSLock()
    private var previewRecipe = DevelopmentSettings()
    private var wantsAnalysis = true
    private var wantsLoupe = false
    @MainActor private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var observers: [NSObjectProtocol] = []
    var onEvent: ((CameraEvent) -> Void)?

    override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
            self?.emit(.interrupted("Camera is in use or temporarily unavailable."))
        })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in self?.start() })
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError
            if error?.code == .mediaServicesWereReset { self?.start() }
            else { self?.emit(.failed(error?.localizedDescription ?? "The camera session failed.")) }
        })
    }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    private func emit(_ event: CameraEvent) { DispatchQueue.main.async { [weak self] in self?.onEvent?(event) } }

    func start() {
        sessionQueue.async {
            do {
                if self.device == nil { try self.configure() }
                if !self.session.isRunning { self.session.startRunning() }
                self.state.running = self.session.isRunning
                self.emit(.state(self.state))
            } catch { self.emit(.failed(error.localizedDescription)) }
        }
    }
    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
            self.state.running = false; self.emit(.state(self.state))
        }
    }

    private func configure() throws {
        devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera], mediaType: .video, position: .unspecified).devices
        devices.sort {
            if $0.position != $1.position { return $0.position == .back }
            return lensRank($0) < lensRank($1)
        }
        let preferredFront = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        let virtual = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
        state.lenses = LensInfo.selectable(devices.map { d in
            LensInfo(id: d.uniqueID, title: d.position == .front ? "Front" : lensTitle(d), front: d.position == .front,
                     magnification: relativeMagnification(d, virtual: virtual))
        }, preferredFrontID: preferredFront?.uniqueID)
        let selectedIDs = Set(state.lenses.map(\.id))
        devices.removeAll { !selectedIDs.contains($0.uniqueID) }
        guard let initial = devices.first(where: { $0.position == .back && $0.deviceType == .builtInWideAngleCamera }) ?? devices.first else {
            throw NSError(domain: "Lucent", code: 2, userInfo: [NSLocalizedDescriptionKey: "No camera is available on this device."])
        }
        session.beginConfiguration()
        defer { session.commitConfiguration(); refreshCapabilities() }
        session.sessionPreset = .photo
        let newInput = try AVCaptureDeviceInput(device: initial)
        guard session.canAddInput(newInput), session.canAddOutput(photoOutput), session.canAddOutput(videoOutput) else { throw ImagingError.renderFailed }
        session.addInput(newInput); input = newInput; device = initial
        session.addOutput(photoOutput)
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.automaticallyConfiguresOutputBufferDimensions = true
        videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
        session.addOutput(videoOutput)
        configureDevice(initial)
    }
    private func lensRank(_ d: AVCaptureDevice) -> Int {
        if d.deviceType == .builtInUltraWideCamera { return 0 }
        if d.deviceType == .builtInWideAngleCamera { return 1 }
        return 2
    }
    private func lensTitle(_ d: AVCaptureDevice) -> String {
        switch d.deviceType {
        case .builtInUltraWideCamera: return "Ultra"
        case .builtInTelephotoCamera: return "Tele"
        default: return "Wide"
        }
    }
    private func relativeMagnification(_ device: AVCaptureDevice, virtual: AVCaptureDevice?) -> Double {
        guard let virtual, let index = virtual.constituentDevices.firstIndex(where: { $0.uniqueID == device.uniqueID }),
              let wide = virtual.constituentDevices.firstIndex(where: { $0.deviceType == .builtInWideAngleCamera }) else {
            return device.deviceType == .builtInUltraWideCamera ? 0.5 : 1
        }
        let factors = [1.0] + virtual.virtualDeviceSwitchOverVideoZoomFactors.map(\.doubleValue)
        guard index < factors.count, wide < factors.count else { return 1 }
        return factors[index] / factors[wide]
    }
    private func configureDevice(_ d: AVCaptureDevice) {
        state.selectedLens = d.uniqueID
        if photoOutput.isAppleProRAWSupported { photoOutput.isAppleProRAWEnabled = false }
        state.capabilities = CaptureCapabilities(
            sensorRAW: photoOutput.availableRawPhotoPixelFormatTypes.contains(where: AVCapturePhotoOutput.isBayerRAWPixelFormat),
            proRAW: photoOutput.isAppleProRAWSupported,
            flash: d.hasFlash)
        let f = d.activeFormat
        state.isoRange = Double(f.minISO)...Double(max(f.minISO, f.maxISO))
        state.shutterRange = max(0.000001, f.minExposureDuration.seconds)...max(f.minExposureDuration.seconds, f.maxExposureDuration.seconds)
        state.apertureRange = Double(d.lensAperture)...Double(d.lensAperture)
        if #available(iOS 27, *) {
            state.apertureRange = Double(f.minLensAperture)...Double(max(f.minLensAperture, f.maxLensAperture))
        }
        state.manualFocus = d.isLockingFocusWithCustomLensPositionSupported
        state.whiteBalance = d.isWhiteBalanceModeSupported(.locked)
        if let max = f.supportedMaxPhotoDimensions.max(by: { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) }) {
            photoOutput.maxPhotoDimensions = max
        }
        photoOutput.maxPhotoQualityPrioritization = .quality
        // Give auto exposure a responsive cadence; long custom exposures may lower it.
        if f.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) {
            do {
                try d.lockForConfiguration()
                d.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                d.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                d.unlockForConfiguration()
            } catch { emit(.failed(error.localizedDescription)) }
        }
        updateReadout(d)
    }
    private func refreshCapabilities() {
        state.capabilities = CaptureCapabilities(
            sensorRAW: photoOutput.availableRawPhotoPixelFormatTypes.contains(where: AVCapturePhotoOutput.isBayerRAWPixelFormat),
            proRAW: photoOutput.isAppleProRAWSupported,
            flash: device?.hasFlash == true)
    }

    func selectLens(_ id: String) {
        sessionQueue.async {
            guard let next = self.devices.first(where: { $0.uniqueID == id }), next != self.device else { return }
            do {
                let nextInput = try AVCaptureDeviceInput(device: next)
                self.session.beginConfiguration()
                let old = self.input
                if let old { self.session.removeInput(old) }
                if self.session.canAddInput(nextInput) {
                    self.session.addInput(nextInput); self.input = nextInput; self.device = next
                    self.controls.zoom = 1
                    self.configureDevice(next)
                } else if let old { self.session.addInput(old) }
                self.session.commitConfiguration()
                self.refreshCapabilities()
                self.applyControls()
                self.emit(.state(self.state))
            } catch { self.emit(.failed(error.localizedDescription)) }
        }
    }

    func update(controls: CameraControls, recipe: DevelopmentSettings) {
        recipeLock.lock(); previewRecipe = recipe; recipeLock.unlock()
        sessionQueue.async { self.controls = controls; self.applyControls() }
    }
    func updateAnalysis(enabled: Bool, loupe: Bool) {
        recipeLock.lock(); wantsAnalysis = enabled; wantsLoupe = loupe; recipeLock.unlock()
    }
    @MainActor func attachPreview(_ layer: AVCaptureVideoPreviewLayer) { previewLayer = layer }
    @MainActor func focusFromPreview(at normalized: CGPoint) {
        guard let layer = previewLayer else { return }
        let point = CGPoint(x: normalized.x * layer.bounds.width, y: normalized.y * layer.bounds.height)
        focus(at: layer.captureDevicePointConverted(fromLayerPoint: point))
    }
    func updateRotation(preview: CGFloat, capture: CGFloat, deviceID: String, mirrored: Bool) {
        sessionQueue.async {
            guard self.device?.uniqueID == deviceID else { return }
            // Analysis follows display rotation; photographs follow physical capture rotation.
            for (connection, angle) in [(self.videoOutput.connection(with: .video), preview),
                                        (self.photoOutput.connection(with: .video), capture)] {
                guard let connection else { continue }
                if connection.isVideoRotationAngleSupported(angle), connection.videoRotationAngle != angle {
                    connection.videoRotationAngle = angle
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = mirrored
                }
            }
        }
    }

    private func applyControls() {
        guard let d = device else { return }
        do {
            try d.lockForConfiguration(); defer { d.unlockForConfiguration() }
            let limits = ExposureLimits(iso: state.isoRange, duration: state.shutterRange)
            let iso = Float(limits.clampISO(controls.iso))
            let duration = CMTime(seconds: limits.clampDuration(controls.shutter), preferredTimescale: 1_000_000_000)
            switch controls.mode {
            case .automatic:
                if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
            case .manual:
                if d.isExposureModeSupported(.custom) {
                    if #available(iOS 27, *) {
                        let aperture = Float(clamp(controls.aperture, to: state.apertureRange))
                        if d.activeFormat.supportsExposureModeCustom(lensAperture: aperture, duration: duration, iso: iso) {
                            d.setExposureModeCustom(lensAperture: aperture, duration: duration, iso: iso, completionHandler: nil)
                        } else { d.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil) }
                    } else { d.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil) }
                }
            case .shutterPriority, .isoPriority:
                if d.isExposureModeSupported(.custom) {
                    if #available(iOS 27, *) {
                        let requestedDuration = controls.mode == .shutterPriority ? duration : AVCaptureDevice.autoExposureDuration
                        let requestedISO = controls.mode == .isoPriority ? iso : AVCaptureDevice.autoISO
                        if d.activeFormat.supportsExposureModeCustom(lensAperture: AVCaptureDevice.autoLensAperture, duration: requestedDuration, iso: requestedISO) {
                            d.setExposureModeCustom(lensAperture: AVCaptureDevice.autoLensAperture, duration: requestedDuration, iso: requestedISO, completionHandler: nil)
                            break
                        }
                    }
                    // Older OS priority loop starts from the current metered value.
                    d.setExposureModeCustom(duration: controls.mode == .shutterPriority ? duration : d.exposureDuration,
                                            iso: controls.mode == .isoPriority ? iso : d.iso, completionHandler: nil)
                }
            case .aperturePriority:
                if #available(iOS 27, *) {
                    let aperture = Float(clamp(controls.aperture, to: state.apertureRange))
                    if d.activeFormat.supportsExposureModeCustom(lensAperture: aperture, duration: AVCaptureDevice.autoExposureDuration, iso: AVCaptureDevice.autoISO) {
                        d.setExposureModeCustom(lensAperture: aperture, duration: AVCaptureDevice.autoExposureDuration, iso: AVCaptureDevice.autoISO, completionHandler: nil)
                    }
                }
            }
            d.setExposureTargetBias(Float(clamp(controls.bias, to: Double(d.minExposureTargetBias)...Double(d.maxExposureTargetBias))), completionHandler: nil)
            if controls.autofocus {
                if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
            } else if d.isLockingFocusWithCustomLensPositionSupported {
                d.setFocusModeLocked(lensPosition: Float(clamp(controls.focus, to: 0...1)), completionHandler: nil)
            }
            if controls.customWhiteBalance && state.whiteBalance {
                let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: Float(controls.temperature), tint: Float(controls.tint))
                var gains = d.deviceWhiteBalanceGains(for: values)
                gains.redGain = min(d.maxWhiteBalanceGain, max(1, gains.redGain))
                gains.greenGain = min(d.maxWhiteBalanceGain, max(1, gains.greenGain))
                gains.blueGain = min(d.maxWhiteBalanceGain, max(1, gains.blueGain))
                d.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            } else if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { d.whiteBalanceMode = .continuousAutoWhiteBalance }
            // Digital framing belongs to preview/development; Bayer capture requires sensor zoom 1.
            d.videoZoomFactor = 1
        } catch { emit(.failed(error.localizedDescription)) }
    }

    func focus(at point: CGPoint) {
        sessionQueue.async {
            guard let d = self.device else { return }
            do {
                try d.lockForConfiguration(); defer { d.unlockForConfiguration() }
                if self.controls.autofocus && d.isFocusPointOfInterestSupported {
                    d.focusPointOfInterest = point
                    if d.isFocusModeSupported(.autoFocus) { d.focusMode = .autoFocus }
                }
                if self.controls.mode == .automatic && d.isExposurePointOfInterestSupported {
                    d.exposurePointOfInterest = point
                    d.exposureMode = .continuousAutoExposure
                }
            } catch { self.emit(.failed(error.localizedDescription)) }
        }
    }

    func capture(_ request: CaptureRequest) {
        sessionQueue.async { [self] in
            do {
                guard self.session.isRunning else { throw NSError(domain: "Lucent", code: 3, userInfo: [NSLocalizedDescriptionKey: "Wait for the camera to start."]) }
                let plan = try CapturePlan(format: request.format, retainNegative: request.retainNegative,
                                           flash: request.flashMode != .off, capabilities: self.state.capabilities)
                if self.photoOutput.isAppleProRAWSupported {
                    self.photoOutput.isAppleProRAWEnabled = request.format == .proRAW
                }
                let settings: AVCapturePhotoSettings
                if request.format == .processed {
                    let codec: AVVideoCodecType = request.heic && self.photoOutput.availablePhotoCodecTypes.contains(.hevc) ? .hevc : .jpeg
                    settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec,
                        AVVideoCompressionPropertiesKey: [AVVideoQualityKey: clamp(request.recipe.compressionQuality ?? 0.9, to: 0.1...1)]])
                } else {
                    let formats = self.photoOutput.availableRawPhotoPixelFormatTypes
                    let raw = formats.first { request.format == .sensorRAW ? AVCapturePhotoOutput.isBayerRAWPixelFormat($0) : AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }
                    guard let raw else { throw request.format == .sensorRAW ? CapturePlanError.unsupportedSensorRAW : CapturePlanError.unsupportedProRAW }
                    settings = AVCapturePhotoSettings(rawPixelFormatType: raw)
                }
                if plan.flash {
                    let mode: AVCaptureDevice.FlashMode = request.flashMode == .auto ? .auto : .on
                    guard self.photoOutput.supportedFlashModes.contains(mode) else {
                        throw NSError(domain: "Lucent", code: 5, userInfo: [NSLocalizedDescriptionKey: "Flash Unavailable"])
                    }
                    settings.flashMode = mode
                }
                // Public API contract: speed preserves custom exposure in still capture.
                settings.photoQualityPrioritization = self.controls.mode == .automatic && request.format == .processed
                    ? (request.processingPriority == 0 ? .speed : request.processingPriority == 1 ? .balanced : .quality) : .speed
                if self.photoOutput.isFastCapturePrioritizationSupported {
                    self.photoOutput.isFastCapturePrioritizationEnabled = request.prioritizeResponsiveness
                }
                if let d = self.device {
                    let dimensions = d.activeFormat.supportedMaxPhotoDimensions.sorted { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) }
                    if let choice = request.highResolution && request.format != .sensorRAW ? dimensions.last : (dimensions.first(where: { Int64($0.width) * Int64($0.height) >= 10_000_000 }) ?? dimensions.first) {
                        settings.maxPhotoDimensions = choice
                    }
                }
                let processor = PhotoProcessor(lossyProRAW: request.lossyProRAW, location: request.location) { [weak self] result in
                    guard let self else { return }
                    self.sessionQueue.async { self.processors.removeValue(forKey: settings.uniqueID) }
                    self.developmentQueue.async {
                        do {
                            let bytes = try result.get()
                            let record = try CaptureStore.shared.create(original: bytes, isRAW: request.format != .processed,
                                                                         origin: request.format.rawValue, recipe: request.recipe, heic: request.heic, location: request.location)
                            // The DNG remains in the local store for re-development even if Photos export omits it.
                            self.emit(.captured(record))
                        } catch { self.emit(.failed("\(error.localizedDescription) Check the library for a preserved original.")) }
                    }
                }
                self.processors[settings.uniqueID] = processor
                self.photoOutput.capturePhoto(with: settings, delegate: processor)
            } catch { self.emit(.failed(error.localizedDescription)) }
        }
    }

    private func updateReadout(_ d: AVCaptureDevice) {
        state.iso = Double(d.iso); state.shutter = d.exposureDuration.seconds
        state.aperture = Double(d.lensAperture); state.meter = Double(d.exposureTargetOffset)
    }
    private func priorityTick() {
        guard let d = device else { return }
        updateReadout(d)
        if (controls.mode == .shutterPriority || controls.mode == .isoPriority), abs(state.meter) > 0.12 {
            // iOS 27 uses the native priority API when the active format supports it.
            var native = false
            if #available(iOS 27, *) {
                native = controls.mode == .shutterPriority ? d.automaticallyAdjustsISO : d.automaticallyAdjustsExposureDuration
            }
            if !native {
                do {
                    try d.lockForConfiguration(); defer { d.unlockForConfiguration() }
                    let limits = ExposureLimits(iso: state.isoRange, duration: state.shutterRange)
                    let adjustISO = controls.mode == .shutterPriority
                    let adjustment = limits.priorityAdjustment(current: adjustISO ? state.iso : state.shutter, meterOffset: state.meter, forISO: adjustISO)
                    d.setExposureModeCustom(duration: CMTime(seconds: adjustISO ? state.shutter : adjustment, preferredTimescale: 1_000_000_000),
                                            iso: Float(adjustISO ? adjustment : state.iso), completionHandler: nil)
                } catch { emit(.failed(error.localizedDescription)) }
            }
        }
        emit(.state(state))
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        if cadenceStart == 0 { cadenceStart = now }
        cadenceFrames += 1
        if now - cadenceStart >= 2 {
            let fps = Double(cadenceFrames) / (now - cadenceStart)
            cadenceFrames = 0; cadenceStart = now
            sessionQueue.async { self.state.framesPerSecond = fps }
            if ProcessInfo.processInfo.arguments.contains("--diagnostics"), let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                print("LUCENT STREAM fps=\(fps) buffer=\(CVPixelBufferGetWidth(buffer))x\(CVPixelBufferGetHeight(buffer)) angle=\(connection.videoRotationAngle) active=\(connection.isActive)")
                if CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA {
                    CVPixelBufferLockBaseAddress(buffer, .readOnly)
                    if let base = CVPixelBufferGetBaseAddress(buffer) {
                        let row = CVPixelBufferGetBytesPerRow(buffer), w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
                        let bytes = base.assumingMemoryBound(to: UInt8.self)
                        let center = (h / 2) * row + (w / 2) * 4
                        print("LUCENT PIXEL centerBGRA=\(bytes[center]),\(bytes[center+1]),\(bytes[center+2]),\(bytes[center+3])")
                        var lo: UInt8 = 255, hi: UInt8 = 0
                        for y in stride(from: 0, to: h, by: max(1, h / 16)) {
                            for x in stride(from: 0, to: w, by: max(1, w / 16)) {
                                let offset = y * row + x * 4
                                for c in 0...2 { lo = min(lo, bytes[offset + c]); hi = max(hi, bytes[offset + c]) }
                            }
                        }
                        print("LUCENT PIXEL range=\(lo)...\(hi)")
                    }
                    CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
                }
            }
        }
        if now - lastPriorityTime > 0.4 {
            lastPriorityTime = now; sessionQueue.async { self.priorityTick() }
        }
        guard now - lastFrameTime > 0.2, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrameTime = now
        recipeLock.lock()
        let aspect = previewRecipe.aspect, zoom = previewRecipe.sensorCrop ?? 1, analyze = wantsAnalysis, loupe = wantsLoupe
        recipeLock.unlock()
        guard analyze || loupe else { return }
        let sample = PreviewAnalysis.sample(CIImage(cvPixelBuffer: buffer), aspect: aspect, zoom: zoom, analyze: analyze, loupe: loupe)
        emit(.analysis(sample.analysis, loupe: sample.loupe))
    }
}

private final class PhotoProcessor: NSObject, AVCapturePhotoCaptureDelegate, AVCapturePhotoFileDataRepresentationCustomizer {
    private var data: Data?
    private var error: Error?
    private let completion: (Result<Data, Error>) -> Void
    private let lossyProRAW: Bool
    private let location: CaptureLocation?
    init(lossyProRAW: Bool, location: CaptureLocation?, completion: @escaping (Result<Data, Error>) -> Void) {
        self.lossyProRAW = lossyProRAW; self.location = location; self.completion = completion
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { self.error = error; return }
        data = photo.fileDataRepresentation(with: self)
    }
    func replacementAppleProRAWCompressionSettings(for photo: AVCapturePhoto, defaultSettings: [String: Any], maximumBitDepth: Int) -> [String: Any] {
        guard lossyProRAW else { return defaultSettings }
        var settings = defaultSettings; settings[AVVideoQualityKey] = 0.8
        return settings
    }
    func replacementMetadata(for photo: AVCapturePhoto) -> [String: Any]? {
        var metadata = photo.metadata
        metadata.removeValue(forKey: kCGImagePropertyGPSDictionary as String)
        if let location { metadata.merge(location.imageProperties, uniquingKeysWith: { _, new in new }) }
        return metadata
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error ?? self.error { completion(.failure(error)) }
        else if let data { completion(.success(data)) }
        else { completion(.failure(ImagingError.encodingFailed)) }
    }
}
