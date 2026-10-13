import XCTest
import AVFoundation
import CoreImage
import LucentCore
@testable import Lucent

final class CameraPreviewTests: XCTestCase {
    func testDiscoveryDeduplicatesAliasesAndKeepsOnePreferredFront() {
        let cameras = [LensInfo(id: "ultra", title: "Ultra", front: false),
                       LensInfo(id: "wide", title: "Wide", front: false),
                       LensInfo(id: "wide", title: "Wide", front: false),
                       LensInfo(id: "front2", title: "Front", front: true),
                       LensInfo(id: "front1", title: "Front", front: true)]
        XCTAssertEqual(LensInfo.selectable(cameras, preferredFrontID: "front1").map(\.id), ["ultra", "wide", "front1"])
        XCTAssertEqual(LensInfo.selectable(cameras, preferredFrontID: nil).filter(\.front).count, 1)
    }
    @MainActor func testNativePreviewUsesTheCaptureLayer() {
        let view = CameraPreviewUIView(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        view.layoutIfNeeded()
        XCTAssertTrue(view.previewLayer.superlayer === view.layer)
        XCTAssertEqual(view.previewLayer.frame, view.bounds)
        XCTAssertEqual(view.previewLayer.videoGravity, .resizeAspectFill)
        view.setZoom(2); view.layoutIfNeeded()
        XCTAssertEqual(view.previewLayer.frame, CGRect(x: -150, y: -200, width: 600, height: 800))
    }
    func testAnalysisRemainsSmallAndDoesNotBuildUnrequestedImages() {
        let image = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 4000, height: 3000))
        let sample = PreviewAnalysis.sample(image, aspect: .square, analyze: true, loupe: false)
        XCTAssertNil(sample.loupe)
        XCTAssertEqual(sample.analysis?.width, 192)
        XCTAssertEqual(sample.analysis?.height, 192)
        XCTAssertEqual(sample.analysis?.clippedFraction, 1)
        let disabled = PreviewAnalysis.sample(image, aspect: .native, analyze: false, loupe: false)
        XCTAssertNil(disabled.analysis); XCTAssertNil(disabled.loupe)
    }
    @MainActor func testPhotoViewerCanZoomAndCenterPortraitImages() {
        let view = PhotoScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        let image = UIImage(data: DemoScene.data())!
        view.update(image: image, inspection: false); view.layoutIfNeeded()
        XCTAssertFalse(view.panGestureRecognizer.isEnabled)
        XCTAssertEqual(view.photo.frame.width, 400, accuracy: 0.1)
        XCTAssertEqual(view.photo.center.y, 300, accuracy: 0.1)
        view.setZoomScale(3, animated: false)
        XCTAssertEqual(view.zoomScale, 3)
        XCTAssertGreaterThan(view.contentSize.width, 400)
        XCTAssertTrue(view.panGestureRecognizer.isEnabled)
        view.setZoomScale(1, animated: false)
        XCTAssertFalse(view.panGestureRecognizer.isEnabled)
    }
}
