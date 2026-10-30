import Perception
import SwiftUI

struct ChatComposer: View {
    @Perception.Bindable var draft: ComposerDraft
    let editor: ComposerEditorController
    let isStreaming: Bool
    var canSend = true
    var canStop = true
    var isBusy = false
    var placeholder = String(localized: "询问 Agents")
    let maximumEditorHeight: CGFloat
    let controls: ChatControlMetrics
    let onSend: () -> Void
    let onStop: () -> Void
    let onOptions: () -> Void
    /// Shown beside send when the session's runtime offers slash commands.
    var showsCommands = false
    var commandsActive = false
    var onCommands: () -> Void = {}
    /// Reports draft mutations from this subtree only. Persisting the draft
    /// must not make the page root observe the editor's text.
    var onDraftChange: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glass

    var body: some View {
        AppGlassEffectContainer(spacing: 12) {
            VStack(spacing: 0) {
                if !draft.attachments.isEmpty { attachmentTray }
                composerLayout
            }
            .appGlassEffect(.interactive, in: RoundedRectangle(cornerRadius: draft.isExpanded ? controls.expandedCornerRadius : controls.collapsedCornerRadius, style: .continuous))
            .appGlassEffectID("composer", in: glass)
        }
        .padding(.horizontal, draft.isExpanded ? ChatControlMetrics.expandedHorizontalInset : ChatControlMetrics.collapsedHorizontalInset)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .animation(reduceMotion ? nil : .appSmooth(duration: 0.24), value: draft.isExpanded)
        // The composer is the only subtree that already re-evaluates on every
        // keystroke, including each Chinese IME marked-text update. Observing
        // the draft from the page root re-evaluated the whole conversation.
        .appOnChange(of: draft.text) { _, _ in onDraftChange() }
        .appOnChange(of: draft.attachments) { _, _ in onDraftChange() }
    }

    @ViewBuilder private var composerLayout: some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            ComposerLayout(expanded: draft.isExpanded, maximumEditorHeight: maximumEditorHeight, controls: controls) {
                optionsButton
                textEditor
                sendButton
                if showsCommands { commandsButton }
            }
        } else {
            ComposerLayoutLegacy(expanded: draft.isExpanded, maximumEditorHeight: maximumEditorHeight,
                controls: controls, editorController: editor, textRevision: draft.text, showsCommands: showsCommands) {
                optionsButton
            } text: {
                textEditor
            } send: {
                sendButton
            } commands: {
                commandsButton
            }
        }
    }

    private var optionsButton: some View {
        Button(action: onOptions) {
            AppSymbol("plus", size: 24)
                .frame(width: controls.touchTarget, height: controls.touchTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "附件与对话选项"))
        .accessibilityIdentifier("chat.composer.options")
    }

    private var textEditor: some View {
        ZStack(alignment: .topLeading) {
            if draft.text.isEmpty {
                Text(placeholder).font(.body).lineLimit(1).foregroundStyle(.secondary).allowsHitTesting(false)
            }
            NativeComposerEditor(draft: draft, controller: editor, maximumHeight: maximumEditorHeight, onCommandSend: onSend)
        }
    }

    private var sendButton: some View {
        Button(action: isStreaming ? onStop : onSend) {
            AppSymbol(isStreaming ? "stop.fill" : "arrow.up", size: isStreaming ? 13 : 18)
                .appSymbolReplaceTransition()
                .foregroundStyle(AppTheme.primaryControlForeground(colorScheme))
                .frame(width: controls.sendDiameter, height: controls.sendDiameter)
                .background(AppTheme.primaryControlBackground(colorScheme).opacity((isStreaming ? canStop : canSend && draft.canAttemptSend) && !isBusy ? 1 : 0.42), in: Circle())
                .frame(width: controls.touchTarget, height: controls.touchTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy || (isStreaming ? !canStop : !canSend || !draft.canAttemptSend))
        .accessibilityLabel(isStreaming ? String(localized: "停止生成") : String(localized: "发送消息"))
        .accessibilityHint(draft.isComposing ? String(localized: "请先确认输入法候选文字") : "")
        .accessibilityIdentifier("chat.composer.send")
    }

    private var commandsButton: some View {
        Button(action: onCommands) {
            AppSymbol("command", size: 18)
                .foregroundStyle(commandsActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: controls.touchTarget, height: controls.touchTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "指令"))
        .accessibilityAddTraits(commandsActive ? .isSelected : [])
        .accessibilityIdentifier("chat.composer.commands")
    }

    private var attachmentTray: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(draft.attachments) { attachment in
                    ChatComposerAttachment(attachment: attachment) {
                        draft.attachments.removeAll { $0.id == attachment.id }
                    }
                }
            }
        }
        .appHiddenScrollIndicators()
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }
}
