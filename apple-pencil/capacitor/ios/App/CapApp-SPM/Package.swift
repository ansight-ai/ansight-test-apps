// swift-tools-version: 5.9
import PackageDescription

// DO NOT MODIFY THIS FILE - managed by Capacitor CLI commands
let package = Package(
    name: "CapApp-SPM",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "CapApp-SPM",
            targets: ["CapApp-SPM"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", exact: "8.5.3"),
        .package(name: "AnsightCapacitor", path: "../../../../../../ansight/ansight-sdk/src/capacitor"),
        .package(name: "AnsightCapacitorPencil", path: "../../../../../../ansight/ansight-sdk/src/capacitor-pencil")
    ],
    targets: [
        .target(
            name: "CapApp-SPM",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm"),
                .product(name: "AnsightCapacitor", package: "AnsightCapacitor"),
                .product(name: "AnsightCapacitorPencil", package: "AnsightCapacitorPencil")
            ]
        )
    ]
)
