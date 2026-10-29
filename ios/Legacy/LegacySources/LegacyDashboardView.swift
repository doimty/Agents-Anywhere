import SwiftUI

struct LegacyDashboardView: View {
    @EnvironmentObject private var store: LegacySessionStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: LegacyStyle.sectionSpacing) {
                    header
                    if let message = store.errorMessage {
                        LegacyCard {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(message)
                                    .font(.footnote)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    devices
                    sessions
                    footer
                }
                .padding(.horizontal, LegacyStyle.gutter)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(AppTheme.appBackground(colorScheme).ignoresSafeArea())
            .navigationBarHidden(true)
            .overlay {
                if store.isWorking, store.sessions.isEmpty, store.connectors.isEmpty {
                    ProgressView("正在加载…")
                        .font(.footnote)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Agents Anywhere")
                    .font(.system(size: 30, weight: .bold, design: .default))
                    .foregroundColor(AppTheme.primaryText(colorScheme))
                Text(store.accountDescription)
                    .font(.footnote)
                    .foregroundColor(AppTheme.secondaryText(colorScheme))
            }
            Spacer(minLength: 0)
            Menu {
                Button {
                    Task { await store.refreshDashboard() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) {
                    store.signOut()
                } label: {
                    Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                ZStack {
                    Circle().fill(AppTheme.groupedFill(colorScheme))
                    Text(initials)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText(colorScheme))
                }
                .frame(width: 40, height: 40)
                .overlay(Circle().strokeBorder(AppTheme.secondaryControlStroke(colorScheme).opacity(0.6), lineWidth: 0.5))
            }
            .disabled(store.isWorking)
        }
    }

    private var initials: String {
        let source = store.accountDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = source.first.map(String.init) ?? "?"
        return first.uppercased()
    }

    // MARK: - Devices

    private var devices: some View {
        VStack(alignment: .leading, spacing: 10) {
            LegacySectionHeader(title: "设备", trailing: "\(store.connectors.count)")
            if store.connectors.isEmpty {
                LegacyCard {
                    LegacyEmptyState(
                        symbol: "desktopcomputer",
                        title: "还没有连接的设备",
                        message: "在电脑上安装 Desktop 或运行 Connector 后，这里会出现。"
                    )
                }
            } else {
                ForEach(store.connectors) { connector in
                    LegacyCard {
                        HStack(spacing: 12) {
                            Image(systemName: connector.connectorKind.contains("mac") ? "laptopcomputer" : "desktopcomputer")
                                .font(.system(size: 18))
                                .foregroundColor(AppTheme.secondaryText(colorScheme))
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(connector.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(AppTheme.primaryText(colorScheme))
                                if let os = connector.deviceOs, !os.isEmpty {
                                    Text(os).font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 4) {
                                LegacyChip(
                                    text: connector.status == .online ? "在线" : "离线",
                                    color: connector.status == .online ? .green : .secondary,
                                    symbol: "circle.fill"
                                )
                                if let relative = LegacyFormat.relative(connector.lastSeenAt) {
                                    Text(relative).font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sessions

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 10) {
            LegacySectionHeader(title: "会话", trailing: "\(store.sessions.count)")
            if store.sessions.isEmpty {
                LegacyCard {
                    LegacyEmptyState(
                        symbol: "bubble.left.and.bubble.right",
                        title: "还没有会话",
                        message: "在电脑上创建会话后，可以从这里查看和回复。"
                    )
                }
            } else {
                ForEach(store.sessions) { session in
                    NavigationLink {
                        LegacySessionView(session: session)
                    } label: {
                        LegacySessionCard(session: session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "iphone")
            Text("iOS 15 版 · \(versionLabel)")
        }
        .font(.caption2)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }
}

private struct LegacySessionCard: View {
    let session: V2SessionMeta
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LegacyCard {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.primaryControlBackground(colorScheme).opacity(0.06))
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.secondaryText(colorScheme))
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 6) {
                    Text(session.title ?? session.externalSessionId ?? "未命名会话")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.primaryText(colorScheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        LegacyChip(text: session.runtimeName ?? session.runtimeType ?? "Runtime",
                                   color: AppTheme.secondaryText(colorScheme))
                        LegacyChip(text: LegacyFormat.statusLabel(session.status),
                                   color: LegacyFormat.statusColor(session.status),
                                   symbol: LegacyFormat.isRunning(session.status) ? "bolt.fill" : nil)
                        if session.unread {
                            LegacyChip(text: "未读", color: .blue)
                        }
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    if let relative = LegacyFormat.relative(session.lastActivityAt ?? session.lastItemAt ?? session.sortAt ?? session.createdAt) {
                        Text(relative)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}
