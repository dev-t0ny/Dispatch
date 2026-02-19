// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Dispatch",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Dispatch", targets: ["DispatchLauncher"]),
        .executable(name: "dispatchctl", targets: ["DispatchCtl"]),
        .executable(name: "dispatch-agent", targets: ["DispatchAgent"])
    ],
    targets: [
        .target(
            name: "DispatchShared",
            path: "Sources/DispatchShared"
        ),
        .executableTarget(
            name: "DispatchLauncher",
            dependencies: ["DispatchShared"],
            path: "Sources/Dispatch"
        ),
        .executableTarget(
            name: "DispatchCtl",
            dependencies: ["DispatchShared"],
            path: "Sources/DispatchCtl"
        ),
        .executableTarget(
            name: "DispatchAgent",
            dependencies: ["DispatchShared"],
            path: "Sources/DispatchAgent"
        ),
    ]
)
