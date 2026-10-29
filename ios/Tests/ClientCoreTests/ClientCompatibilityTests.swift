import Foundation
import Perception
import SwiftUI
import Testing
@testable import ClientCore

@Suite @MainActor struct ClientCompatibilityTests {
    @Test func durationPreservesUnitsArithmeticAndSignedComponents() {
        #expect(ClientDuration.milliseconds(1000) == .seconds(1))
        #expect(ClientDuration.seconds(1) - .milliseconds(250) == .milliseconds(750))
        #expect(ClientDuration.seconds(0.24) + .seconds(0.1) == .milliseconds(340))
        #expect(ClientDuration.seconds(-1) < .zero)
        let negative = ClientDuration.seconds(-1.5)
        #expect(negative.components.seconds == -1)
        #expect(negative.components.attoseconds == -500_000_000_000_000_000)
        #expect(ClientDuration.seconds(0.000001).nanoseconds == 1000)
    }

    @Test func monotonicDeadlinesAndLateFlushesDoNotAccumulateWorkTime() {
        let start = ClientClock.now
        let next = start.advanced(by: .milliseconds(125))
        #expect(abs(start.duration(to: next).timeInterval - 0.125) < 0.000001)
        #expect(next > start && ClientClock.now >= start)
        #expect(abs((next - start).timeInterval - 0.125) < 0.000001)
        var schedule = ReplyFlushSchedule(start: start, interval: .milliseconds(200))
        let first = schedule.deadline
        schedule.advance(after: first.advanced(by: .milliseconds(4)))
        #expect(schedule.deadline == first.advanced(by: .milliseconds(200)))
        let late = start.advanced(by: .seconds(2))
        schedule.advance(after: late)
        #expect(schedule.deadline == late.advanced(by: .milliseconds(200)))
    }

    @Test func deadlineSleepDoesNotReturnBeforeTheMonotonicDeadline() async throws {
        let deadline = ClientClock.now.advanced(by: .milliseconds(15))
        try await ClientTask.sleep(until: deadline)
        #expect(ClientClock.now >= deadline)
        try await ClientTask.sleep(for: .zero)
        try await ClientTask.sleep(for: .seconds(-1))
        try await ClientTask.sleep(until: .now.advanced(by: .seconds(-1)))
    }

    @Test func sleepingTaskCancelsWithoutWaitingForItsDeadline() async throws {
        let began = ClientMutex(false)
        let worker = Task.detached {
            began.withLock { $0 = true }
            try await ClientTask.sleep(for: .seconds(60))
        }
        defer { worker.cancel() }
        try await eventually { began.withLock { $0 } }
        worker.cancel()
        await #expect(throws: CancellationError.self) { try await worker.value }
    }

    @Test func alreadyCancelledZeroAndPastSleepsStillThrow() async {
        let zero = Task { try await ClientTask.sleep(for: .zero) }
        zero.cancel()
        await #expect(throws: CancellationError.self) { try await zero.value }
        let past = Task { try await ClientTask.sleep(until: .now.advanced(by: .seconds(-1))) }
        past.cancel()
        await #expect(throws: CancellationError.self) { try await past.value }
    }

    @Test func mutexSerializesConcurrentUpdatesAndUnlocksAfterThrowing() async {
        let count = ClientMutex(0)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    for _ in 0..<250 { count.withLock { $0 += 1 } }
                }
            }
            await group.waitForAll()
        }
        #expect(count.withLock { $0 } == 4000)
        #expect(throws: LockTestError.self) {
            try count.withLock { value in
                value += 1
                throw LockTestError.expected
            }
        }
        #expect(count.withLock { $0 } == 4001)
    }

    @Test func mutableAuthenticationSurvivesTokenUpdatesWithoutReplacement() async throws {
        let provider = MutableAuthTokenProvider(token: "first")
        #expect(try await provider.accessToken() == "first")
        provider.update("second")
        #expect(try await provider.accessToken() == "second")
        provider.update(nil)
        #expect(try await provider.accessToken() == nil)
    }

    @Test func initializedPropertiesKeepDidSetAndIgnoredCountersOutOfObservation() {
        let model = InitializerProbe(value: 3)
        let changed = ClientMutex(false)
        let ignoredChanged = ClientMutex(false)
        withPerceptionTracking { _ = model.value } onChange: { changed.withLock { $0 = true } }
        withPerceptionTracking { _ = model.assignments } onChange: { ignoredChanged.withLock { $0 = true } }
        model.value = 3
        #expect(model.assignments == 1 && !changed.withLock { $0 })
        model.value = 4
        #expect(model.assignments == 2 && changed.withLock { $0 })
        #expect(!ignoredChanged.withLock { $0 })
    }

    @Test func composerFocusDoesNotInvalidateTheTextObserver() {
        let draft = ComposerDraft()
        draft.text = "Initial"
        let changed = ClientMutex(false)
        withPerceptionTracking { _ = draft.text } onChange: { changed.withLock { $0 = true } }
        draft.isFocused = true
        draft.isComposing = true
        draft.text = "Initial"
        #expect(!changed.withLock { $0 })
        draft.text += " token"
        #expect(changed.withLock { $0 })
    }

    @Test func thumbnailEntriesObserveOnlyTheirOwnCachedPreview() {
        let store = ChatAttachmentStore()
        let first = V2AttachmentContent(rawContent: .object(["fileId": .string("first")]))
        let second = V2AttachmentContent(rawContent: .object(["fileId": .string("second")]))
        let changed = ClientMutex(false)
        withPerceptionTracking { _ = store.preview(for: first) } onChange: { changed.withLock { $0 = true } }
        store.cache(Data([2]), for: second)
        #expect(!changed.withLock { $0 })
        store.cache(Data([1]), for: first)
        #expect(changed.withLock { $0 })
    }

    @Test func environmentAndBindableBackportsKeepTheSameModelReference() {
        let draft = ComposerDraft()
        @Perception.Bindable var bound = draft
        let input = $bound.text
        input.wrappedValue = "Same draft"
        #expect(bound === draft && draft.text == "Same draft")
        // Compile the non-optional/optional Environment overloads and modifier
        // at the package's iOS 15/macOS 13 deployment floor, without a second UI.
        _ = PerceptionEnvironmentProbe().environment(draft).environment(ConversationSettings())
    }

    @Test func timestampCacheKeepsValidInvalidAndFractionalParsing() {
        let plain = V2Timestamp.seconds("2024-01-02T03:04:05Z")
        let fractional = V2Timestamp.seconds("2024-01-02T03:04:05.125Z")
        #expect(plain != nil && fractional != nil)
        #expect(abs((fractional ?? 0) - (plain ?? 0) - 0.125) < 0.000001)
        #expect(V2Timestamp.seconds("not a timestamp") == nil)
        #expect(V2Timestamp.seconds("not a timestamp") == nil)
        #expect(V2Timestamp.seconds("2024-01-02T03:04:05Z") == plain)
    }

    @Test func encodedFilePathsAndLocationSuffixesKeepTheirMeaning() {
        let url = URL(string: "file:///work/My%20File%231.swift#L8C2")!
        let reference = SessionFileReference.reference(from: url)
        #expect(reference?.path == "/work/My File#1.swift")
        #expect(reference?.line == 8 && reference?.column == 2)
        #expect(SessionFileReference.reference(from: URL(string: "https://example.test/file.swift#L8")!) == nil)
    }
}

private enum LockTestError: Error { case expected }

@MainActor @Perceptible private final class InitializerProbe {
    var value: Int { didSet { assignments += 1 } }
    @PerceptionIgnored var assignments = 0
    init(value: Int) { self.value = value }
}

private struct PerceptionEnvironmentProbe: View {
    @Environment(ComposerDraft.self) private var draft
    @Environment(ConversationSettings.self) private var optionalSettings: ConversationSettings?
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var bound = draft
            TextField("Draft", text: $bound.text)
                .disabled(optionalSettings == nil)
        }
    }
}
