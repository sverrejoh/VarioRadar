// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VarioRadarCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "VarioRadarCore", targets: ["VarioRadarCore"]),
    ],
    targets: [
        .target(name: "VarioRadarCore"),
        .testTarget(
            name: "VarioRadarCoreTests",
            dependencies: ["VarioRadarCore"]
        ),
    ]
)
