import SwiftUI
import UIKit

/// Repositions the same three subviews, preserving the editor and its IME state.
@available(iOS 16.0, *)
struct ComposerLayout: Layout {
    let expanded: Bool
    let maximumEditorHeight: CGFloat
    let controls: ChatControlMetrics

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(1, proposal.width ?? 350)
        let textHeight = editorHeight(width: width, subviews: subviews)
        let expandedHeight = controls.textInset + textHeight + controls.textToActions
            + controls.touchTarget + controls.expandedBottomInset
        return CGSize(width: width, height: expanded ? expandedHeight : controls.diameter)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let button = controls.touchTarget
        let inset = expanded ? controls.expandedBottomInset : controls.collapsedInset
        let buttonY = expanded ? bounds.maxY - inset - button : bounds.midY - button / 2
        subviews[0].place(at: CGPoint(x: bounds.minX + inset, y: buttonY), proposal: .init(width: button, height: button))
        subviews[2].place(at: CGPoint(x: bounds.maxX - inset - button, y: buttonY), proposal: .init(width: button, height: button))
        // An optional fourth control (the command menu) sits just left of send.
        if subviews.count > 3 {
            subviews[3].place(at: CGPoint(x: bounds.maxX - inset - button * 2, y: buttonY), proposal: .init(width: button, height: button))
        }
        let textHeight = editorHeight(width: bounds.width, subviews: subviews)
        let textX = expanded ? controls.textInset : inset + button + controls.collapsedTextGap
        subviews[1].place(
            at: CGPoint(x: bounds.minX + textX, y: expanded ? bounds.minY + controls.textInset : bounds.midY - textHeight / 2),
            proposal: .init(width: editorWidth(in: bounds.width, subviews: subviews), height: textHeight)
        )
    }

    private func editorWidth(in width: CGFloat, subviews: Subviews) -> CGFloat {
        let extra = subviews.count > 3 ? controls.touchTarget : 0
        return max(1, expanded ? width - controls.textInset * 2
            : width - (controls.touchTarget + controls.collapsedInset + controls.collapsedTextGap) * 2 - extra)
    }

    private func editorHeight(width: CGFloat, subviews: Subviews) -> CGFloat {
        min(maximumEditorHeight, subviews[1].sizeThatFits(.init(width: editorWidth(in: width, subviews: subviews), height: nil)).height)
    }
}

/// The same persistent editor and controls, placed with the native Layout's
/// formulas. Only UITextView measurement is delivered on the next main turn.
@available(iOS 15.0, *)
struct ComposerLayoutLegacy<Options: View, Text: View, Send: View, Commands: View>: View {
    let expanded: Bool
    let maximumEditorHeight: CGFloat
    let controls: ChatControlMetrics
    let editorController: ComposerEditorController
    let textRevision: String
    let showsCommands: Bool
    @ViewBuilder let options: () -> Options
    @ViewBuilder let text: () -> Text
    @ViewBuilder let send: () -> Send
    @ViewBuilder let commands: () -> Commands
    @State private var measuredHeight = ceil(UIFont.preferredFont(forTextStyle: .body).lineHeight)

    init(expanded: Bool, maximumEditorHeight: CGFloat, controls: ChatControlMetrics,
        editorController: ComposerEditorController, textRevision: String, showsCommands: Bool,
        @ViewBuilder options: @escaping () -> Options, @ViewBuilder text: @escaping () -> Text,
        @ViewBuilder send: @escaping () -> Send, @ViewBuilder commands: @escaping () -> Commands) {
        self.expanded = expanded
        self.maximumEditorHeight = maximumEditorHeight
        self.controls = controls
        self.editorController = editorController
        self.textRevision = textRevision
        self.showsCommands = showsCommands
        self.options = options
        self.text = text
        self.send = send
        self.commands = commands
    }

    private var textHeight: CGFloat { min(maximumEditorHeight, measuredHeight) }
    private var height: CGFloat {
        expanded ? controls.textInset + textHeight + controls.textToActions
            + controls.touchTarget + controls.expandedBottomInset : controls.diameter
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let button = controls.touchTarget
            let inset = expanded ? controls.expandedBottomInset : controls.collapsedInset
            let buttonY = expanded ? height - inset - button : height / 2 - button / 2
            let textX = expanded ? controls.textInset : inset + button + controls.collapsedTextGap
            let extra = showsCommands ? button : 0
            let textWidth = max(1, expanded ? width - controls.textInset * 2
                : width - (button + controls.collapsedInset + controls.collapsedTextGap) * 2 - extra)
            ZStack(alignment: .topLeading) {
                options().frame(width: button, height: button).offset(x: inset, y: buttonY)
                text().frame(width: textWidth, height: textHeight, alignment: .topLeading)
                    .offset(x: textX, y: expanded ? controls.textInset : height / 2 - textHeight / 2)
                send().frame(width: button, height: button).offset(x: width - inset - button, y: buttonY)
                if showsCommands {
                    commands().frame(width: button, height: button)
                        .offset(x: width - inset - button * 2, y: buttonY)
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .background {
                ComposerLegacyMeasurement(controller: editorController, width: textWidth,
                    maximumHeight: maximumEditorHeight, textRevision: textRevision) { next in
                    if measuredHeight != next { measuredHeight = next }
                }
                .frame(width: 0, height: 0).allowsHitTesting(false)
            }
        }
        .frame(height: height)
    }
}

private struct ComposerLegacyMeasurement: UIViewRepresentable {
    let controller: ComposerEditorController
    let width: CGFloat
    let maximumHeight: CGFloat
    let textRevision: String
    let onHeight: (CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let textView = controller.textView, width > 0 else { return }
            let measured = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
            let minimum = ceil(textView.font?.lineHeight ?? 24)
            let height = min(maximumHeight, max(minimum, ceil(measured)))
            let shouldScroll = measured > maximumHeight + 1
            if textView.isScrollEnabled != shouldScroll { textView.isScrollEnabled = shouldScroll }
            onHeight(height)
        }
    }
}
