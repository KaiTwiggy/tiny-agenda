// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TinyAgenda",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TinyAgenda", targets: ["TinyAgenda"])
    ],
    targets: [
        .target(
            name: "TinyAgendaCore",
            path: "Sources/TinyAgendaCore"
        ),
        .executableTarget(
            name: "TinyAgenda",
            dependencies: ["TinyAgendaCore"],
            path: "Sources/TinyAgenda"
        ),
        .testTarget(
            name: "TinyAgendaTests",
            dependencies: ["TinyAgendaCore"],
            path: "Tests/TinyAgendaTests"
        )
    ]
)
