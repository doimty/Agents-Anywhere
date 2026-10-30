import Foundation

/// A small, composable unit of inline styling.
///
/// A `TextProperty` mutates an `AttributeContainer` for a portion of styled text. Textual applies
/// properties to the text spans it styles, and uses them to build higher-level styles like ``InlineStyle``.
public protocol TextProperty: Sendable, Hashable {
  /// Applies this property to an attribute container.
  ///
  /// Implementations should be deterministic and side-effect free.
  ///
  /// - Parameters:
  ///   - attributes: The attribute container to modify.
  ///   - environment: The resolved text environment for the current view.
  func apply(in attributes: inout AttributeContainer, environment: TextEnvironmentValues)
}

/// A type-erased ``TextProperty``.
///
/// Use `AnyTextProperty` when you need to store or pass text properties without exposing their
/// concrete types, or when you want to combine multiple properties into a single value.
///
/// ```swift
/// let emphasis = AnyTextProperty(
///   .foregroundColor(.purple),
///   .fontWeight(.semibold)
/// )
/// ```
public struct AnyTextProperty: TextProperty {
  let base: any TextProperty

  /// Creates a type-erased wrapper around a concrete property.
  public init(_ base: some TextProperty) {
    if let base = base as? AnyTextProperty {
      self = base
    } else {
      self.base = base
    }
  }

  /// Creates an empty (no-op) composition.
  public init() {
    self.init(TupleTextProperty(properties: []))
  }

  /// Creates ordered compositions using deployment-safe, finite arity overloads.
  public init<P0: TextProperty, P1: TextProperty>(_ property0: P0, _ property1: P1) {
    self.init(TupleTextProperty(properties: [AnyTextProperty(property0), AnyTextProperty(property1)]))
  }

  public init<P0: TextProperty, P1: TextProperty, P2: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2) {
    self.init(TupleTextProperty(properties: [AnyTextProperty(property0), AnyTextProperty(property1), AnyTextProperty(property2)]))
  }

  public init<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3) {
    self.init(TupleTextProperty(properties: [AnyTextProperty(property0), AnyTextProperty(property1), AnyTextProperty(property2), AnyTextProperty(property3)]))
  }

  public init<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4) {
    self.init(TupleTextProperty(properties: [AnyTextProperty(property0), AnyTextProperty(property1), AnyTextProperty(property2), AnyTextProperty(property3), AnyTextProperty(property4)]))
  }

  public init<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty, P5: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4, _ property5: P5) {
    self.init(TupleTextProperty(properties: [AnyTextProperty(property0), AnyTextProperty(property1), AnyTextProperty(property2), AnyTextProperty(property3), AnyTextProperty(property4), AnyTextProperty(property5)]))
  }

  public init<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty, P5: TextProperty, P6: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4, _ property5: P5, _ property6: P6) {
    self.init(TupleTextProperty(properties: [AnyTextProperty(property0), AnyTextProperty(property1), AnyTextProperty(property2), AnyTextProperty(property3), AnyTextProperty(property4), AnyTextProperty(property5), AnyTextProperty(property6)]))
  }

  public init<P0: TextProperty, P1: TextProperty, P2: TextProperty, P3: TextProperty, P4: TextProperty, P5: TextProperty, P6: TextProperty, P7: TextProperty>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4, _ property5: P5, _ property6: P6, _ property7: P7) {
    self.init(TupleTextProperty(properties: [AnyTextProperty(property0), AnyTextProperty(property1), AnyTextProperty(property2), AnyTextProperty(property3), AnyTextProperty(property4), AnyTextProperty(property5), AnyTextProperty(property6), AnyTextProperty(property7)]))
  }

  public func apply(in attributes: inout AttributeContainer, environment: TextEnvironmentValues) {
    base.apply(in: &attributes, environment: environment)
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    AnyHashable(lhs.base) == AnyHashable(rhs.base)
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(base)
  }
}
