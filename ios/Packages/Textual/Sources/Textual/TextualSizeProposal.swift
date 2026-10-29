import SwiftUI

/// A deployment-independent size proposal used by inline attachments.
/// SwiftUI's `ProposedViewSize` is confined to the iOS 16+ layout backend.
public struct TextualSizeProposal: Hashable, Sendable, FontScalable {
  public var width: CGFloat?
  public var height: CGFloat?

  public init(width: CGFloat? = nil, height: CGFloat? = nil) {
    self.width = width
    self.height = height
  }

  public init(_ size: CGSize) {
    self.init(width: size.width, height: size.height)
  }

  public static let unspecified = Self()
  public static let zero = Self(width: 0, height: 0)
  public static let infinity = Self(width: .infinity, height: .infinity)

  public func scaled(by fontSize: CGFloat) -> Self {
    Self(width: width.map { $0 * fontSize }, height: height.map { $0 * fontSize })
  }

  public func replacingUnspecifiedDimensions(by size: CGSize = CGSize(width: 10, height: 10)) -> CGSize {
    CGSize(width: width ?? size.width, height: height ?? size.height)
  }
}

@available(iOS 16, tvOS 16, watchOS 9, macOS 13, *)
extension TextualSizeProposal {
  init(_ proposal: ProposedViewSize) {
    self.init(width: proposal.width, height: proposal.height)
  }

  var swiftUI: ProposedViewSize { ProposedViewSize(width: width, height: height) }
}
