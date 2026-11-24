// swift-tools-version:6.0
// Phase 1 feasibility prototype: animated Metal content in a desktop-level window.
import PackageDescription

let package = Package(
    name: "DesktopPrototype",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DesktopPrototype",
            path: "Sources/DesktopPrototype",
            // Shaders are compiled at runtime from source (see Shaders.swift), so no
            // .metal files and no offline Metal toolchain are required.
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
            ]
        )
    ]
)
