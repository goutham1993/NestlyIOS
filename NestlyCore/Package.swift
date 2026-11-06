// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NestlyCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NestlyCore", targets: ["NestlyCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.31.0"),
    ],
    targets: [
        .target(
            name: "NestlyCore",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "NestlyCoreTests",
            dependencies: ["NestlyCore"]
        ),
    ]
)
