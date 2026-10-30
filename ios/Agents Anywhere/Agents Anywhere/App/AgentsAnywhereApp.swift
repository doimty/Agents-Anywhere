import SwiftUI
import PerceptionCore

@main
struct AgentsAnywhereApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearance.storageKey) private var appearanceValue = AppAppearance.system.rawValue

    init() {
        AppFontRegistry.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if CompatibilityRegressionScene.isEnabled {
                    CompatibilityRegressionScene()
                } else {
                    RootView().environment(appState)
                }
                #else
                RootView().environment(appState)
                #endif
            }
                .background {
                    #if targetEnvironment(macCatalyst)
                    MacCatalystWindowTitle(appState: appState)
                    #endif
                }
                .preferredColorScheme(appearance.colorScheme)
                .appOnChange(of: scenePhase) { _, phase in
                    if phase == .background { appState.setAppInBackground(true) }
                    else if phase == .active { appState.setAppInBackground(false) }
                }
        }
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceValue) ?? .system
    }
}
