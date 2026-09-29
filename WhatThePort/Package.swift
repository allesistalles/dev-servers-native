// swift-tools-version: 5.9

import PackageDescription

// The menu-bar app links Sparkle and SwiftUI, which Linux cannot build.
// DevServersCore is the classification, registry and LAN logic, and is what
// `swift test` runs on Linux.
#if os(macOS)
let packagePlatforms: [SupportedPlatform]? = [.macOS(.v14)]
let packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    .package(url: "https://github.com/laurieesc/flicker-dot", exact: "0.2.0"),
]
let appTargets: [Target] = [
    .executableTarget(
        name: "WhatThePort",
        dependencies: [
            .product(name: "Sparkle", package: "Sparkle"),
            .product(name: "FlickerDot", package: "flicker-dot"),
            "DevServersCore",
        ],
        resources: [.process("Resources")],
        linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
    ),
    .testTarget(name: "WhatThePortTests", dependencies: ["WhatThePort"]),
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
