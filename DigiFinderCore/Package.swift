// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "DigiFinderCore",
    platforms: [.iOS(.v17)],
    products: [.library(name: "DigiFinderCore", targets: ["DigiFinderCore"])],
    targets: [
        .target(name: "DigiFinderCore"),
        .testTarget(name: "DigiFinderCoreTests", dependencies: ["DigiFinderCore"])
    ]
)
