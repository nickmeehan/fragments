// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FragmentsCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "FragmentsCore", targets: ["FragmentsCore"])],
    targets: [
        .target(name: "FragmentsCore"),
        .testTarget(name: "FragmentsCoreTests", dependencies: ["FragmentsCore"]),
    ]
)
