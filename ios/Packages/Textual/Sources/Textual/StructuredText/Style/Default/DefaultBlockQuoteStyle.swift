import SwiftUI

extension StructuredText {
  /// The default block quote style used by ``StructuredText/DefaultStyle``.
  public struct DefaultBlockQuoteStyle: BlockQuoteStyle {
    @Environment(\.colorEnvironment) private var colors
    private let backgroundColor: DynamicColor
    private let borderColor: DynamicColor

    /// Creates a block quote style with a background and a leading border.
    public init(backgroundColor: DynamicColor, borderColor: DynamicColor) {
      self.backgroundColor = backgroundColor
      self.borderColor = borderColor
    }

    public func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .frame(maxWidth: .infinity, alignment: .leading)
        .textual.lineSpacing(.fontScaled(0.471))
        .textual.padding(.fontScaled(0.941))
        .background {
          ZStack(alignment: .leading) {
            Rectangle()
              .fill(backgroundColor.bestMatch(for: colors) ?? .clear)
            Rectangle()
              .fill(borderColor.bestMatch(for: colors) ?? .clear)
              .frame(width: 6, alignment: .leading)
          }
          .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
  }
}

extension StructuredText.BlockQuoteStyle where Self == StructuredText.DefaultBlockQuoteStyle {
  /// The default block quote style.
  public static var `default`: Self {
    .init(backgroundColor: .asideBackground, borderColor: .asideBorder)
  }
}
#if DEBUG

@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
#Preview {
  StructuredText(
    markdown: """
      The sky above the port was the color of television, tuned to a dead channel.

      > Outside of a dog, a book is man's best friend. Inside of a dog it's too dark to read.

      It was a bright cold day in April, and the clocks were striking thirteen.
      """
  )
  .padding()
  .textual.textSelection(.enabled)
}
#endif
