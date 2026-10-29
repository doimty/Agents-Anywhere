import SwiftUI
import UniformTypeIdentifiers

struct LegacySessionView: View {
    let session: V2SessionMeta
    @EnvironmentObject private var store: LegacySessionStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsPhotos = false
    @State private var showsFiles = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if let message = store.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(message).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, LegacyStyle.gutter)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))
            }

            transcript
            Divider()
            composer
        }
        .background(AppTheme.appBackground(colorScheme).ignoresSafeArea())
        .navigationTitle(session.title ?? "会话")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 10) {
                    if store.isRealtimeConnected {
                        Circle().fill(Color.green).frame(width: 7, height: 7)
                            .accessibilityLabel("实时更新已连接")
                    }
                    Button {
                        Task { await store.reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(store.isWorking)
                    Button("中断") { Task { await store.interrupt() } }
                        .font(.footnote)
                        .disabled(!LegacyFormat.isRunning(session.status))
                }
            }
        }
        .task { await store.open(session) }
        .task { await store.pollTimeline() }
        .task { await store.realtimeSignals() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await store.refreshNow() } }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            LegacyChip(text: session.runtimeName ?? session.runtimeType ?? "Runtime",
                       color: AppTheme.secondaryText(colorScheme))
            LegacyChip(text: LegacyFormat.statusLabel(session.status),
                       color: LegacyFormat.statusColor(session.status),
                       symbol: "circle.fill")
            if let cwd = session.cwd, !cwd.isEmpty {
                Text((cwd as NSString).lastPathComponent)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LegacyStyle.gutter)
        .padding(.vertical, 8)
    }

    // MARK: - Transcript

    private var transcript: some View {
        VStack(spacing: 0) {
            if !store.actionableNotices.isEmpty {
                LegacyNoticesView(notices: store.actionableNotices)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if store.hasMoreHistory {
                            historyButton
                        }
                        ForEach(store.items.filter(\.isVisibleInChat)) { item in
                            LegacyTimelineRow(item: item, cwd: session.cwd).id(item.id)
                        }
                    }
                    .padding(.horizontal, LegacyStyle.gutter)
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
        }
    }

    private var historyButton: some View {
        Button {
            Task { await store.loadOlder() }
        } label: {
            HStack(spacing: 6) {
                if store.isLoadingOlder { ProgressView().scaleEffect(0.7) }
                Text(store.isLoadingOlder ? "正在加载…" : "加载更早的消息")
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(AppTheme.groupedFill(colorScheme), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(store.isLoadingOlder)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 6) {
            if !store.attachments.isEmpty || store.isUploading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.attachments) { reference in
                            HStack(spacing: 6) {
                                Image(systemName: "paperclip").font(.caption2)
                                Text(reference.name).font(.caption).lineLimit(1)
                                Button {
                                    store.removeAttachment(reference.fileId)
                                } label: {
                                    Image(systemName: "xmark.circle.fill").font(.caption)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.groupedFill(colorScheme), in: Capsule())
                        }
                        if store.isUploading { ProgressView().scaleEffect(0.8) }
                    }
                    .padding(.horizontal, LegacyStyle.gutter)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                HStack(alignment: .bottom, spacing: 8) {
                    Button { showsPhotos = true } label: {
                        Image(systemName: "photo.on.rectangle").font(.system(size: 17))
                    }
                    .disabled(store.isUploading)

                    Button { showsFiles = true } label: {
                        Image(systemName: "folder").font(.system(size: 17))
                    }
                    .disabled(store.isUploading)

                    TextEditor(text: $store.draft)
                        .frame(minHeight: 34, maxHeight: 110)
                        .padding(.horizontal, 4)
                        .background(Color.clear)
                }
                .foregroundColor(AppTheme.secondaryText(colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    AppTheme.groupedFill(colorScheme),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(AppTheme.secondaryControlStroke(colorScheme).opacity(0.5), lineWidth: 0.5)
                )

                Button {
                    Task { await store.sendDraft() }
                } label: {
                    ZStack {
                        Circle().fill(
                            AppTheme.primaryControlBackground(colorScheme)
                                .opacity(canSend && !store.isWorking ? 1 : 0.22)
                        )
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(AppTheme.primaryControlForeground(colorScheme))
                    }
                    .frame(width: 42, height: 42)
                }
                .disabled(!canSend || store.isWorking || store.isUploading)
                .accessibilityLabel("发送")
            }
            .padding(.horizontal, LegacyStyle.gutter)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
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

// MARK: - Rows

private struct LegacyTimelineRow: View {
    let item: V2TimelineItem
    let cwd: String?

    @State private var isExpanded = false
    @Environment(\.colorScheme) private var colorScheme

    private var entry: TimelineEntryPresentation {
        TimelineEntryPresentation(item: item, cwd: cwd)
    }

    private var hasDetails: Bool {
        item.type == .tool || item.type == .artifact
    }

    var body: some View {
        if case let .attachment(content) = item.content {
            LegacyAttachmentRow(content: content)
        } else if item.type == .tool || item.type == .artifact {
            toolRow
        } else {
            messageRow
        }
    }

    private var messageRow: some View {
        VStack(alignment: item.role == .user ? .trailing : .leading, spacing: 4) {
            HStack(spacing: 6) {
                if item.role == .user { Spacer(minLength: 0) }
                Text(LegacyFormat.speaker(for: item))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                if item.status == .failed {
                    Text("失败").font(.caption2).foregroundColor(.red)
                } else if item.status.isActive {
                    Text("进行中").font(.caption2).foregroundColor(.secondary)
                }
                if item.role != .user { Spacer(minLength: 0) }
            }

            if item.displayText.isEmpty {
                Text(LegacyFormat.placeholder(for: item))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else if item.role == .user {
                LegacyMarkdownView(text: item.displayText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        AppTheme.primaryControlBackground(colorScheme).opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .frame(maxWidth: 340, alignment: .trailing)
            } else if item.role == .assistant {
                LegacyMarkdownView(text: item.displayText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(item.displayText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: item.role == .user ? .trailing : .leading)
    }

    private var toolRow: some View {
        LegacyCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(AppTheme.primaryControlBackground(colorScheme).opacity(0.05))
                        Image(systemName: entry.symbol)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.secondaryText(colorScheme))
                    }
                    .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(isExpanded ? nil : 2)
                        if let command = entry.command, !command.isEmpty {
                            Text(command)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(isExpanded ? nil : 2)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        LegacyChip(text: item.status.label,
                                   color: item.status.isFailure ? .red : .secondary)
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
}
