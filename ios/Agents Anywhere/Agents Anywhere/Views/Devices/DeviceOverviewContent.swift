import Perception
import SwiftUI
import UIKit

/// Web shows six project cards and a "show all" toggle; a phone column fits four.
private let collapsedDirectoryCount = 4

struct DeviceProjectList: View {
    let projects: [V2Project]
    let canManage: Bool
    let canReadFiles: Bool
    let onCreate: () -> Void
    let onOpen: (V2Project) -> Void
    let onNewSession: (V2Project) -> Void
    let onFiles: (V2Project) -> Void
    let onEdit: (V2Project) -> Void
    let onPin: (V2Project) -> Void
    let onArchive: (V2Project) -> Void
    let onDelete: (V2Project) -> Void

    var body: some View {
        DeviceSection(String(localized: "Projects")) {
            DeviceHeaderIconButton(title: String(localized: "Create project"), symbol: "plus", action: onCreate)
                .disabled(!canManage)
        } content: {
            if projects.isEmpty {
                DeviceEmptyText(text: String(localized: "No projects yet"))
            } else {
                DeviceDirectoryGrid(items: projects) { project in
                    DeviceDirectoryCard(name: project.name, path: project.workspacePath, pinned: project.pinned,
                        openHint: String(localized: "Show project sessions"),
                        onOpen: { onOpen(project) }, onNewSession: { onNewSession(project) })
                    .contextMenu {
                        AppPageSystemButton(String(localized: "New session"), systemImage: "square.and.pencil") { onNewSession(project) }
                        AppPageSystemButton(String(localized: "Files"), systemImage: "folder") { onFiles(project) }.disabled(!canReadFiles)
                        Divider()
                        AppPageSystemButton(String(localized: "Rename project"), systemImage: "pencil") { onEdit(project) }.disabled(!canManage)
                        AppPageSystemButton(project.pinned ? String(localized: "Unpin") : String(localized: "Pin"), systemImage: "pin") { onPin(project) }.disabled(!canManage)
                        AppPageSystemButton(String(localized: "Copy path"), systemImage: "doc.on.doc") { UIPasteboard.general.string = project.workspacePath }
                        Divider()
                        AppPageSystemButton(String(localized: "Archive project sessions"), systemImage: "archivebox") { onArchive(project) }.disabled(!canManage)
                        AppPageSystemButton(String(localized: "Delete project"), systemImage: "trash", role: .destructive) { onDelete(project) }
                            .disabled(!canManage || project.sidebarSessionCounts.active + project.sidebarSessionCounts.archived > 0)
                    }
                }
            }
        }
    }
}

struct DeviceWorkspaceList: View {
    let workspaces: [WorkspaceDirectoryChoice]
    let canReadFiles: Bool
    let onBrowse: () -> Void
    let onOpen: (WorkspaceDirectoryChoice) -> Void
    let onNewSession: (WorkspaceDirectoryChoice) -> Void

    var body: some View {
        DeviceSection(String(localized: "工作目录")) {
            DeviceHeaderIconButton(title: String(localized: "选择工作目录"), symbol: "plus", action: onBrowse)
                .disabled(!canReadFiles)
        } content: {
            if workspaces.isEmpty {
                DeviceEmptyText(text: String(localized: "No workspaces yet"))
            } else {
                DeviceDirectoryGrid(items: workspaces) { workspace in
                    DeviceDirectoryCard(name: workspace.name, path: workspace.path,
                        openHint: String(localized: "Files"), canOpen: canReadFiles,
                        onOpen: { onOpen(workspace) }, onNewSession: { onNewSession(workspace) })
                    .contextMenu {
                        AppPageSystemButton(String(localized: "New session"), systemImage: "square.and.pencil") { onNewSession(workspace) }
                        AppPageSystemButton(String(localized: "Files"), systemImage: "folder") { onOpen(workspace) }.disabled(!canReadFiles)
                        AppPageSystemButton(String(localized: "Copy path"), systemImage: "doc.on.doc") { UIPasteboard.general.string = workspace.path }
                    }
                }
            }
        }
    }
}

struct DeviceHeaderIconButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AppSymbol(symbol, size: 18).frame(width: 36, height: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(title)
    }
}

/// One column on phones, two on wider layouts, collapsed to a few cards.
private struct DeviceDirectoryGrid<Item: Identifiable, Card: View>: View {
    let items: [Item]
    @ViewBuilder let card: (Item) -> Card
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 8)], spacing: 8) {
                ForEach(expanded ? items : Array(items.prefix(collapsedDirectoryCount))) { card($0) }
            }
            if items.count > collapsedDirectoryCount {
                Button { withAnimation(.appSnappy) { expanded.toggle() } } label: {
                    HStack(spacing: 4) {
                        Text(expanded ? String(localized: "Show less") :
                            String(localized: "Show all \(items.count - collapsedDirectoryCount) more"))
                        AppSymbol("chevron.right", size: 12).rotationEffect(.degrees(expanded ? -90 : 0))
                    }
                    .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                    .frame(minHeight: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct DeviceDirectoryCard: View {
    let name: String
    let path: String
    var pinned = false
    let openHint: String
    var canOpen = true
    let onOpen: () -> Void
    let onNewSession: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    AppSymbol("folder", size: 18).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if pinned { AppSymbol("pin", size: 11).foregroundStyle(.secondary) }
                        }
                        Text(path).font(.caption.monospaced()).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(!canOpen).accessibilityHint(openHint)
            Button(action: onNewSession) {
                AppSymbol("square.and.pencil", size: 18).frame(width: 40, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(String(localized: "New session"))
        }
        .padding(.leading, 14).padding(.trailing, 4).padding(.vertical, 6)
        .background(AppTheme.groupedFill(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct DeviceSessionList: View {
    @Perception.Bindable var model: DeviceManagementModel
    let projects: [V2Project]
    let showsProjectNames: Bool
    let canManage: Bool
    let isWorking: Bool
    let onNewSession: () -> Void
    let onOpen: (String) -> Void
    let onArchive: (V2SessionMeta) -> Void
    let onArchiveAll: () -> Void

    private var restores: Bool { model.sessionFilter == .archived }
    private var isEmpty: Bool { model.filteredSessions.isEmpty }

    var body: some View {
        DeviceSection(String(localized: "Sessions")) {
            HStack(spacing: 8) {
                DevicePillButton(title: model.isSelectingSessions ? String(localized: "Cancel") : String(localized: "Select sessions")) {
                    if model.isSelectingSessions { model.stopSelectingSessions() } else { model.startSelectingSessions() }
                }
                .disabled(!canManage || (isEmpty && !model.isSelectingSessions))
                if !model.isSelectingSessions {
                    DevicePillButton(title: restores ? String(localized: "Restore all in scope") : String(localized: "Archive all in scope"),
                        isLoading: isWorking, action: onArchiveAll)
                        .disabled(!canManage || isEmpty)
                    DeviceHeaderIconButton(title: String(localized: "New session"), symbol: "square.and.pencil", action: onNewSession)
                }
            }
        } content: {
            AppPageHorizontalFit {
                HStack(spacing: 8) { filters; Spacer(minLength: 8); scopeMenu }
            } vertical: {
                VStack(alignment: .leading, spacing: 8) { filters; scopeMenu }
            }
            .padding(.bottom, 4)
            if model.isSelectingSessions {
                Button(String(localized: "Select up to 200 sessions"), action: model.toggleSelectAll)
                    .font(.footnote.weight(.medium)).buttonStyle(.plain).foregroundStyle(.secondary)
                    .frame(minHeight: 32).disabled(!canManage)
            }
            if isEmpty {
                DeviceEmptyText(text: String(localized: "No sessions here"))
            } else {
                DeviceRows(model.filteredSessions) { session in row(session) }
            }
        }
    }

    private var filters: some View {
        DeviceFilterTags(values: V2DeviceSessionFilter.allCases,
            selection: Binding(get: { model.sessionFilter }, set: model.setSessionFilter)) { $0.title }
    }

    private var scopeMenu: some View {
        Menu {
            Picker(showsProjectNames ? String(localized: "Project") : String(localized: "工作目录"),
                selection: Binding(get: { model.projectID }, set: model.selectProject)) {
                Text(allScopesTitle).tag(String?.none)
                ForEach(projects) {
                    Text(showsProjectNames ? $0.name : $0.workspacePath).tag(Optional($0.id))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(scopeTitle).lineLimit(1)
                AppSymbol("chevron.down", size: 12)
            }
            .font(.subheadline).foregroundStyle(.secondary)
            .frame(minHeight: 34).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsProjectNames ? String(localized: "Project") : String(localized: "工作目录"))
    }

    private func row(_ session: V2SessionMeta) -> some View {
        Button { onOpen(session.id) } label: {
            HStack(spacing: 12) {
                if model.isSelectingSessions {
                    AppSymbol(model.selectedSessionIds.contains(session.id) ? "checkmark.circle.fill" : "circle", size: 18)
                        .foregroundStyle(model.selectedSessionIds.contains(session.id) ? .primary : .secondary)
                        .frame(width: 14)
                } else {
                    DeviceStatusDot(tone: tone(session.status))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Untitled session"))
                        .font(.body.weight(session.unread ? .semibold : .medium))
                        .foregroundStyle(.primary).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(session.runtime)
                        if let subtitle = scopeSubtitle(session) {
                            Text(verbatim: "·"); Text(subtitle).lineLimit(1)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let date = activityDate(session) {
                    Text(date, format: .dateTime.month(.abbreviated).day())
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 10).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(session.status.displayName)
        .contextMenu {
            AppPageSystemButton(String(localized: "Open"), systemImage: "arrow.up.right") { onOpen(session.id) }
            AppPageSystemButton(session.archived ? String(localized: "Restore") : String(localized: "Archive"),
                systemImage: session.archived ? "tray.and.arrow.up" : "archivebox") { onArchive(session) }
                .disabled(!canManage || session.id.hasPrefix("local:"))
            AppPageSystemButton(String(localized: "Copy session ID"), systemImage: "doc.on.doc") { UIPasteboard.general.string = session.id }
        }
    }

    /// Same colors as Web's device page session dots.
    private func tone(_ status: V2RuntimeStatus) -> DeviceStatusTone {
        switch status {
        case .running: .ok
        case .waitingApproval, .blocked: .warning
        case .error: .error
        case .waiting, .pending, .stopping: .progress
        default: .neutral
        }
    }
    private var allScopesTitle: String {
        showsProjectNames ? String(localized: "All projects") : String(localized: "All workspaces")
    }
    private var scopeTitle: String {
        guard let project = projects.first(where: { $0.id == model.projectID }) else { return allScopesTitle }
        return showsProjectNames ? project.name : ProjectWorkspacePath.name(project.workspacePath)
    }
    private func scopeSubtitle(_ session: V2SessionMeta) -> String? {
        let project = projects.first { $0.id == session.projectId }
        if showsProjectNames { return project?.name }
        return (session.cwd ?? project?.workspacePath).map(ProjectWorkspacePath.name)
    }
    private func activityDate(_ session: V2SessionMeta) -> Date? {
        V2Timestamp.date(session.sortAt ?? session.lastActivityAt ?? session.lastItemAt)
    }
}

struct DeviceSessionSelectionDock: View {
    let count: Int
    let restores: Bool
    let isWorking: Bool
    let disabled: Bool
    let onCancel: () -> Void
    let onSubmit: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Text("\(count) selected").font(.subheadline).monospacedDigit()
            Spacer(minLength: 0)
            Button(String(localized: "Cancel"), action: onCancel).disabled(isWorking)
            AppGlassButton(restores ? String(localized: "dashboard.device.unarchiveSelected") : String(localized: "dashboard.device.archiveSelected"), systemImage: restores ? "tray.and.arrow.up" : "archivebox",
                style: .prominent, isLoading: isWorking, disabled: disabled || count == 0, maxWidth: nil, action: onSubmit)
        }
        .padding(14).appGlassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 24).padding(.bottom, 12).frame(maxWidth: 760).frame(maxWidth: .infinity)
    }
}
