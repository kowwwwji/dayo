// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DayoCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "DayoCore", targets: ["DayoCore"]),
    ],
    targets: [
        .target(
            name: "DayoCore",
            linkerSettings: [.linkedFramework("EventKit")]
        ),
        .testTarget(name: "DayoCoreTests", dependencies: ["DayoCore"]),
    ],
    swiftLanguageModes: [.v5]
)
