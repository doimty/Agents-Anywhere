import SwiftUI
import UniformTypeIdentifiers

struct LegacySessionView: View {
    let session: V2SessionMeta
    @EnvironmentObject private var store: LegacySessionStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsPhotos = false
    @State private var showsFiles = false

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
                if store.isRealtimeConnected {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                        .accessibilityLabel("实时更新已连接")
                }
            }
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
        .task { await store.pollTimeline() }
        .task { await store.realtimeSignals() }
        .onChange(of: scenePhase) { phase in
            // Returning from the background should not wait for the next tick.
            if phase == .active { Task { await store.refreshNow() } }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if !store.attachments.isEmpty || store.isUploading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.attachments) { reference in
                            HStack(spacing: 6) {
                                Image(systemName: "paperclip")
                                Text(reference.name).lineLimit(1)
                                Button {
                                    store.removeAttachment(reference.fileId)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .clipShape(Capsule())
                        }
                        if store.isUploading {
                            ProgressView().scaleEffect(0.8)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button { showsPhotos = true } label: {
                    Image(systemName: "photo.on.rectangle").font(.system(size: 22))
                }
                .disabled(store.isUploading)

                Button { showsFiles = true } label: {
                    Image(systemName: "folder").font(.system(size: 22))
                }
                .disabled(store.isUploading)

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
                .disabled(!canSend || store.isWorking || store.isUploading)
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showsPhotos) {
            LegacyPhotoPicker(selectionLimit: 5) { files in
                showsPhotos = false
                Task { await store.upload(files) }
            } onCancel: {
                showsPhotos = false
            }
        }
        .fileImporter(
            isPresented: $showsFiles,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                guard !urls.isEmpty else { return }
                var files: [LegacyPickedFile] = []
                for url in urls.prefix(5) {
                    do {
                        files.append(try LegacyPickedFile.from(url: url))
                    } catch {
                        store.report(error.localizedDescription)
                    }
                }
                guard !files.isEmpty else { return }
                Task { await store.upload(files) }
            case .failure(let error):
                store.report(error.localizedDescription)
            }
        }
    }

    private var canSend: Bool {
        !store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.attachments.isEmpty
    }
}

private struct LegacyTimelineRow: View {
    let item: V2TimelineItem
    let cwd: String?

    @State private var isExpanded = false

    private var entry: TimelineEntryPresentation {
        TimelineEntryPresentation(item: item, cwd: cwd)
    }

    private var hasDetails: Bool {
        item.type == .tool || item.type == .artifact
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: entry.symbol)
                    .font(.caption)
                    .frame(width: 18)
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(isExpanded ? nil : 2)
                    if let command = entry.command, !command.isEmpty {
                        Text(command)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(isExpanded ? nil : 3)
                    }
                    if !isExpanded, let output = entry.output, !output.isEmpty, item.status == .failed {
                        Text(output)
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.status.label)
                        .font(.caption2)
                        .foregroundColor(item.status.isFailure ? .red : .secondary)
                    if hasDetails {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            if isExpanded {
                expandedDetails
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard hasDetails else { return }
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
        }
    }

    @ViewBuilder
    private var expandedDetails: some View {
        let changes = entry.changes
        if !changes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(changes) { change in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(change.action.label) \(change.displayPath)")
                            .font(.caption.weight(.medium))
                        if let diff = change.diff {
                            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                                Text(diff)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 180)
                        }
                    }
                }
            }
            .padding(.top, 2)
        }
        if let output = entry.output, !output.isEmpty {
            ScrollView([.vertical], showsIndicators: true) {
                Text(output)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)
            .padding(8)
            .background(Color(uiColor: .tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
