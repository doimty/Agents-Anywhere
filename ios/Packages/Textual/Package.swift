// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "textual",
  platforms: [
    .macOS(.v15),
    .iOS(.v15),
    .tvOS(.v18),
    .watchOS(.v11),
    .visionOS(.v2),
  ],
  products: [
    .library(name: "Textual", targets: ["Textual"])
  ],
  dependencies: [
    .package(path: "../SwiftUIMath/swiftui-math-0.1.0"),
  ],
  targets: [
    .target(
      name: "Textual",
      dependencies: [
        .product(name: "SwiftUIMath", package: "swiftui-math-0.1.0"),
      ],
      resources: [
        .process("Internal/Highlighter/Prism"),
        .copy("PrivacyInfo.xcprivacy"),
      ],
      swiftSettings: [
        .define(
          "TEXTUAL_ENABLE_LINKS",
          .when(platforms: [.macOS, .macCatalyst, .iOS, .watchOS, .visionOS])),
        .define(
          "TEXTUAL_ENABLE_TEXT_SELECTION",
          .when(platforms: [.macOS, .macCatalyst, .iOS, .visionOS])),
      ]
    ),
    .testTarget(
      name: "TextualSelectionTests",
      dependencies: ["Textual"],
      swiftSettings: [.define("TEXTUAL_ENABLE_TEXT_SELECTION")]
    ),
  ]
)
