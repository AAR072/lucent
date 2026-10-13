import SwiftUI
import UniformTypeIdentifiers
import CoreImage
import ImageIO
import LucentCore

struct LibraryView: View {
    @ObservedObject var model: CameraModel
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var importBusy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Group {
                if model.records.isEmpty {
                    ContentUnavailableView("Your photographs", systemImage: "photo.stack", description: Text("Take a photograph, or import an image or supported RAW file to develop."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                            ForEach(model.records) { record in
                                NavigationLink {
                                    PhotoGalleryView(model: model, selectedID: record.id, onClose: { dismiss() })
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ThumbnailView(url: CaptureStore.shared.renderURL(record))
                                            .frame(height: 175).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                                        HStack {
                                            Text(record.recipe.look.title)
                                            Spacer()
                                            Text(record.isRAW ? "RAW" : record.origin == "generated-demo" ? "DEMO" : "PHOTO")
                                        }.font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                                    }
                                }.accessibilityIdentifier("capture-\(record.id.uuidString)")
                            }
                        }.padding(16)
                    }
                }
            }.navigationTitle("Photographs")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { Button { importing = true } label: { if importBusy { ProgressView() } else { Image(systemName: "square.and.arrow.down") } }.disabled(importBusy).accessibilityLabel("Import image") }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .rawImage], allowsMultipleSelection: false) { result in
                    do {
                        guard let url = try result.get().first else { return }
                        importBusy = true
                        DispatchQueue.global(qos: .userInitiated).async {
                            let access = url.startAccessingSecurityScopedResource()
                            defer { if access { url.stopAccessingSecurityScopedResource() } }
                            do {
                                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                                guard (values.fileSize ?? Int.max) <= 200_000_000 else { throw NSError(domain: "Lucent", code: 4, userInfo: [NSLocalizedDescriptionKey: "Choose an image smaller than 200 MB."]) }
                                let data = try Data(contentsOf: url)
                                let raw = ImagePipeline.isRAWData(data)
                                _ = try CaptureStore.shared.create(original: data, isRAW: raw, origin: "imported", recipe: DevelopmentSettings())
                                DispatchQueue.main.async { importBusy = false; model.reloadLibrary() }
                            } catch { DispatchQueue.main.async { importBusy = false; self.error = error.localizedDescription; model.reloadLibrary() } }
                        }
                    } catch { self.error = error.localizedDescription }
                }
                .alert("Import failed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK") { error = nil }
                } message: { Text(error ?? "") }
        }
    }
}

struct ThumbnailView: View {
    let url: URL
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { ZStack { Color.white.opacity(0.06); Image(systemName: "photo").foregroundStyle(.secondary) } }
        }.task(id: url) {
            image = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 600,
                        kCGImageSourceCreateThumbnailWithTransform: true
                      ] as CFDictionary) else { return nil as UIImage? }
                return UIImage(cgImage: cg)
            }.value
        }
    }
}
