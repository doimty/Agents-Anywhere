import SwiftUI

extension StructuredText {
  /// A thematic break style inspired by GitHub’s rendering.
  public struct GitHubThematicBreakStyle: ThematicBreakStyle {
    @Environment(\.colorEnvironment) private var colors
    /// Creates the GitHub thematic break style.
    public init() {}

    public func makeBody(configuration _: Configuration) -> some View {
      Divider()
        .textual.frame(height: .fontScaled(0.25))
        .overlay(DynamicColor.gitHubBorder.bestMatch(for: colors) ?? .clear)
        .textual.blockSpacing(.init(top: 24, bottom: 24))
    }
  }
}

extension StructuredText.ThematicBreakStyle where Self == StructuredText.GitHubThematicBreakStyle {
  /// A GitHub-like thematic break style.
  public static var gitHub: Self {
    .init()
  }
}
#if DEBUG

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
  .textual.paragraphStyle(.gitHub)
  .textual.thematicBreakStyle(.gitHub)
}
#endif
