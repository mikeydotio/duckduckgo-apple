// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SuggestionProcessing",
    platforms: [
        .iOS(.v15),
        .macOS("11.4"),
    ],
    products: [
        .library(name: "SuggestionProcessing", targets: ["SuggestionProcessing"]),
    ],
    dependencies: [
        .package(path: "../BrowserServicesKit"),
    ],
    targets: [
        .target(
            name: "SuggestionProcessing",
            dependencies: [
                "SuggestionsProcessorRust",
                .product(name: "Suggestions", package: "BrowserServicesKit"),
            ]
        ),
        .binaryTarget(
            name: "SuggestionsProcessorRust",
            path: "artifacts/SuggestionsProcessorRust.xcframework"
        ),
        .testTarget(
            name: "SuggestionProcessingTests",
            dependencies: ["SuggestionProcessing"]
        ),
    ]
)
