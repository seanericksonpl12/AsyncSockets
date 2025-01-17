// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AsyncSockets",
    platforms: [
        .iOS("17.0"),
        .macOS("14.0"),
        .tvOS("13.0"),
        .watchOS("6.0")
    ],
    products: [
        .library(
            name: "AsyncSockets",
            targets: ["AsyncSockets"]
        ),
    ],
    targets: [
        .target(
            name: "AsyncSockets"
        ),
        .testTarget(
            name: "AsyncSocketsTests",
            dependencies: ["AsyncSockets"]
        ),
    ]
)
