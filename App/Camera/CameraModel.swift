import SwiftUI
import AVFoundation
import CoreMotion
import LucentCore

@MainActor
final class CameraModel: ObservableObject {
    @Published var state = CameraState()
    @Published var controls = CameraControls()
    @Published var recipe = DevelopmentSettings()
    @Published var format: CaptureFormat = .processed
    @Published var retainNegative = true
    @Published var flashMode: FlashMode = .off
    @Published var highResolution = false
    @Published var heic = false
    @Published var saveToPhotos = false
    @Published var grid: GridStyle = .thirds
    @Published var goldenCorner: GoldenCorner = .topLeft
    @Published var levelMode: LevelMode = .auto
    @Published var processingPriority = 3
    @Published var prioritizeResponsiveness = false
    @Published var lossyProRAW = false
    @Published var rawOnly = false
    @Published var theme: CameraTheme = .standard
    @Published var locationMode: LocationMode = .off
    let location = CaptureLocationService()
    @Published var showHistogram = true
    @Published var showZebras = false
    @Published var showPeaking = false
    @Published var showLoupe = false
    @Published var preview: UIImage?
    @Published var analysis: FrameAnalysis?
    @Published var records: [CaptureRecord] = []
    @Published var busy = false
    @Published var countdown = 0
    @Published var timerSeconds = 0
    @Published var message: String?
    @Published var permissionDenied = false
    @Published var interruption: String?
    @Published var levelDegrees: Double = 0
    @Published var isDemo = false
    @Published var focusPoint = CGPoint(x: 0.5, y: 0.5)
    let service = CameraService()
    private let motion = CMMotionManager()
    private let workQueue = DispatchQueue(label: "org.lucentcamera.demo", qos: .userInitiated)
    private var timerTask: Task<Void, Never>?
    private var demoOriginal: Data?
    private var active = false
    private var hasChosenInitialFormat = false
    private var hasSavedFormat = false
    private var demoGeneration = 0

    init() {
        #if targetEnvironment(simulator)
        isDemo = true
        #endif
        if ProcessInfo.processInfo.arguments.contains("--demo") { isDemo = true }
        service.onEvent = { [weak self] event in self?.receive(event) }
        restorePreferences()
        reloadLibrary()
    }

    func start() {
        guard !active else { return }; active = true
        UIApplication.shared.isIdleTimerDisabled = true
        location.update(mode: isDemo ? .off : locationMode)
        if isDemo {
            state.running = true
            state.lenses = [LensInfo(id: "demo", title: "Test scene", front: false)]
            state.selectedLens = "demo"
            state.manualFocus = true; state.whiteBalance = true
            format = .processed
            if demoOriginal == nil { demoOriginal = DemoScene.data() }
            updateDemo()
        } else {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: service.start()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    Task { @MainActor in
                        guard let self, self.active else { return }
                        if granted { self.service.start() }
                        else { self.permissionDenied = true }
                    }
                }
            default: permissionDenied = true
            }
        }
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.1
            motion.startDeviceMotionUpdates(to: .main) { [weak self] sample, _ in
                guard let g = sample?.gravity else { return }
                Task { @MainActor in
                    let orientation = UIDevice.current.orientation
                    let angle = orientation.isLandscape ? atan2(g.y, -g.x) : atan2(g.x, -g.y)
                    // Normalize to the nearest horizontal/vertical axis.
                    self?.levelDegrees = (angle * 180 / .pi).truncatingRemainder(dividingBy: 90)
                    if let degrees = self?.levelDegrees, degrees > 45 { self?.levelDegrees = degrees - 90 }
                    if let degrees = self?.levelDegrees, degrees < -45 { self?.levelDegrees = degrees + 90 }
                }
            }
        }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    }
    func stop() {
        active = false; timerTask?.cancel(); timerTask = nil; countdown = 0
        UIApplication.shared.isIdleTimerDisabled = false
        service.stop(); motion.stopDeviceMotionUpdates()
        location.stop()
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
    func changed() {
        persistPreferences()
        if active { location.update(mode: isDemo ? .off : locationMode) }
        var previewRecipe = recipe; previewRecipe.sensorCrop = controls.zoom
        service.update(controls: controls, recipe: previewRecipe)
        updateAnalysis()
        if isDemo { updateDemo() }
    }
    func updateAnalysis() {
        persistPreferences()
        service.updateAnalysis(enabled: showHistogram || showPeaking || showZebras, loupe: showLoupe)
    }
    private func updateDemo() {
        guard let original = demoOriginal else { return }
        demoGeneration += 1; let generation = demoGeneration
        var settings = recipe; settings.exposure = controls.bias; settings.sensorCrop = controls.zoom
        settings.useCustomWhiteBalance = controls.customWhiteBalance
        settings.temperature = controls.temperature; settings.tint = controls.tint
        workQueue.async {
            do {
                let pipeline = ImagePipeline.shared
                let image = try pipeline.decode(original, isRAW: false, settings: settings, preview: true)
                let ui = try pipeline.uiImage(image)
                let small = pipeline.resized(image, longEdge: 192)
                let w = Int(small.extent.width), h = Int(small.extent.height)
                var bytes = [UInt8](repeating: 0, count: w * h * 4)
                bytes.withUnsafeMutableBytes { ptr in
                    pipeline.context.render(small, toBitmap: ptr.baseAddress!, rowBytes: w * 4, bounds: small.extent,
                                            format: .BGRA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
                }
                let analysis = FrameAnalysis.analyzeBGRA(bytes, width: w, height: h, rowBytes: w * 4)
                DispatchQueue.main.async {
                    guard generation == self.demoGeneration else { return }
                    self.preview = ui; self.analysis = analysis
                }
            } catch { DispatchQueue.main.async { self.message = error.localizedDescription } }
        }
    }

    private func receive(_ event: CameraEvent) {
        switch event {
        case .state(let state):
            self.state = state
            if state.running { interruption = nil }
            if !hasChosenInitialFormat && state.running {
                hasChosenInitialFormat = true
                if !hasSavedFormat && state.capabilities.sensorRAW { format = .sensorRAW }
                controls.iso = state.iso; controls.shutter = state.shutter; controls.aperture = state.aperture
                changed()
            }
            if format == .sensorRAW && !state.capabilities.sensorRAW || format == .proRAW && !state.capabilities.proRAW {
                format = .processed
            }
            if !state.capabilities.flash { flashMode = .off }
        case .analysis(let analysis, let loupe): self.analysis = analysis; preview = loupe
        case .captured(let record): finishCapture(record)
        case .failed(let detail): busy = false; message = detail; reloadLibrary()
        case .interrupted(let detail): state.running = false; interruption = detail
        }
    }
    func focus(at normalized: CGPoint) {
        focusPoint = normalized
        if !isDemo {
            let zoom = max(1, controls.zoom)
            service.focusFromPreview(at: CGPoint(x: (normalized.x - 0.5) / zoom + 0.5, y: (normalized.y - 0.5) / zoom + 0.5))
        }
    }
    func shutter() {
        guard !busy, countdown == 0, state.running else { return }
        timerTask = Task {
            for remaining in stride(from: timerSeconds, to: 0, by: -1) {
                countdown = remaining
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { countdown = 0; return }
            }
            countdown = 0
            guard !Task.isCancelled else { return }
            captureNow()
        }
    }
    func cancelTimer() { timerTask?.cancel(); countdown = 0 }
    private func captureNow() {
        busy = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        var captureRecipe = recipe; captureRecipe.sensorCrop = controls.zoom
        if format != .processed {
            captureRecipe.useCustomWhiteBalance = controls.customWhiteBalance
            captureRecipe.temperature = controls.temperature; captureRecipe.tint = controls.tint
        }
        if isDemo, let original = demoOriginal {
            captureRecipe.exposure = controls.bias
            let settings = captureRecipe; let heic = heic
            workQueue.async {
                do {
                    let record = try CaptureStore.shared.create(original: original, isRAW: false, origin: "generated-demo", recipe: settings, heic: heic)
                    DispatchQueue.main.async { self.finishCapture(record) }
                } catch { DispatchQueue.main.async { self.busy = false; self.message = error.localizedDescription } }
            }
        } else {
            service.capture(CaptureRequest(format: format, retainNegative: retainNegative, flashMode: flashMode,
                                           highResolution: highResolution, heic: heic, recipe: captureRecipe,
                                           processingPriority: processingPriority, prioritizeResponsiveness: prioritizeResponsiveness,
                                           lossyProRAW: lossyProRAW, location: location.current))
        }
    }
    private func finishCapture(_ record: CaptureRecord) {
        reloadLibrary()
        if saveToPhotos && !isDemo {
            CaptureStore.shared.saveToPhotos(record, includeRAW: retainNegative, rawOnly: rawOnly) { result in
                DispatchQueue.main.async {
                    self.busy = false
                    if case .failure(let error) = result { self.message = error.localizedDescription }
                }
            }
        } else { busy = false }
    }
    func reloadLibrary() { records = CaptureStore.shared.list() }
    func resetControls() { controls = CameraControls(); changed() }

    private struct Preferences: Codable {
        var recipe: DevelopmentSettings
        var grid: GridStyle
        var retainNegative: Bool
        var heic: Bool
        var saveToPhotos: Bool
        var flashMode: FlashMode?
        var showHistogram: Bool?
        var showZebras: Bool?
        var showPeaking: Bool?
        var showLoupe: Bool?
        var goldenCorner: GoldenCorner?
        var levelMode: LevelMode?
        var highResolution: Bool?
        var processingPriority: Int?
        var prioritizeResponsiveness: Bool?
        var lossyProRAW: Bool?
        var rawOnly: Bool?
        var timerSeconds: Int?
        var theme: CameraTheme?
        var locationMode: LocationMode?
        var format: CaptureFormat?
    }
    private func persistPreferences() {
        let settings = Preferences(recipe: recipe, grid: grid, retainNegative: retainNegative, heic: heic, saveToPhotos: saveToPhotos,
                                   flashMode: flashMode, showHistogram: showHistogram, showZebras: showZebras, showPeaking: showPeaking, showLoupe: showLoupe,
                                   goldenCorner: goldenCorner, levelMode: levelMode, highResolution: highResolution,
                                   processingPriority: processingPriority, prioritizeResponsiveness: prioritizeResponsiveness,
                                   lossyProRAW: lossyProRAW, rawOnly: rawOnly, timerSeconds: timerSeconds,
                                   theme: theme, locationMode: locationMode, format: format)
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "Lucent.preferences.v1") }
    }
    private func restorePreferences() {
        guard let data = UserDefaults.standard.data(forKey: "Lucent.preferences.v1"),
              let settings = try? JSONDecoder().decode(Preferences.self, from: data) else { return }
        recipe = settings.recipe; grid = settings.grid; retainNegative = settings.retainNegative
        heic = settings.heic; saveToPhotos = settings.saveToPhotos
        flashMode = settings.flashMode ?? .off; showHistogram = settings.showHistogram ?? true
        showZebras = settings.showZebras ?? false; showPeaking = settings.showPeaking ?? false; showLoupe = settings.showLoupe ?? false
        goldenCorner = settings.goldenCorner ?? .topLeft; levelMode = settings.levelMode ?? .auto
        highResolution = settings.highResolution ?? false; processingPriority = settings.processingPriority ?? 3
        prioritizeResponsiveness = settings.prioritizeResponsiveness ?? false; lossyProRAW = settings.lossyProRAW ?? false
        rawOnly = settings.rawOnly ?? false; timerSeconds = settings.timerSeconds ?? 0
        theme = settings.theme ?? .standard; locationMode = settings.locationMode ?? .off
        if let format = settings.format { self.format = format; hasSavedFormat = true }
    }
}
