// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sage",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "Sage", targets: ["Sage"])
    ],
    dependencies: [
        .package(url: "https://github.com/supabase-community/supabase-swift", from: "2.0.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
    ],
    targets: [
        .target(
            name: "Sage",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ]
        )
    ]
)
