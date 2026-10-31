// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mole-gui",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "mole-gui", targets: ["MoleGUI"]),
    ],
    targets: [
        .target(name: "MoleGUIKit"),
        .executableTarget(name: "MoleGUI", dependencies: ["MoleGUIKit"]),
        .testTarget(name: "MoleGUIKitTests", dependencies: ["MoleGUIKit"]),
    ],
    swiftLanguageModes: [.v5]
)
