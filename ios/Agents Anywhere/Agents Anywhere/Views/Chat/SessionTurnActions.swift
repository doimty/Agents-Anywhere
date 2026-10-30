import SwiftUI
import UIKit

struct SessionTurnActions: View, Equatable {
    let action: TimelineTurnAction
    @State private var copied = false
    @State private var shareText: String?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.action == rhs.action }

    var body: some View {
        HStack(spacing: 2) {
            Button {
                UIPasteboard.general.string = action.copyText; copied = true
            } label: { AppSymbol(copied ? "checkmark" : "document.on.document").frame(width: 44, height: 44) }
            .accessibilityLabel(copied ? String(localized: "已复制") : String(localized: "复制回复"))
            .task(id: copied) {
                guard copied else { return }
                do { try await ClientTask.sleep(for: .seconds(2)); copied = false } catch {}
            }

            if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
                ShareLink(item: TurnReplyShareItem(action: action),
                          preview: SharePreview(String(localized: "回复"))) {
                    shareIcon
                }
                .accessibilityLabel(String(localized: "分享回复"))
            } else {
                Button { shareText = action.copyText } label: { shareIcon }
                    .accessibilityLabel(String(localized: "分享回复"))
            }
        }
        .disabled(!action.hasReplyText)
        .buttonStyle(.plain).font(.system(size: 15)).foregroundStyle(.secondary).padding(.leading, -10)
        .accessibilityIdentifier("chat.turn.actions")
        .sheet(isPresented: sharePresented) {
            LegacyActivityView(activityItems: [shareText ?? ""])
        }
    }

    private var shareIcon: some View {
        AppSymbol("square.and.arrow.up").frame(width: 44, height: 44)
    }

    private var sharePresented: Binding<Bool> {
        Binding(get: { shareText != nil }, set: { presented in if !presented { shareText = nil } })
    }
}

/// Exports the joined reply text only when a share actually starts.
@available(iOS 16.0, *)
private struct TurnReplyShareItem: Transferable {
    let action: TimelineTurnAction
    var text: String { action.copyText }
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.text)
    }
}

private struct LegacyActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
