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
            url: "https://github.com/ayoy/suggestions_processor/releases/download/0.1.0/SuggestionsProcessorRust.xcframework.zip",
            checksum: "11d7dae585296103f7962553dc99a1d2fc240e3c68c97e9ed2f9614ce3a6a56a"
        ),
        .testTarget(
            name: "SuggestionProcessingTests",
            dependencies: ["SuggestionProcessing"]
        ),
    ]
)
