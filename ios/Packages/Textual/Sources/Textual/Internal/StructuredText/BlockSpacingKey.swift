import SwiftUI

extension StructuredText {
  struct BlockSpacingKey: PreferenceKey {
    static let defaultValue = BlockSpacing()

    static func reduce(value: inout BlockSpacing, nextValue: () -> BlockSpacing) {
      value = value.union(nextValue())
    }
  }
}

@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
extension StructuredText.BlockSpacingKey: LayoutValueKey {}
