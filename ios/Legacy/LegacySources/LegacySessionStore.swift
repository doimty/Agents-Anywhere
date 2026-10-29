import Foundation

/// Account-scoped state for the iOS 15 client.
///
/// Owns exactly one `V2APIClient` per signed-in account. Views never construct
/// transports or keep a second copy of the timeline; every mutation goes through
/// this object so sign-out can drop the client and the token together.
@MainActor
final class LegacySessionStore: ObservableObject {
    enum Phase: Equatable {
        case signedOut
        case signedIn
    }

    private enum Keys {
        static let server = "legacy.serverURL"
        static let token = "legacy.accessToken"
    }

    @Published private(set) var phase: Phase = .signedOut
    @Published var serverInput: String
    @Published var email = ""
    @Published var password = ""
    @Published var draft = "" {
        didSet { persistDraft() }
    }
    @Published private(set) var accountLabel = ""
    @Published private(set) var connectors: [V2Connector] = []
    @Published private(set) var sessions: [V2SessionMeta] = []
    @Published private(set) var items: [V2TimelineItem] = []
    @Published private(set) var notices: [V2RuntimeNotice] = []
    @Published private(set) var respondingNoticeID: V2NoticeID?
    @Published private(set) var attachments: [V2AttachmentReference] = []
    @Published private(set) var isUploading = false
    /// True while a session WebSocket is delivering “something changed” signals.
    @Published private(set) var isRealtimeConnected = false
    @Published private(set) var selectedSession: V2SessionMeta?
    @Published private(set) var hasMoreHistory = false
    @Published private(set) var isLoadingOlder = false
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?

    private let keychain = KeychainStore()
    private var client: V2APIClient?
    private var token: String?
    /// Decoded attachment bytes, keyed by file id. Images are small and the
    /// timeline re-renders on every poll, so refetching would be wasteful.
    private var imageCache: [V2AttachmentID: Data] = [:]
    /// Highest timeline sequence already applied from the server. Polling asks
    /// for changes after it, so a refresh never reloads the whole transcript.
    private var cursor = 0

    init() {
        serverInput = UserDefaults.standard.string(forKey: Keys.server) ?? ""
        if let token = try? keychain.readString(account: Keys.token), !token.isEmpty,
           let saved = UserDefaults.standard.string(forKey: Keys.server), let url = URL(string: saved) {
            adopt(serverURL: url, token: token, label: "")
            phase = .signedIn
        }
    }

    var accountDescription: String {
        accountLabel.isEmpty ? String(localized: "已登录") : accountLabel
    }

    // MARK: - Account

    func signIn() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let url = try URL.agentsServer(from: serverInput)
            let api = APIClient(serverURL: url)
            let auth = try await api.login(email: email, password: password)
            let profile = try await api.me(token: auth.accessToken)
            try keychain.saveString(auth.accessToken, account: Keys.token)
            UserDefaults.standard.set(url.absoluteString, forKey: Keys.server)
            adopt(serverURL: url, token: auth.accessToken, label: profile.accountLabel)
            password = ""
            phase = .signedIn
            await refreshDashboard()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        try? keychain.delete(account: Keys.token)
        UserDefaults.standard.removeObject(forKey: Keys.server)
        client = nil
        token = nil
        connectors = []
        sessions = []
        items = []
        selectedSession = nil
        accountLabel = ""
        phase = .signedOut
    }

    func report(_ message: String) {
        errorMessage = message
    }

    func clearError() {
        errorMessage = nil
    }

    private func adopt(serverURL: URL, token: String, label: String) {
        self.token = token
        accountLabel = label
        client = V2APIClient(serverURL: serverURL, tokenProvider: StaticAuthTokenProvider(token: token))
    }

    // MARK: - Dashboard

    func refreshDashboard() async {
        guard let client else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            async let connectors = client.connectors.listConnectors()
            async let sessions = client.sessions.listSessions(archived: false, cursor: nil)
            let (loadedConnectors, loadedSessions) = try await (connectors, sessions)
            self.connectors = loadedConnectors.connectors
            self.sessions = loadedSessions.sessions.sorted { LegacySort.sessionPrecedes($0, $1) }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Session

    func open(_ session: V2SessionMeta) async {
        selectedSession = session
        items = []
        hasMoreHistory = false
        draft = UserDefaults.standard.string(forKey: Self.draftKey(session.id)) ?? ""
        guard let client else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            async let timeline = client.sessions.latestTimeline(sessionId: session.id, limit: 80)
            async let notices = client.runtime.notices(sessionId: session.id)
            let (page, snapshot) = try await (timeline, notices)
            items = page.items.sorted { LegacySort.timelinePrecedes($0, $1) }
            hasMoreHistory = page.hasMore
            cursor = page.nextSeq
            self.notices = snapshot.notices
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() async {
        guard let session = selectedSession else { return }
        await open(session)
    }

    func loadOlder() async {
        guard let client, let session = selectedSession, let oldest = items.first, !isLoadingOlder, hasMoreHistory else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let page = try await client.sessions.timelineHistory(
                sessionId: session.id,
                beforeOrderSeq: oldest.orderSeq,
                limit: 60
            )
            let existing = Set(items.map(\.id))
            items = (page.items.filter { !existing.contains($0.id) } + items).sorted { LegacySort.timelinePrecedes($0, $1) }
            hasMoreHistory = page.hasMore
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Uploads first, then sends the message with the returned file ids. The
    /// upload is session-scoped, so it cannot happen before a session exists.
    func upload(_ files: [LegacyPickedFile]) async {
        guard let client, let session = selectedSession, !files.isEmpty, !isUploading else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            let payload = files.map {
                HTTPUploadFile(fieldName: "files", fileName: $0.name, mediaType: $0.mediaType, data: $0.data)
            }
            let response = try await client.attachments.upload(sessionId: session.id, files: payload)
            attachments.append(contentsOf: response.attachments)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeAttachment(_ fileId: V2AttachmentID) {
        attachments.removeAll { $0.fileId == fileId }
    }

    /// Downloads one attachment image. The endpoint returns base64 in JSON, so
    /// no extra caching layer is needed beyond this in-memory map.
    func loadImage(fileId: V2AttachmentID) async -> Data? {
        if let cached = imageCache[fileId] { return cached }
        guard let client, let session = selectedSession else { return nil }
        do {
            let download = try await client.attachments.download(sessionId: session.id, fileId: fileId)
            guard let data = Data(base64Encoded: download.contentBase64) else { return nil }
            imageCache[fileId] = data
            return data
        } catch {
            return nil
        }
    }

    func sendDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let outgoing = attachments
        guard (!text.isEmpty || !outgoing.isEmpty), let client, let session = selectedSession, !isWorking else { return }
        draft = ""
        attachments = []
        isWorking = true
        defer { isWorking = false }
        do {
            let request = V2RuntimeMessageSendRequest(
                content: text,
                attachments: outgoing.map { V2AttachmentSendReference(fileId: $0.fileId) },
                clientMessageId: UUID().uuidString
            )
            _ = try await client.runtime.sendMessage(sessionId: session.id, request: request).requireSuccess()
            await open(session)
        } catch {
            // The draft and attachments are the only copy of the user's input.
            draft = text
            attachments = outgoing
            errorMessage = error.localizedDescription
        }
    }

    /// Open approvals and input requests. Resolved or expired notices stay out
    /// of the composer area so the blocking card is unmistakable.
    var actionableNotices: [V2RuntimeNotice] {
        notices.filter { $0.status == .open || $0.status == .responding }
    }

    func refreshNotices() async {
        guard let client, let session = selectedSession else { return }
        do {
            notices = try await client.runtime.notices(sessionId: session.id).notices
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Sends one notice action. Actions that declare a required input are
    /// answered from the sheet as `{"text": "..."}`; the schema itself is not
    /// interpreted in this first version.
    func respond(to notice: V2RuntimeNotice, action: V2RuntimeNoticeAction, text: String?) async {
        guard let client, let session = selectedSession, respondingNoticeID == nil else { return }
        respondingNoticeID = notice.id
        defer { respondingNoticeID = nil }
        do {
            let input: JSONValue? = text.map { .object(["text": .string($0)]) }
            let request = V2RuntimeNoticeRespondRequest(actionId: action.actionId, input: input)
            _ = try await client.runtime
                .respondToNotice(sessionId: session.id, noticeId: notice.id, request: request)
                .requireSuccess()
            await refreshNotices()
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// WebSocket as a change *signal*, not a second state machine: any event
    /// triggers the same incremental `timelineChanges` pull the poller uses, so
    /// event payloads never need their own merge rules. The 3-second poller keeps
    /// running as a safety net for disconnects.
    func realtimeSignals() async {
        let clientID = "legacy-\(UUID().uuidString)"
        var backoff: UInt64 = 1_000_000_000
        while !Task.isCancelled {
            guard let client, let session = selectedSession else {
                isRealtimeConnected = false
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                continue
            }
            do {
                let ticket = try await client.realtime.ticket(clientId: clientID, scope: .session(session.id))
                let stream = try client.realtime.sessionEvents(sessionId: session.id, ticket: ticket.ticket)
                isRealtimeConnected = true
                backoff = 1_000_000_000
                var lastRefresh = Date.distantPast
                for try await event in stream {
                    _ = event
                    guard !Task.isCancelled else { break }
                    if selectedSession?.id != session.id { break }
                    // A burst (streaming reply) must not trigger a request per token.
                    if Date().timeIntervalSince(lastRefresh) > 0.4 {
                        lastRefresh = Date()
                        await refreshChanges()
                        await refreshNotices()
                    }
                }
                isRealtimeConnected = false
            } catch {
                isRealtimeConnected = false
            }
            guard !Task.isCancelled else { return }
            do { try await Task.sleep(nanoseconds: backoff) } catch { return }
            backoff = min(backoff * 2, 30_000_000_000)
        }
    }

    /// Called when the app returns to the foreground so the transcript does not
    /// wait for the next poll tick.
    func refreshNow() async {
        await refreshChanges()
        await refreshNotices()
    }

    private static func draftKey(_ sessionID: V2SessionID) -> String {
        "legacy.draft." + sessionID
    }

    /// Drafts are per session and survive relaunch. Attachments are not
    /// persisted: an uploaded file id is only valid for the current session.
    private func persistDraft() {
        guard let id = selectedSession?.id else { return }
        let key = Self.draftKey(id)
        if draft.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(draft, forKey: key)
        }
    }

    /// Near-live updates without the WebSocket event reducer: ask for timeline
    /// changes after the last applied sequence every few seconds. Transient
    /// failures stay silent so a flaky network never paints an error banner over
    /// a readable conversation; the manual refresh button still reports them.
    func pollTimeline() async {
        var tick = 0
        while !Task.isCancelled {
            do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            tick += 1
            await refreshChanges()
            if tick % 3 == 0 { await refreshNotices() }
        }
    }

    private func refreshChanges() async {
        guard let client, let session = selectedSession else { return }
        do {
            let page = try await client.sessions.timelineChanges(
                sessionId: session.id,
                afterSeq: cursor,
                limit: 100
            )
            cursor = page.nextSeq
            merge(page.items)
        } catch {
            // Polling is best-effort; the next tick retries.
        }
    }

    private func merge(_ incoming: [V2TimelineItem]) {
        guard !incoming.isEmpty else { return }
        var byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for item in incoming { byID[item.id] = item }
        items = byID.values.sorted { LegacySort.timelinePrecedes($0, $1) }
    }

    func interrupt() async {
        guard let client, let session = selectedSession else { return }
        do {
            _ = try await client.runtime.interrupt(sessionId: session.id)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum LegacySort {
    /// Ascending `orderSeq`: the timeline renders oldest first.
    static func timelinePrecedes(_ lhs: V2TimelineItem, _ rhs: V2TimelineItem) -> Bool {
        lhs.orderSeq < rhs.orderSeq
    }

    /// Most recent activity first for the dashboard list.
    static func sessionPrecedes(_ lhs: V2SessionMeta, _ rhs: V2SessionMeta) -> Bool {
        let left = lhs.lastActivityAt ?? lhs.createdAt ?? ""
        let right = rhs.lastActivityAt ?? rhs.createdAt ?? ""
        return left > right
    }
}
