import SwiftUI

struct LegacyDashboardView: View {
    @EnvironmentObject private var store: LegacySessionStore

    var body: some View {
        NavigationView {
            List {
                if let message = store.errorMessage {
                    Section {
                        Text(message).foregroundColor(.red).font(.footnote)
                    }
                }

                Section("设备") {
                    if store.connectors.isEmpty {
                        Text("还没有连接的设备。先在电脑上安装 Desktop 或运行 Connector。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    ForEach(store.connectors) { connector in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(connector.name).font(.headline)
                            Text(connector.status == .online ? "在线" : "离线")
                                .font(.caption)
                                .foregroundColor(connector.status == .online ? .green : .secondary)
                        }
                    }
                }

                Section("会话") {
                    if store.sessions.isEmpty {
                        Text("这个账号还没有会话。在电脑上创建会话后会出现在这里。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    ForEach(store.sessions) { session in
                        NavigationLink {
                            LegacySessionView(session: session)
                        } label: {
                            LegacySessionRow(session: session)
                        }
                    }
                }

                Section {
                    Button("退出登录", role: .destructive) { store.signOut() }
                } footer: {
                    Text("\(store.accountDescription) · \(versionLabel)").font(.caption)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Agents Anywhere")
            .refreshable { await store.refreshDashboard() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if store.isWorking { ProgressView() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    /// The build number makes it possible to tell which IPA is installed.
    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }
}

private struct LegacySessionRow: View {
    let session: V2SessionMeta

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(session.title ?? session.externalSessionId ?? "未命名会话")
                    .font(.body)
                    .lineLimit(1)
                if session.archived { Text("已归档").font(.caption2).foregroundColor(.secondary) }
            }
            HStack(spacing: 8) {
                Text(session.runtimeName ?? session.runtimeType ?? session.effectiveRuntimeId)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(LegacyFormat.statusLabel(session.status))
                    .font(.caption)
                    .foregroundColor(LegacyFormat.statusColor(session.status))
            }
        }
        .padding(.vertical, 2)
    }
}
