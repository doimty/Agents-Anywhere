#if TEXTUAL_ENABLE_TEXT_SELECTION
import SwiftUI

extension View {
  @ViewBuilder
  func overlayTextLayoutCollection(
    isEnabled: Bool = true,
    @ViewBuilder content: @escaping (any TextLayoutCollection) -> some View
  ) -> some View {
    if #available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *) {
      overlayPreferenceValue(Text.LayoutKey.self) { value in
        if isEnabled {
          GeometryReader { geometry in
            content(LiveTextLayoutCollection(base: value, geometry: geometry))
          }
        }
      }
    } else {
      #if canImport(UIKit)
        overlayPreferenceValue(PortableTextLayoutKey.self) { value in
          if isEnabled {
            GeometryReader { geometry in
              content(PortableTextLayoutCollection(base: value, geometry: geometry))
            }
          }
        }
      #else
        self
      #endif
    }
  }
}
#endif
