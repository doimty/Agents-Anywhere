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
    @Published var draft = ""
    @Published private(set) var accountLabel = ""
    @Published private(set) var connectors: [V2Connector] = []
    @Published private(set) var sessions: [V2SessionMeta] = []
    @Published private(set) var items: [V2TimelineItem] = []
    @Published private(set) var notices: [V2RuntimeNotice] = []
    @Published private(set) var respondingNoticeID: V2NoticeID?
    @Published private(set) var selectedSession: V2SessionMeta?
    @Published private(set) var hasMoreHistory = false
    @Published private(set) var isLoadingOlder = false
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?

    private let keychain = KeychainStore()
    private var client: V2APIClient?
    private var token: String?

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
        guard let client else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            async let timeline = client.sessions.latestTimeline(sessionId: session.id, limit: 80)
            async let notices = client.runtime.notices(sessionId: session.id)
            let (page, snapshot) = try await (timeline, notices)
            items = page.items.sorted { LegacySort.timelinePrecedes($0, $1) }
            hasMoreHistory = page.hasMore
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

    func sendDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let client, let session = selectedSession, !isWorking else { return }
        draft = ""
        isWorking = true
        defer { isWorking = false }
        do {
            let request = V2RuntimeMessageSendRequest(
                content: text,
                attachments: [],
                clientMessageId: UUID().uuidString
            )
            _ = try await client.runtime.sendMessage(sessionId: session.id, request: request).requireSuccess()
            await open(session)
        } catch {
            // The draft is the only copy of the user's text; put it back.
            draft = text
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
