import SwiftUI

// MARK: - Overview
//
// `TextSelectionBackground` draws selection highlights behind a `Text` fragment.
//
// The platform selection interaction stores a `TextSelectionModel` in the environment at fragment
// scope. This modifier reads the fragment’s anchored `Text.Layout` and forwards it to the AppKit
// selection view so it can convert the current selected range into highlight rectangles.

@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
struct TextSelectionBackground: ViewModifier {
  func body(content: Content) -> some View {
    #if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(AppKit) && !targetEnvironment(macCatalyst)
      content
        .backgroundPreferenceValue(Text.LayoutKey.self) { value in
          if let anchoredLayout = value.first {
            GeometryReader { geometry in
              AppKitTextSelectionView(
                layout: anchoredLayout.layout,
                origin: geometry[anchoredLayout.origin]
              )
            }
          }
        }
    #else
      content
    #endif
  }
}
