import SwiftUI

/// Customizes the appearance of inline elements in ``InlineText`` and ``StructuredText``.
///
/// Use `InlineStyle` to control how inline formatting (code, emphasis, links, strong, and
/// strikethrough) is rendered. Apply a custom style using the ``TextualNamespace/inlineStyle(_:)`` modifier.
///
/// ```swift
/// let style = InlineStyle()
///   .code(.monospaced, .foregroundColor(.purple))
///   .strong(.fontWeight(.bold))
///   .link(.foregroundColor(.blue))
///
/// InlineText(markdown: "Use `git status` to check **uncommitted** changes")
///   .textual.inlineStyle(style)
/// ```
///
/// Each inline element can be customized independently using ``TextProperty`` values.
///
/// `InlineStyle()` creates a baseline style. By default, Textual uses ``InlineStyle/default`` in
/// the environment, which applies a slightly smaller monospaced font for code, semibold for
/// strong, and a link color that adapts to the current color scheme.
public struct InlineStyle: Sendable, Hashable {
  var code: AnyTextProperty = AnyTextProperty(.monospaced)
  var emphasis: AnyTextProperty = AnyTextProperty(.italic)
  var link: AnyTextProperty = AnyTextProperty(.foregroundColor(.accentColor))
  var strong: AnyTextProperty = AnyTextProperty(.bold)
  var strikethrough: AnyTextProperty = AnyTextProperty(.strikethroughStyle(.single))

  /// Creates an inline style with default formatting.
  public init() {}

  /// Returns a copy of this style with custom code formatting.
  ///
  /// - Parameter properties: Text properties to apply to inline code elements.
  /// - Returns: A new style with the modified code formatting.
  public func code() -> Self {
    modifyingStyle { $0.code = AnyTextProperty() }
  }

  public func code<P0: TextProperty>(_ property0: P0) -> Self {
    modifyingStyle { $0.code = AnyTextProperty(property0) }
  }

  public func code<P0: TextProperty, P1: TextProperty>(_ property0: P0, _ property1: P1) -> Self {
    modifyingStyle { $0.code = AnyTextProperty(property0, property1) }
  }

  public func code<P0: TextProperty, P1: TextProperty, P2: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2) -> Self {
    modifyingStyle { $0.code = AnyTextProperty(property0, property1, property2) }
  }

  public func code<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3) -> Self {
    modifyingStyle { $0.code = AnyTextProperty(property0, property1, property2, property3) }
  }

  public func code<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4) -> Self {
    modifyingStyle { $0.code = AnyTextProperty(property0, property1, property2, property3, property4) }
  }

  public func code<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty, P5: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4, _ property5: P5) -> Self {
    modifyingStyle { $0.code = AnyTextProperty(property0, property1, property2, property3, property4, property5) }
  }

  public func code<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty, P5: TextProperty, P6: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4, _ property5: P5, _ property6: P6) -> Self {
    modifyingStyle { $0.code = AnyTextProperty(property0, property1, property2, property3, property4, property5, property6) }
  }

  public func code<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty, P5: TextProperty, P6: TextProperty, P7: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4, _ property5: P5, _ property6: P6, _ property7: P7) -> Self {
    modifyingStyle { $0.code = AnyTextProperty(property0, property1, property2, property3, property4, property5, property6, property7) }
  }

  /// Returns a copy of this style with custom emphasis formatting.
  ///
  /// - Parameter properties: Text properties to apply to emphasized text.
  /// - Returns: A new style with the modified emphasis formatting.
  public func emphasis() -> Self {
    modifyingStyle { $0.emphasis = AnyTextProperty() }
  }

  public func emphasis<P0: TextProperty>(_ property0: P0) -> Self {
    modifyingStyle { $0.emphasis = AnyTextProperty(property0) }
  }

  public func emphasis<P0: TextProperty, P1: TextProperty>(_ property0: P0, _ property1: P1) -> Self {
    modifyingStyle { $0.emphasis = AnyTextProperty(property0, property1) }
  }

  public func emphasis<P0: TextProperty, P1: TextProperty, P2: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2) -> Self {
    modifyingStyle { $0.emphasis = AnyTextProperty(property0, property1, property2) }
  }

  public func emphasis<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3) -> Self {
    modifyingStyle { $0.emphasis = AnyTextProperty(property0, property1, property2, property3) }
  }

  public func emphasis<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4) -> Self {
    modifyingStyle { $0.emphasis = AnyTextProperty(property0, property1, property2, property3, property4) }
  }

  public func emphasis<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty, P5: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4, _ property5: P5) -> Self {
    modifyingStyle { $0.emphasis = AnyTextProperty(property0, property1, property2, property3, property4, property5) }
  }

  public func emphasis<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty, P5: TextProperty, P6: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4, _ property5: P5, _ property6: P6) -> Self {
    modifyingStyle { $0.emphasis = AnyTextProperty(property0, property1, property2, property3, property4, property5, property6) }
  }

  public func emphasis<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty, P5: TextProperty, P6: TextProperty, P7: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4, _ property5: P5, _ property6: P6, _ property7: P7) -> Self {
    modifyingStyle { $0.emphasis = AnyTextProperty(property0, property1, property2, property3, property4, property5, property6, property7) }
  }

  /// Returns a copy of this style with custom link formatting.
  ///
  /// - Parameter properties: Text properties to apply to links.
  /// - Returns: A new style with the modified link formatting.
  public func link() -> Self {
    modifyingStyle { $0.link = AnyTextProperty() }
  }

  public func link<P0: TextProperty>(_ property0: P0) -> Self {
    modifyingStyle { $0.link = AnyTextProperty(property0) }
  }

  public func link<P0: TextProperty, P1: TextProperty>(_ property0: P0, _ property1: P1) -> Self {
    modifyingStyle { $0.link = AnyTextProperty(property0, property1) }
  }

  public func link<P0: TextProperty, P1: TextProperty, P2: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2) -> Self {
    modifyingStyle { $0.link = AnyTextProperty(property0, property1, property2) }
  }

  public func link<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3) -> Self {
    modifyingStyle { $0.link = AnyTextProperty(property0, property1, property2, property3) }
  }

  public func link<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4) -> Self {
    modifyingStyle { $0.link = AnyTextProperty(property0, property1, property2, property3, property4) }
  }

  public func link<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty, P5: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4, _ property5: P5) -> Self {
    modifyingStyle { $0.link = AnyTextProperty(property0, property1, property2, property3, property4, property5) }
  }

  public func link<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty, P5: TextProperty, P6: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4, _ property5: P5, _ property6: P6) -> Self {
    modifyingStyle { $0.link = AnyTextProperty(property0, property1, property2, property3, property4, property5, property6) }
  }

  public func link<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty, P5: TextProperty, P6: TextProperty, P7: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4, _ property5: P5, _ property6: P6, _ property7: P7) -> Self {
    modifyingStyle { $0.link = AnyTextProperty(property0, property1, property2, property3, property4, property5, property6, property7) }
  }

  /// Returns a copy of this style with custom strong formatting.
  ///
  /// - Parameter properties: Text properties to apply to strong (bold) text.
  /// - Returns: A new style with the modified strong formatting.
  public func strong() -> Self {
    modifyingStyle { $0.strong = AnyTextProperty() }
  }

  public func strong<P0: TextProperty>(_ property0: P0) -> Self {
    modifyingStyle { $0.strong = AnyTextProperty(property0) }
  }

  public func strong<P0: TextProperty, P1: TextProperty>(_ property0: P0, _ property1: P1) -> Self {
    modifyingStyle { $0.strong = AnyTextProperty(property0, property1) }
  }

  public func strong<P0: TextProperty, P1: TextProperty, P2: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2) -> Self {
    modifyingStyle { $0.strong = AnyTextProperty(property0, property1, property2) }
  }

  public func strong<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3) -> Self {
    modifyingStyle { $0.strong = AnyTextProperty(property0, property1, property2, property3) }
  }

  public func strong<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4) -> Self {
    modifyingStyle { $0.strong = AnyTextProperty(property0, property1, property2, property3, property4) }
  }

  public func strong<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty, P5: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4, _ property5: P5) -> Self {
    modifyingStyle { $0.strong = AnyTextProperty(property0, property1, property2, property3, property4, property5) }
  }

  public func strong<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty, P5: TextProperty, P6: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4, _ property5: P5, _ property6: P6) -> Self {
    modifyingStyle { $0.strong = AnyTextProperty(property0, property1, property2, property3, property4, property5, property6) }
  }

  public func strong<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty, P5: TextProperty, P6: TextProperty, P7: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4, _ property5: P5, _ property6: P6, _ property7: P7) -> Self {
    modifyingStyle { $0.strong = AnyTextProperty(property0, property1, property2, property3, property4, property5, property6, property7) }
  }

  /// Returns a copy of this style with custom strikethrough formatting.
  ///
  /// - Parameter properties: Text properties to apply to strikethrough text.
  /// - Returns: A new style with the modified strikethrough formatting.
  public func strikethrough() -> Self {
    modifyingStyle { $0.strikethrough = AnyTextProperty() }
  }

  public func strikethrough<P0: TextProperty>(_ property0: P0) -> Self {
    modifyingStyle { $0.strikethrough = AnyTextProperty(property0) }
  }

  public func strikethrough<P0: TextProperty, P1: TextProperty>(_ property0: P0, _ property1: P1) -> Self {
    modifyingStyle { $0.strikethrough = AnyTextProperty(property0, property1) }
  }

  public func strikethrough<P0: TextProperty, P1: TextProperty, P2: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2) -> Self {
    modifyingStyle { $0.strikethrough = AnyTextProperty(property0, property1, property2) }
  }

  public func strikethrough<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3) -> Self {
    modifyingStyle { $0.strikethrough = AnyTextProperty(property0, property1, property2, property3) }
  }

  public func strikethrough<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4) -> Self {
    modifyingStyle { $0.strikethrough = AnyTextProperty(property0, property1, property2, property3, property4) }
  }

  public func strikethrough<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty, P5: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4, _ property5: P5) -> Self {
    modifyingStyle { $0.strikethrough = AnyTextProperty(property0, property1, property2, property3, property4, property5) }
  }

  public func strikethrough<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty, P5: TextProperty, P6: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4, _ property5: P5, _ property6: P6) -> Self {
    modifyingStyle { $0.strikethrough = AnyTextProperty(property0, property1, property2, property3, property4, property5, property6) }
  }

  public func strikethrough<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty, P5: TextProperty, P6: TextProperty, P7: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4, _ property5: P5, _ property6: P6, _ property7: P7) -> Self {
    modifyingStyle { $0.strikethrough = AnyTextProperty(property0, property1, property2, property3, property4, property5, property6, property7) }
  }

  private func modifyingStyle(_ modify: (inout Self) -> Void) -> Self {
    var style = self
    modify(&style)
    return style
  }
}

extension EnvironmentValues {
  @usableFromInline
  @Entry var inlineStyle: InlineStyle = .default
}
