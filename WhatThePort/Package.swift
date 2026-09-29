// swift-tools-version: 5.9

import PackageDescription

// The menu-bar app links SwiftUI, which Linux cannot build.
// DevServersCore is the classification, registry and LAN logic, and is what
// `swift test` runs on Linux.
#if os(macOS)
let packagePlatforms: [SupportedPlatform]? = [.macOS(.v14)]
let packageDependencies: [Package.Dependency] = []
let appTargets: [Target] = [
    .executableTarget(
        name: "DevServers",
        dependencies: ["DevServersCore"],
        path: "Sources/WhatThePort",
        resources: [.process("Resources")]
    ),
    .testTarget(name: "WhatThePortTests", dependencies: ["DevServers"]),
]
#else
let packagePlatforms: [SupportedPlatform]? = nil
let packageDependencies: [Package.Dependency] = []
let appTargets: [Target] = []
#endif

let package = Package(
    name: "WhatThePort",
    defaultLocalization: "en",
    platforms: packagePlatforms,
    dependencies: packageDependencies,
    targets: appTargets + [
        .target(name: "DevServersCore"),
        .testTarget(name: "DevServersCoreTests", dependencies: ["DevServersCore"]),
    ]
)
