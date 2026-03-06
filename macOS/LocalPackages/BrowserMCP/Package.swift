// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "BrowserMCP",
    platforms: [
        .macOS("11.4")
    ],
    products: [
        .executable(
            name: "ddg-browser-mcp",
            targets: ["BrowserMCPTool"]
        ),
        .library(
            name: "BrowserMCPCommon",
            targets: ["BrowserMCPCommon"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
        .package(path: "../UDSHelper"),
    ],
    targets: [
        .executableTarget(
            name: "BrowserMCPTool",
            dependencies: [
                "BrowserMCPCommon",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "UDSHelper", package: "UDSHelper"),
            ]
        ),
        .target(
            name: "BrowserMCPCommon"
        ),
    ]
)
