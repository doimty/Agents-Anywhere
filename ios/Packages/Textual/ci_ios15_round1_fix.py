from pathlib import Path
import re

root = Path(__file__).resolve().parent
source = root / 'Sources' / 'Textual'
changed = []

# The caller has read all these preview tails. Keep the runtime prefix byte-for-byte.
preview_files = [
    source / 'Internal/Image/ImageView.swift',
    source / 'Internal/StructuredText/BlockVStack.swift',
    source / 'StructuredText/StructuredText.swift',
    source / 'InlineText/InlineText.swift',
    source / 'StructuredText/Style/Default/DefaultBlockQuoteStyle.swift',
    source / 'StructuredText/Style/Default/DefaultCodeBlockStyle.swift',
    source / 'StructuredText/Style/Default/DefaultHeadingStyle.swift',
    source / 'StructuredText/Style/Default/DefaultListItemStyle.swift',
    source / 'StructuredText/Style/Default/DefaultParagraphStyle.swift',
    source / 'StructuredText/Style/Default/DefaultTableStyle.swift',
    source / 'StructuredText/Style/Default/DividerThematicBreakStyle.swift',
    source / 'StructuredText/Style/Default/OverflowTableStyle.swift',
    source / 'StructuredText/Style/GitHub/GitHubBlockQuoteStyle.swift',
    source / 'StructuredText/Style/GitHub/GitHubCodeBlockStyle.swift',
    source / 'StructuredText/Style/GitHub/GitHubHeadingStyle.swift',
    source / 'StructuredText/Style/GitHub/GitHubParagraphStyle.swift',
    source / 'StructuredText/Style/GitHub/GitHubTableStyle.swift',
    source / 'StructuredText/Style/GitHub/GitHubThematicBreak.swift',
    root.parent / 'SwiftUIMath/swiftui-math-0.1.0/Sources/SwiftUIMath/Math.swift',
]
availability = '@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)\n'
preview_count = 0
for path in preview_files:
    before = path.read_text(encoding='utf-8')
    lines = before.splitlines(keepends=True)
    first = next(i for i, line in enumerate(lines) if line.startswith('#Preview'))
    start = first
    while start > 0 and (not lines[start - 1].strip() or lines[start - 1].strip().startswith('@available')):
        start -= 1
    prefix, tail = ''.join(lines[:start]), ''.join(lines[start:])
    count = len(re.findall(r'(?m)^#Preview', tail))
    new_tail = re.sub(r'(?m)^#Preview', availability + '#Preview', tail)
    restored = new_tail.replace(availability + '#Preview', '#Preview')
    assert restored == tail, path
    after = prefix + '#if DEBUG\n' + new_tail.rstrip('\n') + '\n#endif\n'
    assert after[:len(prefix)] == prefix, path
    path.write_text(after, encoding='utf-8', newline='\n')
    preview_count += count
    changed.append(path)

# Fixed arity equality snapshots preserve Tuple(...) and .values.N call syntax.
def generics(n, protocol):
    return ', '.join(f'P{i}: {protocol}' for i in range(n))

def types(n):
    return ', '.join(f'P{i}' for i in range(n))

def parameters(n):
    return ', '.join(f'_ property{i}: P{i}' for i in range(n))

def arguments(n):
    return ', '.join(f'property{i}' for i in range(n))

text = 'import Foundation\n\n// Finite arity snapshots avoid the iOS 17 parameter-pack runtime.\n'
text += 'struct Tuple0: Equatable {\n  var values: ()\n  static func == (lhs: Self, rhs: Self) -> Bool { true }\n}\n\nfunc Tuple() -> Tuple0 { Tuple0(values: ()) }\n'
for n in range(1, 9):
    value_type = f'P0' if n == 1 else '(' + types(n) + ')'
    comparisons = ' && '.join(f'lhs.values.{i} == rhs.values.{i}' for i in range(n)) if n > 1 else 'lhs.values == rhs.values'
    value = 'property0' if n == 1 else '(' + arguments(n) + ')'
    text += f'\nstruct Tuple{n}<{generics(n, "Equatable")}>: Equatable {{\n  var values: {value_type}\n  static func == (lhs: Self, rhs: Self) -> Bool {{\n    {comparisons}\n  }}\n}}\n'
    text += f'\nfunc Tuple<{generics(n, "Equatable")}>({parameters(n)}) -> Tuple{n}<{types(n)}> {{\n  Tuple{n}(values: {value})\n}}\n'
path = source / 'Internal/Helpers/Tuple.swift'
path.write_text(text, encoding='utf-8', newline='\n')
changed.append(path)

path = source / 'TextProperty/TupleTextProperty.swift'
path.write_text('''import Foundation

/// Ordered composition with value equality/hash semantics, without parameter packs.
struct TupleTextProperty: TextProperty {
  var properties: [AnyTextProperty]

  func apply(in attributes: inout AttributeContainer, environment: TextEnvironmentValues) {
    for property in properties {
      property.apply(in: &attributes, environment: environment)
    }
  }
}
''', encoding='utf-8', newline='\n')
changed.append(path)

path = source / 'TextProperty/TextProperty.swift'
text = path.read_text(encoding='utf-8')
old = '''  /// Creates a single property by composing multiple properties.
  public init<each P: TextProperty>(_ properties: repeat each P) {
    self.init(TupleTextProperty(repeat each properties))
  }
'''
assert old in text
replacement = '''  /// Creates an empty (no-op) composition.
  public init() {
    self.init(TupleTextProperty(properties: []))
  }

  /// Creates ordered compositions using deployment-safe, finite arity overloads.
'''
# Arity one is already covered by the existing concrete-property initializer.
for n in range(2, 9):
    properties = ', '.join(f'AnyTextProperty(property{i})' for i in range(n))
    replacement += f'  public init<{generics(n, "TextProperty")}>({parameters(n)}) {{\n    self.init(TupleTextProperty(properties: [{properties}]))\n  }}\n\n'
text = text.replace(old, replacement.rstrip('\n') + '\n')
path.write_text(text, encoding='utf-8', newline='\n')
changed.append(path)

path = source / 'InlineText/InlineStyle.swift'
text = path.read_text(encoding='utf-8')
for name in ['code', 'emphasis', 'link', 'strong', 'strikethrough']:
    old = f'''  public func {name}<each P: TextProperty>(_ properties: repeat each P) -> Self {{
    modifyingStyle {{ $0.{name} = AnyTextProperty(repeat each properties) }}
  }}'''
    assert old in text, name
    overloads = [f'  public func {name}() -> Self {{\n    modifyingStyle {{ $0.{name} = AnyTextProperty() }}\n  }}']
    for n in range(1, 9):
        overloads.append(f'  public func {name}<{generics(n, "TextProperty")}>({parameters(n)}) -> Self {{\n    modifyingStyle {{ $0.{name} = AnyTextProperty({arguments(n)}) }}\n  }}')
    text = text.replace(old, '\n\n'.join(overloads))
path.write_text(text, encoding='utf-8', newline='\n')
changed.append(path)

# A fresh computed empty array has no shared non-Sendable stored state.
path = source / 'Internal/TextFragment/PortableTextFragment.swift'
text = path.read_text(encoding='utf-8')
old = '  static let defaultValue: [AnchoredPortableTextLayout] = []'
assert old in text
text = text.replace(old, '  static var defaultValue: [AnchoredPortableTextLayout] { [] }')
path.write_text(text, encoding='utf-8', newline='\n')
changed.append(path)

assert not any(re.search(r'<each\s|repeat\s+each|in\s+repeat\s*\(', path.read_text(encoding='utf-8')) for path in [
    source / 'Internal/Helpers/Tuple.swift', source / 'TextProperty/TupleTextProperty.swift',
    source / 'TextProperty/TextProperty.swift', source / 'InlineText/InlineStyle.swift'])
print(f'Isolated {preview_count} preview declarations in {len(preview_files)} files; replaced all Textual parameter-pack APIs with 0..8 overloads; defaultValue now computed.')
for path in changed:
    print(path.relative_to(root.parent.parent.parent).as_posix())
