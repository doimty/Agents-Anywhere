import SwiftUI

/// Blocking approvals and input requests, rendered above the transcription so
/// answering never requires scrolling back through the conversation.
struct LegacyNoticesView: View {
    @EnvironmentObject private var store: LegacySessionStore
    let notices: [V2RuntimeNotice]

    @State private var pending: PendingInput?

    private struct PendingInput: Identifiable {
        let id: String
        let notice: V2RuntimeNotice
        let action: V2RuntimeNoticeAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(notices) { notice in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(notice.title).font(.headline)
                        Spacer(minLength: 0)
                        if store.respondingNoticeID == notice.id {
                            ProgressView()
                        } else if notice.severity == "warning" || notice.severity == "error" {
                            Text(notice.severity == "error" ? "错误" : "警告")
                                .font(.caption2)
                                .foregroundColor(notice.severity == "error" ? .red : .orange)
                        }
                    }
                    if let message = notice.message, !message.isEmpty {
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if notice.actions.isEmpty {
                        Text("在电脑上继续处理这个请求。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 8) {
                            ForEach(notice.actions) { action in
                                Button(action.label) {
                                    begin(notice: notice, action: action)
                                }
                                .buttonStyle(.bordered)
                                .disabled(store.respondingNoticeID != nil)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .sheet(item: $pending) { item in
            LegacyNoticeInputSheet(
                notice: item.notice,
                action: item.action,
                isWorking: store.respondingNoticeID != nil
            ) { text in
                pending = nil
                Task { await store.respond(to: item.notice, action: item.action, text: text) }
            } onCancel: {
                pending = nil
            }
        }
    }

    private func begin(notice: V2RuntimeNotice, action: V2RuntimeNoticeAction) {
        if action.input.required {
            pending = PendingInput(id: notice.id + ":" + action.actionId, notice: notice, action: action)
        } else {
            Task { await store.respond(to: notice, action: action, text: nil) }
        }
    }
}

private struct LegacyNoticeInputSheet: View {
    let notice: V2RuntimeNotice
    let action: V2RuntimeNoticeAction
    let isWorking: Bool
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text(notice.title).font(.headline)
                    if let message = notice.message { Text(message).font(.footnote) }
                }
                Section("回复") {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle(action.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送") { onSubmit(text) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
