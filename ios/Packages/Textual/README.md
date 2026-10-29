# Textual for iOS

Source: https://github.com/gonzalezreal/textual, version 0.5.0,
commit `01b51875a5406eefc95f52a058cb059e7bc94dc4`. The MIT license is retained.
Only `Sources` and the runtime package dependencies are vendored; the upstream
snapshot test suite is not included.

This local package keeps the text-selection crash fix reproducible in Xcode and
on another development machine. Do not patch a DerivedData checkout.

The package also bundles its own `PrivacyInfo.xcprivacy`. Its `CA92.1` declaration
covers the app-local UserDefaults flag that enables Textual logging; the library
does not rely on the app's manifest to declare its own API use.

The selection changes adapt the stale-position validation from
[upstream PR 80](https://github.com/gonzalezreal/textual/pull/80) and the
empty-paragraph/layout-size fixes from the first two commits of
[upstream PR 88](https://github.com/gonzalezreal/textual/pull/88)
(`2b29f6e` and `9bc4036`). They are not released in 0.5.0.

Local additions apply the same validation to selected text, caret geometry,
range traversal and layout reconciliation. Invalid positions yield an empty
result instead of indexing a replaced layout. Traversal skips empty paragraphs,
lines and runs; valid selections keep their original UTF-16 offsets.

Selection layout snapshots capture their resolved size for comparison. They do
not feed size back through View state or reset overlay identity as text grows.
Reconciliation only publishes a changed range, following the approach in
[upstream PR 67](https://github.com/gonzalezreal/textual/pull/67), and coordination
does not repeatedly clear already-empty selections.

The iOS app supplies native code, table and image components. Local style APIs
expose literal code and attributed table cells (including empty columns), and
allow selection to be scoped to text instead of covering embedded controls.
Attachments remain live SwiftUI views rather than Canvas symbols, so image
buttons can receive input. Embedded controls publish exclusion rectangles to
the selection overlay. The parser, syntax highlighter, formatter and upstream
clipboard exporter remain unchanged; the app's code button copies literal text.

## iOS 15 back-deployment candidate

The public `StructuredText`, `InlineText`, `MarkupParser`, block styles and `.textual`
configuration remain the same. The shared Foundation Markdown parser, presentation
intents, Prism resources, clipboard formatter and live attachment bodies remain in
use. The prefix tokenizer uses the same opt-in patterns through
`NSRegularExpression`, rather than the iOS 16 Swift Regex runtime.

- iOS 18+ retains `ModernTextFragment`, `Text.Layout` and the original interaction
  metadata pipeline, with explicit availability at the modern type boundary.
- iOS 15–17 uses the original `SwiftUI.Text` label, a public TextKit 1 geometry
  provider and the same non-editable UIKit selection/copy/link interaction. This
  is a low-level adapter, not a second Markdown renderer or a WebView.
- `Attachment.sizeThatFits` accepts `TextualSizeProposal` (optional width/height,
  `.unspecified`, `.zero`, `.infinity`) to avoid exposing unavailable SwiftUI layout
  types. The app's image and Git badge attachment conformances use this proposal.
- Custom style labels can mirror font/color traits to the geometry provider with
  `.textual.textProperties(AnyTextProperty(...))`. The existing font-relative
  `.textual.lineSpacing` modifier also mirrors its resolved line spacing.
- Pre-Layout/Grid adapters retain the original styled block children, collapsing
  margins, table cell styles, anchors and overflow scopes.
- Shared observable state uses `ObservableObject`; the reflected-font cache uses
  an internal recursive lock. The remaining `Font.Width` API is explicitly iOS 16+.
- The dependency is the fixed local SwiftUIMath 0.1.0 source beside this package.
  Its original typesetter/Canvas/fonts are retained and its SwiftUI boundary is
  actually back-deployed; bundle minimum-version metadata is not used to conceal
  an unavailable dependency.

**Validation is not complete.** Windows cannot type-check Apple SDK modules or
prove matching SwiftUI/TextKit line breaks and glyph hit testing on iOS 15.
The original application must compile in macOS CI with a 15.0 deployment target;
old-system device/simulator selection, attachments, Dynamic Type, RTL, overflow and
streaming tests and original-style screenshot comparisons are still required.

The Prism bundle is unchanged. A resource-level check found an existing missing
`turtle` base for the `sparql` grammar during bundle initialization; this is a
recorded baseline issue, not an iOS 15 port change or a completed highlighter test.

Run the headless regression tests from the repository root (no app or simulator):

```sh
swift test --package-path ios/Packages/Textual --scratch-path ios/.build/textual-tests
```

When upstream releases these fixes, compare the regression coverage before
switching the Xcode project back to a remote package and removing this copy.
