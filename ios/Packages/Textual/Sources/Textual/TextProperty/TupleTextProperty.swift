import Foundation

/// Ordered composition with value equality/hash semantics, without parameter packs.
struct TupleTextProperty: TextProperty {
  var properties: [AnyTextProperty]

  func apply(in attributes: inout AttributeContainer, environment: TextEnvironmentValues) {
    for property in properties {
      property.apply(in: &attributes, environment: environment)
    }
  }
}
