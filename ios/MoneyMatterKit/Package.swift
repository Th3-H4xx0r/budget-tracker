// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MoneyMatterKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "MoneyMatterKit", targets: ["MoneyMatterKit"]),
    ],
    targets: [
        .target(name: "MoneyMatterKit"),
        .testTarget(
            name: "MoneyMatterKitTests",
            dependencies: ["MoneyMatterKit"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
