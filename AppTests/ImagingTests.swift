import XCTest
import UIKit
import CoreImage
import ImageIO
import LucentCore
@testable import Lucent

final class ImagingTests: XCTestCase {
    func testCompressionQualityChangesEncodedSize() throws {
        var settings = DevelopmentSettings(); settings.maxLongEdge = 512
        let image = try ImagePipeline.shared.decode(DemoScene.data(), isRAW: false, settings: settings)
        let compact = try ImagePipeline.shared.jpeg(image, quality: 0.2)
        let high = try ImagePipeline.shared.jpeg(image, quality: 0.95)
        XCTAssertLessThan(compact.count, high.count)
        XCTAssertNotNil(UIImage(data: compact))
    }
    func testHDRJPEGContainsGainMapAndDecodesAsHDR() throws {
        let rect = CGRect(x: 0, y: 0, width: 512, height: 512)
        let sdr = CIImage(color: CIColor(red: 0.7, green: 0.7, blue: 0.7)).cropped(to: rect)
        let hdr = CIImage(color: CIColor(red: 2, green: 2, blue: 2, alpha: 1,
                                        colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)!).cropped(to: rect)
        var pixel = [Float](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { ptr in
            ImagePipeline.shared.context.render(hdr, toBitmap: ptr.baseAddress!, rowBytes: 16,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf,
                colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)
        }
        XCTAssertGreaterThan(pixel[0], 1)
        let bytes = try ImagePipeline.shared.jpeg(sdr, hdrImage: hdr)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
        let gainMap = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap)
            ?? CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap)
        XCTAssertNotNil(gainMap)
        #if targetEnvironment(simulator)
        throw XCTSkip("HDR gain-map decoding requires physical-device verification; iOS 27 device regression covers highlight reconstruction.")
        #else
        let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0,
            [kCGImageSourceDecodeRequest: kCGImageSourceDecodeToHDR] as CFDictionary))
        let expanded = CIImage(cgImage: cg)
        pixel.withUnsafeMutableBytes { ptr in
            ImagePipeline.shared.context.render(expanded, toBitmap: ptr.baseAddress!, rowBytes: 16,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf,
                colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)
        }
        XCTAssertGreaterThan(pixel[0], 1, "The expanded gain map must restore highlight values above SDR white.")
        #endif
    }
    func testCaptureLocationSurvivesDevelopmentAndEdits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CaptureStore(root: directory)
        var settings = DevelopmentSettings(); settings.maxLongEdge = 256
        let location = CaptureLocation(latitude: 43.65, longitude: -79.38, altitude: nil)
        let record = try store.create(original: DemoScene.data(), isRAW: false, origin: "test", recipe: settings, location: location)
        settings.exposure = -0.5
        let edited = try store.update(record, recipe: settings)
        XCTAssertEqual(store.list().first?.location, location)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(store.renderURL(edited) as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        let gps = try XCTUnwrap(properties[kCGImagePropertyGPSDictionary as String] as? [String: Any])
        XCTAssertEqual(gps[kCGImagePropertyGPSLatitude as String] as? Double, 43.65)
        XCTAssertEqual(gps[kCGImagePropertyGPSLongitudeRef as String] as? String, "W")
    }
    func testSceneDevelopmentHonorsCropAndResolution() throws {
        var settings = DevelopmentSettings(); settings.aspect = .square; settings.maxLongEdge = 512
        let image = try ImagePipeline.shared.decode(DemoScene.data(), isRAW: false, settings: settings)
        XCTAssertEqual(image.extent.width, 512, accuracy: 1)
        XCTAssertEqual(image.extent.height, 512, accuracy: 1)
        let data = try ImagePipeline.shared.jpeg(image)
        XCTAssertGreaterThan(data.count, 1000)
        XCTAssertNotNil(UIImage(data: data))
    }
    func testCaptureAndEditPreserveOriginalAndRecipe() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CaptureStore(root: directory)
        let source = DemoScene.data()
        let record = try store.create(original: source, isRAW: false, origin: "test", recipe: DevelopmentSettings())
        var settings = record.recipe; settings.look = .charcoal; settings.exposure = -1; settings.aspect = .square
        _ = try store.setFavorite(true, record: record)
        let edited = try store.update(record, recipe: settings)
        XCTAssertEqual(edited.favorite, true)
        XCTAssertEqual(try store.originalData(edited), source)
        XCTAssertEqual(store.list().first?.recipe, settings)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.renderURL(edited).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.renderURL(record).path))
        let refreshed = try store.refreshIfNeeded(record)
        XCTAssertEqual(refreshed.recipe, settings)
        XCTAssertEqual(refreshed.renderFile, edited.renderFile)
        try store.trash(edited)
        XCTAssertTrue(store.list().isEmpty)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(".Trash/\(record.id.uuidString)/\(record.originalFile)")), source)
    }
    func testFailedDevelopmentKeepsRecoverableSource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CaptureStore(root: directory)
        let source = Data([1,2,3,4])
        XCTAssertThrowsError(try store.create(original: source, isRAW: true, origin: "test", recipe: DevelopmentSettings()))
        let record = try XCTUnwrap(store.list().first)
        XCTAssertEqual(try store.originalData(record), source)
    }
    func testProcessedImageIsNeverMisclassifiedAsRAW() {
        XCTAssertFalse(ImagePipeline.isRAWData(DemoScene.data()))
        XCTAssertFalse(ImagePipeline.isRAWData(Data([1,2,3,4])))
    }
    func testAllOriginalRecipesAndEffectsRender() throws {
        for look in Look.allCases {
            var settings = DevelopmentSettings(); settings.look = look; settings.grain = 0.25
            settings.halation = 0.4; settings.microcontrast = 0.3; settings.vignette = 0.4
            settings.rotationDegrees = 7; settings.maxLongEdge = 512
            let image = try ImagePipeline.shared.decode(DemoScene.data(), isRAW: false, settings: settings)
            let bytes = try ImagePipeline.shared.jpeg(image)
            XCTAssertNotNil(UIImage(data: bytes), look.rawValue)
        }
    }
}
