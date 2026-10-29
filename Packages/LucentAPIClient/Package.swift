// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LucentAPIClient",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "LucentAPIClient", targets: ["LucentAPIClient"]),
    ],
    targets: [
        .target(name: "LucentAPIClient"),
        .testTarget(
            name: "LucentAPIClientTests",
            dependencies: ["LucentAPIClient"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
