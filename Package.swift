// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TinyAgenda",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TinyAgenda", targets: ["TinyAgenda"])
    ],
    dependencies: [
        // Exact pin: avoids surprise upgrades on CI and matches release.yml Sparkle tools (2.6.4).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: Version(2, 6, 4))
    ],
    targets: [
        .target(
            name: "TinyAgendaCore",
            path: "Sources/TinyAgendaCore"
        ),
        .executableTarget(
            name: "TinyAgenda",
            dependencies: [
                "TinyAgendaCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/TinyAgenda"
        ),
        .testTarget(
            name: "TinyAgendaTests",
            dependencies: ["TinyAgendaCore"],
            path: "Tests/TinyAgendaTests"
        )
    ]
)
