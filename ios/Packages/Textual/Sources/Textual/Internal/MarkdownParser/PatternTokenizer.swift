import Foundation

/// The original opt-in prefix tokenizer, with the same patterns and captures.
/// NSRegularExpression avoids the Swift Regex runtime's iOS 16 floor.
struct PatternTokenizer {
  private let patterns: [Pattern]
  init(patterns: [Pattern]) { self.patterns = patterns }

  func tokenize(_ input: String) throws -> [Token] {
    guard !patterns.isEmpty else { return [.init(type: .text, content: input)] }
    var tokens: [Token] = []
    var currentIndex = input.startIndex
    while currentIndex < input.endIndex {
      var matchFound = false
      for pattern in patterns {
        guard let match = pattern.regex.firstMatch(in: input, options: .anchored,
          range: NSRange(currentIndex..., in: input)),
          let range = Range(match.range, in: input), !range.isEmpty,
          let captured = Range(match.range(at: 1), in: input)
        else { continue }
        if currentIndex < range.lowerBound {
          tokens.append(.init(type: .text, content: String(input[currentIndex..<range.lowerBound])))
        }
        tokens.append(.init(type: pattern.tokenType, content: String(input[range]),
          capturedContent: String(input[captured])))
        currentIndex = range.upperBound
        matchFound = true
        break
      }
      if !matchFound {
        let next = input.index(after: currentIndex)
        if let last = tokens.indices.last, tokens[last].type == .text {
          tokens[last].content += String(input[currentIndex])
        } else {
          tokens.append(.init(type: .text, content: String(input[currentIndex])))
        }
        currentIndex = next
      }
    }
    return tokens
  }
}

extension PatternTokenizer {
  struct Pattern: @unchecked Sendable {
    let regex: NSRegularExpression
    let tokenType: TokenType
  }

  struct Token: Hashable, Sendable {
    let type: TokenType
    var content: String
    var capturedContent: String?
  }

  struct TokenType: Hashable, RawRepresentable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { rawValue = value }
  }
}

extension PatternTokenizer.Pattern {
  static let emoji = Self(regex: try! NSRegularExpression(pattern: #":([a-zA-Z0-9_+-]+):"#), tokenType: .emoji)
  static let mathBlock = Self(regex: try! NSRegularExpression(pattern: #"(?s)\$\$(.+?)\$\$"#), tokenType: .mathBlock)
  static let mathInline = Self(regex: try! NSRegularExpression(pattern: #"\$(?!\$)((?:\\\$|[^$\n])+)\$"#), tokenType: .mathInline)
}

extension PatternTokenizer.TokenType {
  static let text: Self = "text"
  static let emoji: Self = "emoji"
  static let mathBlock: Self = "mathBlock"
  static let mathInline: Self = "mathInline"
}
