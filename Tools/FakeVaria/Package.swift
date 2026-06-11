// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FakeVaria",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../../Packages/VarioRadarCore"),
    ],
    targets: [
        .executableTarget(
            name: "FakeVaria",
            dependencies: [
                .product(name: "VarioRadarCore", package: "VarioRadarCore"),
            ]
        ),
    ]
)
