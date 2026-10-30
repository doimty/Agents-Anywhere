import SwiftUI

extension StructuredText {
  /// A thematic break style that renders a `Divider`.
  public struct DividerThematicBreakStyle: ThematicBreakStyle {
    @Environment(\.colorEnvironment) private var colors
    /// Creates a divider thematic break style.
    public init() {}

    public func makeBody(configuration _: Configuration) -> some View {
      Divider()
        .frame(minHeight: 1)
        .overlay(DynamicColor.grid.bestMatch(for: colors) ?? .clear)
        .textual.blockSpacing(.fontScaled(top: 1.6, bottom: 1.6))
    }
  }
}

extension StructuredText.ThematicBreakStyle where Self == StructuredText.DividerThematicBreakStyle {
  /// A thematic break style that uses a `Divider`.
  public static var divider: Self {
    .init()
  }
}
#if DEBUG && !os(tvOS) && !os(watchOS)

@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
#Preview {
  StructuredText(
    markdown: """
      The sky above the port was the color of television, tuned to a dead channel.

      ---

      It was a bright cold day in April, and the clocks were striking thirteen.
      """
  )
  .padding()
  .textual.textSelection(.enabled)
}
#endif
