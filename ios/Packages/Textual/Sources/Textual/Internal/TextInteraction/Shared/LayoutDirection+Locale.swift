import Foundation
import SwiftUI

extension LayoutDirection {
  static func localeBased(locale: Locale = .current) -> LayoutDirection {
    switch Locale.characterDirection(forLanguage: locale.languageCode ?? "en") {
    case .rightToLeft:
      return .rightToLeft
    case .leftToRight:
      return .leftToRight
    case .topToBottom, .bottomToTop, .unknown:
      return .leftToRight
    @unknown default:
      return .leftToRight
    }
  }
}
