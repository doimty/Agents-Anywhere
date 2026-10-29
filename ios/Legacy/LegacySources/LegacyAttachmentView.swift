import SwiftUI
import UIKit

/// Attachment row in the transcript. Images load through the authenticated
/// attachment endpoint (base64 in the JSON body) and can be opened full screen;
/// other files show name, type and size only.
struct LegacyAttachmentRow: View {
    let content: V2AttachmentContent

    @EnvironmentObject private var store: LegacySessionStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var imageData: Data?
    @State private var isLoading = false
    @State private var showsViewer = false

    private var isImage: Bool {
        content.mediaType?.hasPrefix("image/") == true
    }

    private var title: String {
        content.name ?? String(localized: "附件")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isImage ? "photo" : "doc")
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline).lineLimit(2)
                    if let size = content.size {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if isLoading { ProgressView().scaleEffect(0.7) }
            }

            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onTapGesture { showsViewer = true }
                    .accessibilityLabel(title)
            }

            if let url = content.openUrl.flatMap(URL.init(string:)) {
                Link("在服务器打开", destination: url)
                    .font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppTheme.groupedFill(colorScheme),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppTheme.secondaryControlStroke(colorScheme).opacity(0.55), lineWidth: 0.5)
        )
        .task {
            guard isImage, imageData == nil, !isLoading, let fileId = content.fileId else { return }
            isLoading = true
            imageData = await store.loadImage(fileId: fileId)
            isLoading = false
        }
        .sheet(isPresented: $showsViewer) {
            if let imageData, let image = UIImage(data: imageData) {
                LegacyImageViewer(image: image) { showsViewer = false }
            }
        }
    }
}

private struct LegacyImageViewer: View {
    let image: UIImage
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
                    .padding(16)
            }
            .accessibilityLabel("关闭")
        }
    }
}
