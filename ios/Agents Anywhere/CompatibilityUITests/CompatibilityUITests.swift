import XCTest

final class CompatibilityUITests: XCTestCase {
    /// XCUITest waits for the app on every element query. The native eager
    /// transcript lays out 100 Markdown messages up front, so each query walks
    /// hundreds of nodes. Raise the harness budget instead of shrinking the
    /// conversation, dropping assertions or adding sleeps.
    override func setUp() {
        super.setUp()
        executionTimeAllowance = 480
    }

    @MainActor func testBackportRepeatedMenu() throws { try exerciseMenu(backport: true) }
    @MainActor func testNativeRepeatedMenu() throws { try exerciseMenu(backport: false) }
    @MainActor func testBackportLongConversation() throws { try exerciseConversation(backport: true) }
    @MainActor func testNativeLongConversation() throws { try exerciseConversation(backport: false) }
    @MainActor func testBackportEdgeAndClosingPan() throws { try exerciseGestures(backport: true) }
    @MainActor func testNativeEdgeAndClosingPan() throws { try exerciseGestures(backport: false) }
    @MainActor func testBackportSessionOpening() throws { try exerciseSessionOpening(backport: true) }
    @MainActor func testNativeSessionOpening() throws { try exerciseSessionOpening(backport: false) }
    @MainActor func testBackportSessionCancellation() throws { try exerciseSessionCancellation(backport: true) }
    @MainActor func testNativeSessionCancellation() throws { try exerciseSessionCancellation(backport: false) }
    @MainActor func testBackportSessionErrorAndRetry() throws { try exerciseSessionErrorAndRetry(backport: true) }
    @MainActor func testNativeSessionErrorAndRetry() throws { try exerciseSessionErrorAndRetry(backport: false) }

    @MainActor
    private func launch(backport: Bool, productionSession: Bool = false, slowSnapshot: Bool = false,
                        preobserve: Bool = false, failFirstSnapshot: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.agentsanywhere.app")
        // AppState is constructed even for the offline scene. An invalid URL in
        // NSArgumentDomain makes its restore guard stop before reading Keychain.
        app.launchArguments = ["--compatibility-regression", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-agentsAnywhere.serverURL", "http://["]
        if productionSession { app.launchArguments.append("--compatibility-production-session") }
        if slowSnapshot { app.launchArguments.append("--compatibility-slow-snapshot") }
        if preobserve { app.launchArguments.append("--compatibility-preobserve") }
        if failFirstSnapshot { app.launchArguments.append("--compatibility-fail-first-snapshot") }
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
        // Every element query synchronises with the app. The native Debug build
        // lays out all 100 Markdown messages eagerly, so a single query measures
        // 5-10 s here; the legacy path answers in under a second. Use a budget
        // matched to the measured latency of each path instead of shrinking the
        // fixture, dropping assertions or adding sleeps.
        let queryBudget: TimeInterval = backport ? 8 : 60
        let menu = app.buttons["chat.sidebar.open"]
        let conversation = app.buttons["regression.sidebar.conversation"]
        let newSession = app.buttons["regression.sidebar.new"]
        menu.tap()
        XCTAssertTrue(waitUntil(timeout: queryBudget) { conversation.isHittable })
        conversation.tap()
        let editor = app.textViews["chat.composer.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: queryBudget), "Original long transcript/composer did not open")
        screenshot(app, name: backport ? "backport-long-conversation" : "native-long-conversation")

        let transcript = app.scrollViews["chat.timeline.scroll"]
        XCTAssertTrue(transcript.waitForExistence(timeout: queryBudget))
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
        XCTAssertTrue(waitUntil(timeout: queryBudget) { app.buttons["regression.open-conversation"].isHittable })
        app.buttons["regression.open-conversation"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: queryBudget))
        editor.tap()
        editor.typeText("Local regression reply")
        let send = app.buttons["chat.composer.send"]
        XCTAssertTrue(waitUntil(timeout: queryBudget) { send.isEnabled }, "Composer did not observe the edited draft")
        send.tap()
        XCTAssertTrue(waitUntil(timeout: queryBudget) { (editor.value as? String ?? "") != "Local regression reply" }, "Committed send did not clear the draft")
        screenshot(app, name: backport ? "backport-after-send" : "native-after-send")
        app.terminate()
    }

    @MainActor func testBackportSessionKeyboardAvoidance() throws { try exerciseSessionKeyboard(backport: true) }
    @MainActor func testNativeSessionKeyboardAvoidance() throws { try exerciseSessionKeyboard(backport: false) }

    @MainActor
    private func exerciseSessionKeyboard(backport: Bool) throws {
        let app = launch(backport: backport, productionSession: true)
        defer { app.terminate() }
        selectFixtureSession(app)
        let loading = app.descendants(matching: .any)["chat.opening.loading"]
        XCTAssertTrue(waitUntil(timeout: 30) { !loading.exists })
        assertFixtureHistory(app)

        let editor = app.textViews["chat.composer.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "Production composer did not appear")
        let before = editor.frame
        editor.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10), "Keyboard did not appear")
        XCTAssertTrue(waitUntil(timeout: 10) { editor.frame.minY < before.minY - 40 },
            "Composer did not move up when the keyboard appeared")
        // The field must sit just above the keyboard: not buried under it, and
        // not thrown to the middle of the screen by an oversized inset.
        XCTAssertLessThanOrEqual(editor.frame.maxY, keyboard.frame.minY + 8,
            "Composer editor is hidden behind the keyboard")
        XCTAssertGreaterThan(editor.frame.minY, keyboard.frame.minY - 420,
            "Composer editor jumped too far above the keyboard")
    }

    @MainActor
    private func exerciseSessionOpening(backport: Bool) throws {
        let app = launch(backport: backport, productionSession: true, preobserve: true)
        defer { app.terminate() }
        selectFixtureSession(app)

        let loading = app.descendants(matching: .any)["chat.opening.loading"]
        XCTAssertTrue(loading.waitForExistence(timeout: 15), "The real session opening mask was never shown")
        // No tap or other stimulus after the delayed snapshot is delivered: the
        // production overlay must observe readiness and remove itself on its own.
        XCTAssertTrue(waitUntil(timeout: 30) { !loading.exists }, "The real opening mask remained after the snapshot")
        assertFixtureHistory(app)

        openFixtureDrawer(app)
        let counts = app.staticTexts["regression.sidebar.requests"].label
        XCTAssertEqual(requestCount("snapshots", in: counts), 1, counts)
        XCTAssertEqual(requestCount("completed", in: counts), 1, counts)
        XCTAssertEqual(requestCount("primed", in: counts), 1, counts)
        XCTAssertEqual(requestCount("unexpected", in: counts), 0, counts)
    }

    @MainActor
    private func exerciseSessionErrorAndRetry(backport: Bool) throws {
        let app = launch(backport: backport, productionSession: true, failFirstSnapshot: true)
        defer { app.terminate() }
        selectFixtureSession(app)
        let loading = app.descendants(matching: .any)["chat.opening.loading"]
        XCTAssertTrue(loading.waitForExistence(timeout: 15), "The real session opening mask was never shown")

        // Let the failed snapshot alone update the production mask.
        let error = app.staticTexts["chat.opening.error"]
        let retry = app.buttons["chat.opening.retry"]
        XCTAssertTrue(error.waitForExistence(timeout: 30), "Snapshot failure did not replace the spinner with an error")
        XCTAssertTrue(retry.waitForExistence(timeout: 10), "Snapshot failure did not offer retry")
        XCTAssertFalse(error.label.isEmpty)
        XCTAssertFalse(loading.exists, "Snapshot failure left the spinner visible")
        retry.tap()
        XCTAssertTrue(loading.waitForExistence(timeout: 10), "Retry did not show loading")
        XCTAssertTrue(waitUntil(timeout: 40) { !loading.exists }, "Retry did not finish")
        assertFixtureHistory(app)

        openFixtureDrawer(app)
        let counts = app.staticTexts["regression.sidebar.requests"].label
        XCTAssertEqual(requestCount("snapshots", in: counts), 2, counts)
        XCTAssertEqual(requestCount("failed", in: counts), 1, counts)
        XCTAssertEqual(requestCount("completed", in: counts), 1, counts)
        XCTAssertEqual(requestCount("unexpected", in: counts), 0, counts)
    }

    @MainActor
    private func exerciseSessionCancellation(backport: Bool) throws {
        let app = launch(backport: backport, productionSession: true, slowSnapshot: true)
        defer { app.terminate() }
        selectFixtureSession(app)
        let loading = app.descendants(matching: .any)["chat.opening.loading"]
        XCTAssertTrue(loading.waitForExistence(timeout: 15))
        XCTAssertFalse(waitUntil(timeout: 1) { !loading.exists }, "Slow snapshot returned before cancellation")

        // Leave while the snapshot is in flight, then background and re-enter.
        // The next visit must reuse that in-flight read, not start a second one.
        openFixtureDrawer(app)
        app.buttons["regression.sidebar.new"].tap()
        let requests = app.staticTexts["regression.requests"]
        XCTAssertTrue(requests.waitForExistence(timeout: 10))
        let pending = requests.label
        XCTAssertEqual(requestCount("snapshots", in: pending), 1, pending)
        XCTAssertEqual(requestCount("completed", in: pending), 0, pending)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(waitUntil(timeout: 10) { app.state == .runningBackground || app.state == .runningBackgroundSuspended })
        app.activate()
        selectFixtureSession(app)
        XCTAssertTrue(waitUntil(timeout: 40) { !loading.exists }, "Returning did not finish the shared snapshot")
        assertFixtureHistory(app)

        // The fixture holds a live ticket open. Backgrounding the selected
        // session must cancel it without repeating the durable snapshot.
        openFixtureDrawer(app)
        let sidebarRequests = app.staticTexts["regression.sidebar.requests"]
        XCTAssertTrue(sidebarRequests.waitForExistence(timeout: 10))
        let beforeBackground = sidebarRequests.label
        XCTAssertGreaterThanOrEqual(requestCount("tickets", in: beforeBackground) ?? -1, 1, beforeBackground)
        let previousCancellations = requestCount("cancelled", in: beforeBackground) ?? -1
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(waitUntil(timeout: 10) { app.state == .runningBackground || app.state == .runningBackgroundSuspended })
        app.activate()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.45)).tap()
        openFixtureDrawer(app)
        let afterBackground = sidebarRequests.label
        XCTAssertGreaterThan(requestCount("cancelled", in: afterBackground) ?? -1,
                             previousCancellations, afterBackground)
        app.buttons["regression.sidebar.new"].tap()
        XCTAssertTrue(requests.waitForExistence(timeout: 10))
        assertSingleFixtureSnapshot(requests.label)

        for _ in 0..<2 {
            selectFixtureSession(app)
            assertFixtureHistory(app)
            openFixtureDrawer(app)
            app.buttons["regression.sidebar.new"].tap()
            XCTAssertTrue(requests.waitForExistence(timeout: 10))
            assertSingleFixtureSnapshot(requests.label)
        }
    }

    @MainActor
    private func selectFixtureSession(_ app: XCUIApplication) {
        openFixtureDrawer(app)
        let conversation = app.buttons["regression.sidebar.conversation"]
        XCTAssertTrue(waitUntil { conversation.isHittable }, "Fixture sidebar was not interactive")
        conversation.tap()
    }

    @MainActor
    private func openFixtureDrawer(_ app: XCUIApplication) {
        let menu = app.buttons["chat.sidebar.open"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        let frame = menu.frame
        XCTAssertGreaterThan(frame.width, 0)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        XCTAssertTrue(waitUntil { app.buttons["regression.sidebar.new"].isHittable }, "Fixture drawer did not open")
    }

    @MainActor
    private func assertFixtureHistory(_ app: XCUIApplication) {
        let history = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Offline history from delayed snapshot")).firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 30), "The original history text was not accessible")
        XCTAssertFalse(history.frame.isEmpty, "The original history text has no visible frame")
        XCTAssertTrue(app.frame.intersects(history.frame), "The original history text is offscreen")
    }

    private func assertSingleFixtureSnapshot(_ counts: String) {
        XCTAssertEqual(requestCount("snapshots", in: counts), 1, counts)
        XCTAssertEqual(requestCount("completed", in: counts), 1, counts)
        XCTAssertEqual(requestCount("unexpected", in: counts), 0, counts)
    }

    private func requestCount(_ key: String, in label: String) -> Int? {
        label.split(separator: " ").first { $0.hasPrefix(key + "=") }
            .flatMap { Int($0.dropFirst(key.count + 1)) }
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
