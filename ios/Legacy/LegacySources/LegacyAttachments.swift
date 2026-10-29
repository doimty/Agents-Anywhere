import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// One picked attachment before upload. Kept as `Data` so the upload does not
/// depend on a security-scoped URL that expires with the picker callback.
struct LegacyPickedFile {
    let name: String
    let mediaType: String
    let data: Data

    static let maximumBytes = 25 * 1024 * 1024

    static func from(url: URL) throws -> LegacyPickedFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else {
            throw LegacyAttachmentError.tooLarge(url.lastPathComponent)
        }
        let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        return LegacyPickedFile(
            name: url.lastPathComponent,
            mediaType: type?.preferredMIMEType ?? "application/octet-stream",
            data: data
        )
    }
}

enum LegacyAttachmentError: LocalizedError {
    case tooLarge(String)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .tooLarge(let name): return String(localized: "「\(name)」超过 25 MiB，无法上传。")
        case .unreadable: return String(localized: "无法读取这个文件。")
        }
    }
}

/// `PHPickerViewController` is available on iOS 14, unlike SwiftUI's
/// `PhotosPicker` (iOS 16). It runs out of process, so no photo permission
/// prompt is needed.
struct LegacyPhotoPicker: UIViewControllerRepresentable {
    var selectionLimit: Int = 5
    let onPicked: ([LegacyPickedFile]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = max(1, selectionLimit)
        configuration.selection = .ordered
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: LegacyPhotoPicker

        init(parent: LegacyPhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else { return parent.onCancel() }
            let group = DispatchGroup()
            let lock = NSLock()
            var files: [LegacyPickedFile] = []

            for result in results {
                let provider = result.itemProvider
                guard let identifier = provider.registeredTypeIdentifiers.first(where: {
                    UTType($0)?.conforms(to: .image) == true
                }) else { continue }
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                    defer { group.leave() }
                    guard let data, !data.isEmpty else { return }
                    let type = UTType(identifier)
                    let ext = type?.preferredFilenameExtension ?? "jpg"
                    let file = LegacyPickedFile(
                        name: "Photo-\(UUID().uuidString.prefix(8)).\(ext)",
                        mediaType: type?.preferredMIMEType ?? "image/jpeg",
                        data: data
                    )
                    lock.lock()
                    files.append(file)
                    lock.unlock()
                }
            }

            group.notify(queue: .main) {
                self.parent.onPicked(files.sorted { $0.name < $1.name })
            }
        }
    }
}
