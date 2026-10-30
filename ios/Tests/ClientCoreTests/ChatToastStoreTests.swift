import Foundation
import Testing
@testable import ClientCore

@Suite @MainActor struct ChatToastStoreTests {
    @Test func structuredRuntimeUnavailableExplainsStatusWithoutDiscardingDetails() throws {
        let store = ChatToastStore()
        let original = "runtime instance 'example' is not running (status='starting')"
        let failure = V2ClientFailure(kind: .transient, message: original, code: "runtime_unavailable")
        store.update(source: "session", failure: failure, canRetry: true)
        let toast = try #require(store.items.first)
        #expect(toast.title == String(localized: "Agent 暂不可用"))
        #expect(toast.message.contains(String(localized: "对应设备的 Agent 尚未就绪，请查看设备页中的 Agent 状态后刷新。")))
        #expect(toast.message.contains(original))
        #expect(toast.canRetry)
    }

    @Test func errorsWithoutStructuredRuntimeCodeKeepTheirOriginalMessage() throws {
        let store = ChatToastStore()
        let original = "runtime instance 'example' is not running (status='starting')"
        store.update(source: "session", failure: V2ClientFailure(kind: .transient, message: original))
        let toast = try #require(store.items.first)
        #expect(toast.title == String(localized: "操作未完成"))
        #expect(toast.message == original)
        #expect(!toast.canRetry)
    }

    @Test func dismissalAndCustomHeadingsRemainUnchanged() throws {
        let store = ChatToastStore()
        let failure = V2ClientFailure(kind: .transient, message: "Detail", code: "runtime_unavailable")
        store.update(source: "session", failure: failure, title: "Custom", canRetry: true)
        #expect(store.items.first?.title == "Custom")
        store.dismiss("session")
        store.update(source: "session", failure: failure, canRetry: true)
        #expect(store.items.isEmpty)
        store.update(source: "session", failure: nil)
        store.update(source: "session", failure: failure, canRetry: true)
        #expect(store.items.count == 1)
    }
}
