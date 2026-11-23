// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HealthCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        // Explicit `.static` so a future SwiftPM default change cannot
        // silently flip us to dynamic — which would embed a static slice
        // under *.app/Frameworks/ and trigger App Store rejection.
        .library(
            name: "HealthCore",
            type: .static,
            targets: ["HealthCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: [
        .target(
            name: "HealthCore",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "Sources/HealthCore"
        ),
        .testTarget(
            name: "HealthCoreTests",
            dependencies: ["HealthCore"],
            path: "Tests/HealthCoreTests"
        )
    ]
)
