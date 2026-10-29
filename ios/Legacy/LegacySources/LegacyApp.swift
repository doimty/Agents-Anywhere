import SwiftUI

/// iOS 15 core client.
///
/// This target reuses the typed API, domain models, HTTP transport and Keychain
/// store from the shipped client, and replaces only the SwiftUI layer. It exists
/// because the shipped interface depends on Observation (iOS 17), Textual
/// (iOS 18) and Liquid Glass (iOS 26); those stay untouched so the modern app
/// keeps its behavior while iOS 15 gets a working, installable client.
@main
struct AgentsAnywhereLegacyApp: App {
    @StateObject private var store = LegacySessionStore()

    var body: some Scene {
        WindowGroup {
            LegacyRootView()
                .environmentObject(store)
        }
    }
}

struct LegacyRootView: View {
    @EnvironmentObject private var store: LegacySessionStore

    var body: some View {
        Group {
            switch store.phase {
            case .signedOut:
                LegacyLoginView()
            case .signedIn:
                LegacyDashboardView()
            }
        }
        .onChange(of: store.phase) { phase in
            if phase == .signedIn { Task { await store.refreshDashboard() } }
        }
    }
}
