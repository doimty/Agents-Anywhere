import SwiftUI

/// The block/style/attributed-content surface is shared; only the resolved text
/// layout backend changes. Keep modern text types out of iOS 15 stored properties.
struct TextFragment<Content: AttributedStringProtocol>: View {
  private let content: Content
  init(_ content: Content) { self.content = content }

  var body: some View {
    if #available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *) {
      ModernTextFragment(content)
    } else {
      #if canImport(UIKit)
        PortableTextFragment(content)
      #else
        Text(AttributedString(content))
      #endif
    }
  }
}

@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
struct ModernTextFragment<Content: AttributedStringProtocol>: View {
  @Environment(\.textEnvironment) private var textEnvironment
  @State private var textBuilder: TextBuilder?
  private let content: Content

  init(_ content: Content) { self.content = content }

  var body: some View {
    text
      .customAttribute(TextFragmentAttribute())
      .onGeometryChange(for: CGSize?.self, of: \.textContainerSize) { size in
        guard let size, let textBuilder else { return }
        textBuilder.sizeChanged(size, environment: textEnvironment)
      }
      .onChange(of: content, initial: true) { _, value in
        textBuilder = TextBuilder(value, environment: textEnvironment)
      }
      .modifier(TextSelectionBackground())
      .modifier(AttachmentOverlay(attachments: textBuilder?.attachments ?? []))
      .modifier(TextLinkInteraction(hasLinks: textBuilder?.hasLinks ?? false))
  }

  private var text: Text { textBuilder?.text ?? Text(verbatim: "") }
}

@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
struct TextFragmentAttribute: TextAttribute {}

@available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
extension Text.Layout {
  var isTextFragment: Bool { first?.first?[TextFragmentAttribute.self] != nil }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
  static var textContainer: NamedCoordinateSpace { .named("textContainer") }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension GeometryProxy {
  fileprivate var textContainerSize: CGSize? { bounds(of: .textContainer)?.size }
}
