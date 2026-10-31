import SwiftUI
import UIKit

/// The phone drawer needs a navigation host inside its moving card. The iPad
/// detail already has the split view's host; nesting another stack there would
/// duplicate navigation chrome and safe-area handling.
struct ChatDetailNavigation: ViewModifier {
    let insets: EdgeInsets
    @Environment(\.sidebarDrawerPresentation) private var presentation
    @Environment(\.colorScheme) private var colorScheme
    @State private var keyboardHeight: CGFloat = 0

    func body(content: Content) -> some View {
        Group {
            if presentation == .drawer {
                AppNavigationStack { content }
                    // The page keeps the keyboard safe area so its own bottom
                    // inset follows the keyboard. The drawer already reports the
                    // keyboard inside these insets, so padding with the raw value
                    // lifts the whole page a second time and strands the composer
                    // far above the keyboard. Pad with the container part only.
                    .padding(containerInsets)
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                              let window = UIApplication.shared.connectedScenes
                                .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else {
                            keyboardHeight = 0
                            return
                        }
                        let height = max(0, window.bounds.maxY - frame.minY)
                        if abs(height - keyboardHeight) > 0.5 { keyboardHeight = height }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                        keyboardHeight = 0
                    }
            } else {
                content
            }
        }
        .background(Color(uiColor: .systemBackground))
        .tint(AppTheme.primaryControlBackground(colorScheme))
    }

    /// Only subtract when the reported inset really contains the keyboard;
    /// otherwise the container's own bottom inset stays untouched.
    private var containerInsets: EdgeInsets {
        let bottom = keyboardHeight > 0 && insets.bottom >= keyboardHeight - 24
            ? max(0, insets.bottom - keyboardHeight)
            : insets.bottom
        return EdgeInsets(top: insets.top, leading: insets.leading,
                          bottom: bottom, trailing: insets.trailing)
    }
}

/// Native title/subtitle placements own size, spacing and scroll-edge rendering
/// on iOS 26. iOS 15–18 have no subtitle placement, so the same title and the
/// same status line are composed in the principal item; no header row is added
/// to the timeline and no toolbar action is dropped.
struct ChatPageToolbar: ViewModifier {
    let title: String
    var subtitle: String?
    var status: ChatHeaderStatus?
    var alignsTitleLeading = false
    let onMenu: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .appNavigationSubtitle(alignsTitleLeading ? "" : subtitle ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .appNavigationBarVisible()
            .appRemoveSidebarToggle()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onMenu) { SidebarMenuIcon() }
                        .accessibilityLabel(String(localized: "打开侧栏"))
                        .accessibilityIdentifier("chat.sidebar.open")
                }
                ToolbarItem(placement: .principal) {
                    // No subtitle placement below iOS 26: the same title and
                    // status compose the principal item instead of a new row.
                    VStack(alignment: alignsTitleLeading ? .leading : .center, spacing: 1) {
                        Text(title).font(.headline).lineLimit(1)
                            .accessibilityAddTraits(.isHeader)
                        if subtitle != nil || status != nil {
                            ChatToolbarSubtitle(subtitle: subtitle, status: status)
                        }
                    }
                    .multilineTextAlignment(alignsTitleLeading ? .leading : .center)
                    .frame(maxWidth: .infinity, alignment: alignsTitleLeading ? .leading : .center)
                }
            }
    }
}

private struct ChatToolbarSubtitle: View {
    let subtitle: String?
    let status: ChatHeaderStatus?
    @ScaledMetric(relativeTo: .caption) private var lineHeight: CGFloat = 16

    private var text: String {
        [subtitle, status?.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var body: some View {
        HStack(spacing: 4) {
            if let status {
                Group {
                    if status.isProgress { ProgressView().controlSize(.mini) }
                    else { AppSymbol(status.symbol, size: 12) }
                }.frame(width: lineHeight, height: lineHeight)
            }
            Text(verbatim: text).lineLimit(1)
        }
        .font(.caption).foregroundStyle(.secondary)
        .frame(height: lineHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([subtitle, status?.detail].compactMap { $0 }.joined(separator: " · "))
    }
}

struct SidebarMenuIcon: View {
    var body: some View {
        AppSymbol("sidebar.left", size: 22).accessibilityHidden(true)
    }
}

extension View {
    @ViewBuilder
    func appNavigationSubtitle(_ subtitle: String) -> some View {
        if #available(iOS 26.0, *), AppCompatibility.useNativeUI {
            navigationSubtitle(subtitle)
        } else {
            self
        }
    }

    @ViewBuilder
    func appNavigationBarVisible() -> some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            toolbar(.visible, for: .navigationBar)
        } else {
            navigationBarHidden(false)
        }
    }

}
