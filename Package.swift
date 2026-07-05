// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FRadioPlayer",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
        .tvOS(.v14)
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
