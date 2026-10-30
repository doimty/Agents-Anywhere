import SwiftUI
import Perception

/// The original view tree and stable models stay the same. New OS versions use
/// SwiftUI's native fine-grained observation; iOS 15/16 register the same reads
/// with Perception. Use this at body and deferred ViewBuilder boundaries.
struct AppObservationTracking<Content: View>: View {
    private let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    var body: some View {
        // The package chooses native Observation on iOS 17+ itself. In Debug
        // the wrapper also scopes missing-tracking diagnostics; skipping it on
        // modern systems reports every otherwise valid native read and can turn
        // a long transcript into hundreds of expensive stack-trace reports.
        WithPerceptionTracking { content() }
    }
}
