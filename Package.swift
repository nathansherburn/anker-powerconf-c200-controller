// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "C200Controller",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CUVC",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .executableTarget(
            name: "C200Controller",
            dependencies: ["CUVC"]
        ),
    ]
)
