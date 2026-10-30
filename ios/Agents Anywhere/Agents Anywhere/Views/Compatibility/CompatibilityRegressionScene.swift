#if DEBUG
import Foundation
import SwiftUI
import Perception

/// Offline UI regression entry point. Uses the production drawer, toolbar,
/// transcript and composer; never reads credentials or contacts a real server.
struct CompatibilityRegressionScene: View {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--compatibility-regression")
    }

    @StateObject private var storage = StableViewModel { CompatibilityRegressionData() }
    @State private var isSidebarOpen = false
    @State private var showsTranscript = false
    @State private var transcriptMounted = false
    @State private var ready = false
    private var data: CompatibilityRegressionData { storage.value }

    @ViewBuilder
    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("--compatibility-production-session") {
            CompatibilitySessionOpeningScene()
        } else {
            existingScene
        }
    }

    private var existingScene: some View {
        SidebarDrawer(isOpen: $isSidebarOpen, presentation: .drawer, configuration: .chat) { _ in
            ChatSidebarHeaderView()
        } sidebar: { insets in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        showsTranscript = true
                        isSidebarOpen = false
                    } label: {
                        Label("Long conversation", systemImage: "bubble.left.and.bubble.right")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("regression.sidebar.conversation")
                    Button {
                        showsTranscript = false
                        isSidebarOpen = false
                    } label: {
                        Label("New session", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("regression.sidebar.new")
                }
                .padding(.horizontal, 18)
                .padding(.bottom, insets.bottom)
            }
        } content: { insets in
            AppObservationTracking {
                Group {
                    if showsTranscript, ready, transcriptMounted {
                        ChatTimelineView(model: data.chat, onAttachment: { _ in }, onFile: { _ in })
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                AppObservationTracking {
                                    ChatComposerDock(draft: data.chat.session.composer, settings: data.chat.settings,
                                        maximumEditorHeight: 160, controls: ChatControlMetrics(bodyLineHeight: 22),
                                        canSend: true, canAttach: false, canSelectModel: false,
                                        canSelectPermission: false, onSend: { text in data.append(text) })
                                }
                            }
                    } else {
                        VStack(spacing: 16) {
                            NewSessionWelcomeView(deviceName: "Regression device", agentName: "DSH",
                                onChooseTarget: {})
                            Text(ready ? "Ready" : "Loading")
                                .accessibilityIdentifier("regression.ready")
                            Button("Open long conversation") {
                                showsTranscript = true
                            }.accessibilityIdentifier("regression.open-conversation")
                        }
                        .padding(24)
                    }
                }
                .sidebarDrawerSettledTask(id: showsTranscript) { settled in
                    guard showsTranscript, !transcriptMounted, settled else { return }
                    // Same ownership and delay as SessionChatView: navigation
                    // settles before mounting the expensive transcript subtree.
                    do { try await ClientTask.sleep(for: .milliseconds(120)) } catch { return }
                    guard !Task.isCancelled else { return }
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { transcriptMounted = true }
                }
                .appOnChange(of: showsTranscript) { _, shows in
                    if !shows { transcriptMounted = false }
                }
                .modifier(ChatPageToolbar(title: showsTranscript ? "Long conversation" : "New session",
                    onMenu: { isSidebarOpen.toggle() }))
                .modifier(ChatDetailNavigation(insets: insets))
            }
        }
        .task {
            await data.chat.prepareOpening()
            ready = data.chat.isOpeningReady
        }
        .preferredColorScheme(.light)
    }
}

@MainActor
private struct CompatibilitySessionOpeningScene: View {
    @StateObject private var storage = StableViewModel { CompatibilitySessionOpeningData() }
    @State private var isSidebarOpen = false
    @State private var showsSession = false
    @Environment(\.scenePhase) private var scenePhase
    private var services: V2ClientServices { storage.value.services }

    var body: some View {
        SidebarDrawer(isOpen: $isSidebarOpen, presentation: .drawer, configuration: .chat) { _ in
            ChatSidebarHeaderView()
        } sidebar: { insets in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        if ProcessInfo.processInfo.arguments.contains("--compatibility-preobserve") {
                            storage.value.beginPreobserving()
                        }
                        showsSession = true
                        isSidebarOpen = false
                    } label: {
                        Label("Long conversation", systemImage: "bubble.left.and.bubble.right")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("regression.sidebar.conversation")
                    Button {
                        showsSession = false
                        isSidebarOpen = false
                    } label: {
                        Label("New session", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("regression.sidebar.new")
                    Text(CompatibilitySessionURLProtocol.summary)
                        .accessibilityIdentifier("regression.sidebar.requests")
                }
                .padding(.horizontal, 18)
                .padding(.bottom, insets.bottom)
            }
        } content: { insets in
            Group {
                if showsSession {
                    SessionChatView(session: services.sessionRepository.session(id: "compatibility-session"),
                        services: services, deviceName: "Regression device",
                        onMenu: { isSidebarOpen.toggle() })
                        .equatable()
                        .id("compatibility-session")
                } else {
                    VStack(spacing: 16) {
                        Text("Ready").accessibilityIdentifier("regression.ready")
                        Text(CompatibilitySessionURLProtocol.summary)
                            .accessibilityIdentifier("regression.requests")
                    }
                    .modifier(ChatPageToolbar(title: "New session", onMenu: { isSidebarOpen.toggle() }))
                }
            }
            .modifier(ChatDetailNavigation(insets: insets))
        }
        .appOnChange(of: scenePhase, initial: true) { _, phase in
            if phase == .background { services.sessionRepository.suspend() }
            else if phase == .active { services.sessionRepository.resume() }
        }
        .preferredColorScheme(.light)
    }
}

@MainActor
private final class CompatibilitySessionOpeningData {
    let services: V2ClientServices
    private var openingObserver: Task<Void, Never>?

    func beginPreobserving() {
        guard openingObserver == nil else { return }
        let repository = services.sessionRepository
        let session = repository.session(id: "compatibility-session")
        let observations = repository.observe(sessionId: session.id)
        openingObserver = Task {
            var primed = false
            for await observation in observations {
                if Task.isCancelled { return }
                guard !primed, observation.connection == .connecting, observation.data == nil else { continue }
                do {
                    // Prime only metadata/runtime before the delayed response;
                    // history and readiness still come from production loading.
                    let bytes = try CompatibilitySessionURLProtocol.snapshotData(includeHistory: false)
                    let snapshot = try JSONDecoder().decode(V2SessionSnapshot.self, from: bytes)
                    session.update(V2SessionObservation(sessionId: session.id, data: V2SessionData(snapshot: snapshot),
                        connection: .connecting, error: nil), network: .init(availability: .online))
                    CompatibilitySessionURLProtocol.recordPriming()
                    primed = true
                } catch {
                    assertionFailure("Invalid opening regression snapshot: \(error)")
                    return
                }
            }
        }
    }

    init() {
        CompatibilitySessionURLProtocol.reset()
        // Catch all hosts in this fixture, including accidental default-session requests.
        _ = URLProtocol.registerClass(CompatibilitySessionURLProtocol.self)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CompatibilitySessionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let api = V2APIClient(serverURL: URL(string: "https://regression.invalid")!,
            tokenProvider: StaticAuthTokenProvider(token: "offline-fixture"), urlSession: session)
        // A fresh scope prevents prior runs from restoring a persisted snapshot.
        services = V2ClientServices(api: api, accountID: "ui-fixture-\(UUID().uuidString)")
        services.connectivity.stop()
        services.sessionRepository.updateConnectivity(.init(availability: .online))
    }
}

nonisolated private struct CompatibilitySessionRequestCounts: Sendable {
    var snapshots = 0
    var completed = 0
    var failed = 0
    var primed = 0
    var tickets = 0
    var cancelledTickets = 0
    var unexpected = 0
}

nonisolated private final class CompatibilitySessionURLProtocol: URLProtocol, @unchecked Sendable {
    private static let counts = ClientMutex(CompatibilitySessionRequestCounts())
    private let stopped = ClientMutex(false)

    static func reset() { counts.withLock { $0 = CompatibilitySessionRequestCounts() } }
    static func recordPriming() {
        counts.withLock { if $0.completed == 0 && $0.failed == 0 { $0.primed += 1 } }
    }
    static var summary: String {
        let value = counts.withLock { $0 }
        return "snapshots=\(value.snapshots) completed=\(value.completed) failed=\(value.failed) primed=\(value.primed) tickets=\(value.tickets) cancelled=\(value.cancelledTickets) unexpected=\(value.unexpected)"
    }

    static func snapshotData(includeHistory: Bool) throws -> Data {
        var snapshot = try CompatibilityRegressionTransport.baseSnapshot()
        var timeline = snapshot["timeline"] as! [String: Any]
        timeline["items"] = includeHistory ? [try CompatibilityRegressionTransport.itemObject(order: 1,
            text: "Offline history from delayed snapshot", role: "user")] : []
        timeline["hasMore"] = false
        timeline["nextSeq"] = 1
        snapshot["timeline"] = timeline
        return try JSONSerialization.data(withJSONObject: snapshot)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let fixtureHost = url.host == "regression.invalid"
        let isSnapshot = fixtureHost && request.httpMethod == "GET"
            && url.path == "/api/v2/sessions/compatibility-session/snapshot"
        let isTicket = fixtureHost && request.httpMethod == "POST" && url.path == "/api/v2/ws-ticket"
        let snapshotAttempt = Self.counts.withLock { counts -> Int in
            if isSnapshot { counts.snapshots += 1 }
            else if isTicket { counts.tickets += 1 }
            else { counts.unexpected += 1 }
            return counts.snapshots
        }

        if isTicket {
            // Keep the live request pending so backgrounding must cancel it.
            return
        } else if isSnapshot {
            let arguments = ProcessInfo.processInfo.arguments
            let failsFirst = arguments.contains("--compatibility-fail-first-snapshot")
            let isFailure = failsFirst && snapshotAttempt == 1
            let delay: TimeInterval = arguments.contains("--compatibility-slow-snapshot") || (failsFirst && !isFailure) ? 15 : 3
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
                guard !stopped.withLock({ $0 }) else { return }
                if isFailure {
                    Self.counts.withLock { $0.failed += 1 }
                    respond(url: url, status: 404, data: Data("{}".utf8))
                    return
                }
                do {
                    let data = try Self.snapshotData(includeHistory: true)
                    Self.counts.withLock { $0.completed += 1 }
                    respond(url: url, status: 200, data: data)
                } catch {
                    client?.urlProtocol(self, didFailWithError: error)
                }
            }
        } else {
            // Do not issue a real websocket ticket (or any other network request).
            respond(url: url, status: 404, data: Data("{}".utf8))
        }
    }

    override func stopLoading() {
        let wasStopped = stopped.withLock { value in
            let previous = value
            value = true
            return previous
        }
        if !wasStopped, request.url?.host == "regression.invalid",
           request.url?.path == "/api/v2/ws-ticket", request.httpMethod == "POST" {
            Self.counts.withLock { $0.cancelledTickets += 1 }
        }
    }

    private func respond(url: URL, status: Int, data: Data) {
        guard !stopped.withLock({ $0 }),
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
private final class CompatibilityRegressionData {
    let chat: SessionChatModel
    private let transport: CompatibilityRegressionTransport
    private let repository: V2SessionRepository

    init() {
        transport = CompatibilityRegressionTransport()
        let runtime = V2RuntimeAPI(transport: transport)
        let scope = V2ClientScope(serverURL: URL(string: "https://regression.invalid/api/v2")!, accountID: "ui-fixture")
        repository = V2SessionRepository(scope: scope,
            detail: V2SessionDetailService(sessionAPI: V2SessionAPI(transport: transport), runtimeAPI: runtime,
                realtimeAPI: CompatibilityRegressionRealtime()),
            interactions: V2RuntimeInteractionService(runtimeAPI: runtime))
        chat = SessionChatModel(session: repository.session(id: "compatibility-session"), repository: repository,
            attachments: V2AttachmentService(attachmentAPI: V2AttachmentAPI(transport: transport)))
    }

    func append(_ text: String) {
        do {
            let row = try CompatibilityRegressionTransport.item(order: chat.timeline.rows.count + 1,
                text: text, role: "user")
            chat.session.composer.clear()
            chat.timeline.presentOpening(chat.timeline.rows.map(\.value) + [row], pendingMessages: [])
        } catch {
            assertionFailure("Invalid regression item: \(error)")
        }
    }
}

nonisolated private struct CompatibilityRegressionTransport: HTTPTransport {
    func send<Body: Encodable, Response: Decodable>(_ request: HTTPRequest<Body, Response>) async throws -> Response {
        let response: [String: Any]
        if request.path.hasSuffix("/snapshot") {
            var value = try Self.baseSnapshot()
            var timeline = value["timeline"] as! [String: Any]
            timeline["items"] = try (1...100).map { order in
                try Self.itemObject(order: order,
                    text: "## Message \(order)\n\n" + String(repeating: "Original Markdown body 中文内容 with **emphasis**, a [link](https://example.com), and inline `code`.\n\n", count: 4),
                    role: order.isMultiple(of: 3) ? "user" : "assistant")
            }
            timeline["hasMore"] = true
            value["timeline"] = timeline
            response = value
        } else if request.path.hasSuffix("/timeline") {
            try await ClientTask.sleep(for: .milliseconds(250))
            response = ["sessionId": "compatibility-session", "items": [], "nextSeq": 100, "hasMore": false]
        } else {
            throw URLError(.unsupportedURL)
        }
        return try JSONDecoder().decode(Response.self, from: JSONSerialization.data(withJSONObject: response))
    }

    func upload<Response: Decodable>(_ request: HTTPUploadRequest<Response>) async throws -> Response {
        throw URLError(.unsupportedURL)
    }
    func download(_ url: URL) async throws -> URL { throw URLError(.unsupportedURL) }

    static func item(order: Int, text: String, role: String) throws -> V2TimelineItem {
        try JSONDecoder().decode(V2TimelineItem.self,
            from: JSONSerialization.data(withJSONObject: itemObject(order: order, text: text, role: role)))
    }
    static func itemObject(order: Int, text: String, role: String) throws -> [String: Any] {
        ["id": "compatibility-item-\(order)", "sessionId": "compatibility-session", "orderSeq": order,
         "revision": 1, "updatedSeq": order, "type": "message", "status": "done", "role": role,
         "content": ["text": text], "source": [:], "contentHash": "fixture-\(order)",
         "createdAt": "2026-10-30T00:00:00Z", "updatedAt": "2026-10-30T00:00:00Z"]
    }

    static func baseSnapshot() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(CompatibilityRegressionFixtures.snapshot.utf8)) as! [String: Any]
    }
}

nonisolated private struct CompatibilityRegressionRealtime: V2RealtimeAPIProtocol {
    func ticket(clientId: String, scope: V2RealtimeScope) async throws -> V2WebSocketTicket {
        throw URLError(.unsupportedURL)
    }
    func recover(sessionId: V2SessionID, after cursor: String) async throws -> V2EventRecoveryResponse {
        V2EventRecoveryResponse(events: [], nextCursor: cursor, snapshotRequired: false, serverTime: "")
    }
    func sessionEvents(sessionId: V2SessionID, ticket: String) throws -> AsyncThrowingStream<V2SessionEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func dashboardSnapshots(ticket: String) throws -> AsyncThrowingStream<V2DashboardSnapshot, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
#endif
