// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "XiaxiaLedger",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FinanceCore", targets: ["FinanceCore"]),
        .executable(name: "fin", targets: ["fin"]),
        .executable(name: "XiaxiaLedgerApp", targets: ["XiaxiaLedgerApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        // 共享核心：数据模型、金额、汇总、去重、存储。app、CLI、以后的 MCP 都只用这一份。
        .target(name: "FinanceCore"),
        // 给 AI 用的命令行
        .executableTarget(
            name: "fin",
            dependencies: [
                "FinanceCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // 给人用的 Mac app（SwiftUI 外壳，页面等设计稿定稿后再做）
        .executableTarget(name: "XiaxiaLedgerApp", dependencies: ["FinanceCore"]),
        .testTarget(name: "FinanceCoreTests", dependencies: ["FinanceCore"]),
    ]
)
