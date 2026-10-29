import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Shared draft state holds an owned import job, not a PhotosPickerItem whose
/// type is unavailable on iOS 15. Both backends preserve the original bytes.
nonisolated struct AppPickedPhoto: Equatable, @unchecked Sendable {
    let id: UUID
    let supportedContentTypes: [UTType]
    private let loader: () async throws -> Data?
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func loadData() async throws -> Data? { try await loader() }

    @available(iOS 16.0, *)
    init(_ item: PhotosPickerItem) {
        id = UUID()
        supportedContentTypes = item.supportedContentTypes
        loader = { try await item.loadTransferable(type: Data.self) }
    }

    init(_ result: PHPickerResult) {
        id = UUID()
        let provider = result.itemProvider
        supportedContentTypes = provider.registeredTypeIdentifiers.compactMap { UTType($0) }
        let type = supportedContentTypes.first { $0.conforms(to: .image) }?.identifier ?? UTType.image.identifier
        loader = {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: data) }
                }
            }
        }
    }
}

struct AppPhotoPicker<Label: View>: View {
    @Binding var selection: AppPickedPhoto?
    private let label: Label
    @State private var presented = false
    init(selection: Binding<AppPickedPhoto?>, @ViewBuilder label: () -> Label) {
        _selection = selection; self.label = label()
    }
    var body: some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            AppModernSinglePhotoPicker(selection: $selection, label: label)
        } else {
            Button { presented = true } label: { label }
                .sheet(isPresented: $presented) {
                    AppLegacyPhotoPicker(limit: 1) { results in
                        if let result = results.first { selection = AppPickedPhoto(result) }
                        presented = false
                    }
                }
        }
    }
}

@available(iOS 16.0, *)
private struct AppModernSinglePhotoPicker<Label: View>: View {
    @Binding var selection: AppPickedPhoto?
    let label: Label
    @State private var item: PhotosPickerItem?
    var body: some View {
        PhotosPicker(selection: $item, matching: .images) { label }
            .appOnChange(of: item) { _, value in
                if let value { selection = AppPickedPhoto(value) }
            }.appOnChange(of: selection) { _, value in
                if value == nil { item = nil }
            }
    }
}

extension View {
    @ViewBuilder
    func appPhotosPicker(isPresented: Binding<Bool>, selection: Binding<[AppPickedPhoto]>,
                         maxSelectionCount: Int) -> some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            modifier(AppModernPhotosModifier(presented: isPresented, selection: selection,
                                            limit: maxSelectionCount))
        } else {
            sheet(isPresented: isPresented) {
                AppLegacyPhotoPicker(limit: maxSelectionCount) { results in
                    selection.wrappedValue = results.map(AppPickedPhoto.init)
                    isPresented.wrappedValue = false
                }
            }
        }
    }
}

@available(iOS 16.0, *)
private struct AppModernPhotosModifier: ViewModifier {
    @Binding var presented: Bool
    @Binding var selection: [AppPickedPhoto]
    let limit: Int
    @State private var items: [PhotosPickerItem] = []
    func body(content: Content) -> some View {
        content.photosPicker(isPresented: $presented, selection: $items,
                             maxSelectionCount: limit, matching: .images)
            .appOnChange(of: items) { _, values in
                if !values.isEmpty { selection = values.map(AppPickedPhoto.init) }
            }.appOnChange(of: selection) { _, values in
                if values.isEmpty { items = [] }
            }
    }
}

private struct AppLegacyPhotoPicker: UIViewControllerRepresentable {
    let limit: Int
    let completed: ([PHPickerResult]) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = max(1, limit)
        config.selection = .ordered
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ view: PHPickerViewController, context: Context) {
        context.coordinator.completed = completed
    }
    func makeCoordinator() -> Coordinator { Coordinator(completed: completed) }
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var completed: ([PHPickerResult]) -> Void
        init(completed: @escaping ([PHPickerResult]) -> Void) { self.completed = completed }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            completed(results)
        }
    }
}
