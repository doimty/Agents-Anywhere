// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AgentsAnywhereClient",
    platforms: [.macOS(.v13), .iOS(.v15)],
    dependencies: [
        .package(path: "Packages/Perception"),
    ],
    targets: [
        .target(
            name: "ClientCore",
            dependencies: [.product(name: "Perception", package: "Perception")],
            path: "Agents Anywhere/Agents Anywhere",
            exclude: [
                "App", "Assets.xcassets", "Resources", "Services", "Stores", "Views",
                "ios-dark.icon", "Business/AccountAvatarProcessor.swift",
            ],
            sources: ["API", "Network", "Models", "Domain", "Business", "Repositories"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "ClientCoreTests",
            dependencies: ["ClientCore", .product(name: "Perception", package: "Perception")],
            path: "Tests/ClientCoreTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ],
    swiftLanguageModes: [.v5]
)
