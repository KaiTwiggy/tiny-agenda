// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TinyAgenda",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TinyAgenda", targets: ["TinyAgenda"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4")
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
