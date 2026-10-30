import SwiftUI
import UIKit

/// The drawer ignores every safe area so its card can be full-screen, which
/// also drops the keyboard inset. A bottom `safeAreaInset` then sits under the
/// keyboard, so a composer there must reserve that height itself. Outside the
/// drawer the system still moves the content, so this is a no-op.
private struct AppKeyboardBottomInset: ViewModifier {
    @State private var inset: CGFloat = 0
    @Environment(\.sidebarDrawerPresentation) private var presentation

    func body(content: Content) -> some View {
        content
            .padding(.bottom, presentation == .drawer ? inset : 0)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                      let window = UIApplication.shared.connectedScenes
                        .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return inset = 0 }
                let next = max(0, window.bounds.maxY - frame.minY)
                if abs(next - inset) > 0.5 { inset = next }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                inset = 0
            }
    }
}

extension View {
    /// Reserve the keyboard height inside the drawer's full-screen card.
    func appKeyboardBottomInset() -> some View { modifier(AppKeyboardBottomInset()) }
}
