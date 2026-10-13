import XCTest

final class CameraFlowTests: XCTestCase {
    func testGallerySwipesPreserveEditsAndRespectZoom() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let shutter = app.buttons["shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 15))
        for _ in 0..<3 {
            expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: shutter)
            waitForExpectations(timeout: 20)
            shutter.tap()
            expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: shutter)
            waitForExpectations(timeout: 20)
        }
        app.buttons["photoLibrary"].tap()
        let shot = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'capture-'" )).firstMatch
        XCTAssertTrue(shot.waitForExistence(timeout: 10)); shot.tap()
        let close = app.buttons["closePhoto"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        func expectPosition(_ index: Int) {
            expectation(for: NSPredicate(format: "value BEGINSWITH %@", "Photograph \(index) of "), evaluatedWith: close)
            waitForExpectations(timeout: 10)
        }
        func swipe(_ left: Bool) {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.85 : 0.15, dy: 0.35))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.15 : 0.85, dy: 0.35))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        expectPosition(1)
        app.buttons["Favorite photograph"].tap()
        swipe(true); expectPosition(2)
        XCTAssertTrue(app.buttons["Favorite photograph"].exists)
        swipe(false); expectPosition(1)
        XCTAssertTrue(app.buttons["Remove favorite"].exists)
        let photoCenter = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        photoCenter.doubleTap()
        swipe(true); expectPosition(1)
        photoCenter.doubleTap()
        swipe(true); expectPosition(2)
        app.buttons["editPhoto"].tap()
        swipe(true)
        XCTAssertTrue(app.buttons["Cancel edits"].exists)
        app.buttons["lab-look-charcoal"].tap()
        app.buttons["saveEdit"].tap()
        expectation(for: NSPredicate(format: "enabled == false"), evaluatedWith: app.buttons["saveEdit"])
        waitForExpectations(timeout: 20)
        app.buttons["Cancel edits"].tap(); expectPosition(2)
        swipe(true); expectPosition(3)
        swipe(false); expectPosition(2)
        app.buttons["editPhoto"].tap()
        XCTAssertFalse(app.buttons["saveEdit"].isEnabled)
        app.buttons["Cancel edits"].tap()
        let oldPosition = close.value as? String
        app.buttons["removePhoto"].tap()
        app.buttons["confirmRemovePhoto"].firstMatch.tap()
        expectPosition(2)
        XCTAssertNotEqual(close.value as? String, oldPosition)
        swipe(false); expectPosition(1)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Swipeable photo gallery"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testCaptureDevelopAndSettings() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let shutter = app.buttons["shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 15))
        shutter.tap()
        let library = app.buttons["photoLibrary"]
        library.tap()
        XCTAssertTrue(app.navigationBars["Photographs"].waitForExistence(timeout: 10))
        let shot = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'capture-'" )).firstMatch
        XCTAssertTrue(shot.waitForExistence(timeout: 20))
        shot.tap()
        XCTAssertTrue(app.buttons["editPhoto"].waitForExistence(timeout: 10))
        app.buttons["editPhoto"].tap()
        app.buttons["lab-look-charcoal"].tap()
        let save = app.buttons["saveEdit"]
        if !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isEnabled)
        save.tap()
        let saved = NSPredicate(format: "enabled == false")
        expectation(for: saved, evaluatedWith: save)
        waitForExpectations(timeout: 20)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Photo lab"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testRecipePickerAndManualControls() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["exposureControls"].waitForExistence(timeout: 10))
        let finder = app.otherElements["viewfinder"]
        let before = finder.frame
        XCTAssertGreaterThanOrEqual(before.width, app.frame.width - 2)
        app.buttons["exposureControls"].tap()
        let modeScreenshot = XCTAttachment(screenshot: app.screenshot()); modeScreenshot.name = "Exposure mode palette"; modeScreenshot.lifetime = .keepAlways; add(modeScreenshot)
        XCTAssertTrue(app.buttons["exposure-mode-manual"].waitForExistence(timeout: 5))
        app.buttons["exposure-mode-manual"].tap()
        XCTAssertTrue(app.sliders["ISO"].waitForExistence(timeout: 5))
        XCTAssertEqual(finder.frame.height, before.height, accuracy: 1)
        XCTAssertEqual(finder.frame.width, before.width, accuracy: 1)
        app.buttons["colorRecipes"].tap()
        XCTAssertTrue(app.buttons["look-ember"].waitForExistence(timeout: 5))
        app.buttons["look-ember"].tap()
        app.buttons["Done"].tap()
        app.buttons["cameraMore"].tap()
        app.buttons["cameraSettings"].tap()
        XCTAssertTrue(app.staticTexts["SETTINGS"].waitForExistence(timeout: 5))
    }

    func testCompositionMenuAndSettingsPersistAcrossLaunch() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["gridMenu"].waitForExistence(timeout: 10))
        app.buttons["gridMenu"].tap()
        XCTAssertTrue(app.buttons["Level"].waitForExistence(timeout: 5))
        app.buttons["Level"].tap(); app.buttons["Off"].firstMatch.tap()
        app.buttons["gridMenu"].tap(); app.buttons["Golden Ratio"].firstMatch.tap()
        app.buttons["Bottom Right"].firstMatch.tap()
        app.buttons["cameraMore"].tap()
        XCTAssertTrue(app.buttons["White Balance"].exists)
        XCTAssertTrue(app.buttons["Flash"].exists)
        app.buttons["cameraSettings"].tap()
        XCTAssertTrue(app.staticTexts["SETTINGS"].waitForExistence(timeout: 5))
        let root = XCTAttachment(screenshot: app.screenshot()); root.name = "Settings root"; root.lifetime = .keepAlways; add(root)
        app.buttons["settings-Capture"].tap()
        XCTAssertTrue(app.staticTexts["CAPTURE"].waitForExistence(timeout: 5))
        app.buttons["Most Efficient (HEIC)"].tap()
        app.buttons["settingsBack"].tap(); app.buttons["settings-Looks"].tap()
        XCTAssertTrue(app.staticTexts["Film Simulation"].waitForExistence(timeout: 5))
        let looks = XCTAttachment(screenshot: app.screenshot()); looks.name = "Looks settings"; looks.lifetime = .keepAlways; add(looks)
        app.buttons["settingsBack"].tap(); app.buttons["settingsDone"].tap()
        app.terminate(); app.launch()
        app.buttons["gridMenu"].tap(); app.buttons["Golden Ratio"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Bottom Right"].firstMatch.isSelected)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.3)).tap()
        app.buttons["gridMenu"].tap(); app.buttons["Level"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Off"].firstMatch.isSelected)
    }
}
