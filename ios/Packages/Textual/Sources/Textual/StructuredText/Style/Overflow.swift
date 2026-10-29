import SwiftUI

/// Controls how content behaves when it overflows horizontally.
public enum OverflowMode: Hashable {
  case wrap
  case scroll
}

/// The original overflow style surface, shared by both text-layout backends.
public enum OverflowState: Hashable {
  case wrap
  case scroll(containerWidth: CGFloat?)
  public var containerWidth: CGFloat? {
    guard case .scroll(let width) = self else { return nil }
    return width
  }
}

public struct Overflow<Content: View>: View {
  @Environment(\.overflowMode) private var mode
  @State private var containerWidth: CGFloat?
  @State private var contentHeight: CGFloat?
  private let content: (OverflowState) -> Content

  public init(@ViewBuilder content: @escaping () -> Content) { self.init { _ in content() } }
  public init(@ViewBuilder content: @escaping (_ state: OverflowState) -> Content) { self.content = content }

  public var body: some View {
    switch mode {
    case .wrap:
      content(.wrap).frame(maxWidth: .infinity, alignment: .leading)
    case .scroll:
      ScrollView(.horizontal) {
        ZStack {
          Color.clear.frame(minHeight: contentHeight)
          content(.scroll(containerWidth: containerWidth))
            .textualReadSize { contentHeight = $0.height }
            .modifier(TextSelectionInteraction())
            .textualIsolateLayouts()
        }
      }
      .textualReadSize { containerWidth = $0.width }
      .background {
        GeometryReader { geometry in
          Color.clear.preference(key: OverflowFrameKey.self,
            value: [geometry.frame(in: .named("textContainer"))])
        }
      }
    }
  }
}

extension View {
  @ViewBuilder
  func textualIsolateLayouts() -> some View {
    if #available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *) {
      transformPreference(Text.LayoutKey.self) { $0 = [] }
    } else {
      #if canImport(UIKit)
        transformPreference(PortableTextLayoutKey.self) { $0 = [] }
      #else
        self
      #endif
    }
  }
}

extension EnvironmentValues {
  @usableFromInline @Entry var overflowMode = OverflowMode.scroll
}
