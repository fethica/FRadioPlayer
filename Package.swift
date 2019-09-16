// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FRadioPlayer",
    platforms: [
        .macOS(.v10_12),
        .iOS(.v10),
        .tvOS(.v10)
    ],
    products: [
        .library(
            name: "FRadioPlayer",
            targets: ["FRadioPlayer"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FRadioPlayer",
            dependencies: []),
        .testTarget(
            name: "FRadioPlayerTests",
            dependencies: ["FRadioPlayer"]),
    ]
)
