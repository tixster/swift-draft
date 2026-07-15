// swift-tools-version: 6.3

import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "swift-draft",
  platforms: [
    .iOS(.v13),
    .macOS(.v10_15),
    .tvOS(.v13),
    .watchOS(.v6),
    .visionOS(.v1),
  ],
  products: [
    .library(
      name: "SwiftDraft",
      targets: ["SwiftDraft"]
    )
  ],
  dependencies: [
    .package(
      url: "https://github.com/swiftlang/swift-syntax",
      from: "603.0.0"
    )
  ],
  targets: [
    .macro(
      name: "SwiftDraftMacros",
      dependencies: [
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "SwiftDraft",
      dependencies: ["SwiftDraftMacros"]
    ),
    .target(
      name: "SwiftDraftAccessFixture",
      dependencies: ["SwiftDraft"]
    ),
    .testTarget(
      name: "SwiftDraftMacrosTests",
      dependencies: [
        "SwiftDraftMacros",
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "SwiftDraftTests",
      dependencies: ["SwiftDraft"]
    ),
    .testTarget(
      name: "SwiftDraftAccessTests",
      dependencies: [
        "SwiftDraft",
        "SwiftDraftAccessFixture",
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
