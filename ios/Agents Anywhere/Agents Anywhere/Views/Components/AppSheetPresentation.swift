import SwiftUI

enum AppSheetSize: Equatable {
    case compact
    case expanded
}

extension View {
    /// Short pickers keep their chosen height across native navigation pushes.
    /// Long forms opt into the large system detent without replacing the sheet.
    /// iOS 15 keeps a standard sheet; see `AppCompatibility.appPresentationDetents`.
    func appSheetPresentation(_ size: AppSheetSize) -> some View {
        modifier(AppSheetPresentation(size: size))
    }
}

private struct AppSheetPresentation: ViewModifier {
    let size: AppSheetSize
    @State private var compactDetent: AppSheetDetent = .medium

    private var detents: Set<AppSheetDetent> {
        size == .expanded ? [.large] : [.medium, .large]
    }

    private var selection: Binding<AppSheetDetent> {
        Binding(
            get: { size == .expanded ? .large : compactDetent },
            set: { if size == .compact { compactDetent = $0 } }
        )
    }

    func body(content: Content) -> some View {
        content
            .appPresentationDetents(detents, selection: selection)
            .appSheetScrollContentInteraction()
            .appSheetDragIndicator()
    }
}
