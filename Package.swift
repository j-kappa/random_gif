// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RandomGif",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "RandomGif",
            path: "Sources/RandomGif"
        )
    ]
)
