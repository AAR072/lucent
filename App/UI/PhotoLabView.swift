import SwiftUI
import ImageIO
import LucentCore

struct PhotoLabView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var record: CaptureRecord
    @State private var recipe: DevelopmentSettings
    @State private var image: UIImage?
    @State private var busy = false
    @State private var rendering = false
    @State private var error: String?
    @State private var savedToPhotos = false
    @State private var panel = "Quick Edit"
    @State private var editing = false
    @State private var inspection = false
    @State private var infoOpen = false
    @State private var metadataExpanded = false
    @State private var removeOpen = false
    @State private var histogram: FrameAnalysis?
    @State private var metadata = ""
    @State private var zoomed = false
    let onSave: () -> Void
    let onClose: (() -> Void)?
    let onBack: (() -> Void)?
    let onRemove: (() -> Void)?
    let onPagingChanged: ((Bool) -> Void)?
    let position: String
    init(record: CaptureRecord, onSave: @escaping () -> Void, onClose: (() -> Void)? = nil,
         onBack: (() -> Void)? = nil, onRemove: (() -> Void)? = nil,
         onPagingChanged: ((Bool) -> Void)? = nil, position: String = "") {
        _record = State(initialValue: record); _recipe = State(initialValue: record.recipe)
        self.onSave = onSave
        self.onClose = onClose
        self.onBack = onBack; self.onRemove = onRemove
        self.onPagingChanged = onPagingChanged; self.position = position
    }
    private struct RenderRequest: Equatable { var recipe: DevelopmentSettings; var inspection: Bool }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.black
                ZoomablePhoto(image: image, inspection: inspection, onZoomChanged: { magnified in
                    zoomed = magnified
                    updatePaging(zoomed: magnified)
                })
                    .frame(width: geometry.size.width, height: max(1, geometry.size.height - (editing ? 276 : 68)))
                VStack(spacing: 0) {
                    Spacer()
                    if editing {
                        VStack(spacing: 0) {
                            editor.frame(height: 208)
                            actionBar.padding(.horizontal, 20).frame(height: 68)
                        }.frame(height: 276).background(Color(white: 0.055))
                    } else { reviewDrawer.padding(.horizontal, 20).padding(.bottom, 20) }
                }
                if !editing { reviewHeader.padding(.top, max(12, geometry.safeAreaInsets.top)).padding(.horizontal, 16) }
                if rendering { ProgressView().padding(10).background(.ultraThinMaterial, in: Capsule()).padding(.top, 70) }
            }
        }.background(.black).ignoresSafeArea(.container).statusBarHidden(true).persistentSystemOverlays(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { updatePaging() }
            .onChange(of: editing) { _, _ in updatePaging() }
            .onChange(of: inspection) { _, _ in updatePaging() }
            .onChange(of: busy) { _, _ in updatePaging() }
            .task(id: RenderRequest(recipe: recipe, inspection: inspection)) {
                rendering = true
                do { try await Task.sleep(nanoseconds: 120_000_000) } catch { return }
                let currentRecipe = recipe, currentRecord = record, fullResolution = inspection
                let result = await PhotoRenderer.shared.render(record: currentRecord, recipe: currentRecipe, fullResolution: fullResolution)
                guard !Task.isCancelled else { return }
                rendering = false
                switch result {
                case .success(let output):
                    image = output.0; histogram = output.1; metadata = output.3
                    if let refreshed = output.2 { record = refreshed; onSave() }
                case .failure(let failure): error = failure.localizedDescription
                }
            }
            .sheet(isPresented: $infoOpen) {
                NavigationStack {
                    Form {
                        Section("Capture") {
                            Text(metadata.isEmpty ? "No camera metadata" : metadata)
                            Text(record.created, format: .dateTime)
                            Text(record.origin)
                        }
                        Section("Development") {
                            Text("\(record.recipe.look.title) · SDR sRGB")
                            Text(record.isRAW ? "Original negative preserved" : "Original image preserved")
                            if let cg = image?.cgImage { Text("Preview: \(cg.width) × \(cg.height)") }
                        }
                    }.navigationTitle("Photograph information")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { infoOpen = false } } }
                }.presentationDetents([.medium, .large])
            }
            .alert("Photo lab", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
            .confirmationDialog("Remove this photograph from Lucent?", isPresented: $removeOpen, titleVisibility: .visible) {
                Button("Remove photograph", role: .destructive) {
                    do {
                        try CaptureStore.shared.trash(record)
                        if let onRemove { onRemove() } else { onSave(); dismiss() }
                    }
                    catch { self.error = error.localizedDescription }
                }.accessibilityIdentifier("confirmRemovePhoto")
            } message: { Text("The negative and edit remain recoverable in Lucent’s Documents/Captures/.Trash folder.") }
    }

    private var reviewHeader: some View {
        ZStack {
            HStack {
                Button { if let onBack { onBack() } else { dismiss() } } label: { Label("Photographs", systemImage: "chevron.left").font(.system(size: 15)).frame(height: 44) }
                Spacer()
                Button { inspection.toggle() } label: { Text("1:1").font(.system(size: 14, weight: .medium, design: .monospaced)).frame(width: 44, height: 44) }
                    .foregroundStyle(inspection ? Color.accentColor : .white).accessibilityLabel("Inspect original pixels").accessibilityIdentifier("pixelInspection")
            }
            Button { if let onClose { onClose() } else { dismiss() } } label: {
                Image(systemName: "xmark").font(.system(size: 18)).frame(width: 44, height: 44).background(.black.opacity(0.5), in: Circle())
            }.accessibilityLabel("Close photograph").accessibilityIdentifier("closePhoto").accessibilityValue(position)
        }.foregroundStyle(.white)
    }

    private var reviewDrawer: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { metadataExpanded.toggle() } } label: {
                VStack(spacing: 10) {
                    Capsule().fill(.white.opacity(0.25)).frame(width: 34, height: 4)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.created, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.system(size: 13, weight: .medium))
                            Text(metadata.isEmpty ? record.recipe.look.title : metadata).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: metadataExpanded ? "chevron.down" : "chevron.up").font(.system(size: 12))
                    }
                }.padding(.horizontal, 24).frame(height: 84)
            }.buttonStyle(.plain).accessibilityLabel("Expand photograph details")
            if metadataExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    Text(record.isRAW ? "RAW negative" : "Original image").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    Text(metadata).font(.system(size: 13))
                    HStack { Text(record.recipe.look.title); Spacer(); Text("SDR · sRGB") }.font(.system(size: 12, design: .monospaced))
                    Button("More information") { infoOpen = true }.font(.system(size: 13))
                    if savedToPhotos { Text("Saved to Photos").font(.caption).foregroundStyle(.mint) }
                }.padding(.horizontal, 24).padding(.bottom, 20)
            }
            actionBar.frame(height: 60).padding(.horizontal, 12)
        }.background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 24))
            .gesture(DragGesture(minimumDistance: 25).onEnded { drag in
                withAnimation(.easeInOut(duration: 0.2)) { metadataExpanded = drag.translation.height < 0 }
            })
    }

    private var editor: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
              ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["Frame", "Quick Edit", "Exposure", "Film", "Balance"], id: \.self) { name in
                        Button { panel = name } label: {
                            Text(name.uppercased()).font(.system(size: 13, weight: .semibold, design: .monospaced)).tracking(1)
                                .foregroundStyle(panel == name ? .white : .secondary).frame(width: 129, height: 44)
                        }.accessibilityIdentifier("lab-panel-\(name)").id(name)
                    }
                }
              }.onAppear { proxy.scrollTo(panel, anchor: .center) }
                .onChange(of: panel) { _, name in withAnimation { proxy.scrollTo(name, anchor: .center) } }
            }.frame(height: 44)
            Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
            ScrollView {
                VStack(spacing: 12) {
                    switch panel {
                    case "Quick Edit":
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 20) {
                                ForEach(Look.allCases) { look in
                                    Button { recipe.look = look } label: {
                                        VStack(spacing: 5) {
                                            RoundedRectangle(cornerRadius: 10).fill(lookColor(look)).frame(width: 60, height: 60)
                                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(recipe.look == look ? Color.accentColor : .clear, lineWidth: 3))
                                            Text(look.title).font(.system(size: 12)).foregroundStyle(.white)
                                        }.frame(width: 70)
                                    }.accessibilityIdentifier("lab-look-\(look.rawValue)")
                                }
                            }.padding(.horizontal, 18).padding(.top, 10)
                        }
                        ExposureDial(value: $recipe.exposure).padding(.horizontal, 26)
                    case "Exposure":
                        HistogramView(bins: histogram?.histogram ?? []).frame(height: 52)
                        ExposureDial(value: $recipe.exposure)
                    case "Frame":
                        Picker("Aspect ratio", selection: $recipe.aspect) { ForEach(AspectRatio.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                        ControlSlider(title: "Straighten", label: String(format: "%.1f°", recipe.rotationDegrees), value: $recipe.rotationDegrees, range: -15...15)
                        Picker("Long edge", selection: $recipe.maxLongEdge) {
                            Text("Full resolution").tag(0); Text("4096 pixels").tag(4096); Text("2048 pixels").tag(2048)
                        }.pickerStyle(.menu)
                    case "Film":
                        effect("Grain", value: $recipe.grain)
                        effect("Bloom", value: $recipe.halation)
                        effect("Vignette", value: $recipe.vignette)
                        effect("Detail", value: $recipe.microcontrast)
                        if record.isRAW {
                            Toggle("Minimal RAW development", isOn: Binding(get: { recipe.minimalRAWProcessing == true }, set: { recipe.minimalRAWProcessing = $0 }))
                        }
                    default:
                        Toggle("Custom white balance", isOn: $recipe.useCustomWhiteBalance)
                        if recipe.useCustomWhiteBalance {
                            Menu("White balance preset") {
                                ForEach([("Daylight", 5500.0), ("Cloudy", 6500), ("Shade", 7500), ("Tungsten", 3000)], id: \.0) { preset in
                                    Button(preset.0) { recipe.temperature = preset.1; recipe.tint = 0 }
                                }
                            }
                            ControlSlider(title: "Kelvin", label: "\(Int(recipe.temperature)) K", value: $recipe.temperature, range: 2000...12000)
                            ControlSlider(title: "Tint", label: String(format: "%+.0f", recipe.tint), value: $recipe.tint, range: -100...100)
                        }
                    }
                }.padding(.vertical, 4)
            }.disabled(busy)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 14) {
            if editing {
                Button { recipe = record.recipe; editing = false; inspection = false } label: {
                    Image(systemName: "xmark").font(.system(size: 19, weight: .medium)).frame(width: 48, height: 44)
                }.accessibilityLabel("Cancel edits")
                Spacer()
                HStack(spacing: 20) {
                    Button { panel = "Exposure" } label: { Image(systemName: "sun.max").font(.system(size: 19)) }.accessibilityLabel("Exposure panel")
                    Button { panel = "Film" } label: { Image(systemName: "film").font(.system(size: 19)) }.accessibilityLabel("Film panel")
                }.padding(.horizontal, 20).frame(height: 44).background(.black, in: Capsule())
                Spacer()
                Button { save() } label: {
                    Image(systemName: "checkmark").font(.system(size: 21, weight: .semibold)).frame(width: 50, height: 44)
                }.buttonStyle(.borderedProminent).disabled(busy || recipe == record.recipe)
                    .accessibilityLabel("Save edit").accessibilityIdentifier("saveEdit")
            } else {
                Button {
                    do { record = try CaptureStore.shared.setFavorite(record.favorite != true, record: record); onSave() }
                    catch { self.error = error.localizedDescription }
                } label: { Image(systemName: record.favorite == true ? "heart.fill" : "heart").font(.system(size: 21)).frame(width: 44, height: 44) }
                    .accessibilityLabel(record.favorite == true ? "Remove favorite" : "Favorite photograph")
                Spacer()
                Button { editing = true; inspection = false } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 21)).frame(width: 44, height: 44)
                }.accessibilityLabel("Develop photograph").accessibilityIdentifier("editPhoto")
                Spacer()
                Menu {
                    ShareLink(item: CaptureStore.shared.renderURL(record)) { Label("Share photograph", systemImage: "photo") }
                    if record.isRAW { ShareLink(item: CaptureStore.shared.originalURL(record)) { Label("Share RAW", systemImage: "doc") } }
                    Button("Save to Photos") { saveToPhotos() }
                } label: { Image(systemName: "square.and.arrow.up").font(.system(size: 21)).frame(width: 44, height: 44) }
                    .disabled(busy || rendering).accessibilityLabel("Export photograph")
                Spacer()
                Button { removeOpen = true } label: { Image(systemName: "trash").font(.system(size: 21)).frame(width: 44, height: 44) }
                    .disabled(busy).accessibilityLabel("Remove photograph").accessibilityIdentifier("removePhoto")
            }
            if busy { ProgressView() }
        }.disabled(busy)
    }
    private func saveToPhotos() {
        busy = true
        CaptureStore.shared.saveToPhotos(record, includeRAW: true) { result in
            DispatchQueue.main.async {
                busy = false
                switch result {
                case .success: savedToPhotos = true
                case .failure(let failure): error = failure.localizedDescription
                }
            }
        }
    }
    private func updatePaging(zoomed: Bool? = nil) {
        onPagingChanged?(!editing && !inspection && !busy && !(zoomed ?? self.zoomed))
    }
    nonisolated fileprivate static func readMetadata(_ data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return "" }
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        var parts = [String]()
        if let model = tiff[kCGImagePropertyTIFFModel as String] as? String { parts.append(model) }
        if let iso = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber], let first = iso.first { parts.append("ISO \(first.intValue)") }
        if let duration = exif[kCGImagePropertyExifExposureTime as String] as? NSNumber { parts.append(shutterLabel(duration.doubleValue)) }
        if let aperture = exif[kCGImagePropertyExifFNumber as String] as? NSNumber { parts.append(String(format: "ƒ/%.1f", aperture.doubleValue)) }
        return parts.joined(separator: " · ")
    }
    private func effect(_ title: String, value: Binding<Double>) -> some View {
        ControlSlider(title: title, label: "\(Int(value.wrappedValue * 100))%", value: value, range: 0...1)
    }
    private func save() {
        busy = true; savedToPhotos = false
        let currentRecord = record, currentRecipe = recipe
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try CaptureStore.shared.update(currentRecord, recipe: currentRecipe) }
            }.value
            busy = false
            switch result {
            case .success(let saved): record = saved; onSave()
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }
}

/// Serial rendering bounds RAW decoder memory; canceled slider requests skip queued work.
private actor PhotoRenderer {
    static let shared = PhotoRenderer()
    func render(record: CaptureRecord, recipe: DevelopmentSettings, fullResolution: Bool) -> Result<(UIImage, FrameAnalysis?, CaptureRecord?, String), Error> {
        Result {
            try Task.checkCancellation()
            let data = try CaptureStore.shared.originalData(record)
            let developed = try ImagePipeline.shared.decode(data, isRAW: record.isRAW, settings: recipe, preview: !fullResolution, hdrOutput: recipe.hdr == true)
            let preview = try ImagePipeline.shared.uiImage(developed, hdr: recipe.hdr == true)
            let analysis = PreviewAnalysis.sample(developed, aspect: recipe.aspect, analyze: true, loupe: false).analysis
            try Task.checkCancellation()
            let refreshed = record.renderVersion != 2 ? try CaptureStore.shared.refreshIfNeeded(record) : nil
            return (preview, analysis, refreshed, PhotoLabView.readMetadata(data))
        }
    }
}
