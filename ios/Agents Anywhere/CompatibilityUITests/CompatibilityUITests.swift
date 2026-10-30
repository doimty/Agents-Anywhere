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
    func testBackportEdgeAndClosingPan() throws {
        try exerciseGestures(backport: true)
    }

    @MainActor
    func testNativeEdgeAndClosingPan() throws {
        try exerciseGestures(backport: false)
    }

    @MainActor
    private func exerciseGestures(backport: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.agentsanywhere.app")
        app.launchArguments = ["--compatibility-regression", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if backport { app.launchArguments += ["--force-ios15-paths", "--force-perception-backport"] }
        app.launch()
        XCTAssertTrue(app.staticTexts["regression.ready"].waitForExistence(timeout: 20))
        let menu = app.buttons["chat.sidebar.open"]
        let conversation = app.buttons["regression.sidebar.conversation"]
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.40))
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.40)))
        let opened = waitUntil { conversation.exists && conversation.isHittable }
        if !opened { recordFailure(app, name: "opening-pan") }
        XCTAssertTrue(opened, "Opening edge pan did not open the original drawer")
        screenshot(app, name: backport ? "backport-edge-open" : "native-edge-open")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.40))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.40)))
        XCTAssertTrue(waitUntil { menu.exists && menu.isHittable }, "Closing pan left the drawer stuck")
        app.terminate()
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

        // Gesture assertions run independently, so a failing recognizer cannot
        // prevent long-conversation and composer regression from executing.

        menu.tap()
        XCTAssertTrue(waitUntil { conversation.isHittable })
        conversation.tap()
        let editor = app.textViews["chat.composer.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 20), "Long transcript/composer did not finish opening")
        let detailReady = waitUntil { menu.isHittable }
        if !detailReady { recordFailure(app, name: "after-conversation-navigation") }
        XCTAssertTrue(detailReady, "Drawer did not release the newly selected conversation")
        screenshot(app, name: backport ? "backport-long-conversation" : "native-long-conversation")

        // A long transcript must not block the toolbar/main thread while its
        // Markdown rows are being measured or while the reader is scrolling.
        let transcript = app.scrollViews["chat.timeline.scroll"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 5))
        transcript.swipeDown(velocity: .fast)
        menu.tap()
        let responsive = waitUntil(timeout: 5) { conversation.isHittable }
        if !responsive { recordFailure(app, name: "long-conversation-sidebar") }
        XCTAssertTrue(responsive, "Long transcript blocked the sidebar")
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
    private func recordFailure(_ app: XCUIApplication, name: String) {
        screenshot(app, name: name)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + "-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    @MainActor
    private func screenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
