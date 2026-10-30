#if canImport(UIKit)
import SwiftUI
import UIKit

/// iOS 15 keeps SwiftUI.Text as the visible label. TextKit 1 supplies public,
/// deployment-independent glyph geometry to the existing interaction system.
/// Attachments remain live SwiftUI views; no Markdown or block-style replacement.
struct PortableTextFragment<Content: AttributedStringProtocol>: View {
  @Environment(\.textEnvironment) private var environment
  @Environment(\.portableTextProperties) private var properties
  @Environment(\.portableLineSpacing) private var lineSpacing
  @Environment(\.multilineTextAlignment) private var alignment
  @Environment(\.layoutDirection) private var direction
  @StateObject private var cache = PortableTextCache()
  @State private var width: CGFloat?
  private let content: Content

  init(_ content: Content) { self.content = content }

  var body: some View {
    let presentation = cache.presentation(
      AttributedString(content[content.startIndex..<content.endIndex]),
      environment: environment, properties: properties,
      width: width, lineSpacing: lineSpacing, alignment: alignment, direction: direction
    )
    presentation.text
      .textualReadSize { size in
        let proposedWidth = max(1, size.width)
        if width != proposedWidth { width = proposedWidth }
      }
      .anchorPreference(key: PortableTextLayoutKey.self, value: .topLeading) {
        [AnchoredPortableTextLayout(layout: presentation.layout, origin: $0)]
      }
      .overlay(alignment: .topLeading) {
        ZStack(alignment: .topLeading) {
          ForEach(presentation.layout.attachments) { placement in
            placement.attachment.body
              .frame(width: placement.rect.width, height: placement.rect.height)
              .offset(x: placement.rect.minX, y: placement.rect.minY)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .overlay {
        if presentation.layout.hasLinks {
          PortableLinkOverlay(layout: presentation.layout)
        }
      }
  }
}

@MainActor
private final class PortableTextCache: ObservableObject {
  private var key: Key?
  private var value: PortableTextPresentation?

  struct Key: Equatable {
    let source: AttributedString
    let environment: TextEnvironmentValues
    let properties: [AnyTextProperty]
    let width: CGFloat?
    let lineSpacing: CGFloat
    let alignment: TextAlignment
    let direction: LayoutDirection
  }

  func presentation(
    _ source: AttributedString, environment: TextEnvironmentValues,
    properties: [AnyTextProperty], width: CGFloat?, lineSpacing: CGFloat,
    alignment: TextAlignment, direction: LayoutDirection
  ) -> PortableTextPresentation {
    let nextKey = Key(source: source, environment: environment, properties: properties,
      width: width, lineSpacing: lineSpacing, alignment: alignment, direction: direction)
    if key == nextKey, let value { return value }
    let result = PortableTextPresentation(source: source, environment: environment,
      properties: properties, width: width, lineSpacing: lineSpacing,
      alignment: alignment, direction: direction)
    key = nextKey
    value = result
    return result
  }
}

@MainActor
private struct PortableTextPresentation {
  let text: Text
  let layout: PortableTextLayout

  init(source: AttributedString, environment: TextEnvironmentValues,
       properties: [AnyTextProperty], width: CGFloat?, lineSpacing: CGFloat,
       alignment: TextAlignment, direction: LayoutDirection) {
    var visibleText = Text(verbatim: "")
    let native = NSMutableAttributedString(string: "")
    for run in source.runs {
      var attributes = run.attributes
      for property in properties { property.apply(in: &attributes, environment: environment) }
      var slice = AttributedString(source[run.range])
      slice.setAttributes(attributes)
      var runEnvironment = environment
      runEnvironment.font = attributes.font ?? environment.font
      var segment: Text
      let nativeSegment: NSMutableAttributedString
      if let attachment = run.textual.attachment {
        let size = attachment.sizeThatFits(TextualSizeProposal(width: width), in: runEnvironment)
        let safeSize = CGSize(width: max(1, size.width.isFinite ? size.width : 1),
          height: max(1, size.height.isFinite ? size.height : 1))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let placeholder = UIGraphicsImageRenderer(size: safeSize, format: format).image { _ in }
        let baseline = attachment.baselineOffset(in: runEnvironment)
        segment = Text(SwiftUI.Image(uiImage: placeholder)).baselineOffset(baseline)
        let textAttachment = NSTextAttachment()
        textAttachment.image = placeholder
        textAttachment.bounds = CGRect(x: 0, y: baseline, width: safeSize.width, height: safeSize.height)
        nativeSegment = NSMutableAttributedString(attributedString: NSAttributedString(attachment: textAttachment))
        if let original = try? NSAttributedString(slice, including: \.textual), original.length > 0 {
          nativeSegment.addAttributes(original.attributes(at: 0, effectiveRange: nil),
            range: NSRange(location: 0, length: 1))
        }
        nativeSegment.addAttribute(.textual.attachment, value: attachment,
          range: NSRange(location: 0, length: 1))
      } else {
        segment = Text(slice)
        nativeSegment = NSMutableAttributedString(attributedString:
          (try? NSAttributedString(slice, including: \.textual))
            ?? NSAttributedString(string: String(slice.characters)))
      }
      if nativeSegment.length > 0 {
        let range = NSRange(location: 0, length: nativeSegment.length)
        nativeSegment.addAttribute(.font, value: (attributes.font ?? environment.font ?? .body)
          .portableUIFont(in: environment), range: range)
        if let foreground = attributes.foregroundColor {
          nativeSegment.addAttribute(.foregroundColor, value: UIColor(foreground), range: range)
        }
        if let background = attributes.backgroundColor {
          nativeSegment.addAttribute(.backgroundColor, value: UIColor(background), range: range)
        }
        if let baseline = attributes.baselineOffset {
          nativeSegment.addAttribute(.baselineOffset, value: baseline, range: range)
        }
        if let kern = attributes.kern {
          nativeSegment.addAttribute(.kern, value: kern, range: range)
        }
        if let link = run.link { nativeSegment.addAttribute(.link, value: link, range: range) }
      }
      visibleText = visibleText + segment
      native.append(nativeSegment)
    }
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = lineSpacing
    paragraph.baseWritingDirection = direction == .rightToLeft ? .rightToLeft : .leftToRight
    switch alignment {
    case .leading: paragraph.alignment = direction == .rightToLeft ? .right : .left
    case .center: paragraph.alignment = .center
    case .trailing: paragraph.alignment = direction == .rightToLeft ? .left : .right
    }
    if native.length > 0 {
      native.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: native.length))
    }
    text = visibleText
    layout = PortableTextLayout(native, width: width)
  }
}

struct AnchoredPortableTextLayout {
  let layout: PortableTextLayout
  let origin: Anchor<CGPoint>
}

struct PortableTextLayoutKey: PreferenceKey {
  static var defaultValue: [AnchoredPortableTextLayout] { [] }
  static func reduce(value: inout [AnchoredPortableTextLayout], nextValue: () -> [AnchoredPortableTextLayout]) {
    value.append(contentsOf: nextValue())
  }
}

/// All positions are UTF-16 ranges, like UITextInput and NSAttributedString.
/// Composed sequences and glyph clusters are materialized once, not on each hit test.
final class PortableTextLayout {
  struct AttachmentPlacement: Identifiable {
    let id: Int
    let attachment: AnyAttachment
    let rect: CGRect
  }

  let attributedString: NSAttributedString
  let bounds: CGRect
  let nativeLines: [PortableTextLine]
  let attachments: [AttachmentPlacement]
  let hasLinks: Bool

  init(_ attributedString: NSAttributedString, width: CGFloat?) {
    self.attributedString = attributedString
    let storage = NSTextStorage(attributedString: attributedString)
    let manager = NSLayoutManager()
    let container = NSTextContainer(size: CGSize(width: width ?? 1_000_000, height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    storage.addLayoutManager(manager)
    manager.addTextContainer(container)
    manager.ensureLayout(for: container)
    bounds = manager.usedRect(for: container)
    var lines: [PortableTextLine] = []
    var placements: [AttachmentPlacement] = []
    var containsLinks = false
    let fullRange = manager.glyphRange(for: container)
    let string = attributedString.string as NSString
    manager.enumerateLineFragments(forGlyphRange: fullRange) { rect, used, _, lineGlyphs, _ in
      var runs: [PortableTextRun] = []
      var glyph = lineGlyphs.location
      while glyph < NSMaxRange(lineGlyphs) {
        var actualGlyphs = NSRange()
        let rawCharacters = manager.characterRange(forGlyphRange: NSRange(location: glyph, length: 1), actualGlyphRange: &actualGlyphs)
        guard rawCharacters.length > 0, rawCharacters.location < string.length else { glyph += 1; continue }
        let characters = string.rangeOfComposedCharacterSequences(for: rawCharacters)
        let glyphs = manager.glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
        let clippedGlyphs = NSIntersectionRange(glyphs, lineGlyphs)
        guard clippedGlyphs.length > 0 else { glyph += 1; continue }
        let glyphRect = manager.boundingRect(forGlyphRange: clippedGlyphs, in: container)
        let attributes = attributedString.attributes(at: characters.location, effectiveRange: nil)
        var bidiLevel: UInt8 = 0
        _ = manager.getGlyphs(in: NSRange(location: glyph, length: 1), glyphs: nil, properties: nil,
          characterIndexes: nil, bidiLevels: &bidiLevel)
        let runDirection: LayoutDirection = bidiLevel & 1 == 0 ? .leftToRight : .rightToLeft
        let url = (attributes[.link] as? URL) ?? (attributes[.link] as? String).flatMap(URL.init(string:))
        containsLinks = containsLinks || url != nil
        let slice = PortableTextRunSlice(typographicBounds: glyphRect,
          characterRange: characters.location..<NSMaxRange(characters))
        runs.append(PortableTextRun(layoutDirection: runDirection, typographicBounds: glyphRect, url: url, nativeSlices: [slice]))
        if let attachment = attributes[.textual.attachment] as? AnyAttachment {
          placements.append(AttachmentPlacement(id: characters.location, attachment: attachment, rect: glyphRect))
        }
        glyph = max(glyph + 1, NSMaxRange(clippedGlyphs))
      }
      if !runs.isEmpty {
        lines.append(PortableTextLine(origin: used.origin,
          typographicBounds: CGRect(x: used.minX, y: rect.minY, width: used.width, height: rect.height),
          nativeRuns: runs))
      }
    }
    nativeLines = lines
    attachments = placements
    hasLinks = containsLinks
  }

  func url(at point: CGPoint) -> URL? {
    if attachments.contains(where: { $0.rect.contains(point) }) { return nil }
    return nativeLines.flatMap(\.nativeRuns).first(where: { $0.typographicBounds.contains(point) })?.url
  }
}

struct PortableTextLine {
  let origin: CGPoint
  let typographicBounds: CGRect
  let nativeRuns: [PortableTextRun]
}

struct PortableTextRun {
  let layoutDirection: LayoutDirection
  let typographicBounds: CGRect
  let url: URL?
  let nativeSlices: [PortableTextRunSlice]
}

struct PortableTextRunSlice {
  let typographicBounds: CGRect
  let characterRange: Range<Int>
}

#if TEXTUAL_ENABLE_TEXT_SELECTION
extension PortableTextLine: TextLine { var runs: [any TextRun] { nativeRuns } }
extension PortableTextRun: TextRun { var slices: [any TextRunSlice] { nativeSlices } }
extension PortableTextRunSlice: TextRunSlice {}

private struct PositionedPortableTextLayout: TextLayout {
  let base: PortableTextLayout
  let origin: CGPoint
  var attributedString: NSAttributedString { base.attributedString }
  var bounds: CGRect { base.bounds }
  var lines: [any TextLine] { base.nativeLines }
}

struct PortableTextLayoutCollection: TextLayoutCollection {
  private let positioned: [PositionedPortableTextLayout]
  var layouts: [any TextLayout] { positioned }

  init(base: [AnchoredPortableTextLayout], geometry: GeometryProxy) {
    positioned = base.map { PositionedPortableTextLayout(base: $0.layout, origin: geometry[$0.origin]) }
  }

  func isEqual(to other: any TextLayoutCollection) -> Bool {
    guard let other = other as? PortableTextLayoutCollection, positioned.count == other.positioned.count else { return false }
    return zip(positioned, other.positioned).allSatisfy { $0.base === $1.base && $0.origin == $1.origin }
  }

  func needsPositionReconciliation(with other: any TextLayoutCollection) -> Bool {
    guard let other = other as? PortableTextLayoutCollection, positioned.count == other.positioned.count else { return true }
    return !zip(positioned, other.positioned).allSatisfy { $0.base === $1.base }
  }

  @available(iOS 18, macOS 15, tvOS 18, watchOS 11, visionOS 2, *)
  func index(of layout: Text.Layout) -> Int? { nil }
}
#endif

private struct PortableLinkOverlay: UIViewRepresentable {
  @Environment(\.openURL) private var openURL
  let layout: PortableTextLayout
  func makeUIView(context: Context) -> PortableLinkView { PortableLinkView(layout: layout, openURL: openURL) }
  func updateUIView(_ view: PortableLinkView, context: Context) { view.layout = layout; view.openURL = openURL }
}

private final class PortableLinkView: UIView {
  var layout: PortableTextLayout
  var openURL: OpenURLAction
  init(layout: PortableTextLayout, openURL: OpenURLAction) {
    self.layout = layout
    self.openURL = openURL
    super.init(frame: .zero)
    backgroundColor = .clear
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    super.point(inside: point, with: event) && layout.url(at: point) != nil
  }
  @objc private func tapped(_ gesture: UITapGestureRecognizer) {
    if let url = layout.url(at: gesture.location(in: self)) { openURL(url) }
  }
}
#endif
