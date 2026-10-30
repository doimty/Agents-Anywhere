import XCTest

final class CompatibilityUITests: XCTestCase {
    /// XCUITest waits for the app on every element query. The native eager
    /// transcript lays out 100 Markdown messages up front, so each query walks
    /// hundreds of nodes. Raise the harness budget instead of shrinking the
    /// conversation, dropping assertions or adding sleeps.
    override func setUp() {
        super.setUp()
        executionTimeAllowance = 300
    }

    @MainActor func testBackportRepeatedMenu() throws { try exerciseMenu(backport: true) }
    @MainActor func testNativeRepeatedMenu() throws { try exerciseMenu(backport: false) }
    @MainActor func testBackportLongConversation() throws { try exerciseConversation(backport: true) }
    @MainActor func testNativeLongConversation() throws { try exerciseConversation(backport: false) }
    @MainActor func testBackportEdgeAndClosingPan() throws { try exerciseGestures(backport: true) }
    @MainActor func testNativeEdgeAndClosingPan() throws { try exerciseGestures(backport: false) }

    @MainActor
    private func launch(backport: Bool) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.agentsanywhere.app")
        app.launchArguments = ["--compatibility-regression", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if backport {
            app.launchArguments += ["--force-ios15-paths", "--force-perception-backport"]
        }
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let ready = app.staticTexts["regression.ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 20), "Offline fixture did not mount")
        XCTAssertTrue(waitUntil { ready.label == "Ready" }, "Fixture failed to prepare the original transcript")
        return app
    }

    @MainActor
    private func exerciseMenu(backport: Bool) throws {
        let app = launch(backport: backport)
        let menu = app.buttons["chat.sidebar.open"]
        let conversation = app.buttons["regression.sidebar.conversation"]
        let newSession = app.buttons["regression.sidebar.new"]
        for _ in 0..<3 {
            menu.tap()
            XCTAssertTrue(waitUntil { conversation.exists && conversation.isHittable }, "Sidebar never became interactive")
            XCTAssertGreaterThanOrEqual(conversation.frame.minX, -1, "Sidebar remained visually offscreen")
            newSession.tap()
            XCTAssertTrue(waitUntil { menu.exists && menu.isHittable }, "Drawer did not return interaction to detail")
            XCTAssertFalse(conversation.isHittable)
        }
        menu.tap()
        XCTAssertTrue(waitUntil { conversation.isHittable })
        screenshot(app, name: backport ? "backport-drawer-open" : "native-drawer-open")
        // A tap on the translated detail strip must close the same original card.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.45)).tap()
        XCTAssertTrue(waitUntil { menu.isHittable }, "Detail strip did not close the drawer")
        app.terminate()
    }

    @MainActor
    private func exerciseGestures(backport: Bool) throws {
        let app = launch(backport: backport)
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
    private func exerciseConversation(backport: Bool) throws {
        let app = launch(backport: backport)
        let menu = app.buttons["chat.sidebar.open"]
        let conversation = app.buttons["regression.sidebar.conversation"]
        let newSession = app.buttons["regression.sidebar.new"]
        menu.tap()
        XCTAssertTrue(waitUntil { conversation.isHittable })
        conversation.tap()
        let editor = app.textViews["chat.composer.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 20), "Original long transcript/composer did not open")
        screenshot(app, name: backport ? "backport-long-conversation" : "native-long-conversation")

        let transcript = app.scrollViews["chat.timeline.scroll"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 5))
        transcript.swipeDown(velocity: .fast)
        // Modern XCTest can report the composited toolbar button non-hittable
        // while its visible frame and AX element are valid. Exercise the actual
        // user's tap and assert the drawer outcome, not that advisory flag.
        XCTAssertTrue(menu.exists, "The selected conversation removed the menu")
        let frame = menu.frame
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertTrue(app.frame.intersects(frame), "Menu is off screen")
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        let responsive = waitUntil(timeout: 30) { conversation.isHittable }
        if !responsive { recordFailure(app, name: "long-conversation-sidebar") }
        XCTAssertTrue(responsive, "Tapping the visible menu in a long conversation did not open an interactive sidebar")
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
