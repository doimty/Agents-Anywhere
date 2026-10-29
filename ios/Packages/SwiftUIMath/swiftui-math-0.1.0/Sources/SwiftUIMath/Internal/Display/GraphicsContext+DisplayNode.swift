import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension GraphicsContext {
  func draw(_ displayNode: Math.DisplayNode, size: CGSize, foregroundColor: Color) {
    var context = self
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    context.translateBy(x: 0, y: displayNode.descent)

    let cgColor: CGColor
    if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, *) {
      cgColor = foregroundColor.resolve(in: environment).cgColor
    } else {
      #if canImport(UIKit)
        let traits = UITraitCollection(traitsFrom: [
          UITraitCollection(userInterfaceStyle: environment.colorScheme == .dark ? .dark : .light),
          UITraitCollection(accessibilityContrast: environment.colorSchemeContrast == .increased ? .high : .normal),
        ])
        cgColor = UIColor(foregroundColor).resolvedColor(with: traits).cgColor
      #else
        cgColor = CGColor(gray: 0, alpha: 1)
      #endif
    }
    context.withCGContext { $0.draw(displayNode, foregroundColor: cgColor) }
  }

  func draw(_ displayNode: Math.DisplayNode, size: CGSize, with shading: GraphicsContext.Shading) {
    var context = self
    context.fill(Path(CGRect(origin: .zero, size: size)), with: shading)
    context.blendMode = .destinationIn
    context.drawLayer { $0.draw(displayNode, size: size, foregroundColor: .black) }
  }
}
