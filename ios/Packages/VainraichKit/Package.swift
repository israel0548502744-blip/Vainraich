// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "VainraichKit",
    defaultLocalization: "he",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FinanceCore", targets: ["FinanceCore"]),
        .library(name: "DocumentAI", targets: ["DocumentAI"]),
    ],
    targets: [
        .target(name: "FinanceCore"),
        .target(name: "DocumentAI", dependencies: ["FinanceCore"]),
        .testTarget(name: "FinanceCoreTests", dependencies: ["FinanceCore"]),
        .testTarget(name: "DocumentAITests", dependencies: ["DocumentAI", "FinanceCore"]),
    ]
)
