import Foundation
import Testing
@testable import ClientCore

@Suite @MainActor struct RuntimeFailureRecoveryTests {
    private func liveResponse(_ http: TestHTTPTransport, _ call: TestHTTPTransport.Call, status: String = "running") throws -> Data {
        if call.path.hasSuffix("/state") {
            var response = try fixtureObject("state")
            var state = response["state"] as! [String: Any]
            state["status"] = status
            response["state"] = state
            return try JSONSerialization.data(withJSONObject: response)
        }
        if call.path.hasSuffix("/capabilities") {
            var response = try fixtureObject("capabilities")
            var set = response["capabilitySet"] as! [String: Any]
            let template = (set["capabilities"] as! [[String: Any]])[0]
            set["capabilities"] = ["session.send_message", "session.interrupt", "session.commands", "catalog.model", "runtime.attachment"].map { id in
                var capability = template
                capability["capabilityId"] = id
                return capability
            }
            response["capabilitySet"] = set
            return try JSONSerialization.data(withJSONObject: response)
        }
        return try http.defaultResponse(call)
    }

    private func chat(_ repo: V2SessionRepository, _ http: TestHTTPTransport) -> SessionChatModel {
        SessionChatModel(session: repo.session(id: "session"), repository: repo,
            attachments: .init(attachmentAPI: V2AttachmentAPI(transport: http)))
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test(arguments: [409, 502])
    func interruptFailureImmediatelyInvalidatesControlsAndRetainsLocalWork(status: Int) async throws {
        let http = TestHTTPTransport(), gate = TestGate()
        http.respond = { try liveResponse(http, $0) }
        let repo = repository(transport: http)
        defer { gate.release(); repo.reset() }
        let model = chat(repo, http), session = repo.session(id: "session")
        let connection = Task { await session.connect() }
        defer { connection.cancel() }
        try await eventually { session.runtime.isFresh }
        #expect(model.isRunning && session.canSend && model.canUseCommands)
        #expect(session.runtime.allows("session.interrupt"))
        let row = try #require(session.timeline.first)
        let notice = try #require(session.notices.notices.first)
        notice.fields["approve"] = ["answer": .string("Keep this answer")]
        session.draft = "Keep this draft"
        let pending = V2PendingMessage(id: "previous", content: "Unconfirmed", attachmentIDs: [])
        pending.update(.uncertain(V2ClientFailure(kind: .transient, message: "Unconfirmed")))
        session.stage(pending)
        let original = HTTPError.server(statusCode: status, message: "运行时暂不可用",
            detail: status == 409 ? .object(["code": .string("runtime_unavailable")]) : nil)
        var readFinished = false
        http.respond = { call in
            if call.path.hasSuffix("/interrupt") { throw original }
            if call.path.hasSuffix("/state") {
                await gate.wait()
                readFinished = true
                throw URLError(.cannotConnectToHost)
            }
            return try liveResponse(http, call)
        }

        // This must return while the recovery read is still blocked, retaining
        // the write's original failure instead of awaiting or reporting the read.
        await model.interrupt()
        #expect(model.error == original.localizedDescription && !model.isWorking)
        #expect(!session.runtime.isFresh && !session.canSend && !model.canUseCommands)
        #expect(!session.runtime.allows("session.interrupt") && !model.canAttach)
        #expect(!model.isRunning && model.sendingPlaceholder == nil)
        #expect(!notice.canRespond(fresh: session.runtime.isFresh))
        #expect(session.runtime.state?.status == .running, "Invalidation must not invent idle")
        #expect(repo.cached(sessionId: "session")?.liveStateIsFresh == false)
        #expect(session.timeline.first === row && session.draft == "Keep this draft")
        #expect(session.pendingMessages.first === pending)
        #expect(notice.fields["approve"]?["answer"] == .string("Keep this answer"))
        try await eventually { http.count("state") == 2 && http.count("capabilities") == 2 && http.count("notices") == 2 }
        gate.release()
        try await eventually { readFinished }
        await settle()
        await model.interrupt() // Disabled controls cannot send another write.
        _ = try await repo.load(sessionId: "session")
        #expect(!session.runtime.isFresh && !model.isRunning && session.timeline.first === row)
        #expect(model.error == original.localizedDescription)
        #expect(http.count("interrupt") == 1 && http.count("state") == 2)
        #expect(http.count("capabilities") == 2 && http.count("notices") == 2)
        #expect(http.count("snapshot") == 1)
    }

    @Test(arguments: ["idle", "running"])
    func successfulLiveRecoveryUsesTheReturnedFactWithoutReplayingTheWrite(status: String) async throws {
        let http = TestHTTPTransport(), gate = TestGate()
        http.respond = { try liveResponse(http, $0) }
        let repo = repository(transport: http)
        defer { gate.release(); repo.reset() }
        let model = chat(repo, http), session = repo.session(id: "session")
        let connection = Task { await session.connect() }
        defer { connection.cancel() }
        try await eventually { session.runtime.isFresh }
        session.draft = "Retained"
        http.respond = { call in
            if call.path.hasSuffix("/interrupt") { throw URLError(.timedOut) }
            if call.path.hasSuffix("/state") { await gate.wait() }
            return try liveResponse(http, call, status: status)
        }
        do { try await repo.interrupt(sessionId: "session"); Issue.record("Write failure was swallowed") }
        catch { #expect((error as? URLError)?.code == .timedOut) }
        #expect(!session.runtime.isFresh && !model.isRunning)
        try await eventually { http.count("state") == 2 }
        gate.release()
        try await eventually { session.runtime.isFresh }
        #expect(session.runtime.state?.status.rawValue == status)
        #expect(session.canSend && session.runtime.allows("session.interrupt"))
        #expect(model.isRunning == (status == "running"))
        #expect((model.sendingPlaceholder != nil) == (status == "running"))
        #expect(session.draft == "Retained" && http.count("interrupt") == 1)
        #expect(http.count("state") == 2 && http.count("capabilities") == 2 && http.count("notices") == 2)
        #expect(http.count("snapshot") == 1)
    }

    @Test(arguments: ["state", "capabilities", "notices"])
    func everyLiveReadMustSucceedBeforeFactsBecomeFresh(failingRead: String) async throws {
        let http = TestHTTPTransport()
        http.respond = { try liveResponse(http, $0) }
        let repo = repository(transport: http)
        defer { repo.reset() }
        let session = repo.session(id: "session"), connection = Task { await repo.session(id: "session").connect() }
        defer { connection.cancel() }
        try await eventually { session.runtime.isFresh }
        var readFailed = false
        http.respond = { call in
            if call.path.hasSuffix("/interrupt") {
                return try JSONSerialization.data(withJSONObject: ["ok": false, "error": ["code": "runtime_unavailable", "message": "Unavailable"]])
            }
            if call.path.hasSuffix("/" + failingRead) {
                readFailed = true
                throw HTTPError.server(statusCode: 503, message: "Read unavailable")
            }
            return try liveResponse(http, call, status: "idle")
        }
        do { try await repo.interrupt(sessionId: "session"); Issue.record("RPC rejection was swallowed") }
        catch { #expect((error as? V2RuntimeError)?.code == "runtime_unavailable") }
        try await eventually { readFailed }
        await settle()
        #expect(!session.runtime.isFresh && !session.canSend)
        #expect(session.runtime.state?.status == .running, "Partial reads must not replace live facts")
        #expect(session.failure?.code == "runtime_unavailable")
        #expect(http.count("interrupt") == 1 && http.count("state") == 2)
        #expect(http.count("capabilities") == 2 && http.count("notices") == 2)
    }

    @Test(arguments: ["send", "steer", "interrupt", "selection", "respond", "command", "sync"])
    func runtimeWritesShareFailureInvalidationAndPreserveTheOriginalError(operation: String) async throws {
        let http = TestHTTPTransport(), gate = TestGate()
        http.respond = { try liveResponse(http, $0) }
        let repo = repository(transport: http)
        defer { gate.release(); repo.reset() }
        let session = repo.session(id: "session"), connection = Task { await repo.session(id: "session").connect() }
        defer { connection.cancel() }
        try await eventually { session.runtime.isFresh }
        let baseline = http.calls.count
        let original = HTTPError.server(statusCode: 503, message: "Opaque failure", detail: .object(["code": .string("runtime_unavailable")]))
        http.respond = { call in
            if call.method != .get { throw original }
            if call.path.hasSuffix("/state") { await gate.wait(); throw URLError(.timedOut) }
            return try liveResponse(http, call)
        }
        do {
            switch operation {
            case "send": _ = try await repo.send(sessionId: "session", content: "Hello", clientMessageID: "client")
            case "steer": _ = try await repo.steer(sessionId: "session", content: "Hello", clientMessageID: "client")
            case "interrupt": try await repo.interrupt(sessionId: "session")
            case "selection": try await repo.setSelection(sessionId: "session", scope: .model, selectionId: "model")
            case "respond": try await repo.respond(sessionId: "session", noticeId: "notice", actionId: "approve")
            case "command": _ = try await repo.executeCommand(sessionId: "session", request: .init(command: "plan", args: [], raw: "/plan"))
            default: try await repo.sync(sessionId: "session")
            }
            Issue.record("Runtime failure was swallowed")
        } catch {
            #expect((error as? HTTPError)?.statusCode == 503)
            #expect((error as? HTTPError)?.serverCode == "runtime_unavailable")
            #expect(error.localizedDescription == original.localizedDescription)
        }
        #expect(!session.runtime.isFresh && !session.canSend)
        try await eventually { http.count("state") == 2 }
        #expect(http.calls.dropFirst(baseline).filter { $0.method != .get }.count == 1)
        #expect(http.count("snapshot") == 1)
    }

    @Test func rejectedCommandEnvelopeStillReturnsItsResultAndInvalidatesFacts() async throws {
        let http = TestHTTPTransport(), gate = TestGate()
        http.respond = { try liveResponse(http, $0) }
        let repo = repository(transport: http)
        defer { gate.release(); repo.reset() }
        let session = repo.session(id: "session"), connection = Task { await repo.session(id: "session").connect() }
        defer { connection.cancel() }
        try await eventually { session.runtime.isFresh }
        session.draft = "/plan"
        http.respond = { call in
            if call.method == .post {
                return try JSONSerialization.data(withJSONObject: ["ok": false, "code": "runtime_unavailable", "message": "Command unavailable", "serverTime": ""])
            }
            if call.path.hasSuffix("/state") { await gate.wait(); throw URLError(.timedOut) }
            return try liveResponse(http, call)
        }
        let result = try await repo.executeCommand(sessionId: "session", request: .init(command: "plan", args: [], raw: "/plan"))
        #expect(!result.ok && result.code == "runtime_unavailable")
        #expect(!session.runtime.isFresh && !session.canSend && session.draft == "/plan")
        #expect(http.calls.filter { $0.path.hasSuffix("/commands") && $0.method == .post }.count == 1)
    }

    @Test func overlappingFailuresCoalesceAndCannotTrustAReadStartedBeforeTheLastFailure() async throws {
        let http = TestHTTPTransport(), gate = TestGate()
        http.respond = { try liveResponse(http, $0) }
        let repo = repository(transport: http)
        defer { gate.release(); repo.reset() }
        let session = repo.session(id: "session"), connection = Task { await repo.session(id: "session").connect() }
        defer { connection.cancel() }
        try await eventually { session.runtime.isFresh }
        var completedReads = 0
        http.respond = { call in
            if call.method != .get { throw URLError(.networkConnectionLost) }
            await gate.wait()
            completedReads += 1
            return try liveResponse(http, call)
        }
        do { try await repo.interrupt(sessionId: "session") } catch {}
        try await eventually { http.count("state") == 2 && http.count("capabilities") == 2 && http.count("notices") == 2 }
        // These simulate other writes already in flight when controls went stale.
        do { _ = try await repo.steer(sessionId: "session", content: "Steer", clientMessageID: "steer") } catch {}
        do { try await repo.setSelection(sessionId: "session", scope: .model, selectionId: "model") } catch {}
        await settle()
        #expect(http.count("state") == 2 && http.count("capabilities") == 2 && http.count("notices") == 2)
        gate.release()
        try await eventually { completedReads == 3 }
        await settle()
        #expect(!session.runtime.isFresh && !session.canSend)
        #expect(session.runtime.state?.status == .running)
        #expect(http.count("interrupt") == 1 && http.count("steer") == 1 && http.count("selections") == 1)
        #expect(http.count("state") == 2 && http.count("capabilities") == 2 && http.count("notices") == 2)
    }

    @Test func failedSendRetainsDraftAttachmentsAndUncertainPendingWithoutReplay() async throws {
        let http = TestHTTPTransport()
        http.respond = { try liveResponse(http, $0) }
        let repo = repository(transport: http)
        defer { repo.reset() }
        let session = repo.session(id: "session"), connection = Task { await repo.session(id: "session").connect() }
        defer { connection.cancel() }
        try await eventually { session.runtime.isFresh }
        let row = try #require(session.timeline.first)
        let attachment = ChatAttachment(name: "photo.png", data: Data([1]), mediaType: "image/png", previewData: Data([2]))
        session.draft = "Keep this message"
        session.composer.attachments = [attachment]
        session.draftAttachmentIDs = ["file_uploaded"]
        http.respond = { call in
            if call.path.hasSuffix("/messages") { throw URLError(.timedOut) }
            if call.path.hasSuffix("/state") { throw URLError(.cannotConnectToHost) }
            return try liveResponse(http, call)
        }
        let pending = try #require(await session.sendDraft())
        guard case .uncertain = pending.delivery else { Issue.record("Write failure must remain uncertain"); return }
        #expect(session.pendingMessages.first === pending && pending.content == "Keep this message")
        #expect(session.draft == pending.content && session.composer.attachments == [attachment])
        #expect(session.draftAttachmentIDs == ["file_uploaded"] && pending.attachmentIDs == ["file_uploaded"])
        #expect(session.timeline.first === row && !session.runtime.isFresh)
        #expect(await session.sendDraft() == nil)
        try await eventually { http.count("state") == 2 }
        await settle()
        #expect(http.count("messages") == 1 && http.count("snapshot") == 1)
        #expect(session.pendingMessages.first === pending && session.draft == "Keep this message")
    }

    @Test func localValidationNeverInvalidatesFactsOrStartsRecovery() async throws {
        let http = TestHTTPTransport()
        http.respond = { try liveResponse(http, $0) }
        let repo = repository(transport: http)
        defer { repo.reset() }
        let session = repo.session(id: "session"), connection = Task { await repo.session(id: "session").connect() }
        defer { connection.cancel() }
        try await eventually { session.runtime.isFresh }
        let baseline = http.calls.count
        do { _ = try await repo.send(sessionId: "session", content: "  ", clientMessageID: "client"); Issue.record("Empty message was accepted") }
        catch { #expect(error is V2BusinessError) }
        do { _ = try await repo.steer(sessionId: "session", content: "Hello", attachmentIDs: Array(repeating: "file", count: 11), clientMessageID: "client"); Issue.record("Too many attachments were accepted") }
        catch { #expect(error is V2BusinessError) }
        await settle()
        #expect(session.runtime.isFresh && session.canSend && http.calls.count == baseline)
    }

    @Test func aPreFailureReconcileCannotRestoreFreshnessAfterFailureRecoveryFails() async throws {
        let http = TestHTTPTransport(), realtime = TestRealtimeAPI(), gate = TestGate()
        http.respond = { try liveResponse(http, $0) }
        let repo = repository(transport: http, realtime: realtime)
        defer { gate.release(); repo.reset() }
        let session = repo.session(id: "session"), connection = Task { await repo.session(id: "session").connect() }
        defer { connection.cancel() }
        try await eventually { session.runtime.isFresh }
        var oldReadFinished = false
        http.respond = { call in
            if call.path.hasSuffix("/state") { await gate.wait(); oldReadFinished = true }
            return try liveResponse(http, call)
        }
        realtime.yield(try event("session.refetch_required", seq: 11))
        try await eventually { http.count("state") == 2 }
        http.respond = { call in
            if call.path.hasSuffix("/interrupt") { throw URLError(.networkConnectionLost) }
            if call.path.hasSuffix("/state") { throw URLError(.cannotConnectToHost) }
            return try liveResponse(http, call)
        }
        do { try await repo.interrupt(sessionId: "session") } catch {}
        try await eventually { http.count("state") == 3 }
        gate.release()
        try await eventually { oldReadFinished }
        await settle()
        #expect(!session.runtime.isFresh && !session.canSend)
        #expect(repo.cached(sessionId: "session")?.liveStateIsFresh == false)
        #expect(http.count("interrupt") == 1)
    }

    @Test(arguments: [false, true])
    func stoppedOrResetAccountRejectsLateRecoveryEvenWhenTransportIgnoresCancellation(reset: Bool) async throws {
        let http = TestHTTPTransport(), gate = TestGate()
        http.respond = { try liveResponse(http, $0) }
        let repo = repository(transport: http)
        defer { gate.release(); repo.reset() }
        let old = repo.session(id: "session"), connection = Task { await repo.session(id: "session").connect() }
        defer { connection.cancel() }
        try await eventually { old.runtime.isFresh }
        var completedReads = 0
        http.respond = { call in
            if call.path.hasSuffix("/interrupt") { throw URLError(.timedOut) }
            await gate.wait()
            completedReads += 1
            return try liveResponse(http, call, status: "idle")
        }
        do { try await repo.interrupt(sessionId: "session") } catch {}
        try await eventually { http.count("state") == 2 && http.count("capabilities") == 2 && http.count("notices") == 2 }
        if reset { repo.reset() }
        else { repo.updateConnectivity(.init(availability: .offline)) }
        let current = repo.session(id: "session")
        current.draft = "Current account draft"
        gate.release()
        try await eventually { completedReads == 3 }
        await settle()
        #expect(!old.runtime.isFresh && !current.runtime.isFresh && !current.canSend)
        #expect(current.draft == "Current account draft" && http.count("interrupt") == 1)
        if reset {
            #expect(!old.isValid && current !== old)
            #expect(current.metadata == nil && repo.cached(sessionId: "session") == nil)
        } else {
            #expect(current === old && current.connection == .offline)
            #expect(current.runtime.state?.status == .running)
        }
    }

    @Test func newerLivePushCannotBeOverwrittenByFailureRecovery() async throws {
        let http = TestHTTPTransport(), realtime = TestRealtimeAPI(), gate = TestGate()
        http.respond = { try liveResponse(http, $0) }
        let repo = repository(transport: http, realtime: realtime)
        defer { gate.release(); repo.reset() }
        let session = repo.session(id: "session"), connection = Task { await repo.session(id: "session").connect() }
        defer { connection.cancel() }
        try await eventually { session.runtime.isFresh }
        var oldReadFinished = false
        http.respond = { call in
            if call.path.hasSuffix("/interrupt") { throw URLError(.timedOut) }
            if call.path.hasSuffix("/state") { await gate.wait(); oldReadFinished = true }
            return try liveResponse(http, call)
        }
        do { try await repo.interrupt(sessionId: "session") } catch {}
        try await eventually { http.count("state") == 2 }
        var state = try fixtureObject("state")["state"] as! [String: Any]
        state["status"] = "idle"
        realtime.yield(try event("runtime.state.updated", seq: 11, payload: ["state": state]))
        try await eventually { session.runtime.state?.status == .idle }
        #expect(!session.runtime.isFresh, "A partial live push cannot restore freshness")
        gate.release()
        try await eventually { oldReadFinished }
        await settle()
        #expect(session.runtime.state?.status == .idle && !session.runtime.isFresh && !session.canSend)
        #expect(http.count("state") == 2 && http.count("interrupt") == 1)
    }

    @Test(arguments: [false, true])
    func newerSuccessfulReadWinsOverAnOlderFailureRecoveryRead(oldReadFails: Bool) async throws {
        let http = TestHTTPTransport(), realtime = TestRealtimeAPI(), gate = TestGate()
        http.respond = { try liveResponse(http, $0) }
        let repo = repository(transport: http, realtime: realtime)
        defer { gate.release(); repo.reset() }
        let session = repo.session(id: "session"), connection = Task { await repo.session(id: "session").connect() }
        defer { connection.cancel() }
        try await eventually { session.runtime.isFresh }
        var oldReadFinished = false
        http.respond = { call in
            if call.path.hasSuffix("/interrupt") { throw URLError(.timedOut) }
            if call.path.hasSuffix("/state") {
                await gate.wait()
                oldReadFinished = true
                if oldReadFails { throw URLError(.cannotConnectToHost) }
            }
            return try liveResponse(http, call)
        }
        do { try await repo.interrupt(sessionId: "session") } catch {}
        try await eventually { http.count("state") == 2 }
        http.respond = { try liveResponse(http, $0, status: "idle") }
        realtime.yield(try event("session.refetch_required", seq: 11))
        try await eventually { http.count("state") == 3 && session.runtime.isFresh }
        #expect(session.runtime.state?.status == .idle)
        gate.release()
        try await eventually { oldReadFinished }
        await settle()
        #expect(session.runtime.isFresh && session.canSend && session.runtime.state?.status == .idle)
        #expect(http.count("interrupt") == 1 && http.count("state") == 3)
    }

    @Test func lateWriteFailureCannotInvalidateOrRecoverANewAccountEntry() async throws {
        let http = TestHTTPTransport(), gate = TestGate()
        http.respond = { try liveResponse(http, $0) }
        let repo = repository(transport: http)
        defer { gate.release(); repo.reset() }
        let old = repo.session(id: "session"), connection = Task { await repo.session(id: "session").connect() }
        defer { connection.cancel() }
        try await eventually { old.runtime.isFresh }
        http.respond = { call in
            if call.path.hasSuffix("/interrupt") { await gate.wait(); throw URLError(.timedOut) }
            return try liveResponse(http, call)
        }
        let write = Task { () -> Error? in
            do { try await repo.interrupt(sessionId: "session"); return nil }
            catch { return error }
        }
        try await eventually { http.count("interrupt") == 1 }
        repo.reset()
        let current = repo.session(id: "session")
        current.draft = "New account"
        gate.release()
        let failure = await write.value
        #expect((failure as? URLError)?.code == .timedOut)
        await settle()
        #expect(!old.isValid && current.metadata == nil && current.failure == nil)
        #expect(current.draft == "New account" && repo.cached(sessionId: "session") == nil)
        #expect(http.count("state") == 1 && http.count("interrupt") == 1)
    }
}
