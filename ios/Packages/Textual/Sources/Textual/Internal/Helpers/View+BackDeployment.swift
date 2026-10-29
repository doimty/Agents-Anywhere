import SwiftUI

extension View {
  /// Same initial/change semantics without requiring the iOS 17 onChange overloads.
  func textualOnChange<Value: Equatable>(
    of value: Value,
    initial: Bool = false,
    _ action: @escaping () -> Void
  ) -> some View {
    onAppear { if initial { action() } }
      .onChange(of: value) { _ in action() }
  }

  func textualOnChange<Value: Equatable>(
    of value: Value,
    initial: Bool = false,
    _ action: @escaping (Value, Value) -> Void
  ) -> some View {
    modifier(TextualValueChange(value: value, initial: initial, action: action))
  }

  func textualReadSize(_ action: @escaping (CGSize) -> Void) -> some View {
    background {
      GeometryReader { geometry in
        Color.clear
          .onAppear { action(geometry.size) }
          .onChange(of: geometry.size) { action($0) }
      }
    }
  }
}

private struct TextualValueChange<Value: Equatable>: ViewModifier {
  let value: Value
  let initial: Bool
  let action: (Value, Value) -> Void
  @State private var previous: Value

  init(value: Value, initial: Bool, action: @escaping (Value, Value) -> Void) {
    self.value = value
    self.initial = initial
    self.action = action
    _previous = State(initialValue: value)
  }

  func body(content: Content) -> some View {
    content
      .onAppear { if initial { previous = value; action(value, value) } }
      .onChange(of: value) { newValue in
        let oldValue = previous
        previous = newValue
        action(oldValue, newValue)
      }
  }
}

struct PortableMonospacedModifier: ViewModifier {
  @Environment(\.font) private var font
  func body(content: Content) -> some View {
    content.font((font ?? .body).monospaced())
      .textual.textProperties(AnyTextProperty(.monospaced))
  }
}

struct TextPropertiesModifier: ViewModifier {
  @Environment(\.portableTextProperties) private var inherited
  let properties: AnyTextProperty

  func body(content: Content) -> some View {
    content.environment(\.portableTextProperties, inherited + [properties])
  }
}

extension EnvironmentValues {
  @Entry var portableTextProperties: [AnyTextProperty] = []
  @Entry var portableLineSpacing: CGFloat = 0
}

extension TextualNamespace where Base: View {
  /// Mirrors explicit text properties to both renderers. Useful for custom styles
  /// whose standard SwiftUI modifiers are not visible to UIKit's text layout engine.
  @MainActor public func textProperties(_ properties: AnyTextProperty) -> some View {
    base.modifier(TextPropertiesModifier(properties: properties))
  }
}
