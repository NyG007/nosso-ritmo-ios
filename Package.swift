// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NossoRitmoCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "NossoRitmoCore", targets: ["NossoRitmoCore"])],
    targets: [
        .target(name: "NossoRitmoCore", path: "Core"),
        .testTarget(name: "NossoRitmoCoreTests", dependencies: ["NossoRitmoCore"], path: "Tests")
    ]
)
