// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LucentCore",
    platforms: [.iOS("18.0"), .macOS(.v14)],
    products: [.library(name: "LucentCore", targets: ["LucentCore"])],
    targets: [
        .target(name: "LucentCore"),
        .testTarget(name: "LucentCoreTests", dependencies: ["LucentCore"])
    ]
)
