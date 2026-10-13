import XCTest
import LucentCore
@testable import Lucent

/// Private camera samples can be staged in the built host app; they are never repository assets.
final class RAWFixtureTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: "dng") else {
            throw XCTSkip("Stage local RAW fixtures in the built host app to run device-sample regression checks.")
        }
        return try Data(contentsOf: url)
    }
    func testProRAWToneMappingPreservesHighlightDetail() throws {
        let data = try fixture("QA-ProRAW")
        let natural = try ImagePipeline.shared.decode(data, isRAW: true, settings: DevelopmentSettings(), preview: true)
        var minimal = DevelopmentSettings(); minimal.minimalRAWProcessing = true
        let stripped = try ImagePipeline.shared.decode(data, isRAW: true, settings: minimal, preview: true)
        let mapped = try XCTUnwrap(PreviewAnalysis.sample(natural, aspect: .native, analyze: true, loupe: false).analysis)
        let unmapped = try XCTUnwrap(PreviewAnalysis.sample(stripped, aspect: .native, analyze: true, loupe: false).analysis)
        XCTAssertLessThan(mapped.clippedFraction, unmapped.clippedFraction)
        XCTAssertGreaterThan(natural.extent.height, natural.extent.width)
    }
    func testBayerNegativeDevelopsInPortraitOrientation() throws {
        let data = try fixture("QA-Bayer")
        XCTAssertTrue(ImagePipeline.isRAWData(data))
        let image = try ImagePipeline.shared.decode(data, isRAW: true, settings: DevelopmentSettings(), preview: true)
        XCTAssertGreaterThan(image.extent.height, image.extent.width)
        XCTAssertNotNil(try ImagePipeline.shared.uiImage(image).cgImage)
    }
}
