import SwiftUI

struct LegacyLoginView: View {
    @EnvironmentObject private var store: LegacySessionStore
    @State private var showsAdvanced = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("服务器地址", text: $store.serverInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("服务")
                } footer: {
                    Text("填写 Cloud 或自托管服务地址，例如 https://cloud.agents-anywhere.com。")
                }

                Section("账号") {
                    TextField("邮箱", text: $store.email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                    SecureField("密码", text: $store.password)
                }

                Section {
                    Button {
                        Task { await store.signIn() }
                    } label: {
                        HStack {
                            Spacer()
                            if store.isWorking { ProgressView().padding(.trailing, 6) }
                            Text(store.isWorking ? "正在登录…" : "登录")
                            Spacer()
                        }
                    }
                    .disabled(store.isWorking || store.email.isEmpty || store.password.isEmpty || store.serverInput.isEmpty)
                } footer: {
                    if let message = store.errorMessage {
                        Text(message).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Agents Anywhere")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}
