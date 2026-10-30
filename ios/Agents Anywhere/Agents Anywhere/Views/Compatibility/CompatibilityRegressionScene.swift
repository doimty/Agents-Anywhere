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
    @State private var ready = false
    private var data: CompatibilityRegressionData { storage.value }

    var body: some View {
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
                    if showsTranscript, ready {
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
