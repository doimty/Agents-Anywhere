// swift-tools-version: 6.0

import PackageDescription

// Vendored SwiftUIMath 0.1.0 (github.com/gonzalezreal/swiftui-math) with the
// iOS 15 deployment floor used by the original-interface port. The upstream
// snapshot-testing dependency and test target are development-only and removed
// so app package resolution stays hermetic.
let package = Package(
  name: "swiftui-math",
  platforms: [
    .macOS(.v13),
    .iOS(.v15),
    .tvOS(.v17),
    .watchOS(.v10),
    .visionOS(.v1),
  ],
  products: [
    .library(name: "SwiftUIMath", targets: ["SwiftUIMath"])
  ],
  targets: [
    .target(
      name: "SwiftUIMath",
      dependencies: [],
      resources: [.copy("mathFonts.bundle")]
    ),
  ]
)
