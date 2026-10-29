import SwiftUI

struct LegacyLoginView: View {
    @EnvironmentObject private var store: LegacySessionStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                wordmark

                LegacyCard {
                    VStack(spacing: 14) {
                        field(symbol: "server.rack", title: "服务器") {
                            TextField("https://cloud.agents-anywhere.com", text: $store.serverInput)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .font(.subheadline)
                        }
                        divider
                        field(symbol: "envelope", title: "邮箱") {
                            TextField("you@example.com", text: $store.email)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.emailAddress)
                                .font(.subheadline)
                        }
                        divider
                        field(symbol: "lock", title: "密码") {
                            SecureField("••••••••", text: $store.password)
                                .textContentType(.password)
                                .font(.subheadline)
                        }
                    }
                }

                if let message = store.errorMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text(message)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(
                        Color.orange.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }

                LegacyPrimaryButton(
                    title: store.isWorking ? "正在登录…" : "登录",
                    symbol: "arrow.right",
                    isEnabled: canSubmit,
                    isLoading: store.isWorking
                ) {
                    Task { await store.signIn() }
                }

                Text("使用 Cloud 账号，或填写自托管服务地址。登录凭据只保存在本机钥匙串。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, LegacyStyle.gutter)
            .padding(.top, 48)
            .padding(.bottom, 32)
        }
        .background(AppTheme.appBackground(colorScheme).ignoresSafeArea())
    }

    private var wordmark: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.primaryControlBackground(colorScheme))
                    Image(systemName: "command")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppTheme.primaryControlForeground(colorScheme))
                }
                .frame(width: 38, height: 38)
                Text("Agents Anywhere")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppTheme.primaryText(colorScheme))
            }
            Text("在手机上查看会话、回复审批，工作设备继续执行。")
                .font(.subheadline)
                .foregroundColor(AppTheme.secondaryText(colorScheme))
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(AppTheme.secondaryControlStroke(colorScheme).opacity(0.45))
            .frame(height: 0.5)
    }

    private func field<Content: View>(symbol: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
                content()
                    .foregroundColor(AppTheme.primaryText(colorScheme))
            }
        }
    }

    private var canSubmit: Bool {
        !store.serverInput.isEmpty && !store.email.isEmpty && !store.password.isEmpty && !store.isWorking
    }
}
