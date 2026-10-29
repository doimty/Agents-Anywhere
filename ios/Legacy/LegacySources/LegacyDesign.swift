import SwiftUI

/// Visual language shared by the iOS 15 screens. Mirrors the shipped app's theme
/// (`AppTheme`): monochrome surfaces, thin strokes, generous corner radii, and a
/// single accent for the primary action.
enum LegacyStyle {
    static let corner: CGFloat = 18
    static let gutter: CGFloat = 20
    static let sectionSpacing: CGFloat = 24
    static let rowSpacing: CGFloat = 10
}

struct LegacyCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppTheme.groupedFill(colorScheme),
                in: RoundedRectangle(cornerRadius: LegacyStyle.corner, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LegacyStyle.corner, style: .continuous)
                    .strokeBorder(AppTheme.secondaryControlStroke(colorScheme).opacity(0.55), lineWidth: 0.5)
            )
    }
}

struct LegacyChip: View {
    let text: String
    var color: Color = .secondary
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            }
            Text(text).font(.caption2.weight(.medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
    }
}

struct LegacySectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing).font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}

struct LegacyPrimaryButton: View {
    let title: String
    var symbol: String?
    var isEnabled = true
    var isLoading = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().scaleEffect(0.8)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundColor(AppTheme.primaryControlForeground(colorScheme))
            .background(
                AppTheme.primaryControlBackground(colorScheme).opacity(isEnabled ? 1 : 0.25),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }
}

struct LegacyEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundColor(.secondary)
            Text(title).font(.subheadline.weight(.medium))
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}
