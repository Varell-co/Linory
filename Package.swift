// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Linory",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Linory", targets: ["Linory"])],
    targets: [
        .target(name: "LyricsCore"),
        .executableTarget(name: "Linory", dependencies: ["LyricsCore"]),
        .executableTarget(name: "LyricsCoreChecks", dependencies: ["LyricsCore"], path: "Checks")
    ]
)
