import SwiftUI

enum AppSheetSize: Equatable {
    case compact
    case expanded
}

extension View {
    /// Short pickers keep their chosen height across native navigation pushes.
    /// Long forms opt into the large system detent without replacing the sheet.
    func appSheetPresentation(_ size: AppSheetSize) -> some View {
        modifier(AppSheetPresentation(size: size))
    }
}

private struct AppSheetPresentation: ViewModifier {
    let size: AppSheetSize

    func body(content: Content) -> some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            content.modifier(AppNativeSheetPresentation(size: size))
        } else {
            content.background {
                AppPageSheetDetents(size: size).frame(width: 0, height: 0)
            }
        }
    }
}

@available(iOS 16.0, *)
private struct AppNativeSheetPresentation: ViewModifier {
    let size: AppSheetSize
    @State private var compactDetent: PresentationDetent = .medium

    private var selection: Binding<PresentationDetent> {
        Binding(
            get: { size == .expanded ? .large : compactDetent },
            set: { if size == .compact { compactDetent = $0 } }
        )
    }

    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            withDetents(content).presentationContentInteraction(.scrolls)
        } else {
            withDetents(content)
        }
    }

    private func withDetents(_ content: Content) -> some View {
        content
            .presentationDetents(size == .expanded ? [.large] : [.medium, .large], selection: selection)
            .presentationDragIndicator(.visible)
    }
}
