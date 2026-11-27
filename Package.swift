// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "XiaxiaLedger",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "FinanceCore", targets: ["FinanceCore"]),
        .library(name: "LedgerUI", targets: ["LedgerUI"]),
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
        // iPhone 和 Mac 共用的 SwiftUI 界面。正式 app 工程在 App/（XcodeGen），只是套个壳。
        .target(name: "LedgerUI", dependencies: ["FinanceCore"],
                // 夏夏和 AI 伙伴的形象图（design/mascot/build.py 生成）
                // 更新日志（官网、Mac 更新窗口、app「这次更新了什么」共用一份，见 scripts/changelog.py）
                resources: [.copy("Resources/Mascot"), .copy("Resources/V3"), .copy("Resources/Changelog.json")]),
        // Mac 开发版：swift run XiaxiaLedgerApp 直接看界面
        .executableTarget(name: "XiaxiaLedgerApp", dependencies: ["LedgerUI"]),
        .testTarget(name: "FinanceCoreTests", dependencies: ["FinanceCore"]),
        .testTarget(name: "LedgerUITests", dependencies: ["LedgerUI", "FinanceCore"]),
    ]
)
