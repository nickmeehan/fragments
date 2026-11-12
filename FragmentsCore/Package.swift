// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FragmentsCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "FragmentsCore", targets: ["FragmentsCore"])],
    targets: [
        // What every action imports. Zero dependencies, Foundation only: the app ships it as source and compiles it
        // with the user's swiftc, so it must build alone.
        .target(name: "FragmentsAction"),
        .target(name: "FragmentsCore", dependencies: ["FragmentsAction"]),
        // The bundled actions, one folder each, exactly as a folder of yours in ~/.fragments/actions looks.
        .executableTarget(name: "Cowork", dependencies: ["FragmentsAction"], path: "Actions/cowork"),
        .executableTarget(name: "Rex", dependencies: ["FragmentsAction"], path: "Actions/rex"),
        .testTarget(name: "FragmentsCoreTests", dependencies: ["FragmentsCore", "FragmentsAction", "Cowork", "Rex"]),
    ]
)
