// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OpenOats",
    platforms: [.macOS(.v15)], // Only applies to Apple platforms
    products: [
        .library(name: "OpenOatsCore", targets: ["OpenOatsCore"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "OpenOatsCore",
            dependencies: [],
            path: "Sources/OpenOatsCore"
        )
    ]
)

// whisper.cpp only builds on macOS — on Windows the C# host provides its own whisper.
#if os(macOS)
package.dependencies.append(.package(url: "https://github.com/ggml-org/whisper.cpp.git", branch: "master"))
package.targets.first { $0.name == "OpenOatsCore" }?.dependencies.append(
    .product(name: "whisper", package: "whisper.cpp")
)
#endif

#if os(macOS)
package.products.append(.executable(name: "OpenOatsMac", targets: ["OpenOatsMac"]))
package.dependencies.append(.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"))
package.targets.append(
    .executableTarget(
        name: "OpenOatsMac",
        dependencies: [
            "OpenOatsCore",
            .product(name: "Sparkle", package: "Sparkle"),
        ],
        path: "Sources/OpenOatsMac",
        exclude: ["Info.plist", "OpenOats.entitlements", "Assets"]
    )
)
#endif

// We want to be able to build on Windows. A dynamic library.
#if os(Windows)
package.products.append(.library(name: "OpenOatsWindows", type: .dynamic, targets: ["OpenOatsWindows"]))
package.targets.append(
    .target(
        name: "OpenOatsWindows",
        dependencies: ["OpenOatsCore"],
        path: "Sources/OpenOatsWindows"
    )
)
#endif
