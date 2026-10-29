import SwiftUI

enum LegacyFormat {
    static func isRunning(_ status: V2RuntimeStatus) -> Bool {
        status == .running || status == .waiting || status == .waitingApproval
    }

    static func statusLabel(_ status: V2RuntimeStatus) -> String {
        switch status {
        case .idle: return String(localized: "空闲")
        case .waiting: return String(localized: "等待输入")
        case .waitingApproval: return String(localized: "等待审批")
        case .running: return String(localized: "运行中")
        case .error: return String(localized: "出错")
        }
    }

    static func statusColor(_ status: V2RuntimeStatus) -> Color {
        switch status {
        case .running: return .green
        case .waitingApproval: return .orange
        case .waiting: return .blue
        case .error: return .red
        case .idle: return .secondary
        }
    }

    static func speaker(for item: V2TimelineItem) -> String {
        switch item.role {
        case .user: return String(localized: "你")
        case .assistant: return String(localized: "Agent")
        case .tool: return String(localized: "工具")
        case .system: return String(localized: "系统")
        case .unknown, .none:
            switch item.type {
            case .tool: return String(localized: "工具")
            case .reasoning: return String(localized: "思考")
            case .marker: return String(localized: "状态")
            default: return String(localized: "记录")
            }
        }
    }

    static func placeholder(for item: V2TimelineItem) -> String {
        switch item.type {
        case .tool: return String(localized: "（工具调用）")
        case .reasoning: return String(localized: "（思考中）")
        case .turnStart: return String(localized: "（回合开始）")
        case .turnEnd: return String(localized: "（回合结束）")
        case .fileChange: return String(localized: "（文件变更）")
        case .attachment: return String(localized: "（附件）")
        case .artifact: return String(localized: "（产物）")
        case .marker, .system: return String(localized: "（状态更新）")
        case .message, .unknown: return String(localized: "（无文本内容）")
        }
    }
}
