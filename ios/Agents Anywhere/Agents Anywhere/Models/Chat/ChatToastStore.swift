import Foundation
import Perception

struct ChatToast: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String
    let canRetry: Bool
}

/// One current issue per source. Dismissing an issue does not change connection
/// facts or enable writes, and repeated identical observations do not reopen it.
@MainActor @Perceptible final class ChatToastStore {
    private(set) var items: [ChatToast] = []
    private var latest: [String: V2ClientFailure] = [:]

    func update(source: String, failure: V2ClientFailure?, title: String? = nil, canRetry: Bool = false) {
        guard latest[source] != failure else { return }
        latest[source] = failure
        items.removeAll { $0.id == source }
        guard let failure, failure.kind != .cancelled else { return }
        let heading: String
        let message: String
        if failure.code == "runtime_unavailable" {
            heading = String(localized: "Agent 暂不可用")
            // This code covers starting, stopped and other unavailable states.
            // Keep the original detail and never infer the cause from its text.
            message = String(localized: "对应设备的 Agent 尚未就绪，请查看设备页中的 Agent 状态后刷新。") + "\n\n" + failure.message
        } else {
            switch failure.kind {
            case .invalidResponse: heading = String(localized: "会话数据格式不兼容")
            case .authentication: heading = String(localized: "登录状态需要验证")
            case .offline: heading = String(localized: "网络已断开")
            default: heading = String(localized: "操作未完成")
            }
            message = failure.message
        }
        items.append(ChatToast(id: source, title: title ?? heading, message: message, canRetry: canRetry))
    }
    func dismiss(_ id: String) { items.removeAll { $0.id == id } }
}
