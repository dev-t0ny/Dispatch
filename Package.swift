// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Dispatch",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Dispatch", targets: ["DispatchLauncher"])
    ],
    targets: [
        .executableTarget(
            name: "DispatchLauncher",
            path: "Sources/Dispatch"
        ),
    ]
)
