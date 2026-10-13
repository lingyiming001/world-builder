// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WorldBuilder",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "WorldBuilder", targets: ["WorldBuilder"])],
    targets: [.executableTarget(name: "WorldBuilder")]
)
