// swift-tools-version:6.0
// Gloaming: an open-source animated Metal wallpaper for macOS.
//
// Layout note: PROJECT.md §12 suggests App/, Desktop/, Rendering/, Models/ … as siblings.
// SwiftPM targets cannot share or nest directories, so everything except the app shell
// lives in the `WallpaperCore` library (Gloaming/Core/<Desktop|Rendering|Models|…>)
// and the thin executable lives in Gloaming/App. This keeps Core unit-testable.
import PackageDescription

let package = Package(
    name: "Gloaming",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Gloaming", targets: ["Gloaming"]),
    ],
    targets: [
        .target(
            name: "WallpaperCore",
            path: "Gloaming/Core",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
            ]
        ),
        .executableTarget(
            name: "Gloaming",
            dependencies: ["WallpaperCore"],
            path: "Gloaming/App"
        ),
        .testTarget(
            name: "WallpaperCoreTests",
            dependencies: ["WallpaperCore"],
            path: "Tests/WallpaperCoreTests"
        ),
    ]
)
