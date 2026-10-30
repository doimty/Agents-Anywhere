import SwiftUI

/// The phone drawer needs a navigation host inside its moving card. The iPad
/// detail already has the split view's host; nesting another stack there would
/// duplicate navigation chrome and safe-area handling.
struct ChatDetailNavigation: ViewModifier {
    let insets: EdgeInsets
    @Environment(\.sidebarDrawerPresentation) private var presentation
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        Group {
            if presentation == .drawer {
                AppNavigationStack { content }
                    .ignoresSafeArea(.keyboard)
                    // Preserve the drawer's stable, untransformed safe area,
                    // including keyboard avoidance. Pages add no other inset.
                    .padding(insets)
            } else {
                content
            }
        }
        .background(Color(uiColor: .systemBackground))
        .tint(AppTheme.primaryControlBackground(colorScheme))
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
                }
                if alignsTitleLeading {
                    ToolbarItem(placement: .principal) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title).font(.headline).lineLimit(1)
                                .accessibilityAddTraits(.isHeader)
                            if subtitle != nil || status != nil {
                                ChatToolbarSubtitle(subtitle: subtitle, status: status)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .appSharedBackgroundHidden()
                } else if subtitle != nil || status != nil {
                    if #available(iOS 26.0, *), AppCompatibility.useNativeUI {
                        ToolbarItem(placement: .subtitle) {
                            ChatToolbarSubtitle(subtitle: subtitle, status: status)
                        }
                    } else {
                        ToolbarItem(placement: .principal) {
                            VStack(spacing: 1) {
                                Text(title).font(.headline).lineLimit(1)
                                ChatToolbarSubtitle(subtitle: subtitle, status: status)
                            }
                        }
                    }
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

    @ViewBuilder
    func appSharedBackgroundHidden() -> some View {
        if #available(iOS 26.0, *), AppCompatibility.useNativeUI {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
