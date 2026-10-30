import XCTest

final class CompatibilityUITests: XCTestCase {
    @MainActor
    func testBackportDrawerAndLongConversation() throws {
        try exerciseDrawerAndConversation(backport: true)
    }

    @MainActor
    func testNativeDrawerAndLongConversation() throws {
        try exerciseDrawerAndConversation(backport: false)
    }

    @MainActor
    private func exerciseDrawerAndConversation(backport: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.agentsanywhere.app")
        app.launchArguments = ["--compatibility-regression", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if backport {
            // Both switches are necessary. UI-only forcing would leave the
            // native ObservationRegistrar running and mask missing scopes.
            app.launchArguments += ["--force-ios15-paths", "--force-perception-backport"]
        }
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let ready = app.staticTexts["regression.ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 20), "Offline regression host did not mount")
        XCTAssertTrue(waitUntil { ready.label == "Ready" }, "Fixture failed to prepare the original transcript")

        let menu = app.buttons["chat.sidebar.open"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        let conversation = app.buttons["regression.sidebar.conversation"]
        let newSession = app.buttons["regression.sidebar.new"]

        // Each iteration must move the original detail card away, enable the
        // visible sidebar, accept a row tap, then return hit testing to detail.
        for _ in 0..<3 {
            menu.tap()
            XCTAssertTrue(waitUntil { conversation.exists && conversation.isHittable }, "Sidebar never became interactive")
            XCTAssertGreaterThanOrEqual(conversation.frame.minX, -1, "Sidebar remained visually offscreen")
            screenshot(app, name: backport ? "backport-drawer-open" : "native-drawer-open")
            newSession.tap()
            XCTAssertTrue(waitUntil { menu.exists && menu.isHittable }, "Drawer did not return hit testing to the detail")
            XCTAssertFalse(conversation.isHittable)
        }

        // The left-edge gesture and the closing pan are production features too.
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.40))
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.40)))
        XCTAssertTrue(waitUntil { conversation.exists && conversation.isHittable }, "Opening edge pan did not open the original drawer")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.40))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.40)))
        XCTAssertTrue(waitUntil { menu.exists && menu.isHittable }, "Closing pan left the drawer stuck")

        menu.tap()
        XCTAssertTrue(waitUntil { conversation.isHittable })
        conversation.tap()
        let editor = app.textViews["chat.composer.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 20), "Long transcript/composer did not finish opening")
        XCTAssertTrue(waitUntil { menu.isHittable })
        screenshot(app, name: backport ? "backport-long-conversation" : "native-long-conversation")

        // A long transcript must not block the toolbar/main thread while its
        // Markdown rows are being measured or while the reader is scrolling.
        let transcript = app.scrollViews.firstMatch
        transcript.swipeDown(velocity: .fast)
        menu.tap()
        XCTAssertTrue(waitUntil(timeout: 5) { conversation.isHittable }, "Long transcript blocked the sidebar")
        newSession.tap()
        XCTAssertTrue(waitUntil { app.buttons["regression.open-conversation"].isHittable })
        app.buttons["regression.open-conversation"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("Local regression reply")
        let send = app.buttons["chat.composer.send"]
        XCTAssertTrue(waitUntil { send.isEnabled }, "Composer did not observe the edited draft")
        send.tap()
        XCTAssertTrue(waitUntil { (editor.value as? String ?? "") != "Local regression reply" }, "Committed send did not clear the draft")
        screenshot(app, name: backport ? "backport-after-send" : "native-after-send")
        app.terminate()
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 8, _ predicate: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func screenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
