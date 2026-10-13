import SwiftUI
import AVKit
import LucentCore

struct CameraView: View {
    @ObservedObject var model: CameraModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var settingsOpen = false
    @State private var libraryOpen = false
    @State private var controlsOpen = false
    @State private var modesOpen = false
    @State private var looksOpen = false
    @State private var focusVisible = false
    @State private var dragStartControls: CameraControls?
    private var accent: Color { model.theme == .standard ? Color(red: 0.96, green: 0.97, blue: 0.24) : .white }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            Group {
                if landscape {
                    HStack(spacing: 0) {
                        viewfinder(landscape: true)
                        VStack(spacing: 4) {
                            header
                            lensPicker
                            compositionToolbar
                            shutterBar
                        }.padding(.horizontal, 12).frame(width: 220)
                    }
                } else {
                    VStack(spacing: 0) {
                        header.padding(.horizontal, 18).frame(height: 64)
                        viewfinder(landscape: false)
                        compositionToolbar
                        lensPicker.padding(.horizontal, 12)
                        shutterBar
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .overlay(alignment: .topTrailing) {
                    if modesOpen {
                        modePalette.padding(.trailing, 18).padding(.top, landscape ? 52 : 64)
                    }
                }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task { model.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.start() } else { model.stop() }
        }
        .onChange(of: model.controls) { _, _ in model.changed() }
        .onChange(of: model.recipe) { _, _ in model.changed() }
        .onChange(of: model.showHistogram) { _, _ in model.updateAnalysis() }
        .onChange(of: model.showPeaking) { _, _ in model.updateAnalysis() }
        .onChange(of: model.showZebras) { _, _ in model.updateAnalysis() }
        .onChange(of: model.showLoupe) { _, _ in model.updateAnalysis() }
        .onChange(of: model.grid) { _, _ in model.changed() }
        .onChange(of: model.goldenCorner) { _, _ in model.changed() }
        .onChange(of: model.levelMode) { _, _ in model.changed() }
        .onChange(of: model.flashMode) { _, _ in model.changed() }
        .onChange(of: model.format) { _, _ in model.changed() }
        .onCameraCaptureEvent(isEnabled: model.state.running && !model.busy && model.countdown == 0 && !settingsOpen && !libraryOpen) { event in
            if event.phase == .ended { model.shutter() }
        }
        .sheet(isPresented: $settingsOpen) { CameraSettingsView(model: model) }
        .fullScreenCover(isPresented: $libraryOpen, onDismiss: { model.reloadLibrary() }) { LibraryView(model: model) }
        .sheet(isPresented: $looksOpen) {
            NavigationStack {
                LookPicker(selection: $model.recipe.look)
                    .navigationTitle("Color recipes")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { looksOpen = false } } }
            }.presentationDetents([.medium, .large])
        }
        .alert("Lucent", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
        .ignoresSafeArea(.container)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(String(format: "%+.1f EV", model.controls.bias))
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                if model.showHistogram {
                    HistogramView(bins: model.analysis?.histogram ?? []).frame(width: 94, height: 35)
                }
            }
            Spacer()
            Button { withAnimation(.easeInOut(duration: 0.18)) { modesOpen.toggle() } } label: {
                Group {
                    if model.theme == .standard {
                        Text(model.controls.mode == .automatic ? "AUTO" : model.controls.mode == .manual ? "MAN" : model.controls.mode == .isoPriority ? "ISO" : "SHTR")
                            .font(.system(size: 15, weight: .medium, design: .monospaced)).tracking(2)
                    } else { Image(systemName: modeSymbol(model.controls.mode)).font(.system(size: 36, weight: .light)) }
                }.frame(width: 60, height: 44).contentShape(Rectangle())
            }.foregroundStyle(modesOpen ? accent : .white)
                .buttonStyle(.plain).padding(.top, 11)
                .accessibilityLabel("Exposure controls").accessibilityIdentifier("exposureControls")

        }.foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 3)
    }

    private var modePalette: some View {
        VStack(spacing: 12) {
            ForEach([ExposureMode.automatic, .manual, .isoPriority, .shutterPriority, .aperturePriority]) { mode in
                if mode != .aperturePriority || model.state.apertureRange.lowerBound != model.state.apertureRange.upperBound {
                    Button {
                        if mode != .automatic {
                            model.controls.iso = model.state.iso; model.controls.shutter = model.state.shutter
                        }
                        model.controls.mode = mode; controlsOpen = mode != .automatic; modesOpen = false
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: modeSymbol(mode)).font(.system(size: 32, weight: .light))
                            Text(mode.title).font(.system(size: 11)).multilineTextAlignment(.center)
                        }.frame(width: 72, height: 62)
                    }.foregroundStyle(model.controls.mode == mode ? accent : .white).accessibilityIdentifier("exposure-mode-\(mode.rawValue)")
                }
            }
            Button { model.controls.bias = 0; modesOpen = false } label: {
                VStack(spacing: 5) { Image(systemName: "restart.circle").font(.system(size: 32, weight: .light)); Text("Reset Bias").font(.system(size: 11)) }
                    .frame(width: 72, height: 62)
            }.foregroundStyle(.white)
        }.padding(10).background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 20))
    }
    private func modeSymbol(_ mode: ExposureMode) -> String {
        switch mode {
        case .automatic: return "a.circle"
        case .manual: return "m.circle"
        case .isoPriority: return "circle.bottomrighthalf.pattern.checkered"
        case .shutterPriority: return "figure.walk.motion"
        case .aperturePriority: return "camera.aperture"
        }
    }

    private func viewfinder(landscape: Bool) -> some View {
        GeometryReader { geometry in
            let ratio = landscape ? model.recipe.aspect.landscapeRatio : model.recipe.aspect.portraitRatio
            let width = min(geometry.size.width, geometry.size.height * ratio)
            let height = width / ratio
            ZStack {
                Color.black
                if model.isDemo, let image = model.preview {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: width, height: height).clipped()
                } else if !model.isDemo && !model.permissionDenied {
                    CameraPreview(service: model.service, deviceID: model.state.selectedLens, zoom: model.controls.zoom)
                        .frame(width: width, height: height)
                }
                if model.state.running {
                    AnalysisOverlay(analysis: model.analysis, peaking: model.showPeaking, zebras: model.showZebras).allowsHitTesting(false)
                    CompositionGrid(style: model.grid, corner: model.goldenCorner).allowsHitTesting(false)
                    if model.levelMode == .on || model.levelMode == .auto && model.grid != .none {
                        LevelView(degrees: model.levelDegrees).allowsHitTesting(false)
                    }
                    if focusVisible {
                        RoundedRectangle(cornerRadius: 5).stroke(accent, lineWidth: 1.5).frame(width: 76, height: 76)
                            .position(x: model.focusPoint.x * width, y: model.focusPoint.y * height).allowsHitTesting(false)
                    }
                    if model.countdown > 0 {
                        Text("\(model.countdown)").font(.system(size: 70, weight: .light, design: .rounded)).shadow(radius: 10)
                            .allowsHitTesting(false)
                    }
                    VStack {
                        Spacer()
                        if model.showLoupe, let cg = model.preview?.cgImage, let crop = cg.cropping(to: loupeRect(image: cg)) {
                            HStack {
                                Image(decorative: crop, scale: 1).resizable().scaledToFill().frame(width: 108, height: 108)
                                    .clipped().overlay(Rectangle().stroke(accent, lineWidth: 1))
                                Spacer()
                            }.allowsHitTesting(false)
                        }
                        if controlsOpen {
                            ManualControls(model: model)
                                .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            HStack(spacing: 12) {
                                Text("ISO \(Int(model.state.iso))")
                                Text(shutterLabel(model.state.shutter))
                                Text(String(format: "ƒ/%.1f", model.state.aperture))
                                Spacer()
                                Text(String(format: "%+.1f", model.state.meter))
                                    .foregroundStyle(abs(model.state.meter) > 1 ? Color.orange : .white)
                            }.font(.system(size: 13, weight: .medium, design: .monospaced))
                                .padding(9).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                                .allowsHitTesting(false)
                        }
                    }.padding(12)
                } else if model.permissionDenied {
                    VStack(spacing: 16) {
                        Image(systemName: "camera").font(.system(size: 38))
                        Text("Allow camera access").font(.headline)
                        Text("Enable Camera for Lucent in Settings to begin.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    }.padding(24)
                } else { ProgressView(model.interruption ?? "Starting camera") }
                if model.isDemo {
                    Text("GENERATED TEST SCENE").font(.system(size: 9, weight: .semibold)).tracking(1)
                        .padding(6).background(.black.opacity(0.5), in: Capsule()).offset(y: -height * 0.24).allowsHitTesting(false)
                }
            }
            .frame(width: width, height: height).clipped()
            .contentShape(Rectangle())
            .onTapGesture { point in
                if model.countdown > 0 { model.cancelTimer() }
                else {
                    model.focus(at: CGPoint(x: point.x / max(1, width), y: point.y / max(1, height)))
                    focusVisible = true
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 15).onChanged { drag in
                if dragStartControls == nil { dragStartControls = model.controls }
                guard let start = dragStartControls else { return }
                if model.controls.mode == .manual {
                    if abs(drag.translation.width) > abs(drag.translation.height) {
                        model.controls.iso = logarithmicValue(logarithmicFraction(start.iso, range: model.state.isoRange) + Double(drag.translation.width) / 400, range: model.state.isoRange)
                    } else {
                        model.controls.shutter = logarithmicValue(logarithmicFraction(start.shutter, range: model.state.shutterRange) - Double(drag.translation.height) / 400, range: model.state.shutterRange)
                    }
                } else { model.controls.bias = clamp(start.bias - Double(drag.translation.height) / 120, to: -3...3) }
            }.onEnded { _ in dragStartControls = nil })
            .accessibilityElement(children: .contain).accessibilityIdentifier("viewfinder")
            .accessibilityLabel(model.isDemo ? "Generated camera test scene" : "Camera viewfinder")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loupeRect(image: CGImage) -> CGRect {
        let side = CGFloat(min(image.width, image.height)) * 0.25
        let x = clamp(Double(model.focusPoint.x) * Double(image.width) - side / 2, to: 0...max(0, Double(image.width) - side))
        let y = clamp(Double(model.focusPoint.y) * Double(image.height) - side / 2, to: 0...max(0, Double(image.height) - side))
        return CGRect(x: x, y: y, width: side, height: side)
    }

    private struct LensChoice: Identifiable {
        var lens: LensInfo
        var crop: Double
        var id: String { "\(lens.id)-\(crop)" }
        var magnification: Double { lens.magnification * crop }
        var title: String { magnification < 1 ? String(format: "%.1f", magnification) : String(format: "%g", magnification) }
    }
    private var lensChoices: [LensChoice] {
        model.state.lenses.filter { !$0.front }.flatMap { lens in
            lens.title == "Wide" || lens.title == "Tele" ? [LensChoice(lens: lens, crop: 1), LensChoice(lens: lens, crop: 2)] : [LensChoice(lens: lens, crop: 1)]
        }.sorted { $0.magnification < $1.magnification }
    }
    private var lensPicker: some View {
        HStack(spacing: 22) {
            Button(model.controls.autofocus ? "AF" : "MF") {
                model.controls.autofocus.toggle(); controlsOpen = !model.controls.autofocus
            }.font(.system(size: 15, weight: .semibold)).frame(width: 37, height: 37)
                .foregroundStyle(model.controls.autofocus ? .black : .white)
                .background(model.controls.autofocus ? accent : .white.opacity(0.12), in: Circle())
                .frame(width: 44, height: 46).disabled(!model.state.manualFocus).accessibilityLabel("Focus mode")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(lensChoices) { choice in
                        let selected = model.state.selectedLens == choice.lens.id && model.controls.zoom == choice.crop
                        Button {
                            model.controls.zoom = choice.crop
                            model.service.selectLens(choice.lens.id)
                        } label: {
                            Text(choice.title + (selected ? "×" : ""))
                                .font(.system(size: selected ? 14 : 12, weight: .medium, design: .rounded))
                                .frame(width: selected ? 37 : 29, height: selected ? 37 : 29)
                                .foregroundStyle(selected ? .black : .white)
                                .background(selected ? accent : .white.opacity(0.1), in: Circle())
                                .frame(width: 44, height: 44)
                        }.accessibilityLabel("\(choice.lens.title), \(choice.title) times\(choice.crop > 1 ? ", digital crop" : "")")
                    }
                    if model.state.lenses.contains(where: { $0.front && $0.id == model.state.selectedLens }) {
                        Text("Front").font(.system(size: 14)).foregroundStyle(accent).padding(.horizontal, 8)
                    }
                }
            }.frame(height: 46).overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.5))
            Menu {
                Button { settingsOpen = true } label: { Label("Settings", systemImage: "gearshape") }
                    .accessibilityIdentifier("cameraSettings")
                Menu {
                    whiteBalancePreset("Cloudy", kelvin: 6500)
                    whiteBalancePreset("Daylight", kelvin: 5500)
                    whiteBalancePreset("Fluorescent", kelvin: 3800)
                    whiteBalancePreset("Incandescent", kelvin: 2800)
                    Button { model.controls.customWhiteBalance = false } label: { Label("Auto", systemImage: "a.circle") }
                } label: { Label("White Balance", systemImage: "thermometer.variable") }
                    .disabled(!model.state.whiteBalance)
                Menu {
                    Picker("Flash", selection: $model.flashMode) {
                        ForEach([FlashMode.auto, .off, .on]) { mode in
                            Label(mode.title, systemImage: mode == .auto ? "bolt.badge.automatic.fill" : mode == .off ? "bolt.slash.fill" : "bolt.fill").tag(mode)
                        }
                    }.pickerStyle(.inline)
                } label: { Label("Flash", systemImage: model.flashMode == .off ? "bolt.slash.fill" : model.flashMode == .auto ? "bolt.badge.automatic.fill" : "bolt.fill") }
                    .disabled(!model.state.capabilities.flash).accessibilityIdentifier("flashMenu")
                if let front = model.state.lenses.first(where: \.front) {
                    Button {
                        let rear = model.state.lenses.first { !$0.front && $0.title == "Wide" } ?? model.state.lenses.first { !$0.front }
                        if let destination = model.state.selectedLens == front.id ? rear : front {
                            model.controls.zoom = 1; model.service.selectLens(destination.id)
                        }
                    } label: { Label("Flip Camera", systemImage: "arrow.triangle.2.circlepath.camera") }
                        .accessibilityIdentifier("flipCamera")
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 22, weight: .semibold)).frame(width: 46, height: 46)
                    .background(.white.opacity(0.12), in: Circle())
            }.accessibilityLabel("More").accessibilityIdentifier("cameraMore")
        }.padding(.horizontal, 12).offset(y: 6).frame(height: 88)
    }
    private func whiteBalancePreset(_ name: String, kelvin: Double) -> some View {
        Button {
            model.controls.temperature = kelvin; model.controls.tint = 0; model.controls.customWhiteBalance = true
        } label: {
            Text(name)
            Text("\(Int(kelvin).formatted())K")
        }
    }

    private var compositionToolbar: some View {
        HStack(spacing: 0) {
            Menu {
                ForEach(CaptureFormat.allCases) { value in
                    Button(value.title) { model.format = value }
                        .disabled(value == .sensorRAW && !model.state.capabilities.sensorRAW || value == .proRAW && !model.state.capabilities.proRAW)
                }
            } label: {
                Text(model.format == .processed ? (model.heic ? "HEIC" : "JPEG") : model.format == .sensorRAW ? "RAW" : "ProRAW")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced)).frame(width: 46, height: 46)
            }.accessibilityLabel("Capture format: \(model.format.title)")
            Spacer()
            Menu {
                Picker("Aspect Ratio", selection: $model.recipe.aspect) {
                    ForEach([AspectRatio.native, .square, .classic, .panorama, .wide, .insta]) { aspect in
                        VStack(alignment: .leading) {
                            Text(aspectName(aspect))
                            Text(aspect == .insta ? "4:5 or 1.91:1" : aspect.title)
                        }.tag(aspect)
                    }
                }.pickerStyle(.inline)
            } label: { Image(systemName: "aspectratio").font(.system(size: 23, weight: .light)).frame(width: 46, height: 46) }
                .accessibilityLabel("Change Aspect Ratio").accessibilityIdentifier("aspectMenu")
            Spacer()
            CompositionMenu(model: model)


        }.padding(.horizontal, 30).offset(y: 3).font(.system(size: 18)).foregroundStyle(.white.opacity(0.85)).frame(height: 60)
    }

    private func aspectName(_ aspect: AspectRatio) -> String {
        switch aspect {
        case .native: return "Original"
        case .square: return "Square"
        case .classic: return "35mm"
        case .panorama: return "Pano"
        case .wide: return "Wide"
        case .insta: return "Insta"
        }
    }

    private var shutterBar: some View {
        ZStack {
            HStack {
            Button { model.reloadLibrary(); libraryOpen = true } label: {
                Group {
                    if let record = model.records.first { ThumbnailView(url: CaptureStore.shared.renderURL(record)) }
                    else { Image(systemName: "photo.stack").font(.system(size: 24)) }
                }.frame(width: 70, height: 70).clipped().clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.25), lineWidth: 1))
            }.foregroundStyle(.white).accessibilityLabel("Photo library").accessibilityIdentifier("photoLibrary")
            Spacer()
            Button { looksOpen = true } label: {
                RoundedRectangle(cornerRadius: 18).fill(lookColor(model.recipe.look)).frame(width: 70, height: 70)
                    .overlay(Image(systemName: "camera.filters").font(.system(size: 28, weight: .light)).foregroundStyle(.white.opacity(0.8)))
            }.foregroundStyle(.white).accessibilityLabel("Color recipes").accessibilityIdentifier("colorRecipes")
            }.padding(.horizontal, 15).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 12)
            Button { model.shutter() } label: {
                ZStack {
                    Circle().stroke(accent.opacity(model.busy ? 0.25 : 0.8), lineWidth: 2).frame(width: 88, height: 88)
                    Circle().fill(model.busy ? .white.opacity(0.2) : .white).frame(width: 76, height: 76)
                    if model.busy { ProgressView().tint(accent) }
                }
            }.disabled(model.busy || !model.state.running || model.countdown > 0)
                .accessibilityLabel("Take photograph").accessibilityIdentifier("shutter").offset(y: -7)
        }.frame(height: 126)
    }
}

func lookColor(_ look: Look) -> Color {
    switch look {
    case .neutral: return Color(red: 0.80, green: 0.84, blue: 0.67)
    case .ember: return Color(red: 0.80, green: 0.51, blue: 0.31)
    case .verdant: return Color(red: 0.36, green: 0.61, blue: 0.44)
    case .silver: return Color(red: 0.60, green: 0.64, blue: 0.66)
    case .charcoal: return Color(red: 0.34, green: 0.34, blue: 0.35)
    }
}

struct LookPicker: View {
    @Binding var selection: Look
    var body: some View {
        List(Look.allCases) { look in
            Button { selection = look } label: {
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 8).fill(lookColor(look)).frame(width: 42, height: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(look.title).font(.headline).foregroundStyle(.primary)
                        Text(look.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if look == selection { Image(systemName: "checkmark") }
                }.padding(.vertical, 4)
            }.accessibilityIdentifier("look-\(look.rawValue)")
        }
    }
}
