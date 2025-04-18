// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftRadioPlayer",
    platforms: [
        .macOS(.v10_12),
        .iOS(.v10),
        .tvOS(.v10)
    ],
    products: [
        .library(
            name: "SwiftRadioPlayer",
            targets: ["SwiftRadioPlayer"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SwiftRadioPlayer",
            dependencies: []),
        .testTarget(
            name: "SwiftRadioPlayerTests",
            dependencies: ["SwiftRadioPlayer"]),
    ]
)
