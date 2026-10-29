import SwiftUI

/// Retain native stack navigation on iOS 16; only the backend changes on 15.
struct AppNavigationStack<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            NavigationStack { content }
        } else {
            NavigationView { content }.navigationViewStyle(StackNavigationViewStyle())
        }
    }
}

/// The exact original typed route binding drives both backends. Deep links,
/// restored paths, programmatic pushes and system Back never use a second path.
struct AppRouteNavigationStack<Route: Hashable, Root: View, Destination: View>: View {
    @Binding private var path: [Route]
    private let root: Root
    private let destination: (Route) -> Destination

    init(path: Binding<[Route]>, @ViewBuilder root: () -> Root,
         @ViewBuilder destination: @escaping (Route) -> Destination) {
        _path = path; self.root = root(); self.destination = destination
    }

    var body: some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            NavigationStack(path: $path) {
                root.navigationDestination(for: Route.self, destination: destination)
            }
        } else {
            NavigationView {
                AppLegacyRouteLevel(path: $path, depth: 0, content: AnyView(root),
                                    destination: { AnyView(destination($0)) })
            }.navigationViewStyle(StackNavigationViewStyle())
        }
    }
}

struct AppRouteNavigationLink<Route: Hashable, Label: View>: View {
    let value: Route
    @Binding var path: [Route]
    private let label: Label

    init(value: Route, path: Binding<[Route]>, @ViewBuilder label: () -> Label) {
        self.value = value; _path = path; self.label = label()
    }

    var body: some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            NavigationLink(value: value) { label }
        } else {
            Button { path.append(value) } label: {
                HStack(spacing: 6) {
                    label
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).accessibilityAddTraits(.isLink)
        }
    }
}

private struct AppLegacyRouteLevel<Route: Hashable>: View {
    @Binding var path: [Route]
    let depth: Int
    let content: AnyView
    let destination: (Route) -> AnyView
    @State private var mounted = false

    var body: some View {
        let next = path.indices.contains(depth) ? path[depth] : nil
        let expectedPrefix = Array(path.prefix(depth + 1))
        content.background(
            NavigationLink(isActive: Binding(
                get: { mounted && path.count > depth },
                set: { active in
                    // Ignore obsolete back callbacks when a route was replaced
                    // by a newer session/deep-link while the old view disappears.
                    guard mounted, !active, path.count > depth,
                          path.starts(with: expectedPrefix) else { return }
                    path = Array(path.prefix(depth))
                })) {
                    if let next {
                        AnyView(AppLegacyRouteLevel(
                            path: $path, depth: depth + 1,
                            content: AnyView(destination(next).id(next)),
                            destination: destination).id(next))
                    }
                } label: { EmptyView() }
                .hidden().id(next)
        ).onAppear {
            // Mount one level at a time: simultaneous hidden-link pushes before
            // NavigationView attaches can otherwise lose a deep route on 15.
            DispatchQueue.main.async { mounted = true }
        }
    }
}

struct AppLabeledContent<Content: View, Label: View>: View {
    private let content: Content
    private let label: Label
    init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content(); self.label = label()
    }
    var body: some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            LabeledContent { content } label: { label }
        } else {
            HStack(alignment: .firstTextBaseline) {
                label
                Spacer(minLength: 16)
                content.foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }.accessibilityElement(children: .contain)
        }
    }
}

extension AppLabeledContent where Label == Text {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.label = Text(verbatim: title); self.content = content()
    }
}

extension AppLabeledContent where Label == Text, Content == Text {
    init(_ title: String, value: String) {
        self.label = Text(verbatim: title); self.content = Text(verbatim: value)
    }
}

struct AppContentUnavailableView<Label: View, Description: View, Actions: View>: View {
    private let label: Label
    private let description: Description
    private let actions: Actions
    init(@ViewBuilder label: () -> Label, @ViewBuilder description: () -> Description,
         @ViewBuilder actions: () -> Actions) {
        self.label = label(); self.description = description(); self.actions = actions()
    }
    var body: some View {
        if #available(iOS 17.0, *), AppCompatibility.useNativeUI {
            ContentUnavailableView { label } description: { description } actions: { actions }
        } else {
            VStack(spacing: 14) {
                label.font(.title2.weight(.semibold))
                description.font(.subheadline).foregroundStyle(.secondary)
                actions
            }.multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
        }
    }
}

extension AppContentUnavailableView where Description == Text?, Actions == EmptyView {
    init(@ViewBuilder label: () -> Label, @ViewBuilder description: () -> Text? = { nil }) {
        self.label = label(); self.description = description(); self.actions = EmptyView()
    }
}

struct AppMultilineTextField: View {
    let title: String
    @Binding var text: String
    var lineLimit: ClosedRange<Int> = 1...5
    @ScaledMetric(relativeTo: .body) private var lineHeight: CGFloat = 20
    init(_ title: String, text: Binding<String>, lineLimit: ClosedRange<Int> = 1...5) {
        self.title = title; _text = text; self.lineLimit = lineLimit
    }
    var body: some View {
        if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
            TextField(title, text: $text, axis: .vertical).lineLimit(lineLimit)
        } else {
            TextEditor(text: $text).overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(title).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 8)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }.frame(minHeight: lineHeight * CGFloat(lineLimit.lowerBound) + 16,
                    maxHeight: lineHeight * CGFloat(lineLimit.upperBound) + 16)
                .accessibilityLabel(title)
        }
    }
}
