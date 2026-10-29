import SwiftUI
import Perception

/// The original view tree and stable models stay the same. New OS versions use
/// SwiftUI's native fine-grained observation; iOS 15/16 register the same reads
/// with Perception. Use this at body and deferred ViewBuilder boundaries.
struct AppObservationTracking<Content: View>: View {
    private let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View {
        if #available(iOS 17.0, *), AppCompatibility.useNativeUI {
            content()
        } else {
            WithPerceptionTracking { content() }
        }
    }
}
