import Foundation
import Photos
import LucentCore
import ImageIO
import UniformTypeIdentifiers

struct CaptureRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let created: Date
    let originalFile: String
    let isRAW: Bool
    let origin: String
    var recipe: DevelopmentSettings
    var renderFile: String
    var renderVersion: Int?
    var favorite: Bool? = nil
    var location: CaptureLocation? = nil
}

final class CaptureStore {
    static let shared = CaptureStore()
    let root: URL
    private let mutationLock = NSRecursiveLock()
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Captures", isDirectory: true)
    }
    func directory(_ record: CaptureRecord) -> URL { root.appendingPathComponent(record.id.uuidString, isDirectory: true) }
    func originalURL(_ record: CaptureRecord) -> URL { directory(record).appendingPathComponent(record.originalFile) }
    func renderURL(_ record: CaptureRecord) -> URL { directory(record).appendingPathComponent(record.renderFile) }
    func originalData(_ record: CaptureRecord) throws -> Data { try Data(contentsOf: originalURL(record)) }

    func create(original: Data, isRAW: Bool, origin: String, recipe: DevelopmentSettings,
                heic: Bool = false, location: CaptureLocation? = nil) throws -> CaptureRecord {
        var suffix = isRAW ? "dng" : "jpg"
        if !isRAW, let source = CGImageSourceCreateWithData(original as CFData, nil),
           let type = CGImageSourceGetType(source), let ext = UTType(type as String)?.preferredFilenameExtension { suffix = ext }
        let record = CaptureRecord(id: UUID(), created: Date(), originalFile: "original.\(suffix)", isRAW: isRAW,
                                   origin: origin, recipe: recipe, renderFile: heic ? "developed.heic" : "developed.jpg", renderVersion: 2, location: location)
        let folder = directory(record)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        // Persist the source and manifest before rendering; a decoder failure must not lose a shot.
        try original.write(to: originalURL(record), options: .atomic)
        try writeManifest(record)
        try render(record, heic: heic)
        return record
    }

    func render(_ record: CaptureRecord, heic: Bool) throws {
        let original = try originalData(record)
        var image = try ImagePipeline.shared.decode(original, isRAW: record.isRAW, settings: record.recipe)
        if let location = record.location { image = image.settingProperties(location.imageProperties) }
        let hdr = record.recipe.hdr == true ? try ImagePipeline.shared.decode(original, isRAW: record.isRAW, settings: record.recipe, hdrOutput: true) : nil
        let quality = record.recipe.compressionQuality ?? 0.9
        let data = try heic ? ImagePipeline.shared.heic(image, quality: quality, hdrImage: hdr) : ImagePipeline.shared.jpeg(image, quality: quality, hdrImage: hdr)
        try data.write(to: renderURL(record), options: .atomic)
    }
    func update(_ record: CaptureRecord, recipe: DevelopmentSettings) throws -> CaptureRecord {
        mutationLock.lock(); defer { mutationLock.unlock() }
        let current = try load(record)
        var edited = current; edited.recipe = recipe; edited.renderVersion = 2
        // Render to a new file first so a failed edit leaves the previous image and recipe intact.
        let heic = current.renderFile.hasSuffix(".heic")
        edited.renderFile = "developed-\(UUID().uuidString).\(heic ? "heic" : "jpg")"
        try render(edited, heic: heic)
        do { try writeManifest(edited) } catch {
            try? FileManager.default.removeItem(at: renderURL(edited)); throw error
        }
        if edited.renderFile != current.renderFile { try? FileManager.default.removeItem(at: renderURL(current)) }
        return edited
    }
    func refreshIfNeeded(_ record: CaptureRecord) throws -> CaptureRecord {
        mutationLock.lock(); defer { mutationLock.unlock() }
        let current = try load(record)
        return current.renderVersion == 2 ? current : try update(current, recipe: current.recipe)
    }
    func setFavorite(_ favorite: Bool, record: CaptureRecord) throws -> CaptureRecord {
        mutationLock.lock(); defer { mutationLock.unlock() }
        var current = try load(record); current.favorite = favorite
        try writeManifest(current)
        return current
    }
    /// Keep removed photographs recoverable in the app's Documents directory.
    func trash(_ record: CaptureRecord) throws {
        mutationLock.lock(); defer { mutationLock.unlock() }
        let trash = root.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: directory(record), to: trash.appendingPathComponent(record.id.uuidString))
    }
    private func load(_ record: CaptureRecord) throws -> CaptureRecord {
        try JSONDecoder().decode(CaptureRecord.self, from: Data(contentsOf: directory(record).appendingPathComponent("capture.json")))
    }
    func list() -> [CaptureRecord] {
        guard let directories = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return directories.compactMap { url in
            guard let data = try? Data(contentsOf: url.appendingPathComponent("capture.json")) else { return nil }
            return try? JSONDecoder().decode(CaptureRecord.self, from: data)
        }.sorted { $0.created > $1.created }
    }
    private func writeManifest(_ record: CaptureRecord) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: directory(record).appendingPathComponent("capture.json"), options: .atomic)
    }

    func saveToPhotos(_ record: CaptureRecord, includeRAW: Bool, rawOnly: Bool = false, completion: @escaping (Result<Void, Error>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                completion(.failure(NSError(domain: "Lucent", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photos access was not granted. Your photograph is saved in Lucent."])))
                return
            }
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.creationDate = record.created
                request.location = record.location?.clLocation
                request.addResource(with: .photo, fileURL: rawOnly && record.isRAW ? self.originalURL(record) : self.renderURL(record), options: nil)
                if includeRAW && record.isRAW && !rawOnly {
                    request.addResource(with: .alternatePhoto, fileURL: self.originalURL(record), options: nil)
                }
            } completionHandler: { success, error in
                if success { completion(.success(())) }
                else { completion(.failure(error ?? ImagingError.encodingFailed)) }
            }
        }
    }
}
