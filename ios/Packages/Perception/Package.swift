// swift-tools-version: 6.0

import CompilerPluginSupport
import PackageDescription

// Vendored 2.0.11 (github.com/pointfreeco/swift-perception) so the iOS 15
// original-interface target resolves hermetically during Xcode package
// resolution. Only the library and macro targets are kept; upstream test and
// documentation dependencies are development-only and were removed here.
let package = Package(
  name: "swift-perception",
  platforms: [
    .iOS(.v13),
    .macOS(.v10_15),
    .tvOS(.v13),
    .watchOS(.v6),
  ],
  products: [
    .library(
      name: "PerceptionCore",
      targets: ["PerceptionCore"]
    ),
    .library(
      name: "Perception",
      targets: ["Perception"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.6.0"),
    .package(url: "https://github.com/swiftlang/swift-syntax", "509.0.0"..<"605.0.0"),
  ],
  targets: [
    .target(
      name: "Perception",
      dependencies: [
        "PerceptionCore",
        "PerceptionMacros",
      ]
    ),
    .target(
      name: "PerceptionCore",
      dependencies: [
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay")
      ]
    ),
    .macro(
      name: "PerceptionMacros",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
      ]
    ),
  ],
  swiftLanguageModes: [.v5]
)

for target in package.targets {
  target.swiftSettings = target.swiftSettings ?? []
  target.swiftSettings?.append(contentsOf: [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  ])
}
