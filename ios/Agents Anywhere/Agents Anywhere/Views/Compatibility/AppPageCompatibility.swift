import SwiftUI
import UIKit

/// Keeps the SF Symbol label used by native menus without requiring the iOS 17
/// convenience initializer on the same iOS 15 pages.
struct AppPageSystemButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole? = nil
    let action: () -> Void

    init(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        if #available(iOS 17.0, *), AppCompatibility.useNativeUI {
            Button(title, systemImage: systemImage, role: role, action: action)
        } else {
            Button(role: role, action: action) {
                Label(title, systemImage: systemImage)
            }
        }
    }
}

extension View {
    @ViewBuilder func appPageAutocorrectionDisabled() -> some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            autocorrectionDisabled()
        } else {
            disableAutocorrection(true)
        }
    }

    @ViewBuilder func appPageHorizontalContainerCornerOffset() -> some View {
        if #available(iOS 26.0, *), AppCompatibility.useNativeUI {
            containerCornerOffset(.horizontal, sizeToFit: true)
        } else {
            self
        }
    }

    @ViewBuilder func appPageCompletionImpact(trigger: Int) -> some View {
        if #available(iOS 17.0, *), AppCompatibility.useNativeUI {
            sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.65), trigger: trigger)
        } else {
            onChange(of: trigger) { _ in
                let feedback = UIImpactFeedbackGenerator(style: .rigid)
                feedback.prepare()
                feedback.impactOccurred(intensity: 0.65)
            }
        }
    }
}

/// The native fit decision is retained on iOS 16+. Earlier systems measure the
/// same horizontal candidate at its ideal width before choosing the same column.
struct AppPageHorizontalFit<Horizontal: View, Vertical: View>: View {
    @ViewBuilder let horizontal: () -> Horizontal
    @ViewBuilder let vertical: () -> Vertical

    var body: some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            ViewThatFits(in: .horizontal) {
                horizontal()
                vertical()
            }
        } else {
            AppPageMeasuredHorizontalFit(horizontal: horizontal, vertical: vertical)
        }
    }
}

private struct AppPageMeasuredHorizontalFit<Horizontal: View, Vertical: View>: View {
    @ViewBuilder let horizontal: () -> Horizontal
    @ViewBuilder let vertical: () -> Vertical
    @State private var availableWidth: CGFloat = 0
    @State private var idealWidth: CGFloat = 0

    var body: some View {
        Group {
            if availableWidth == 0 || idealWidth <= availableWidth + 0.5 {
                horizontal()
            } else {
                vertical()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: AppPageAvailableWidth.self, value: geometry.size.width)
            }
        }
        .background(alignment: .topLeading) {
            horizontal()
                .fixedSize(horizontal: true, vertical: false)
                .hidden()
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: AppPageIdealWidth.self, value: geometry.size.width)
                    }
                }
                .frame(width: 0, height: 0, alignment: .topLeading)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onPreferenceChange(AppPageAvailableWidth.self) { width in
            DispatchQueue.main.async { if availableWidth != width { availableWidth = width } }
        }
        .onPreferenceChange(AppPageIdealWidth.self) { width in
            DispatchQueue.main.async { if idealWidth != width { idealWidth = width } }
        }
    }
}

private struct AppPageAvailableWidth: PreferenceKey {
    nonisolated static var defaultValue: CGFloat { 0 }
    nonisolated static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct AppPageIdealWidth: PreferenceKey {
    nonisolated static var defaultValue: CGFloat { 0 }
    nonisolated static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Attach to the content column, after its padding, not to a row or a toolbar.
struct AppPageScrollTitleMarker: View {
    let coordinateSpace: UUID

    var body: some View {
        if #available(iOS 18.0, *), AppCompatibility.useNativeUI {
            EmptyView()
        } else {
            GeometryReader { geometry in
                Color.clear.preference(key: AppPageScrollTop.self,
                    value: geometry.frame(in: .named(coordinateSpace)).minY)
            }
        }
    }
}

private struct AppPageScrollTop: PreferenceKey {
    nonisolated static var defaultValue: CGFloat? { nil }
    nonisolated static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() { value = next }
    }
}

extension View {
    func appPageScrollTitle(_ showsTitle: Binding<Bool>, coordinateSpace: UUID,
        threshold: CGFloat = 56) -> some View {
        modifier(AppPageScrollTitle(showsTitle: showsTitle, coordinateSpace: coordinateSpace, threshold: threshold))
    }
}

private struct AppPageScrollTitle: ViewModifier {
    @Binding var showsTitle: Bool
    let coordinateSpace: UUID
    let threshold: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), AppCompatibility.useNativeUI {
            content
                .coordinateSpace(name: coordinateSpace)
                .onScrollGeometryChange(for: Bool.self) {
                    $0.contentOffset.y + $0.contentInsets.top > threshold
                } action: { _, scrolled in
                    update(scrolled)
                }
        } else {
            content
                .coordinateSpace(name: coordinateSpace)
                .onPreferenceChange(AppPageScrollTop.self) { top in
                    if let top { DispatchQueue.main.async { update(-top > threshold) } }
                }
        }
    }

    private func update(_ next: Bool) {
        guard next != showsTitle else { return }
        withAnimation(.easeOut(duration: 0.15)) { showsTitle = next }
    }
}

extension View {
    /// SwiftUI alert text fields first render on iOS 16. iOS 15 presents a real
    /// system alert with the same draft binding, validation and actions instead.
    func appPageTextInputAlert(_ title: String, isPresented: Binding<Bool>,
        text: Binding<String>, placeholder: String,
        saveTitle: String = String(localized: "Save"),
        cancelTitle: String = String(localized: "Cancel"),
        saveDisabled: Bool = false, onCancel: @escaping () -> Void = {},
        onSave: @escaping () -> Void) -> some View {
        modifier(AppPageTextInputAlert(title: title, isPresented: isPresented, text: text,
            placeholder: placeholder, saveTitle: saveTitle, cancelTitle: cancelTitle,
            saveDisabled: saveDisabled, onCancel: onCancel, onSave: onSave))
    }
}

private struct AppPageTextInputAlert: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    @Binding var text: String
    let placeholder: String
    let saveTitle: String
    let cancelTitle: String
    let saveDisabled: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            content.alert(title, isPresented: $isPresented) {
                TextField(placeholder, text: $text)
                Button(cancelTitle, role: .cancel, action: onCancel)
                Button(saveTitle, action: onSave)
                    .disabled(saveDisabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } else {
            content.background {
                AppPageUIKitTextInputAlert(configuration: .init(title: title,
                    isPresented: $isPresented, text: $text, placeholder: placeholder,
                    saveTitle: saveTitle, cancelTitle: cancelTitle, saveDisabled: saveDisabled,
                    onCancel: onCancel, onSave: onSave))
                    .frame(width: 0, height: 0)
            }
        }
    }
}

private struct AppPageTextInputConfiguration {
    let title: String
    let isPresented: Binding<Bool>
    let text: Binding<String>
    let placeholder: String
    let saveTitle: String
    let cancelTitle: String
    let saveDisabled: Bool
    let onCancel: () -> Void
    let onSave: () -> Void
}

private struct AppPageUIKitTextInputAlert: UIViewControllerRepresentable {
    let configuration: AppPageTextInputConfiguration

    func makeUIViewController(context: Context) -> AppPageTextInputPresenter {
        AppPageTextInputPresenter(configuration: configuration)
    }
    func updateUIViewController(_ controller: AppPageTextInputPresenter, context: Context) {
        controller.configuration = configuration
        controller.updatePresentation()
    }
    static func dismantleUIViewController(_ controller: AppPageTextInputPresenter, coordinator: ()) {
        controller.dismissInput()
    }
}

private final class AppPageTextInputPresenter: UIViewController {
    var configuration: AppPageTextInputConfiguration
    private var inputAlert: UIAlertController?
    private var saveAction: UIAlertAction?

    init(configuration: AppPageTextInputConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updatePresentation()
    }

    func updatePresentation() {
        guard configuration.isPresented.wrappedValue else { dismissInput(); return }
        if let inputAlert {
            inputAlert.title = configuration.title
            if let field = inputAlert.textFields?.first, field.text != configuration.text.wrappedValue {
                field.text = configuration.text.wrappedValue
            }
            updateSaveAction()
            return
        }
        guard isViewLoaded, view.window != nil, presentedViewController == nil else { return }
        let alert = UIAlertController(title: configuration.title, message: nil, preferredStyle: .alert)
        alert.addTextField { [weak self] field in
            guard let self else { return }
            field.placeholder = self.configuration.placeholder
            field.text = self.configuration.text.wrappedValue
            field.addTarget(self, action: #selector(self.textChanged(_:)), for: .editingChanged)
        }
        alert.addAction(UIAlertAction(title: configuration.cancelTitle, style: .cancel) { [weak self] _ in
            guard let self else { return }
            self.inputAlert = nil
            self.saveAction = nil
            self.configuration.onCancel()
            self.configuration.isPresented.wrappedValue = false
        })
        let save = UIAlertAction(title: configuration.saveTitle, style: .default) { [weak self] _ in
            guard let self else { return }
            self.inputAlert = nil
            self.saveAction = nil
            // Invoke first so item-backed presentations still expose the item
            // being renamed when their binding's false setter clears it.
            self.configuration.onSave()
            self.configuration.isPresented.wrappedValue = false
        }
        alert.addAction(save)
        alert.preferredAction = save
        inputAlert = alert
        saveAction = save
        updateSaveAction()
        present(alert, animated: true)
    }

    @objc private func textChanged(_ field: UITextField) {
        configuration.text.wrappedValue = field.text ?? ""
        updateSaveAction()
    }
    private func updateSaveAction() {
        saveAction?.isEnabled = !configuration.saveDisabled
            && !configuration.text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    func dismissInput() {
        let previous = inputAlert
        inputAlert = nil
        saveAction = nil
        previous?.dismiss(animated: false)
    }
}

/// UISheetPresentationController is already available on iOS 15. Do not replace
/// SwiftUI's presentation delegate: it owns dismiss and unsaved-draft blocking.
struct AppPageSheetDetents: UIViewControllerRepresentable {
    let size: AppSheetSize

    func makeUIViewController(context: Context) -> AppPageSheetDetentsController {
        AppPageSheetDetentsController(size: size)
    }
    func updateUIViewController(_ controller: AppPageSheetDetentsController, context: Context) {
        controller.size = size
        controller.applyDetents()
    }
}

final class AppPageSheetDetentsController: UIViewController {
    var size: AppSheetSize
    private weak var configuredSheet: UISheetPresentationController?
    private var configuredSize: AppSheetSize?

    init(size: AppSheetSize) {
        self.size = size
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        applyDetents()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyDetents()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyDetents()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyDetents()
    }

    func applyDetents() {
        var controller: UIViewController? = parent
        while let current = controller {
            if let sheet = current.presentationController as? UISheetPresentationController {
                guard configuredSheet !== sheet || configuredSize != size else { return }
                let previousSelection = sheet.selectedDetentIdentifier
                sheet.detents = size == .expanded ? [.large()] : [.medium(), .large()]
                sheet.prefersGrabberVisible = true
                sheet.prefersScrollingExpandsWhenScrolledToEdge = false
                if size == .expanded { sheet.selectedDetentIdentifier = .large }
                else if previousSelection == nil { sheet.selectedDetentIdentifier = .medium }
                configuredSheet = sheet
                configuredSize = size
                return
            }
            controller = current.parent
        }
    }
}

extension AppContentUnavailableView where Label == SwiftUI.Label<Text, AppSymbol>, Description == Text?, Actions == EmptyView {
    init(_ title: String, appSymbol: String, description: Text? = nil) {
        self.init {
            SwiftUI.Label { Text(verbatim: title) } icon: { AppSymbol(appSymbol, size: 36) }
        } description: { description }
    }
}

extension View {
    /// iOS 15's SwiftUI refresh action is presented by List, but not ScrollView.
    /// Keep the same scroll page and run its existing action from a local control.
    @ViewBuilder func appPageRefreshable(action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            refreshable { await action() }
        } else {
            background {
                AppPageRefreshControl(action: action).frame(width: 0, height: 0)
            }
        }
    }
}

private struct AppPageRefreshControl: UIViewRepresentable {
    let action: @MainActor @Sendable () async -> Void

    func makeCoordinator() -> AppPageRefreshCoordinator { AppPageRefreshCoordinator(action: action) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.action = action
        DispatchQueue.main.async { context.coordinator.attach(to: view) }
    }
    static func dismantleUIView(_ view: UIView, coordinator: AppPageRefreshCoordinator) {
        coordinator.detach()
    }
}

@MainActor
private final class AppPageRefreshCoordinator: NSObject {
    var action: @MainActor @Sendable () async -> Void
    private let control = UIRefreshControl()
    private weak var scrollView: UIScrollView?
    private var previousControl: UIRefreshControl?
    private var previousBounce = false
    private var playback: Task<Void, Never>?
    private var generation = 0

    init(action: @escaping @MainActor @Sendable () async -> Void) {
        self.action = action
        super.init()
        control.addTarget(self, action: #selector(refresh), for: .valueChanged)
    }

    func attach(to view: UIView) {
        var ancestor = view.superview
        for _ in 0..<6 {
            guard let candidate = ancestor else { return }
            if let scroll = findScroll(in: candidate, depth: 6) {
                guard scrollView !== scroll else { return }
                detach()
                scrollView = scroll
                previousControl = scroll.refreshControl
                previousBounce = scroll.alwaysBounceVertical
                scroll.refreshControl = control
                scroll.alwaysBounceVertical = true
                return
            }
            ancestor = candidate.superview
        }
    }

    private func findScroll(in view: UIView, depth: Int) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        guard depth > 0 else { return nil }
        for child in view.subviews {
            if let scroll = findScroll(in: child, depth: depth - 1) { return scroll }
        }
        return nil
    }

    @objc private func refresh() {
        guard playback == nil else { return }
        let current = generation
        playback = Task { [weak self] in
            guard let self else { return }
            await self.action()
            guard self.generation == current else { return }
            self.control.endRefreshing()
            self.playback = nil
        }
    }

    func detach() {
        generation += 1
        playback?.cancel()
        playback = nil
        control.endRefreshing()
        if let scrollView, scrollView.refreshControl === control {
            scrollView.refreshControl = previousControl
            scrollView.alwaysBounceVertical = previousBounce
        }
        scrollView = nil
        previousControl = nil
    }
}
