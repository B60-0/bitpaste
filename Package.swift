// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BitPaste",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "bitpaste", targets: ["BitPaste"])
    ],
    targets: [
        .executableTarget(name: "BitPaste")
    ]
)
