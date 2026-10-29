import SwiftUI

struct LegacySessionView: View {
    let session: V2SessionMeta
    @EnvironmentObject private var store: LegacySessionStore

    var body: some View {
        VStack(spacing: 0) {
            if let message = store.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }

            if !store.actionableNotices.isEmpty {
                LegacyNoticesView(notices: store.actionableNotices)
                Divider()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if store.hasMoreHistory {
                            Button {
                                Task { await store.loadOlder() }
                            } label: {
                                HStack(spacing: 6) {
                                    if store.isLoadingOlder { ProgressView() }
                                    Text(store.isLoadingOlder ? "正在加载…" : "加载更早的消息")
                                }
                                .frame(maxWidth: .infinity)
                                .font(.footnote)
                            }
                            .disabled(store.isLoadingOlder)
                        }

                        ForEach(store.items.filter(\.isVisibleInChat)) { item in
                            LegacyTimelineRow(item: item, cwd: session.cwd).id(item.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: store.items.count) { _ in
                    guard let last = store.items.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
                .onAppear {
                    guard let last = store.items.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }

            Divider()
            composer
        }
        .navigationTitle(session.title ?? "会话")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await store.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(store.isWorking)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("中断") { Task { await store.interrupt() } }
                    .disabled(!LegacyFormat.isRunning(session.status))
            }
        }
        .task { await store.open(session) }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // `TextField(axis:)` is iOS 16; keep a real multiline editor.
            TextEditor(text: $store.draft)
                .frame(minHeight: 38, maxHeight: 110)
                .padding(6)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button {
                Task { await store.sendDraft() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
            }
            .disabled(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isWorking)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct LegacyTimelineRow: View {
    let item: V2TimelineItem
    let cwd: String?

    private var entry: TimelineEntryPresentation {
        TimelineEntryPresentation(item: item, cwd: cwd)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if item.type == .tool || item.type == .artifact {
                toolRow
            } else {
                HStack(spacing: 6) {
                    Text(LegacyFormat.speaker(for: item))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if item.status == .failed {
                        Text("失败").font(.caption2).foregroundColor(.red)
                    } else if item.status == .running || item.status == .pending {
                        Text("进行中").font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if item.displayText.isEmpty {
                    Text(LegacyFormat.placeholder(for: item))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else if item.role == .user || item.role == .assistant {
                    LegacyMarkdownView(text: item.displayText)
                } else {
                    Text(item.displayText)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(10)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var toolRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.symbol)
                .font(.caption)
                .frame(width: 18)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                if let command = entry.command, !command.isEmpty {
                    Text(command)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                if let output = entry.output, !output.isEmpty, item.status == .failed {
                    Text(output)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            Text(item.status.label)
                .font(.caption2)
                .foregroundColor(item.status.isFailure ? .red : .secondary)
        }
    }

    private var background: Color {
        switch item.role {
        case .user: return Color.accentColor.opacity(0.12)
        case .assistant: return Color(uiColor: .secondarySystemBackground)
        default: return Color(uiColor: .tertiarySystemBackground)
        }
    }
}
