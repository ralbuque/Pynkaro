// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pynkaro",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Pynkaro",
            path: "Sources/Pynkaro"
        )
    ]
)
