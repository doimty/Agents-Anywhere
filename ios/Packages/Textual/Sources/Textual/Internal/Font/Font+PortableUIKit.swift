#if canImport(UIKit)
import SwiftUI
import UIKit
import CoreText

extension Font {
  /// Resolve the same provider/modifier chain used for font-relative measurements.
  /// This conversion never inspects Text.Layout or private text renderer state.
  func portableUIFont(in environment: TextEnvironmentValues) -> UIFont {
    provider()?.portableUIFont(in: environment)
      ?? UIFont.preferredFont(forTextStyle: .body, compatibleWith: environment.portableFontTraits)
  }
}

extension TextEnvironmentValues {
  var portableFontTraits: UITraitCollection {
    UITraitCollection(traitsFrom: [
      UITraitCollection(legibilityWeight: UILegibilityWeight(legibilityWeight)),
      UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize)),
      UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light),
      UITraitCollection(accessibilityContrast: colorSchemeContrast == .increased ? .high : .normal),
    ])
  }
}

extension AnyFontProvider {
  fileprivate func portableUIFont(in environment: TextEnvironmentValues) -> UIFont {
    switch base {
    case let value as TextStyleFontProvider:
      var descriptor = UIFontDescriptor.preferredFontDescriptor(
        withTextStyle: UIFont.TextStyle(value.style), compatibleWith: environment.portableFontTraits)
      if let design = value.design, let designed = descriptor.withDesign(design.portableUIKitDesign) {
        descriptor = designed
      }
      if let weight = value.weight {
        descriptor = descriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight.portableUIKitWeight.rawValue]])
      }
      return UIFont(descriptor: descriptor, size: descriptor.pointSize * value.scale)
    case let value as SystemFontProvider:
      let font = UIFont.systemFont(ofSize: value.size * value.scale,
        weight: (value.weight ?? .regular).portableUIKitWeight)
      guard let design = value.design,
        let descriptor = font.fontDescriptor.withDesign(design.portableUIKitDesign) else { return font }
      return UIFont(descriptor: descriptor, size: font.pointSize)
    case let value as NamedFontProvider:
      let font = UIFont(name: value.name, size: value.size)
        ?? UIFont.preferredFont(forTextStyle: value.textStyle.map(UIFont.TextStyle.init) ?? .body,
          compatibleWith: environment.portableFontTraits)
      let scaled: UIFont
      if let style = value.textStyle {
        scaled = UIFontMetrics(forTextStyle: UIFont.TextStyle(style))
          .scaledFont(for: font, compatibleWith: environment.portableFontTraits)
      } else { scaled = font }
      return UIFont(descriptor: scaled.fontDescriptor, size: scaled.pointSize * value.scale)
    case let value as PlatformFontProvider:
      let descriptor = CTFontCopyFontDescriptor(value.font) as UIFontDescriptor
      return UIFont(descriptor: descriptor, size: CTFontGetSize(value.font) * value.scale)
    case let value as FontModifierProvider<AnyFontProvider, WeightFontModifier>:
      return value.base.portableUIFont(in: environment).portableWeight(value.modifier.weight)
    case let value as FontModifierProvider<AnyFontProvider, LeadingFontModifier>:
      return value.base.portableUIFont(in: environment)
    case let value as StaticFontModifierProvider<AnyFontProvider, BoldFontModifier>:
      return value.base.portableUIFont(in: environment).portableWeight(.bold)
    case let value as StaticFontModifierProvider<AnyFontProvider, ItalicFontModifier>:
      let font = value.base.portableUIFont(in: environment)
      let traits = font.fontDescriptor.symbolicTraits.union(.traitItalic)
      return font.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: font.pointSize) } ?? font
    case let value as StaticFontModifierProvider<AnyFontProvider, MonospacedFontModifier>:
      let font = value.base.portableUIFont(in: environment)
      return font.fontDescriptor.withDesign(.monospaced).map { UIFont(descriptor: $0, size: font.pointSize) } ?? font
    case let value as StaticFontModifierProvider<AnyFontProvider, MonospacedDigitFontModifier>:
      return value.base.portableUIFont(in: environment).portableFeature(type: 6, selector: 0)
    case let value as StaticFontModifierProvider<AnyFontProvider, LowercaseSmallCapsFontModifier>:
      return value.base.portableUIFont(in: environment).portableFeature(type: 37, selector: 1)
    case let value as StaticFontModifierProvider<AnyFontProvider, UppercaseSmallCapsFontModifier>:
      return value.base.portableUIFont(in: environment).portableFeature(type: 38, selector: 1)
    default:
      if #available(iOS 16, tvOS 16, watchOS 9, *) {
        if let value = base as? FontModifierProvider<AnyFontProvider, WidthFontModifier> {
          let font = value.base.portableUIFont(in: environment)
          let width = Mirror(reflecting: value.modifier.width).descendant("value") as? CGFloat ?? 0
          let descriptor = font.fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.width: width]])
          return UIFont(descriptor: descriptor, size: font.pointSize)
        }
      }
      return UIFont.preferredFont(forTextStyle: .body, compatibleWith: environment.portableFontTraits)
    }
  }
}

extension UIFont {
  fileprivate func portableWeight(_ weight: Font.Weight) -> UIFont {
    let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight.portableUIKitWeight.rawValue]])
    return UIFont(descriptor: descriptor, size: pointSize)
  }

  fileprivate func portableFeature(type: Int, selector: Int) -> UIFont {
    let settings: [[UIFontDescriptor.FeatureKey: Int]] = [[.type: type, .selector: selector]]
    let descriptor = fontDescriptor.addingAttributes([.featureSettings: settings])
    return UIFont(descriptor: descriptor, size: pointSize)
  }
}

extension Font.Weight {
  fileprivate var portableUIKitWeight: UIFont.Weight {
    let value = Mirror(reflecting: self).descendant("value") as? CGFloat
    return value.map(UIFont.Weight.init(rawValue:)) ?? .regular
  }
}

extension Font.Design {
  fileprivate var portableUIKitDesign: UIFontDescriptor.SystemDesign {
    switch self {
    case .default: return .default
    case .serif: return .serif
    case .rounded: return .rounded
    case .monospaced: return .monospaced
    @unknown default: return .default
    }
  }
}
#endif
