import XCTest
@testable import LucentCore

final class CoreTests: XCTestCase {
    func testUnavailableRAWNeverSilentlyFallsBack() {
        let caps = CaptureCapabilities(sensorRAW: false, proRAW: false, flash: true)
        XCTAssertThrowsError(try CapturePlan(format: .sensorRAW, retainNegative: true, flash: false, capabilities: caps)) {
            XCTAssertEqual($0 as? CapturePlanError, .unsupportedSensorRAW)
        }
        XCTAssertThrowsError(try CapturePlan(format: .proRAW, retainNegative: true, flash: false, capabilities: caps))
    }
    func testNegativeRetentionAndFlashPolicy() throws {
        let caps = CaptureCapabilities(sensorRAW: true, proRAW: true, flash: false)
        let plan = try CapturePlan(format: .processed, retainNegative: true, flash: true, capabilities: caps)
        XCTAssertFalse(plan.retainNegative)
        XCTAssertFalse(plan.flash)
        XCTAssertFalse(try CapturePlan(format: .sensorRAW, retainNegative: true, flash: true, capabilities: caps).flash)
        XCTAssertTrue(try CapturePlan(format: .sensorRAW, retainNegative: true, flash: true,
                                       capabilities: CaptureCapabilities(sensorRAW: true, proRAW: false, flash: true)).flash)
        XCTAssertTrue(try CapturePlan(format: .sensorRAW, retainNegative: true, flash: false, capabilities: caps).retainNegative)
    }
    func testPaddedPreviewHistogramAndClipping() {
        let pixels: [UInt8] = [0,0,0,255, 255,255,255,255, 255,255,255,255,
                              128,128,128,255, 64,64,64,255, 255,255,255,255]
        let result = FrameAnalysis.analyzeBGRA(pixels, width: 2, height: 2, rowBytes: 12)!
        XCTAssertEqual(result.histogram.reduce(0, +), 4)
        XCTAssertEqual(result.histogram[0], 1)
        XCTAssertEqual(result.histogram[63], 1)
        XCTAssertEqual(result.histogram[32], 1)
        XCTAssertEqual(result.clippedFraction, 0.25)
        XCTAssertEqual(result.highlights, [false, true, false, false])
    }
    func testInvalidFramesAreRejected() {
        XCTAssertNil(FrameAnalysis.analyzeBGRA([], width: 0, height: 1, rowBytes: 0))
        XCTAssertNil(FrameAnalysis.analyzeBGRA([0], width: 4, height: 4, rowBytes: 16))
        XCTAssertNil(FrameAnalysis.analyzeBGRA([], width: 1, height: 1, rowBytes: Int.max))
    }
    func testWarningsCatchIndividualChannelsAndVideoWhite() {
        let pixels: [UInt8] = [0, 0, 255, 255, 235, 235, 235, 255, 120, 120, 120, 255]
        let result = FrameAnalysis.analyzeBGRA(pixels, width: 3, height: 1, rowBytes: 12)!
        XCTAssertEqual(result.highlights, [true, true, false])
        XCTAssertEqual(result.highlightChannels, [1, 7, 0])
        XCTAssertEqual(result.clippedFraction, 2.0 / 3.0)
    }
    func testPeakingFindsEdgesWithoutMarkingUniformAreas() {
        var pixels = [UInt8]()
        for _ in 0..<7 {
            for x in 0..<7 { pixels += [UInt8](repeating: x < 3 ? 0 : 255, count: 3) + [255] }
        }
        let result = FrameAnalysis.analyzeBGRA(pixels, width: 7, height: 7, rowBytes: 28)!
        XCTAssertTrue(result.edges[3 * 7 + 2])
        XCTAssertTrue(result.edges[3 * 7 + 3])
        XCTAssertFalse(result.edges[3 * 7 + 5])
    }
    func testAspectCropsStayInsideSensorInBothOrientations() {
        for aspect in AspectRatio.allCases {
            for (w, h) in [(4032.0, 3024.0), (3024.0, 4032.0)] {
                let r = aspect.crop(width: w, height: h)
                XCTAssertGreaterThanOrEqual(r.x, 0)
                XCTAssertGreaterThanOrEqual(r.y, 0)
                XCTAssertLessThanOrEqual(r.x + r.width, w + 0.001)
                XCTAssertLessThanOrEqual(r.y + r.height, h + 0.001)
                XCTAssertEqual(r.width / r.height, w > h ? aspect.landscapeRatio : aspect.portraitRatio, accuracy: 0.00001)
            }
        }
    }
    func testPriorityFeedbackDirectionAndBoundaries() {
        let limits = ExposureLimits(iso: 25...1600, duration: 0.0001...1)
        XCTAssertLessThan(limits.priorityAdjustment(current: 200, meterOffset: 1, forISO: true), 200)
        XCTAssertGreaterThan(limits.priorityAdjustment(current: 200, meterOffset: -1, forISO: true), 200)
        XCTAssertEqual(limits.priorityAdjustment(current: 1600, meterOffset: -3, forISO: true), 1600)
        XCTAssertEqual(limits.clampDuration(.nan), 0.0001)
    }
    func testLogarithmicControlsRoundTrip() {
        for fraction in stride(from: 0.0, through: 1.0, by: 0.05) {
            let value = logarithmicValue(fraction, range: 0.000125...1)
            XCTAssertEqual(logarithmicFraction(value, range: 0.000125...1), fraction, accuracy: 0.000001)
        }
        XCTAssertEqual(shutterLabel(1 / 125), "1/125")
        XCTAssertEqual(shutterLabel(2), "2.0s")
        XCTAssertEqual(shutterLabel(.infinity), "—")
    }
    func testDevelopmentRecipeRoundTrip() throws {
        var recipe = DevelopmentSettings()
        recipe.look = .ember; recipe.exposure = -1.25; recipe.aspect = .panorama
        recipe.useCustomWhiteBalance = true; recipe.rotationDegrees = 1.5
        let decoded = try JSONDecoder().decode(DevelopmentSettings.self, from: JSONEncoder().encode(recipe))
        XCTAssertEqual(decoded, recipe)
    }
    func testOldRecipesUseCalibratedRAWDevelopmentByDefault() throws {
        let encoded = try JSONEncoder().encode(DevelopmentSettings())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "minimalRAWProcessing")
        let old = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNil(try JSONDecoder().decode(DevelopmentSettings.self, from: old).minimalRAWProcessing)
    }
}
